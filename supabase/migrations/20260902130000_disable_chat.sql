-- Turn the in-app chat off at the server.
--
-- Chat was built and shipped but never actually used in production. An audit on
-- 2026-09-02 found that the send path the app calls -- the 14-argument
-- send_chat_message -- had lost the "is this caller even in this thread?" check
-- that its older 7-argument sibling still carried. Both are SECURITY DEFINER,
-- and chat_messages' only INSERT policy is `deny_direct_message_insert`, so the
-- function was the sole gatekeeper and the gate was open: any signed-in user
-- with a thread id could post into any thread in the system. (Anonymous callers
-- were stopped only incidentally, by sender_name being NOT NULL.)
--
-- Rather than repair a feature nobody was using, chat is switched off at both
-- ends: `kChatEnabled` in lib/core/config/feature_flags.dart hides every entry
-- point in the app, and this migration makes the server refuse chat traffic
-- regardless of what any client tries.
--
-- NOTHING IS DROPPED. All five chat tables keep their columns, policies,
-- indexes and triggers; all chat functions except one dead overload survive.
-- The Dart code is untouched too -- all 22 files under lib/features/chat/ are
-- still there. Only the privileges and the test rows go.
--
-- ---------------------------------------------------------------------------
-- TO TURN CHAT BACK ON, run this, then set kChatEnabled = true and rebuild.
-- Fix the missing authorization check in send_chat_message BEFORE you do --
-- restoring these grants without it re-opens the hole described above.
--
--   GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
--     public.chat_threads, public.chat_messages,
--     public.chat_thread_participants, public.chat_message_reactions,
--     public.chat_audit_log
--     TO anon, authenticated;
--
--   GRANT EXECUTE ON FUNCTION
--     public.acknowledge_chat_message(uuid),
--     public.create_chat_thread(text),
--     public.delete_chat_thread(uuid),
--     public.get_or_create_direct_thread(uuid),
--     public.get_thread_participants(uuid),
--     public.get_thread_reactions(uuid),
--     public.get_threads_with_preview(),
--     public.remove_thread_participant(uuid, uuid),
--     public.send_chat_message(uuid, text, uuid, text, uuid, text, boolean,
--                              uuid, text, text, text, text, text, bigint)
--     TO anon, authenticated;
--
--   ALTER PUBLICATION supabase_realtime ADD TABLE
--     public.chat_threads, public.chat_messages,
--     public.chat_thread_participants, public.chat_message_reactions;
--
--   CREATE TRIGGER trg_order_status_chat_message
--     AFTER UPDATE ON public.orders
--     FOR EACH ROW EXECUTE FUNCTION public.auto_post_order_status_message();
-- ---------------------------------------------------------------------------

-- 1. The orders -> chat coupling has to go FIRST.
--
-- trg_order_status_chat_message fires on every row update of orders and INSERTs
-- into chat_messages. Triggers run as the calling user, so revoking INSERT
-- below while this still existed would make ordinary order status changes start
-- failing outright -- taking down the app's core flow to disable a feature
-- nobody uses. The function itself (auto_post_order_status_message) is kept so
-- the trigger can simply be recreated; only the attachment to orders is removed.
DROP TRIGGER IF EXISTS "trg_order_status_chat_message" ON "public"."orders";

-- 2. Drop the dead 7-argument send_chat_message overload.
--
-- It is unreachable from the app (ChatRepository always sends all fourteen
-- named params, so PostgREST resolves to the other one) and it is the last
-- thing that should survive a chat shutdown: SECURITY DEFINER, granted to anon,
-- and the only remaining path that writes chat_messages. This is dropped rather
-- than merely revoked because nothing should ever call it again -- if chat comes
-- back, its access check belongs in the 14-arg version, which is the one the
-- app actually uses.
DROP FUNCTION IF EXISTS "public"."send_chat_message"(
  "p_thread_id" "uuid",
  "p_content" "text",
  "p_order_mention_id" "uuid",
  "p_order_mention_text" "text",
  "p_user_mention_id" "uuid",
  "p_user_mention_text" "text",
  "p_is_urgent" boolean
);

