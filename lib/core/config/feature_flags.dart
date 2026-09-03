/// Build-time switches for features that are shipped but deliberately turned
/// off. A flag here is not a user setting and not remote config -- flipping one
/// requires a rebuild, which is the point: these gate whole features, not
/// preferences.
library;

/// Whether the in-app chat is reachable.
///
/// Turned off 2026-09-02. Chat was built and shipped but never actually used in
/// production, and an audit found its send path had lost its "is this person
/// even in this thread?" check, letting any signed-in user post into any
/// thread. Rather than repair a feature nobody was using, the whole thing was
/// switched off at both ends: this flag hides every entry point, and migration
/// `20260902130000_disable_chat.sql` revokes the database privileges so the
/// server refuses chat traffic even if a client tries anyway.
///
/// **None of the chat code was deleted.** All 22 files under
/// `lib/features/chat/` plus the models in `lib/shared/models/` are intact, and
/// the chat tables still exist (emptied of their test rows). To bring chat
/// back: set this to `true` and run the re-enable SQL written out in that
/// migration's header comment. Fix the missing authorization check in
/// `send_chat_message` before you do.
const bool kChatEnabled = false;
