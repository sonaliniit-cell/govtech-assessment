**session**

One row per conversation/session, core timestamps, IP, user, website, channel.

**session_metrics**

One row per session with derived engagement and success metrics; supports all three defined KPIs.

**session_feedback**

Optional row per session with explicit user rating and comment, used to populate CSAT‑related fields in session_metrics.

**Required fields From Task 1 model:**

fact_conversation.is_escalated_to_agent (boolean).

fact_conversation.status (to filter valid/closed conversations).

fact_conversation.resolved_intent (optional slice by intent category).

dim_website.website_id (to compute per‑website rates).

Time fields started_at, ended_at (for time‑bucketed rates).

**New table proposed below:**

session_feedback.session_id (FK to session / conversation).

session_feedback.rating (INT, e.g. 1–5).

session_feedback.comment (TEXT, optional free‑text).

session_feedback.sentiment (JSONB / label from NLP on comment).

Plus:

fact_conversation.conversation_id (mapped to session_id).

dim_website.website_id for aggregation by website.

**From Task 1 model plus Task 2 session table:**

session.session_id, session_starttstamp, session_endtstamp.

session.ip_address (for grouping per user footprint).

conversation_id link (or session table built directly from fact_conversation).

**From fact_message:**

Count of messages per conversation.

Timestamps of first/last message for accurate duration if needed.

**New aggregated fields (stored in metrics table, see below):**

session_metrics.total_messages.

session_metrics.duration_seconds.

session_metrics.is_short_conversation (boolean).