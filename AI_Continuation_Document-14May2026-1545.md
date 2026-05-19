# PROJECT CONTINUATION DOCUMENT
## Session 3 — 14 May 2026

---

### 1. PROJECT IDENTITY

- **Project Name:** URA Core
- **What This Project Is:** An internal ERP mobile/web app built in Flutter for a logistics/delivery business. It manages orders, reps, entities (clients), inventory, and team communication. Used by managers, verifiers, reps, and storage staff.
- **Primary Objective:** Deliver a production-ready internal operations platform — order lifecycle management, real-time chat, role-based dashboards, and automated notifications.
- **Strategic Intent:** Replace manual coordination (phone calls, WhatsApp groups) with a structured ERP tool. Chat is intentionally designed to complement WhatsApp (not replace it) for file sharing.
- **Hard Constraints:**
  - Flutter + Supabase only. No Firebase for data (Firebase is messaging/notifications only).
  - BLoC/Cubit pattern exclusively for state management (no Provider, Riverpod, etc.).
  - `AppResult<T>` sealed class (`AppSuccess` / `AppFailure`) for all async results — never raw try/catch in UI.
  - GetIt (`sl<T>()`) for dependency injection throughout.
  - Arabic-first UI with RTL layout. Tajawal font. All user-facing strings in Arabic.
  - `flutter analyze` must remain at zero errors before any commit.

---

### 2. WHAT EXISTS RIGHT NOW

**Built and working:**
- Auth flow: register (with mandatory WhatsApp phone), login, pending-approval gate, password reset, session persistence.
- Role-based routing: manager, verifier, rep, storageActor each get a distinct home screen.
- Verifier dashboard: order creation, entity/rep picker, order templates (fingerprint-based deduplication), order status management.
- Manager dashboard: stats screen (`fl_chart`), user orders view, pending-user approval.
- Real-time chat — full Phase 1 + Phase 2 feature set (see §4 for detail).
- Notifications: Firebase Messaging + local notifications + in-app badge counts.
- Profile screen: read-only for others, editable phone for self (with mandatory-phone guard).
- Settings screen (basic).
- Splash screen (native, both light/dark).

**Partially built / needs attention:**
- `lib/features/chat/data/chat_storage_service.dart` — **still exists on disk** but is completely dead code (no imports, not referenced anywhere). Should be deleted. `flutter analyze` passes only because it is unreferenced, not because it was cleaned up.
- System messages toggle in `ThreadMembersScreen` requires the thread's `system_messages_enabled` column — verified the column exists in the migration, but end-to-end toggle behaviour has not been user-tested yet.

**Broken or blocked:**
- Nothing is currently broken. `flutter analyze` → **No issues found** as of end of this session.
- Supabase Storage bucket `chat-attachments` was intentionally never created (feature was replaced).

**Not started:**
- Push notification deep-linking into a specific chat thread when tapped.
- Order search/filter on manager dashboard.
- Offline / poor-network handling (graceful degradation).
- Any automated tests (unit, widget, integration).

---

### 3. ARCHITECTURE & TECHNICAL MAP

**Tech stack:**
| Layer | Choice |
|---|---|
| UI | Flutter 3.x, Material 3, `google_fonts` (Tajawal) |
| State | `flutter_bloc` — Cubits only |
| Backend | Supabase (Postgres + Realtime + Auth + RPC functions) |
| DI | `get_it` (`sl<T>()`) — all repos/cubits registered in `lib/core/di/injection.dart` |
| Routing | `go_router` — routes defined in `lib/router/app_router.dart` |
| Notifications | Firebase Messaging + `flutter_local_notifications` |
| Charts | `fl_chart` |
| Fonts | `google_fonts` (Tajawal) |
| URL launch | `url_launcher` ^6.3.0 |
| Image pick | `image_picker` (kept for potential future use, currently only used nowhere post-refactor) |

