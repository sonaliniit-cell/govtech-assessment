-- Q3.1 Long sessions by IP
-- Duration is computed in seconds using EXTRACT(EPOCH ...).
-- Filter to IPs whose average session duration > 15 minutes (900 seconds).

SELECT
    ip_address,
    AVG(EXTRACT(EPOCH FROM (session_endtstamp - session_starttstamp))) AS avg_session_duration_seconds
FROM session
WHERE session_endtstamp IS NOT NULL
GROUP BY ip_address
HAVING AVG(EXTRACT(EPOCH FROM (session_endtstamp - session_starttstamp))) > 15 * 60
ORDER BY avg_session_duration_seconds DESC;