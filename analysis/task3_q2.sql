-- Q3.2 Idle time between sessions
-- idle_time_seconds = start of current session - end of previous session for same IP.
-- Unit: seconds.

WITH ordered_sessions AS (
    SELECT
        session_id,
        ip_address,
        session_starttstamp,
        session_endtstamp,
        LAG(session_endtstamp) OVER (
            PARTITION BY ip_address
            ORDER BY session_starttstamp
        ) AS prev_session_endtstamp
    FROM session
)
SELECT
    session_id,
    ip_address,
    session_starttstamp,
    prev_session_endtstamp,
    CASE
        WHEN prev_session_endtstamp IS NULL THEN NULL
        ELSE EXTRACT(EPOCH FROM (session_starttstamp - prev_session_endtstamp))::BIGINT
    END AS idle_time_seconds
FROM ordered_sessions
WHERE prev_session_endtstamp IS NOT NULL
ORDER BY ip_address, session_starttstamp;

--(Uses LAG window function to access previous row per IP. )