**Key files:**
```
lib/
  app.dart                          # MaterialApp.router + ThemeData (Tajawal font set here)
  core/
    di/injection.dart               # GetIt registrations — all singletons/factories here
    errors/app_result.dart          # AppSuccess<T> / AppFailure sealed classes
    errors/error_handler.dart       # Maps Supabase/Dart exceptions → AppError
    logging/app_logger.dart         # Logger singleton
  router/app_router.dart            # go_router config + role-based redirect guard
  shared/
    models/
      chat_message.dart             # ChatMessage + ChatMessageReaction + ChatMessageType enum
      chat_thread.dart              # ChatThread (includes lastMessage* + systemMessagesEnabled)
      profile.dart                  # Profile (id, fullName, phone?, role, isApproved)
      order.dart                    # Order model + OrderStatus enum
  features/
    auth/
      data/auth_repository.dart     # signIn, signUp(+phone), signOut, updatePhone, resetPassword
      logic/auth_cubit.dart         # Manages AuthState; signUp now takes phone param
      ui/register_screen.dart       # Has mandatory phone field (validated before API call)
    chat/
      data/chat_repository.dart     # All Supabase queries; RPCs: get_threads_with_preview,
                                    #   send_chat_message, get_thread_reactions, etc.
      data/chat_storage_service.dart  ⚠️ DEAD FILE — delete this
      logic/chat_thread_cubit.dart  # Single-thread state; reactions (optimistic), reply-to
      logic/chat_threads_cubit.dart # Thread list state
      ui/chat_hub_screen.dart       # Thread list + live client-side search
      ui/chat_thread_screen.dart    # Message view; WhatsApp attach; reply strip; input bar
      ui/thread_members_screen.dart # Member list + system-messages toggle (creator only)
      ui/widgets/chat_message_bubble.dart  # Full Phase 2 bubble: swipe, reactions, system pill,
                                           #   reply block, order card, long-press sheet
    profile/ui/profile_screen.dart  # StatefulWidget; phone editable for isSelf
supabase/
  migrations/
    20260510_order_templates.sql    # order_templates + order_template_items tables
    phase2_chat_upgrade.sql         # All Phase 2 chat schema + RPCs + triggers (APPLIED)
```

**Core logic flow (chat message send):**
1. User types in `chat_thread_screen.dart` → taps send → `_send()` called
2. `_send()` reads `_replyTarget`, `_pendingMention*`, `_isUrgentOverride` from local state
3. Calls `context.read<ChatThreadCubit>().sendMessage(...)` with all params
4. Cubit calls `ChatRepository.sendMessage(...)` → `_supabase.rpc('send_chat_message', params: {...})`
5. Supabase RPC inserts into `chat_messages`; Realtime fires the `.stream()` subscription
6. `subscribeToThread()` stream emits → cubit calls `_emitMerged()` → merges `_reactions` map into messages → `emit(ChatThreadLoaded(...))`
7. `BlocBuilder` rebuilds `ListView` → new `ChatMessageBubble` rendered

**Core logic flow (WhatsApp attach):**
1. User taps paperclip icon → `_openWhatsApp()` called
2. If `widget.isDirect`: calls `_otherParticipant()` → gets their `Profile.phone` → `launchUrl('https://wa.me/$number')`
3. If group: shows `_WhatsAppMemberSheet` bottom sheet listing `_threadMembers` sorted by (has phone, no phone) → tap → `launchUrl`

**Naming conventions:**
- Cubits: `FeatureCubit` / states: `FeatureLoading`, `FeatureLoaded`, `FeatureError`
- Repository methods: verb + noun (`getThreads`, `sendMessage`, `addReaction`)
- SQL RPCs: snake_case (`get_threads_with_preview`, `send_chat_message`)
- Private widgets in a file: prefixed `_` (`_ChatHubBody`, `_WhatsAppMemberSheet`)

---

### 4. RECENT WORK — WHAT JUST HAPPENED (HIGH PRIORITY)

**This session covered three areas:**

#### A. Chat Feature Overhaul (Phase 1 + Phase 2)
All features from a research document ("Comparative Analysis of Consumer Messaging Paradigms") were implemented:

| Feature | Status | Key File |
|---|---|---|
| Thread last-message preview | ✅ Done | `get_threads_with_preview` RPC + `chat_hub_screen.dart` |
| Live thread search | ✅ Done | `chat_hub_screen.dart` (client-side filter) |
| Tajawal font + 1.5x line-height | ✅ Done | `app.dart`, `chat_message_bubble.dart` |
| RTL send icon flip | ✅ Done | `Transform.flip` in `chat_thread_screen.dart` |
| Smart input bar (attach left, @/urgent/send right) | ✅ Done | `chat_thread_screen.dart` |
| Long-press context menu + emoji quick-pick | ✅ Done | `chat_message_bubble.dart` → `_ContextSheet` |
| Swipe-to-reply (RTL-aware, haptic) | ✅ Done | `chat_message_bubble.dart` GestureDetector |
| Reply strip above input + quoted block in bubble | ✅ Done | `chat_thread_screen.dart` + `chat_message_bubble.dart` |
| System messages (order status → gray pill) | ✅ Done | DB trigger + `ChatMessageType.system` bubble rendering |
| System messages toggle (per-thread, creator only) | ✅ Done | `thread_members_screen.dart` SwitchListTile |
| Emoji reactions (optimistic, toggleable) | ✅ Done | Cubit + `chat_message_bubble.dart` Wrap chips |
| Order mention rich card | ✅ Done | `_buildOrderCard()` in bubble |

