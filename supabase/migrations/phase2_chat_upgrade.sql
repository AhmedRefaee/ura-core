-- ============================================================
-- Phase 2 schema additions (run BEFORE function definitions)
-- ============================================================

-- 1. system_messages_enabled flag on threads
ALTER TABLE chat_threads
  ADD COLUMN IF NOT EXISTS system_messages_enabled BOOL NOT NULL DEFAULT TRUE;

-- 2. message_type (user | system | action)
ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS message_type TEXT NOT NULL DEFAULT 'user';

-- 3. Reply-to (denormalized to preserve streaming without joins)
ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS reply_to_id      UUID REFERENCES chat_messages(id),
  ADD COLUMN IF NOT EXISTS reply_to_content TEXT,
  ADD COLUMN IF NOT EXISTS reply_to_sender  TEXT;

-- 4. Action payload (Block Kit-style JSON cards)
ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS action_payload JSONB;

-- 5. Attachment columns (files stored in Supabase Storage bucket 'chat-attachments')
ALTER TABLE chat_messages
  ADD COLUMN IF NOT EXISTS attachment_url        TEXT,
  ADD COLUMN IF NOT EXISTS attachment_type       TEXT,
  ADD COLUMN IF NOT EXISTS attachment_name       TEXT,
  ADD COLUMN IF NOT EXISTS attachment_size_bytes BIGINT;

-- 6. Emoji reactions table
CREATE TABLE IF NOT EXISTS chat_message_reactions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES auth.users(id),
  emoji      TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(message_id, user_id, emoji)
);
ALTER TABLE chat_message_reactions ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'chat_message_reactions' AND policyname = 'Users can read reactions'
  ) THEN
    CREATE POLICY "Users can read reactions"
      ON chat_message_reactions FOR SELECT USING (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'chat_message_reactions' AND policyname = 'Users can manage own reactions'
  ) THEN
    CREATE POLICY "Users can manage own reactions"
      ON chat_message_reactions
      FOR ALL
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- 7. Chat audit log (written by DB triggers only; regular users cannot read)
CREATE TABLE IF NOT EXISTS chat_audit_log (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type TEXT NOT NULL,
  thread_id  UUID REFERENCES chat_threads(id),
  message_id UUID REFERENCES chat_messages(id),
  actor_id   UUID NOT NULL,
  payload    JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);


-- ============================================================
-- RPC: update send_chat_message to accept new params
-- Replace existing function signature
-- ============================================================

