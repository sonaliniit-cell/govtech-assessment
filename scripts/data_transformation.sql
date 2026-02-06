-- Session table: aggregated conversation/session attributes
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE session (
    session_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id     BIGINT UNIQUE REFERENCES fact_conversation(conversation_id),

    session_starttstamp TIMESTAMPTZ NOT NULL,
    session_endtstamp   TIMESTAMPTZ,
    ip_address          INET,                 -- INET for IPv4/IPv6 instead of VARCHAR(15)
    user_id             INT REFERENCES dim_user(user_id),

    website_id          INT REFERENCES dim_website(website_id),
    channel_id          INT REFERENCES dim_channel(channel_id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_session_ip ON session (ip_address);
CREATE INDEX idx_session_website ON session (website_id);
CREATE INDEX idx_session_start ON session (session_starttstamp);

-- populating session from fact_conversation once per conversation
INSERT INTO session (
    conversation_id,
    session_starttstamp,
    session_endtstamp,
    ip_address,
    user_id,
    website_id,
    channel_id
)
SELECT
    fc.conversation_id,
    fc.started_at,
    fc.ended_at,
    (fc.metadata ->> 'ip_address')::inet,
    fc.user_id,
    fc.website_id,
    fc.channel_id
FROM fact_conversation fc
ON CONFLICT (conversation_id) DO NOTHING;

-- (Assumes IP is stored in fact_conversation.metadata as ip_address; adjust as needed.)

-- Session metrics table
CREATE TABLE session_metrics (
    session_id              UUID PRIMARY KEY REFERENCES session(session_id),

    -- Derived engagement metrics
    total_messages          INT NOT NULL,
    user_messages           INT NOT NULL,
    bot_messages            INT NOT NULL,
    duration_seconds        INT NOT NULL,  -- session_end - session_start (or last message - first message)
    is_short_conversation   BOOLEAN NOT NULL,

    -- Success flags
    is_contained            BOOLEAN NOT NULL,  -- inverse of escalation
    has_escalation          BOOLEAN NOT NULL,

    -- Quality metrics
    csat_rating             INT,              -- nullable (1–5) if available
    csat_comment            TEXT,
    csat_sentiment          JSONB,           -- sentiment analysis for comment

    computed_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_session_metrics_contained ON session_metrics (is_contained);
CREATE INDEX idx_session_metrics_short ON session_metrics (is_short_conversation);
CREATE INDEX idx_session_metrics_csat ON session_metrics (csat_rating);

-- aggregation from fact_message and fact_conversation
-- Derive message counts and duration per session
WITH convo_base AS (
    SELECT
        s.session_id,
        fc.conversation_id,
        fc.started_at,
        COALESCE(fc.ended_at, NOW()) AS ended_at
    FROM session s
    JOIN fact_conversation fc
      ON fc.conversation_id = s.conversation_id
),
msg_agg AS (
    SELECT
        cb.session_id,
        COUNT(*) AS total_messages,
        COUNT(*) FILTER (WHERE fm.sender_type = 'user') AS user_messages,
        COUNT(*) FILTER (WHERE fm.sender_type = 'bot')  AS bot_messages,
        EXTRACT(EPOCH FROM (MAX(fm.sent_at) - MIN(fm.sent_at)))::INT AS duration_seconds
    FROM convo_base cb
    JOIN fact_message fm
      ON fm.conversation_id = cb.conversation_id
    GROUP BY cb.session_id
),
flags AS (
    SELECT
        cb.session_id,
        NOT fc.is_escalated_to_agent AS is_contained,
        fc.is_escalated_to_agent     AS has_escalation
    FROM convo_base cb
    JOIN fact_conversation fc
      ON fc.conversation_id = cb.conversation_id
)
INSERT INTO session_metrics (
    session_id,
    total_messages,
    user_messages,
    bot_messages,
    duration_seconds,
    is_short_conversation,
    is_contained,
    has_escalation
)
SELECT
    m.session_id,
    m.total_messages,
    m.user_messages,
    m.bot_messages,
    m.duration_seconds,
    -- short conversation rule: < 3 messages OR duration < 60 seconds
    (m.total_messages < 3 OR m.duration_seconds < 60) AS is_short_conversation,
    f.is_contained,
    f.has_escalation
FROM msg_agg m
JOIN flags f USING (session_id)
ON CONFLICT (session_id) DO UPDATE
SET
    total_messages        = EXCLUDED.total_messages,
    user_messages         = EXCLUDED.user_messages,
    bot_messages          = EXCLUDED.bot_messages,
    duration_seconds      = EXCLUDED.duration_seconds,
    is_short_conversation = EXCLUDED.is_short_conversation,
    is_contained          = EXCLUDED.is_contained,
    has_escalation        = EXCLUDED.has_escalation,
    computed_at           = NOW();

-- Session feedback table (optional but recommended)
--   To store CSAT inputs directly, then mirror into session_metrics:

CREATE TABLE session_feedback (
    session_id      UUID PRIMARY KEY REFERENCES session(session_id),
    rating          INT CHECK (rating BETWEEN 1 AND 5),
    comment         TEXT,
    sentiment       JSONB,            -- derived NLP sentiment on comment
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- You can then periodically join session_feedback into session_metrics:

UPDATE session_metrics sm
SET
    csat_rating   = sf.rating,
    csat_comment  = sf.comment,
    csat_sentiment= sf.sentiment
FROM session_feedback sf
WHERE sf.session_id = sm.session_id;