#### B. WhatsApp Redirect (replaced file upload)
**Decision:** Supabase Storage was never provisioned. Instead of uploading files, the attach button opens WhatsApp directly to the contact's number. Reasoning: zero storage cost, zero infra, team already uses WhatsApp for file sharing.

- `file_picker` and `open_file` packages **removed** from `pubspec.yaml`
- `url_launcher` ^6.3.0 **added**
- `ChatStorageService.uploadAttachment` / `sendAttachment` cubit method **removed**
- `ChatThreadLoaded.uploadingAttachment` field **removed**
- `_showAttachmentPicker()` → replaced with `_openWhatsApp()` + `_launchWhatsApp()` + `_WhatsAppMemberSheet`
- `chat_message_bubble.dart` file-open tap: `OpenFile.open()` → `launchUrl()` (for any legacy attachment messages that might exist in DB)

#### C. Mandatory WhatsApp Phone Number
**Registration:** `register_screen.dart` now has a `_phoneController` field. Phone is validated non-empty client-side before calling the API. `AuthCubit.signUp()` and `AuthRepository.signUp()` both now accept `phone` as a required param. Profile insert includes `'phone': phone`.

**Profile editing:** `ProfileScreen` converted from `StatelessWidget` to `StatefulWidget`. Holds local `_phone` state. When `isSelf == true`, the phone `ListTile` shows an edit pencil. Tapping opens `_EditPhoneDialog` — pre-filled, empty submission blocked with error text. On save: calls `AuthRepository.updatePhone(uid, newPhone)` → updates DB → `setState` + `AuthCubit.refreshProfile()`.

#### D. VS Code Launch Config Fix
Edge config was missing `--web-browser-flag --no-sandbox` (same flag Chrome uses). Added. Firefox/web-server is a fundamental limitation — VS Code has no browser protocol to auto-refresh Firefox on restart; user must press F5 in Firefox manually after a full restart.

**SQL migration issues resolved this session:**
- `phase2_chat_upgrade.sql` had a function ordering bug: `get_threads_with_preview()` referenced `t.system_messages_enabled` before the `ALTER TABLE` that added the column. Fixed by moving the function definition to the bottom of the file (after all `ALTER TABLE` statements).
- `20260510_order_templates.sql` had `CREATE POLICY IF NOT EXISTS` syntax (invalid in PostgreSQL). Was already fixed in the file on disk; user was pasting an older version. File is correct.
- Both migrations have been successfully applied to the Supabase project.

---

### 5. WHAT COULD GO WRONG

**Known issues:**
- `lib/features/chat/data/chat_storage_service.dart` still exists on disk. It is dead code (no imports). `flutter analyze` passes because it's unreferenced. Should be deleted with `del lib\features\chat\data\chat_storage_service.dart`. Low risk if left, but confusing.
- `image_picker` is still in `pubspec.yaml` (was kept from before). It is not currently used anywhere in the codebase. Can be removed if desired, but leaving it does no harm.

**Edge cases to watch:**
- WhatsApp direct thread: if `_threadMembers` hasn't loaded yet when the user taps attach (race condition on `_loadMentionData`), `_otherParticipant()` returns `null` → snackbar "لا يوجد رقم واتساب لهذا المستخدم". This is acceptable UX but worth monitoring.
- Phone numbers in DB may not be in international format (e.g., stored as `0501234567` instead of `9665XXXXXXXX`). The WhatsApp URL `https://wa.me/0501234567` would fail. There is no validation enforcing international format — only client-side non-empty check. Consider adding format hint and stripping leading zeros.
- System messages trigger uses sender_id = `'00000000-0000-0000-0000-000000000000'::uuid`. This UUID must not correspond to a real user; confirm it doesn't exist in `auth.users`.
- The `chat_audit_log` table's `actor_id` references no FK (intentionally, to allow system UUID). Verify RLS is set correctly on this table — it was created without RLS policies in the migration.

**Technical debt:**
- No tests of any kind exist.
- `AuthRepository` is not injected via interface — directly instantiated via GetIt. Difficult to mock.
- `ChatRepository` instantiates `SupabaseClient` directly in the class body rather than via constructor injection.
- `_loadMentionData()` in `chat_thread_screen.dart` catches all errors silently (`catch (_)`). Mention data failures are invisible to the user.

