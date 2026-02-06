-- Dimension tables
-- dim_website: one row per website where the chatbot runs
CREATE TABLE dim_website (
    website_id      SERIAL PRIMARY KEY,
    website_key     TEXT NOT NULL UNIQUE,     -- e.g. domain or site code
    name            TEXT NOT NULL,
    url             TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- dim_page: logical pages within a website (e.g. /pricing, /support)
CREATE TABLE dim_page (
    page_id         SERIAL PRIMARY KEY,
    website_id      INT NOT NULL REFERENCES dim_website(website_id),
    page_path       TEXT NOT NULL,           -- e.g. "/pricing"
    page_name       TEXT,
    UNIQUE (website_id, page_path)
);

-- dim_language: ISO language codes
CREATE TABLE dim_language (
    language_id     SERIAL PRIMARY KEY,
    language_code   VARCHAR(10) NOT NULL UNIQUE,  -- e.g. "en", "en-SG"
    language_name   TEXT NOT NULL
);

-- dim_channel: source channel of conversation
CREATE TABLE dim_channel (
    channel_id      SERIAL PRIMARY KEY,
    channel_key     TEXT NOT NULL UNIQUE,    -- e.g. "web", "whatsapp", "messenger"
    description     TEXT
);

-- dim_user: both authenticated and anonymous end users
CREATE TABLE dim_user (
    user_id             SERIAL PRIMARY KEY,
    external_user_id    TEXT,                -- app-level id if known
    email               TEXT,
    display_name        TEXT,
    is_anonymous        BOOLEAN NOT NULL DEFAULT TRUE,
    language_id         INT REFERENCES dim_language(language_id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_dim_user_external UNIQUE (external_user_id)
);

-- Fact tables

-- fact_conversation: one row per conversation/session
CREATE TABLE fact_conversation (
    conversation_id         BIGSERIAL PRIMARY KEY,
    conversation_key        TEXT NOT NULL UNIQUE,  -- external session id
    user_id                 INT REFERENCES dim_user(user_id),
    website_id              INT NOT NULL REFERENCES dim_website(website_id),
    page_id                 INT REFERENCES dim_page(page_id),
    channel_id              INT REFERENCES dim_channel(channel_id),
    language_id             INT REFERENCES dim_language(language_id),

    started_at              TIMESTAMPTZ NOT NULL,
    ended_at                TIMESTAMPTZ,          -- null if still open
    status                  TEXT NOT NULL,        -- e.g. "open","closed","abandoned"
    initial_intent          TEXT,                 -- intent at first message
    resolved_intent         TEXT,                 -- final or dominant intent
    is_escalated_to_agent   BOOLEAN NOT NULL DEFAULT FALSE,
    metadata                JSONB,                -- device, browser, geo, etc.

    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_fact_conversation_user ON fact_conversation (user_id);
CREATE INDEX idx_fact_conversation_website ON fact_conversation (website_id);
CREATE INDEX idx_fact_conversation_started_at ON fact_conversation (started_at);
CREATE INDEX idx_fact_conversation_status ON fact_conversation (status);


-- fact_message: one row per message (user or bot)
CREATE TABLE fact_message (
    message_id          BIGSERIAL PRIMARY KEY,
    conversation_id     BIGINT NOT NULL REFERENCES fact_conversation(conversation_id),
    sender_type         TEXT NOT NULL,       -- 'user' or 'bot' or 'agent'
    user_id             INT REFERENCES dim_user(user_id),  -- nullable for bot messages
    sent_at             TIMESTAMPTZ NOT NULL,

    content_type        TEXT NOT NULL,       -- 'text','image','quick_reply','event'
    content_text        TEXT,                -- main text, if any
    content_payload     JSONB,               -- raw payload, buttons, attachments

    nlp_intent          TEXT,                -- intent for this utterance
    nlp_confidence      NUMERIC(5,4),        -- 0.0000 - 1.0000
    nlp_entities        JSONB,               -- list/dict of entities
    nlp_sentiment       JSONB,               -- sentiment score, label, etc.

    message_index       INT NOT NULL,        -- order within conversation
    is_user_visible     BOOLEAN NOT NULL DEFAULT TRUE,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_fact_message_conv_index UNIQUE (conversation_id, message_index)
);

CREATE INDEX idx_fact_message_conversation ON fact_message (conversation_id);
CREATE INDEX idx_fact_message_user ON fact_message (user_id);
CREATE INDEX idx_fact_message_sent_at ON fact_message (sent_at);
CREATE INDEX idx_fact_message_sender_type ON fact_message (sender_type);

-- staging tables

CREATE TABLE stg_conversations (
    conversation_key    TEXT,
    external_user_id    TEXT,
    website_key         TEXT,
    page_path           TEXT,
    channel_key         TEXT,
    language_code       TEXT,
    started_at          TIMESTAMPTZ,
    ended_at            TIMESTAMPTZ,
    status              TEXT,
    initial_intent      TEXT,
    resolved_intent     TEXT,
    is_escalated_to_agent BOOLEAN,
    metadata            JSONB
);

CREATE TABLE stg_messages (
    conversation_key    TEXT,
    external_user_id    TEXT,
    sender_type         TEXT,
    sent_at             TIMESTAMPTZ,
    content_type        TEXT,
    content_text        TEXT,
    content_payload     JSONB,
    nlp_intent          TEXT,
    nlp_confidence      NUMERIC(5,4),
    nlp_entities        JSONB,
    nlp_sentiment       JSONB,
    message_index       INT
);

-- Populate dimensions from staging

-- Website
INSERT INTO dim_website (website_key, name, url)
SELECT DISTINCT
    s.website_key,
    INITCAP(REPLACE(s.website_key, '-', ' ')) AS name,
    'https://' || s.website_key AS url
FROM stg_conversations s
LEFT JOIN dim_website d USING (website_key)
WHERE d.website_key IS NULL;

-- Page
INSERT INTO dim_page (website_id, page_path, page_name)
SELECT DISTINCT
    w.website_id,
    s.page_path,
    NULL
FROM stg_conversations s
JOIN dim_website w ON w.website_key = s.website_key
LEFT JOIN dim_page p
    ON p.website_id = w.website_id
   AND p.page_path = s.page_path
WHERE p.page_id IS NULL;

-- Language
INSERT INTO dim_language (language_code, language_name)
SELECT DISTINCT
    s.language_code,
    s.language_code AS language_name
FROM stg_conversations s
LEFT JOIN dim_language l USING (language_code)
WHERE l.language_code IS NULL;

-- Channel
INSERT INTO dim_channel (channel_key, description)
SELECT DISTINCT
    s.channel_key,
    s.channel_key
FROM stg_conversations s
LEFT JOIN dim_channel c USING (channel_key)
WHERE c.channel_key IS NULL;

-- User
INSERT INTO dim_user (external_user_id, email, display_name, is_anonymous, language_id)
SELECT DISTINCT
    sc.external_user_id,
    NULL,
    NULL,
    (sc.external_user_id IS NULL) AS is_anonymous,
    l.language_id
FROM stg_conversations sc
LEFT JOIN dim_language l ON l.language_code = sc.language_code
LEFT JOIN dim_user u ON u.external_user_id = sc.external_user_id
WHERE u.user_id IS NULL;

-- Build fact tables from staging

-- Conversations
INSERT INTO fact_conversation (
    conversation_key,
    user_id,
    website_id,
    page_id,
    channel_id,
    language_id,
    started_at,
    ended_at,
    status,
    initial_intent,
    resolved_intent,
    is_escalated_to_agent,
    metadata
)
SELECT
    sc.conversation_key,
    u.user_id,
    w.website_id,
    p.page_id,
    c.channel_id,
    l.language_id,
    sc.started_at,
    sc.ended_at,
    sc.status,
    sc.initial_intent,
    sc.resolved_intent,
    COALESCE(sc.is_escalated_to_agent, FALSE),
    sc.metadata
FROM stg_conversations sc
JOIN dim_website  w ON w.website_key = sc.website_key
LEFT JOIN dim_page     p ON p.website_id = w.website_id AND p.page_path = sc.page_path
LEFT JOIN dim_channel  c ON c.channel_key = sc.channel_key
LEFT JOIN dim_language l ON l.language_code = sc.language_code
LEFT JOIN dim_user     u ON u.external_user_id = sc.external_user_id;


-- Messages
INSERT INTO fact_message (
    conversation_id,
    sender_type,
    user_id,
    sent_at,
    content_type,
    content_text,
    content_payload,
    nlp_intent,
    nlp_confidence,
    nlp_entities,
    nlp_sentiment,
    message_index
)
SELECT
    fc.conversation_id,
    sm.sender_type,
    u.user_id,
    sm.sent_at,
    sm.content_type,
    sm.content_text,
    sm.content_payload,
    sm.nlp_intent,
    sm.nlp_confidence,
    sm.nlp_entities,
    sm.nlp_sentiment,
    sm.message_index
FROM stg_messages sm
JOIN fact_conversation fc ON fc.conversation_key = sm.conversation_key
LEFT JOIN dim_user u ON u.external_user_id = sm.external_user_id;

-- 2. Seed dimension data (websites, pages, languages, channels, users)

INSERT INTO dim_website (website_key, name, url)
VALUES
  ('site-a.com', 'Site A', 'https://site-a.com'),
  ('site-b.com', 'Site B', 'https://site-b.com');

INSERT INTO dim_page (website_id, page_path, page_name)
SELECT website_id, '/pricing', 'Pricing'
FROM dim_website
WHERE website_key = 'site-a.com';

INSERT INTO dim_page (website_id, page_path, page_name)
SELECT website_id, '/support', 'Support'
FROM dim_website
WHERE website_key = 'site-b.com';

INSERT INTO dim_language (language_code, language_name)
VALUES
  ('en', 'English'),
  ('en-SG', 'English (Singapore)');

INSERT INTO dim_channel (channel_key, description)
VALUES
  ('web', 'Embedded web widget'),
  ('whatsapp', 'WhatsApp bot');

-- Users
INSERT INTO dim_user (external_user_id, email, display_name, is_anonymous, language_id)
VALUES
  ('user_ext_1', 'alice@example.com', 'Alice', FALSE,
      (SELECT language_id FROM dim_language WHERE language_code = 'en')),
  ('user_ext_2', 'bob@example.com', 'Bob', FALSE,
      (SELECT language_id FROM dim_language WHERE language_code = 'en-SG')),
  (NULL, NULL, NULL, TRUE,
      (SELECT language_id FROM dim_language WHERE language_code = 'en'));


-- 3. Seed conversations (5 conversations across 2 websites)

-- Conversation 1: Site A, Alice, pricing question (web)
INSERT INTO fact_conversation (
  conversation_key, user_id, website_id, page_id, channel_id, language_id,
  started_at, ended_at, status, initial_intent, resolved_intent,
  is_escalated_to_agent, metadata
)
VALUES (
  'conv_1',
  (SELECT user_id FROM dim_user WHERE external_user_id = 'user_ext_1'),
  (SELECT website_id FROM dim_website WHERE website_key = 'site-a.com'),
  (SELECT page_id FROM dim_page WHERE page_path = '/pricing'),
  (SELECT channel_id FROM dim_channel WHERE channel_key = 'web'),
  (SELECT language_id FROM dim_language WHERE language_code = 'en'),
  NOW() - INTERVAL '30 minutes',
  NOW() - INTERVAL '25 minutes',
  'closed',
  'pricing_question',
  'pricing_question',
  FALSE,
  '{"device":"desktop","country":"SG"}'::jsonb
);

-- Conversation 2: Site A, anonymous user, support question (web)
INSERT INTO fact_conversation (
  conversation_key, user_id, website_id, page_id, channel_id, language_id,
  started_at, ended_at, status, initial_intent, resolved_intent,
  is_escalated_to_agent, metadata
)
VALUES (
  'conv_2',
  (SELECT user_id FROM dim_user WHERE external_user_id IS NULL LIMIT 1),
  (SELECT website_id FROM dim_website WHERE website_key = 'site-a.com'),
  (SELECT page_id FROM dim_page WHERE page_path = '/pricing'),
  (SELECT channel_id FROM dim_channel WHERE channel_key = 'web'),
  (SELECT language_id FROM dim_language WHERE language_code = 'en'),
  NOW() - INTERVAL '10 minutes',
  NOW() - INTERVAL '5 minutes',
  'closed',
  'support_question',
  'support_question',
  TRUE,
  '{"device":"mobile","country":"MY"}'::jsonb
);

-- Conversation 3: Site B, Bob, billing issue (whatsapp)
INSERT INTO fact_conversation (
  conversation_key, user_id, website_id, page_id, channel_id, language_id,
  started_at, ended_at, status, initial_intent, resolved_intent,
  is_escalated_to_agent, metadata
)
VALUES (
  'conv_3',
  (SELECT user_id FROM dim_user WHERE external_user_id = 'user_ext_2'),
  (SELECT website_id FROM dim_website WHERE website_key = 'site-b.com'),
  (SELECT page_id FROM dim_page WHERE page_path = '/support'),
  (SELECT channel_id FROM dim_channel WHERE channel_key = 'whatsapp'),
  (SELECT language_id FROM dim_language WHERE language_code = 'en-SG'),
  NOW() - INTERVAL '1 hour',
  NOW() - INTERVAL '45 minutes',
  'closed',
  'billing_issue',
  'billing_issue',
  TRUE,
  '{"device":"phone","country":"SG"}'::jsonb
);

-- Conversation 4: Site B, Bob, another question (open)
INSERT INTO fact_conversation (
  conversation_key, user_id, website_id, page_id, channel_id, language_id,
  started_at, ended_at, status, initial_intent, resolved_intent,
  is_escalated_to_agent, metadata
)
VALUES (
  'conv_4',
  (SELECT user_id FROM dim_user WHERE external_user_id = 'user_ext_2'),
  (SELECT website_id FROM dim_website WHERE website_key = 'site-b.com'),
  (SELECT page_id FROM dim_page WHERE page_path = '/support'),
  (SELECT channel_id FROM dim_channel WHERE channel_key = 'web'),
  (SELECT language_id FROM dim_language WHERE language_code = 'en-SG'),
  NOW() - INTERVAL '3 minutes',
  NULL,
  'open',
  'general_question',
  NULL,
  FALSE,
  '{"device":"desktop","country":"SG"}'::jsonb
);

-- Conversation 5: Site A, anonymous, very short session
INSERT INTO fact_conversation (
  conversation_key, user_id, website_id, page_id, channel_id, language_id,
  started_at, ended_at, status, initial_intent, resolved_intent,
  is_escalated_to_agent, metadata
)
VALUES (
  'conv_5',
  (SELECT user_id FROM dim_user WHERE external_user_id IS NULL LIMIT 1),
  (SELECT website_id FROM dim_website WHERE website_key = 'site-a.com'),
  (SELECT page_id FROM dim_page WHERE page_path = '/pricing'),
  (SELECT channel_id FROM dim_channel WHERE channel_key = 'web'),
  (SELECT language_id FROM dim_language WHERE language_code = 'en'),
  NOW() - INTERVAL '2 minutes',
  NOW() - INTERVAL '1 minute',
  'closed',
  'chitchat',
  'chitchat',
  FALSE,
  '{"device":"tablet","country":"ID"}'::jsonb
);


-- 4. Seed messages for each conversation

-- conv_1 messages
INSERT INTO fact_message (
  conversation_id, sender_type, user_id, sent_at,
  content_type, content_text, content_payload,
  nlp_intent, nlp_confidence, nlp_entities, nlp_sentiment, message_index
)
SELECT
  fc.conversation_id,
  'user',
  u.user_id,
  fc.started_at,
  'text',
  'Hi, I have a question about your pricing.',
  '{}'::jsonb,
  'pricing_question',
  0.92,
  '[]'::jsonb,
  '{"score":0.1,"label":"neutral"}'::jsonb,
  1
FROM fact_conversation fc
JOIN dim_user u ON u.user_id = fc.user_id
WHERE fc.conversation_key = 'conv_1';

INSERT INTO fact_message (
  conversation_id, sender_type, user_id, sent_at,
  content_type, content_text, content_payload,
  nlp_intent, nlp_confidence, nlp_entities, nlp_sentiment, message_index
)
SELECT
  fc.conversation_id,
  'bot',
  NULL,
  fc.started_at + INTERVAL '1 minute',
  'text',
  'Sure, what would you like to know about our pricing?',
  '{}'::jsonb,
  'follow_up',
  0.99,
  '[]'::jsonb,
  '{"score":0.3,"label":"positive"}'::jsonb,
  2
FROM fact_conversation fc
WHERE fc.conversation_key = 'conv_1';

-- Example: single short message for conv_5
INSERT INTO fact_message (
  conversation_id, sender_type, user_id, sent_at,
  content_type, content_text, content_payload,
  nlp_intent, nlp_confidence, nlp_entities, nlp_sentiment, message_index
)
SELECT
  fc.conversation_id,
  'user',
  fc.user_id,
  fc.started_at,
  'text',
  'Hello?',
  '{}'::jsonb,
  'chitchat',
  0.6,
  '[]'::jsonb,
  '{"score":0.0,"label":"neutral"}'::jsonb,
  1
FROM fact_conversation fc
WHERE fc.conversation_key = 'conv_5';

-- (You can add a few more messages for conv_2, conv_3, conv_4 similarly.)