-- 3. Stop realtime from broadcasting chat.
--
-- Realtime does respect RLS, but leaving the tables published means the server
-- keeps doing replication work for a dead feature, and it is one more surface
-- that has to be reasoned about. Off is simpler than argued-safe.
ALTER PUBLICATION "supabase_realtime" DROP TABLE "public"."chat_threads";
ALTER PUBLICATION "supabase_realtime" DROP TABLE "public"."chat_messages";
ALTER PUBLICATION "supabase_realtime" DROP TABLE "public"."chat_thread_participants";
ALTER PUBLICATION "supabase_realtime" DROP TABLE "public"."chat_message_reactions";

-- 4. Take the tables away from the API roles.
--
-- This is what actually closes the hole: with no table privileges and no
-- callable RPC, there is no route to chat data through PostgREST for either an
-- anonymous or a signed-in caller. `postgres` and `service_role` keep their
-- access, so admin_delete_organization (which cleans chat rows as part of
-- deleting an org, and is NOT a chat feature) keeps working.
REVOKE ALL ON TABLE "public"."chat_threads" FROM "anon", "authenticated";
REVOKE ALL ON TABLE "public"."chat_messages" FROM "anon", "authenticated";
REVOKE ALL ON TABLE "public"."chat_thread_participants" FROM "anon", "authenticated";
REVOKE ALL ON TABLE "public"."chat_message_reactions" FROM "anon", "authenticated";
REVOKE ALL ON TABLE "public"."chat_audit_log" FROM "anon", "authenticated";

-- 5. Take the RPCs away from the API roles.
--
-- PUBLIC is revoked alongside the two named roles because Postgres grants
-- EXECUTE to PUBLIC by default on every new function -- revoking anon and
-- authenticated alone would leave that default in place and change nothing.
--
-- The three trigger functions (auto_post_order_status_message, log_chat_event,
-- notify_chat_message) are deliberately left alone: they are only ever invoked
-- by triggers, never by a client, so their grants are irrelevant.
REVOKE EXECUTE ON FUNCTION "public"."acknowledge_chat_message"("uuid")
  FROM PUBLIC, "anon", "authenticated";
REVOKE EXECUTE ON FUNCTION "public"."create_chat_thread"("text")
  FROM PUBLIC, "anon", "authenticated";
REVOKE EXECUTE ON FUNCTION "public"."delete_chat_thread"("uuid")
  FROM PUBLIC, "anon", "authenticated";
REVOKE EXECUTE ON FUNCTION "public"."get_or_create_direct_thread"("uuid")
  FROM PUBLIC, "anon", "authenticated";
REVOKE EXECUTE ON FUNCTION "public"."get_thread_participants"("uuid")
  FROM PUBLIC, "anon", "authenticated";
REVOKE EXECUTE ON FUNCTION "public"."get_thread_reactions"("uuid")
  FROM PUBLIC, "anon", "authenticated";
REVOKE EXECUTE ON FUNCTION "public"."get_threads_with_preview"()
  FROM PUBLIC, "anon", "authenticated";
REVOKE EXECUTE ON FUNCTION "public"."remove_thread_participant"("uuid", "uuid")
  FROM PUBLIC, "anon", "authenticated";
REVOKE EXECUTE ON FUNCTION "public"."send_chat_message"(
  "uuid", "text", "uuid", "text", "uuid", "text", boolean,
  "uuid", "text", "text", "text", "text", "text", bigint
) FROM PUBLIC, "anon", "authenticated";

-- 6. Clear the test rows.
--
-- Explicitly requested: chat was only ever exercised in testing, nothing in
-- these tables is real business data. The tables themselves stay so the schema
-- is ready if chat returns. One TRUNCATE listing all five satisfies the foreign
-- keys between them without needing CASCADE -- and CASCADE would be wrong to
-- reach for anyway, since it is confirmed that no table outside chat references
-- these.
TRUNCATE TABLE
  "public"."chat_message_reactions",
  "public"."chat_audit_log",
  "public"."chat_messages",
  "public"."chat_thread_participants",
  "public"."chat_threads";
