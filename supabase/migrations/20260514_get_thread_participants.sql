CREATE OR REPLACE FUNCTION get_thread_participants(p_thread_id UUID)
RETURNS TABLE(
  id          UUID,
  full_name   TEXT,
  phone       TEXT,
  role        TEXT,
  is_approved BOOL,
  created_at  TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT
    p.id,
    p.full_name,
    p.phone,
    p.role,
    p.is_approved,
    p.created_at
  FROM chat_thread_participants ctp
  JOIN profiles p ON p.id = ctp.user_id
  WHERE ctp.thread_id = p_thread_id
  ORDER BY p.full_name;
$$;
