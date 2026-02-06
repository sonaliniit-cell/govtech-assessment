-- Q3.4 Peak traffic and concurrency
-- For each hour (Asia/Singapore time) on :target_date:
--   1) sessions_started_in_hour
--   2) sessions_active_in_hour (any overlap with the hour window)

WITH params AS (
    SELECT
        (:target_date::date)                          AS target_date,
        (:target_date::date + INTERVAL '1 day')       AS target_date_plus_1
),
session_local AS (
    -- Convert UTC timestamps to Asia/Singapore for bucketing
    SELECT
        s.session_id,
        s.session_starttstamp AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Singapore' AS session_start_local,
        s.session_endtstamp   AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Singapore' AS session_end_local
    FROM session s
),
hours AS (
    -- Generate one row per hour in the target date (local)
    SELECT
        generate_series(
            (target_date)::timestamptz,
            (target_date_plus_1)::timestamptz - INTERVAL '1 hour',
            INTERVAL '1 hour'
        ) AT TIME ZONE 'Asia/Singapore' AS hour_start_local
    FROM params
),
sessions_per_hour AS (
    SELECT
        h.hour_start_local,
        h.hour_start_local + INTERVAL '1 hour' AS hour_end_local,
        COUNT(*) FILTER (
            WHERE
                session_start_local >= h.hour_start_local
                AND session_start_local < h.hour_start_local + INTERVAL '1 hour'
        ) AS sessions_started_in_hour,
        COUNT(*) FILTER (
            WHERE
                -- session overlaps the hour window at any point
                session_start_local < h.hour_start_local + INTERVAL '1 hour'
                AND COALESCE(session_end_local, h.hour_start_local + INTERVAL '1 hour')
                    >= h.hour_start_local
        ) AS sessions_active_in_hour
    FROM hours h
    LEFT JOIN session_local s
      ON s.session_start_local < h.hour_start_local + INTERVAL '1 hour'
         AND COALESCE(s.session_end_local, h.hour_start_local + INTERVAL '1 hour')
             >= h.hour_start_local
    GROUP BY h.hour_start_local
)
SELECT
    hour_start_local AS hour_bucket_local,
    sessions_started_in_hour,
    sessions_active_in_hour
FROM sessions_per_hour
ORDER BY hour_bucket_local;