**Assumptions that could be wrong:**
- The `profiles` table has a `phone` column — this was assumed from `Profile.fromMap` parsing `map['phone']`. If the column doesn't exist in the actual DB schema (pre-existing rows), `updatePhone` will succeed but `fetchProfile` won't return it unless the column exists. Verify with `SELECT column_name FROM information_schema.columns WHERE table_name='profiles' AND column_name='phone';`
- The emulator (API 36) listed in `launch.json` as `"emulator-5554"` may not be running when needed. It wasn't listed in `flutter devices` at the time of this session.

---

### 6. HOW TO THINK ABOUT THIS PROJECT

**1. Core architectural pattern:**
Repository → Cubit → UI, with `AppResult<T>` as the universal return type for async operations. Every repository method returns `AppResult` — never throws. The Cubit maps `AppSuccess` / `AppFailure` and emits the appropriate state. UI consumes state via `BlocBuilder` / `BlocConsumer`. This pattern was chosen for consistency and testability — every failure path is explicit.

**2. Most common mistake a new person would make:**
Adding error handling in the UI layer directly (try/catch in widget code) or returning raw data from a repository instead of wrapping in `AppResult`. The whole system relies on the Cubit being the sole handler of errors. Breaking this means error states stop appearing and failures become silent.

**3. What looks like it should be refactored but should NOT be:**
The `_loadMentionData()` method in `chat_thread_screen.dart` looks like it belongs in the Cubit. It doesn't — it's intentionally in the View layer because mention data (members + active orders) is UI concern only (autocomplete), not message-sending concern. Moving it to the Cubit would couple the thread state to mention data, creating unnecessary re-renders every time the mention list loads.

---

### 7. DO NOT TOUCH LIST

- **Do NOT** refactor `AppResult` / `ErrorHandler` — stable pattern used everywhere.
- **Do NOT** switch routing away from `go_router` or restructure `app_router.dart` routes without full audit of all `context.go()` / `context.push()` calls.
- **Do NOT** remove the `image_picker` dependency without confirming nothing in the codebase references it.
- **Do NOT** create the `chat-attachments` Supabase Storage bucket — the feature was intentionally replaced with WhatsApp redirect.
- **Do NOT** add any new packages without checking: (a) whether an existing package already covers it, (b) pub.dev compatibility with the current Flutter/Dart SDK constraint (`sdk: ^3.11.3`).
- **Do NOT** change the `send_chat_message` RPC signature in Supabase without updating `ChatRepository.sendMessage()` params to match.
- **Do NOT** alter the `get_threads_with_preview` RPC ordering logic — threads are sorted by `COALESCE(last_message_at, created_at) DESC`, intentionally falling back to `created_at` for threads with no messages.
- **Preserve** the `ChatMessageType` enum values (`user`, `system`, `action`) — these map directly to the `message_type` column default values in the DB.
- **Preserve** the optimistic reaction update pattern in `ChatThreadCubit` — rollback on failure is intentional and must remain symmetric.
- **Ask before** adding any new Supabase RPC functions — they require DB migration coordination.

---

### 8. CONFIDENCE & FRESHNESS

| Area | Confidence | Notes |
|---|---|---|
| Chat Phase 1 + Phase 2 Flutter code | ✅ HIGH | Built and verified this session; `flutter analyze` clean |
| Phase 2 SQL migrations applied to Supabase | ✅ HIGH | Both files ran successfully; ordering bug fixed |
| WhatsApp redirect implementation | ✅ HIGH | Built and verified this session |
| Mandatory phone on register | ✅ HIGH | Built and verified this session |
| Phone editable in profile (not removable) | ✅ HIGH | Built and verified this session |
| `profiles.phone` column exists in live DB | ⚠️ MEDIUM | Inferred from `Profile.fromMap` parsing it; not directly confirmed via SQL |
| Auth flow (login/register/session) | ⚠️ MEDIUM | Existed before this session; not re-tested |
| Verifier dashboard (order templates, etc.) | ⚠️ MEDIUM | Existed before this session; not touched |
| Manager dashboard / stats | ⚠️ MEDIUM | Existed before this session; not touched |
| Notification system (Firebase + badges) | ⚠️ MEDIUM | Existed before this session; not touched |
| System messages end-to-end (trigger fires) | ❓ LOW | SQL trigger written and applied but not user-tested live |
| `chat_audit_log` RLS | ❓ LOW | Table created but no RLS policies written for it |
