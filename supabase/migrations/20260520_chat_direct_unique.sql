-- Migration: chat_direct_unique
-- Purpose: enforce DB-level uniqueness on direct 1-to-1 chat threads
--          and replace get_or_create_direct_thread with a race-safe version.
--
-- Scope (ONLY these changes):
--   1. Add direct_pair_key column to chat_threads
--   2. Backfill existing direct threads
--   3. Partial unique index on (direct_pair_key) WHERE is_direct = true
--   4. Replace get_or_create_direct_thread with race-safe, renamed-param version
--
-- NOT changed: create_chat_thread, add_thread_participant,
--              remove_thread_participant, get_threads_with_preview,
--              any order/inventory/status objects.

-- ── 1. Add column ─────────────────────────────────────────────────────────────
ALTER TABLE chat_threads
  ADD COLUMN IF NOT EXISTS direct_pair_key text;

-- ── 2. Backfill existing direct threads ────────────────────────────────────────
-- Uses p1.user_id < p2.user_id to enumerate each pair exactly once.
UPDATE chat_threads t
SET    direct_pair_key = sub.pk
FROM (
  SELECT
    t2.id,
    LEAST(p1.user_id::text, p2.user_id::text)
      || '_' ||
    GREATEST(p1.user_id::text, p2.user_id::text) AS pk
  FROM   chat_threads t2
  JOIN   chat_thread_participants p1 ON p1.thread_id = t2.id
  JOIN   chat_thread_participants p2
         ON  p2.thread_id = t2.id
         AND p2.user_id   > p1.user_id
  WHERE  t2.is_direct = TRUE
) sub
WHERE  sub.id = t.id
AND    t.direct_pair_key IS NULL;

-- Safety: abort if any duplicate pair_keys exist before creating the index.
DO $$
DECLARE dup_count int;
BEGIN
  SELECT COUNT(*) INTO dup_count FROM (
    SELECT direct_pair_key
    FROM   chat_threads
    WHERE  is_direct = TRUE
    AND    direct_pair_key IS NOT NULL
    GROUP  BY direct_pair_key
    HAVING COUNT(*) > 1
  ) x;
  IF dup_count > 0 THEN
    RAISE EXCEPTION
      'Cannot create unique index: % duplicate direct_pair_key value(s) found. '
      'Resolve duplicates before re-running this migration.', dup_count;
  END IF;
END $$;

-- ── 3. Partial unique index ────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS chat_threads_direct_pair_uq
  ON chat_threads(direct_pair_key)
  WHERE is_direct = TRUE;

-- ── 4. Replace get_or_create_direct_thread ─────────────────────────────────────
-- Changes vs. current version:
--   - param renamed from p_verifier_id → p_other_user_id (any role allowed)
--   - lookup now uses direct_pair_key index (O(log n)) instead of 3 subquery EXISTS + COUNT
--   - INSERT uses ON CONFLICT DO NOTHING + re-SELECT to handle concurrent callers
--   - SET search_path = public added for SECURITY DEFINER safety
--
-- Postgres cannot rename a function parameter via CREATE OR REPLACE,
-- so we drop first and immediately recreate within the same transaction.
DROP FUNCTION IF EXISTS public.get_or_create_direct_thread(uuid);

CREATE OR REPLACE FUNCTION public.get_or_create_direct_thread(p_other_user_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_me         uuid := auth.uid();
  v_pair_key   text;
  v_thread_id  uuid;
  v_caller_name text;
  v_other_name  text;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF p_other_user_id = v_me THEN
    RAISE EXCEPTION 'Cannot create a direct thread with yourself';
  END IF;

  -- Stable pair key: LEAST/GREATEST ensures the same key regardless of caller order
  v_pair_key := LEAST(v_me::text, p_other_user_id::text)
             || '_' ||
                GREATEST(v_me::text, p_other_user_id::text);

  -- Fast indexed lookup
  SELECT id INTO v_thread_id
  FROM   chat_threads
  WHERE  is_direct        = TRUE
  AND    direct_pair_key  = v_pair_key;

  IF v_thread_id IS NOT NULL THEN
    RETURN v_thread_id;
  END IF;

  -- Resolve display names for the thread title
  SELECT full_name INTO v_caller_name FROM profiles WHERE id = v_me;
  SELECT full_name INTO v_other_name  FROM profiles WHERE id = p_other_user_id;

  -- Insert with ON CONFLICT to be safe against concurrent callers
  INSERT INTO chat_threads (title, created_by, is_direct, direct_pair_key)
  VALUES (
    COALESCE(v_caller_name, 'مستخدم') || ' — ' || COALESCE(v_other_name, 'موظف'),
    v_me,
    TRUE,
    v_pair_key
  )
  ON CONFLICT (direct_pair_key) WHERE is_direct = TRUE DO NOTHING
  RETURNING id INTO v_thread_id;

  IF v_thread_id IS NULL THEN
    -- Race: another concurrent caller inserted first — re-read
    SELECT id INTO v_thread_id
    FROM   chat_threads
    WHERE  is_direct       = TRUE
    AND    direct_pair_key = v_pair_key;

    RETURN v_thread_id;
  END IF;

  -- Add both participants
  INSERT INTO chat_thread_participants (thread_id, user_id, added_by)
  VALUES
    (v_thread_id, v_me,              v_me),
    (v_thread_id, p_other_user_id,   v_me)
  ON CONFLICT DO NOTHING;

  RETURN v_thread_id;
END;
$function$;

-- Ensure only authenticated users can call it
REVOKE ALL ON FUNCTION public.get_or_create_direct_thread(uuid) FROM public;
GRANT  EXECUTE ON FUNCTION public.get_or_create_direct_thread(uuid) TO authenticated;
