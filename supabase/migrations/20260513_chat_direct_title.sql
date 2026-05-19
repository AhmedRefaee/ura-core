-- Replace get_threads_with_preview to expose other_participant_id and
-- other_participant_name for direct (1-to-1) threads.
--
-- All existing columns, ordering, and SECURITY DEFINER settings are preserved.
-- The two new columns are NULL for group threads.

CREATE OR REPLACE FUNCTION get_threads_with_preview()
RETURNS TABLE(
  id                       uuid,
  title                    text,
  created_by               uuid,
  created_at               timestamptz,
  is_direct                bool,
  system_messages_enabled  bool,
  last_message_content     text,
  last_message_sender_name text,
  last_message_at          timestamptz,
  other_participant_id     uuid,
  other_participant_name   text
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT
    t.id,
    t.title,
    t.created_by,
    t.created_at,
    t.is_direct,
    t.system_messages_enabled,
    m.content      AS last_message_content,
    m.sender_name  AS last_message_sender_name,
    m.created_at   AS last_message_at,
    op.id          AS other_participant_id,
    op.full_name   AS other_participant_name
  FROM chat_threads t
  LEFT JOIN LATERAL (
    SELECT content, sender_name, created_at
    FROM   chat_messages
    WHERE  thread_id = t.id
    ORDER  BY created_at DESC
    LIMIT  1
  ) m ON true
  LEFT JOIN LATERAL (
    SELECT p.id, p.full_name
    FROM   chat_thread_participants ctp
    JOIN   profiles p ON p.id = ctp.user_id
    WHERE  ctp.thread_id = t.id
      AND  ctp.user_id  != auth.uid()
      AND  t.is_direct   = true
    LIMIT  1
  ) op ON true
  ORDER BY COALESCE(m.created_at, t.created_at) DESC;
$$;