CREATE OR REPLACE FUNCTION send_chat_message(
  p_thread_id         UUID,
  p_content           TEXT,
  p_order_mention_id  UUID     DEFAULT NULL,
  p_order_mention_text TEXT    DEFAULT NULL,
  p_user_mention_id   UUID     DEFAULT NULL,
  p_user_mention_text  TEXT    DEFAULT NULL,
  p_is_urgent         BOOL     DEFAULT FALSE,
  p_reply_to_id       UUID     DEFAULT NULL,
  p_reply_to_content  TEXT     DEFAULT NULL,
  p_reply_to_sender   TEXT     DEFAULT NULL,
  p_attachment_url    TEXT     DEFAULT NULL,
  p_attachment_type   TEXT     DEFAULT NULL,
  p_attachment_name   TEXT     DEFAULT NULL,
  p_attachment_size_bytes BIGINT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_sender_id   UUID := auth.uid();
  v_sender_name TEXT;
BEGIN
  SELECT full_name INTO v_sender_name FROM profiles WHERE id = v_sender_id;

  INSERT INTO chat_messages (
    id, thread_id, sender_id, sender_name, content,
    order_mention_id, order_mention_text,
    user_mention_id,  user_mention_text,
    is_urgent,
    reply_to_id, reply_to_content, reply_to_sender,
    attachment_url, attachment_type, attachment_name, attachment_size_bytes,
    message_type, created_at
  ) VALUES (
    gen_random_uuid(), p_thread_id, v_sender_id, v_sender_name, p_content,
    p_order_mention_id, p_order_mention_text,
    p_user_mention_id,  p_user_mention_text,
    p_is_urgent,
    p_reply_to_id, p_reply_to_content, p_reply_to_sender,
    p_attachment_url, p_attachment_type, p_attachment_name, p_attachment_size_bytes,
    'user', now()
  );
END;
$$;


-- ============================================================
-- Trigger: auto-post system message on order status change
-- ============================================================

CREATE OR REPLACE FUNCTION auto_post_order_status_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO chat_messages (
      id, thread_id, sender_id, sender_name, content,
      order_mention_id, message_type, created_at
    )
    SELECT
      gen_random_uuid(),
      cm.thread_id,
      '00000000-0000-0000-0000-000000000000'::uuid,
      'النظام',
      'تغيّرت حالة الطلب إلى: ' || NEW.status,
      NEW.id,
      'system',
      now()
    FROM (
      SELECT DISTINCT cm2.thread_id
      FROM   chat_messages cm2
      JOIN   chat_threads  ct ON ct.id = cm2.thread_id
      WHERE  cm2.order_mention_id = NEW.id
        AND  cm2.message_type     = 'user'
        AND  ct.system_messages_enabled = TRUE
    ) cm;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_status_chat_message ON orders;
CREATE TRIGGER trg_order_status_chat_message
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION auto_post_order_status_message();


-- ============================================================
-- Trigger: passive audit log on every chat_messages INSERT/UPDATE
-- ============================================================

CREATE OR REPLACE FUNCTION log_chat_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO chat_audit_log (
    event_type, thread_id, message_id, actor_id, payload, created_at
  ) VALUES (
    CASE WHEN TG_OP = 'INSERT' THEN 'message_sent' ELSE 'message_updated' END,
    NEW.thread_id,
    NEW.id,
    NEW.sender_id,
    jsonb_build_object(
      'content_length', length(NEW.content),
      'is_urgent',      NEW.is_urgent,
      'message_type',   NEW.message_type
    ),
    now()
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chat_audit ON chat_messages;
CREATE TRIGGER trg_chat_audit
  AFTER INSERT OR UPDATE ON chat_messages
  FOR EACH ROW
  EXECUTE FUNCTION log_chat_event();


-- ============================================================
-- RPC: get_thread_reactions (used by cubit to merge reactions into messages)
-- ============================================================

CREATE OR REPLACE FUNCTION get_thread_reactions(p_thread_id UUID)
RETURNS TABLE(message_id UUID, user_id UUID, emoji TEXT)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT r.message_id, r.user_id, r.emoji
  FROM   chat_message_reactions r
  JOIN   chat_messages m ON m.id = r.message_id
  WHERE  m.thread_id = p_thread_id;
$$;


-- ============================================================
-- RPC: get_threads_with_preview
-- Must come AFTER system_messages_enabled column is added above
-- ============================================================

CREATE OR REPLACE FUNCTION get_threads_with_preview()
RETURNS TABLE(
  id uuid,
  title text,
  created_by uuid,
  created_at timestamptz,
  is_direct bool,
  system_messages_enabled bool,
  last_message_content text,
  last_message_sender_name text,
  last_message_at timestamptz
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
    m.content        AS last_message_content,
    m.sender_name    AS last_message_sender_name,
    m.created_at     AS last_message_at
  FROM chat_threads t
  LEFT JOIN LATERAL (
    SELECT content, sender_name, created_at
    FROM   chat_messages
    WHERE  thread_id = t.id
    ORDER  BY created_at DESC
    LIMIT  1
  ) m ON true
  ORDER BY COALESCE(m.created_at, t.created_at) DESC;
$$;


-- ============================================================
-- Supabase Storage bucket (run via Supabase dashboard or CLI)
-- ============================================================
-- Create a bucket named 'chat-attachments' with:
--   public: false (use signed URLs)
--   file size limit: 10485760 (10 MB)
--   allowed MIME types: image/*, application/pdf, text/*
--
-- INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
-- VALUES (
--   'chat-attachments',
--   'chat-attachments',
--   false,
--   10485760,
--   ARRAY['image/jpeg','image/png','image/webp','image/gif',
--         'application/pdf','text/plain']
-- )
-- ON CONFLICT (id) DO NOTHING;
