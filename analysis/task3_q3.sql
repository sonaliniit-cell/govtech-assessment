-- Q3.3 Conversation quality signals
-- Short conversation rule:
--   is_short_conversation = (total_messages < 3 OR session_duration_seconds < 60)

WITH per_session AS (
    SELECT
        s.session_id,
        s.ip_address,
        s.session_starttstamp,
        s.session_endtstamp,
        s.website_id,
        COUNT(fm.message_id) AS total_messages,
        EXTRACT(EPOCH FROM (
            COALESCE(s.session_endtstamp, MAX(fm.sent_at)) - s.session_starttstamp
        ))::INT AS session_duration_seconds
    FROM session s
    LEFT JOIN fact_message fm
      ON fm.conversation_id = s.conversation_id
    GROUP BY
        s.session_id,
        s.ip_address,
        s.session_starttstamp,
        s.session_endtstamp,
        s.website_id
),
per_session_with_flag AS (
    SELECT
        session_id,
        ip_address,
        session_starttstamp,
        total_messages,
        session_duration_seconds,
        website_id,
        (total_messages < 3 OR session_duration_seconds < 60) AS is_short_conversation
    FROM per_session
)
-- 1) Per-session outputs
SELECT
    session_id,
    ip_address,
    session_starttstamp,
    total_messages,
    session_duration_seconds,
    is_short_conversation
FROM per_session_with_flag
ORDER BY session_starttstamp;

-- 2) Aggregation by website
-- (You can keep this as a second query in the same file or wrap both parts with CTEs.)

SELECT
    website_id,
    COUNT(*) AS total_sessions,
    COUNT(*) FILTER (WHERE is_short_conversation) AS short_sessions,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE is_short_conversation) / NULLIF(COUNT(*), 0),
        2
    ) AS pct_short_sessions
FROM per_session_with_flag
GROUP BY website_id
ORDER BY pct_short_sessions DESC;