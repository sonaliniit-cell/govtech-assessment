**1.Data model (Markdown doc)**

**Tables and relationships Main tables:**

dim_website (dimension)

dim_page (dimension)

dim_user (dimension)

dim_language (dimension, optional but handy)

dim_channel (dimension, optional)

fact_conversation (fact – one row per conversation/session)

fact_message (fact – one row per message in a conversation)

**Relationships:**

dim_website 1‑N dim_page

dim_website 1‑N fact_conversation

dim_page 1‑N fact_conversation

dim_user 1‑N fact_conversation

dim_user 1‑N fact_message

dim_language 1‑N dim_user, fact_conversation

dim_channel 1‑N fact_conversation

fact_conversation 1‑N fact_message

**Rationale and trade‑offs Normalization:**

User, website, page, channel, and language are modeled as separate dimensions to avoid duplication, make updates easy, and support re‑use across facts.

Conversations and messages hold foreign keys to these dimensions, which keeps fact rows lean and consistent.

**Scale and querying:**

Conversations and messages are expected to be largest tables; we index on conversation_id, user_id, and timestamps to support analytics and operational queries.

Optionally, you can partition fact_message and fact_conversation by date (created_at) for large volumes.

**stg_conversations:** pre‑parsed conversation‑level info.

**stg_messages:** pre‑parsed message‑level info.

