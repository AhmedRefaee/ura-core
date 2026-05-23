-- Fix get_threads_with_preview: add participant filter + require at least one message
--
-- Defect 1 (duplicates): no WHERE clause restricting to threads the caller belongs to.
--   Fix: JOIN chat_thread_participants me ON me.thread_id = t.id AND me.user_id = auth.uid()
--
-- Defect 2 (empty threads in Recent Chats): LEFT JOIN LATERAL on messages allowed
--   zero-message threads through. Fix: change to INNER JOIN LATERAL (no ON CONFLICT alias
--   needed — LATERAL inner join simply excludes rows with no matching messages).

CREATE OR REPLACE FUNCTION public.get_threads_with_preview()
RETURNS TABLE(
  id                    uuid,
  title                 text,
  created_by            uuid,
  created_at            timestamptz,
  is_direct             bool,
  system_messages_enabled bool,
  last_message_content  text,
  last_message_sender_name text,
  last_message_at       timestamptz,
  other_participant_id  uuid,
  other_participant_name text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    t.id,
    t.title,
    t.created_by,
    t.created_at,
    t.is_direct,
    t.system_messages_enabled,
    m.content        AS last_message_content,
    m.sender_name    AS last_message_sender_name,
    m.created_at     AS last_message_at,
    op.id            AS other_participant_id,
    op.full_name     AS other_participant_name
  FROM chat_threads t
  -- ① Only threads the current user belongs to
  JOIN chat_thread_participants me
    ON me.thread_id = t.id
   AND me.user_id   = auth.uid()
  -- ② Only threads that have at least one message (INNER, not LEFT)
  JOIN LATERAL (
    SELECT content, sender_name, created_at
    FROM   chat_messages
    WHERE  thread_id = t.id
    ORDER  BY created_at DESC
    LIMIT  1
  ) m ON true
  -- ③ Other participant name for direct threads only
  LEFT JOIN LATERAL (
    SELECT p.id, p.full_name
    FROM   chat_thread_participants ctp
    JOIN   profiles p ON p.id = ctp.user_id
    WHERE  ctp.thread_id = t.id
      AND  ctp.user_id  != auth.uid()
      AND  t.is_direct   = true
    LIMIT  1
  ) op ON true
  ORDER BY m.created_at DESC;
$$;

REVOKE ALL   ON FUNCTION public.get_threads_with_preview() FROM public;
GRANT  EXECUTE ON FUNCTION public.get_threads_with_preview() TO authenticated;
