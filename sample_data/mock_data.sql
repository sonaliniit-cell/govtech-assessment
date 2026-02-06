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
