# PROJECT CONTINUATION DOCUMENT
## Session 3 — 17 May 2026

---

### 1. PROJECT IDENTITY

- **Project Name:** URA Core
- **What This Project Is:** A Flutter mobile app (Android + iOS) for a logistics/distribution company. It manages order lifecycle across four user roles: Verifier (creates orders), Rep (picks up and delivers), Storage Actor (approves inventory), and Manager (oversight). Backend is Supabase (Postgres + Auth + Edge Functions + Realtime).
- **Primary Objective:** Build a production-ready order management and tracking system where each role can perform its stage of the order flow and all users can see a full annotated history of what happened at each step.
- **Strategic Intent:** Replace a manual/paper-based process with a real-time, role-aware digital workflow. Long-term: full traceability, audit trail, and push notifications for every state transition.
- **Hard Constraints:**
  - Flutter only — no web or desktop targets in scope.
  - Supabase is the sole backend. No Firebase for data (Firebase only for push notifications via FCM).
  - All DB mutations go through SECURITY DEFINER RPCs or direct table writes where RLS allows. Never bypass RLS from client.
  - Arabic UI throughout. All user-facing strings are Arabic.
  - BLoC/Cubit pattern for all state management — no Provider, Riverpod, etc.
  - Directory structure: feature-per-folder under `lib/features/`, shared models/widgets under `lib/shared/`.

---

### 2. WHAT EXISTS RIGHT NOW

**Built and working:**
- Full auth flow (Supabase Auth, role-based routing via `go_router`)
- All four role dashboards with Realtime order list subscriptions
- Full order lifecycle: assigned → picked_up → on_the_move → delivered → delivered_to_storage
- Order creation (Verifier), order editing (Verifier, with edit log)
- Storage actor item check flow (`check_order_item`, `approve_transaction`, `storage_confirm_pickup`, `storage_confirm_delivery`)
- Rep flow: `mark_picked_up`, `start_move`, `mark_delivered`
- Chat/communication system per order thread with reactions, mentions, urgent notes
- Push notifications (FCM via Edge Functions `send-push`, `push-on-order-status`, `push-on-chat-message`)
- Shared `OrderStatusTimeline` widget used on ALL four screens (rep, storage, verifier/manager)
- Per-step notes stored in `audit_log` and displayed in the timeline for every user
- Verifier creation notes captured via `orders_log_creation` DB trigger
- Receipt upload and viewer for order items
- Inventory management (CRUD) for storage actors
- Export to Excel (manager)
- Manager stats dashboard
- Splash screen customized

**Partially built:**
- Urgent notes system (DB functions exist, UI exists, but UI integration may not be complete for all states — not verified this session)
- `approve_transaction` function exists in DB but may be a legacy path — `storage_confirm_pickup` is the active one; relationship unclear

**Broken or blocked:**
- Nothing known to be broken after this session's fixes. Previous `22P02` enum cast bug is fixed.

**Not started yet:**
- Offline support / local caching
- Any web admin dashboard
- Manager-level order creation (currently only verifiers create)

---

### 3. ARCHITECTURE & TECHNICAL MAP

**Tech stack:**
- Flutter 3.x, Dart SDK ^3.11.3
- `supabase_flutter: ^2.12.2`
- `flutter_bloc: ^9.1.1` + `equatable`
- `go_router: ^17.1.0`
- `get_it: ^8.0.3` (service locator / DI)
- `firebase_core` + `firebase_messaging` (push only)
- Supabase project ID: `musaqyislgvshurfrjwx` (region: ap-south-1)

**Key DB tables:**
| Table | Purpose |
|---|---|
| `orders` | Core order record. `status` is `order_status` enum. `notes` = verifier's creation notes (do NOT overwrite with step notes). |
| `audit_log` | One row per significant action. Has `action`, `old_status`, `new_status`, `performed_by`, `notes`, `server_timestamp`. |
| `order_items` | Line items per order. Has `check_status` (item_check_status enum), `final_quantity`. |
| `chat_messages` | Per-thread messages. `message_type` is TEXT ('user'/'system'). |
| `chat_threads` | Chat thread per conversation. `system_messages_enabled` flag. |
| `profiles` | User profiles. `role` is `user_role` enum: verifier/rep/storage_actor/manager. |
| `inventory` | Stock items with quantities. |
| `receipts` | Photo receipts uploaded per order_item. |
| `urgent_notes` | Blocking notes attached to orders at a specific stage. |

**Key enums:**
- `order_status`: assigned → picked_up → on_the_move → delivered → delivered_to_storage
- `order_direction`: outbound / inbound_rep / inbound_external
- `user_role`: verifier / rep / storage_actor / manager
- `item_check_status`: pending / checked / rejected

**Key DB functions (RPCs):**
| Function | Who calls it | What it does |
|---|---|---|
| `mark_picked_up(order_id, notes)` | Rep | assigned→picked_up. Backfills notes into audit_log. Does NOT update orders.notes. |
| `start_move(order_id, notes)` | Rep | picked_up→on_the_move. Inserts audit_log entry with notes. Does NOT update orders.notes. |
| `mark_delivered(order_id, notes)` | Rep | on_the_move→delivered. Inserts audit_log entry with notes. Does NOT update orders.notes. |
| `storage_confirm_pickup(order_id, notes, quantities)` | Storage | assigned→picked_up. Decrements inventory. Inserts audit_log entry with old/new status + notes. |
| `storage_confirm_delivery(order_id, notes, quantities)` | Storage | on_the_move or assigned → delivered. Increments inventory. Inserts audit_log with status + notes. |
| `auto_post_order_status_message()` | Trigger (AFTER UPDATE status) | Posts system message to chat threads that mention the order. Fixed: ELSE branch now casts to `::text`. |
| `log_order_created()` | Trigger (AFTER INSERT orders) | Inserts `order_created` audit_log entry with verifier's notes and `performed_by = NEW.created_by`. |
| `log_order_status_change()` | Trigger (AFTER UPDATE orders) | Inserts `status_change` audit_log entry. notes=NULL (step notes come from function-inserted entries). |

**Key Flutter files:**
```
lib/
  shared/
    models/
      order.dart               — Order model + OrderStatus/Direction enums
      audit_log_entry.dart     — AuditLogEntry model
      order_item.dart          — OrderItem model + ItemCheckStatus enum
      profile.dart             — Profile model + UserRole enum
    widgets/
      order_status_timeline.dart  — SHARED timeline widget used by all 4 screens
      order_list_tile.dart
      receipt_viewer_screen.dart
    order_status_theme.dart    — OrderStatus extensions (.icon, .color, .label)
  features/
    rep/
      data/rep_orders_repository.dart    — fetchMyOrders, fetchOrderDetail, fetchAuditLog, mark_* RPCs
      logic/rep_order_detail_cubit.dart  — RepOrderDetailLoaded has: order, receipts, auditLog, communicationHistory, stockItems
      ui/rep_order_detail_screen.dart    — Shows: StatusStepper → Timeline → InfoCard → Items → Action → Chat
    storage/
      data/storage_repository.dart       — fetchAuditLog, confirmPickup, confirmDelivery, item checks
      logic/storage_order_detail_cubit.dart — StorageOrderDetailLoaded has: order, receipts, auditLog, stockItems, pendingStatuses, editedQuantities
      ui/storage_order_detail_screen.dart — Shows: InfoCard → Timeline → Items → Action
    manager/
      data/manager_repository.dart       — fetchOrderDetail, fetchAuditLog, fetchReceipts, fetchPendingUsers, etc.
      logic/task_detail_cubit.dart       — TaskDetailLoaded has: order, auditLog, receipts, stockItems. Has isClosed guards.
      ui/task_detail_screen.dart         — Shows: InfoCard → Timeline → Items → EditHistory → Chat
    verifier/
      data/order_repository.dart         — createOrder (INSERT), fetchOrderForEdit, updateOrder
      logic/create_order_cubit.dart
      ui/create_order_screen.dart
  core/
    di/injection.dart          — GetIt DI setup
    errors/app_result.dart     — AppResult<T> = AppSuccess<T> | AppFailure
    logging/app_logger.dart    — Logger wrapper
```

**Core order flow (outbound with storage):**
1. Verifier creates order → INSERT into orders (status=assigned, notes=verifier_notes) → `log_order_created` trigger fires → audit_log entry created
2. Storage actor reviews items, marks checked/rejected, confirms pickup → `storage_confirm_pickup` RPC → status=picked_up, inventory decremented, audit_log entry with notes
3. Rep starts move → `start_move` RPC → status=on_the_move, audit_log entry with notes
4. Rep delivers → `mark_delivered` RPC → status=delivered, audit_log entry with notes
5. Every status change also fires `log_order_status_change` trigger → additional `status_change` audit_log entry (no notes)
6. Every status change fires `auto_post_order_status_message` → system chat message if thread exists
7. Every status change fires push notification triggers

**`orders.notes` invariant (CRITICAL):** This field stores the verifier's CREATION notes only. Step notes (rep, storage) are stored exclusively in `audit_log.notes`. RPCs `mark_picked_up`, `start_move`, `mark_delivered` were recently fixed to NOT overwrite this field.

**`OrderStatusTimeline` lookup logic:**
- `_entryFor(status)`: Prefers audit_log entries with `newStatus == status AND notes != null`. Falls back to any entry with that `newStatus`.
- `_creationNotes`: Looks for `action == 'order_created'` entry, falls back to `order.notes`.
- Direction-aware: inboundExternal (2 steps), inboundRep (5 steps), outbound (4 steps).

---

### 4. RECENT WORK — WHAT JUST HAPPENED (HIGH PRIORITY)

**What was worked on this session:**

1. **Fixed critical DB bug: enum cast error (22P02)**
   - Trigger `auto_post_order_status_message` had `ELSE NEW.status` (order_status enum) in a CASE expression alongside text literals. PostgreSQL tried to coerce all text branches to the enum. Fix: changed `ELSE NEW.status` → `ELSE NEW.status::text`.
   - Migration: `20260517_fix_order_status_trigger_type_cast.sql`

2. **Built `OrderStatusTimeline` shared widget**
   - File: `lib/shared/widgets/order_status_timeline.dart`
   - Shows per-step notes for: Created (verifier), PickedUp (storage/rep), OnTheMove (rep), Delivered (rep/storage), DeliveredToStorage (storage for inboundRep)
   - Direction-aware step labels and reached conditions
   - Replaced private `_StatusTimeline` that only existed in `task_detail_screen.dart`

3. **Added audit log to rep and storage screens**
   - Added `fetchAuditLog()` to `RepOrdersRepository` and `StorageRepository`
   - Added `auditLog: List<AuditLogEntry>` to `RepOrderDetailLoaded` and `StorageOrderDetailLoaded`
   - Updated both cubits' `load()` to fetch audit log in `Future.wait` (non-fatal failure — shows empty timeline rather than error)
   - Added `OrderStatusTimeline` widget to `rep_order_detail_screen.dart` and `storage_order_detail_screen.dart`

4. **Fixed verifier notes not appearing in timeline**
   - Root cause: No audit_log entry existed for order creation → "Created" step had no notes
   - Also: `start_move`/`mark_delivered`/`mark_picked_up` were overwriting `orders.notes` with rep notes
   - Fix 1: New `orders_log_creation` DB trigger → inserts `order_created` audit_log entry on INSERT to orders
   - Fix 2: Removed `notes = COALESCE(p_notes, notes)` from `mark_picked_up`, `start_move`, `mark_delivered`
   - `_creationNotes` in timeline widget looks up `order_created` entry first, falls back to `order.notes`
   - Migration: `20260517_fix_verifier_notes_in_audit_log.sql`

5. **Fixed DB audit_log for storage notes**
   - `storage_confirm_pickup`: Added `old_status='assigned', new_status='picked_up'` to its audit_log INSERT so `_entryFor(pickedUp)` can find notes
   - `storage_confirm_delivery`: Added correct old/new status to its audit_log INSERT (direction-aware)
   - `mark_picked_up`: Added backfill — after trigger creates `status_change` entry, backfills notes into it
   - Migration: `20260517_fix_audit_log_notes_in_status_functions.sql`

6. **Fixed verifier screen: timeline buried below chat**
   - `task_detail_screen.dart` had `OrderStatusTimeline` AFTER `_CommunicationHistorySection` → user never saw it
   - Reordered: InfoCard → Timeline → Items → EditHistory → Chat

7. **Fixed `isClosed` guard in `task_detail_cubit.dart`**
   - Added `if (isClosed) return;` after `Future.wait` and after `fetchItemsByIds` to prevent StateError on navigation

**Decisions made and WHY:**
- **`orders.notes` = verifier's notes only**: Rep/storage step notes belong in `audit_log`, not the order record. This preserves the verifier's intent throughout the order lifecycle. Without this, the InfoCard would show the last rep's notes instead of the verifier's instructions.
- **Non-fatal audit log failure for rep/storage**: If `fetchAuditLog` fails, show empty timeline rather than block the entire screen. Verifier screen treats it as fatal (existing behavior preserved).
- **Shared `OrderStatusTimeline` widget**: Extracted from manager screen to avoid duplication and ensure consistent notes display across all roles.
- **`_entryFor` prefers notes**: When two audit_log entries exist for the same status transition (trigger's `status_change` with no notes, and function's explicit entry with notes), always surface the one with notes.

**Discussed but NOT implemented:**
- Removing the duplicate `status_change` entries that the trigger creates alongside function-inserted entries. Currently both exist for each transition. Harmless but slightly redundant.
- Fixing `orders.notes` for HISTORICAL orders that already had rep notes overwritten (data migration not done).

**Open threads:**
- The `approve_transaction` function (legacy?) vs `storage_confirm_pickup` — unclear which is the active storage approval path. Both exist in DB. `storage_confirm_pickup` is what the Flutter UI calls.
- `storage_confirm_delivery` sets `status='delivered'` for both inbound_rep and inbound_external. For inbound_rep, `delivered_to_storage` is set later by `approve_order` (manager action?). This flow is not fully traced.
- The `delivered_to_storage` status is not handled in `AuditLogEntry._statusFromString()` — it returns null for this value. Low priority if no rep/storage action produces this status directly.

---

### 5. WHAT COULD GO WRONG

**Known issues:**
- For orders created BEFORE the `orders_log_creation` trigger was added (pre-17-May-2026), there is no `order_created` audit_log entry. The "Created" step in the timeline falls back to `order.notes`, which for old orders may contain rep notes (pre-fix) or be null. This is cosmetic only.
- Old orders (pre-fix) may have `orders.notes` reflecting a rep's step notes rather than the verifier's creation notes. No data migration was run.

**Edge cases:**
- `storage_confirm_pickup` inserts its own audit_log entry AND the trigger inserts a `status_change` entry. Two entries for `picked_up` transition. `_entryFor` correctly picks the one with notes. But if future code iterates all entries, it may encounter duplicates.
- If `performed_by` is NULL in audit_log (shouldn't happen for current functions, but could for edge cases), the FK join `performer:profiles!audit_log_performed_by_fkey` will return null performer — handled gracefully in UI.
- `_creationNotes` returns `order.notes` as fallback. If the verifier later edits the order and changes notes, `orders.notes` updates but the `order_created` audit_log entry retains the original creation notes. The timeline will show the original note (correct behavior), while the InfoCard shows the updated note. These will differ — that's intentional.

**Technical debt:**
- `audit_log` gets two entries per status transition for function-driven changes (function INSERT + trigger INSERT). The trigger's `status_change` entries are always notes=NULL and are essentially redundant for all transitions that have explicit function entries. Not harmful but noisy.
- The `orders.notes` field has an informal invariant (verifier-only) that is enforced by application code, not DB constraints. A new RPC that doesn't know this rule could accidentally overwrite it.

**Assumptions that could be wrong:**
- Assumed `storage_confirm_pickup` is the active outbound-storage flow (not `approve_transaction`). If `approve_transaction` is also used in production, it does NOT insert a `new_status='picked_up'` audit_log entry with notes properly.
- Assumed Flutter app always passes non-null `auth.uid()` to session via PostgREST JWT. The `log_order_created` trigger uses `NEW.created_by` (not `auth.uid()`) to avoid any JWT context issues — this is correct.

---

### 6. HOW TO THINK ABOUT THIS PROJECT

**1. Core architectural pattern:**
Feature-per-folder with cubit-per-screen. Each screen has exactly one cubit. Each cubit owns its state. Repositories are thin data-access wrappers — no business logic. Business logic lives in Supabase RPCs (SECURITY DEFINER), not in Flutter. This was chosen because: (a) the DB must be the single source of truth for RLS/security, (b) multiple clients (future web admin) can reuse the same RPCs.

**2. Most common mistake a new person would make:**
Putting step-transition logic in Flutter instead of Supabase RPCs. Example: trying to update `orders.status` directly from the Flutter client. This would bypass RLS, audit logging, inventory deduction, and push notifications. Always go through the designated RPC.

**3. Looks like it should be refactored but should NOT be:**
The dual audit_log entries per transition (trigger's `status_change` + function's explicit entry). It looks like an error but it exists because the trigger provides a safety net for transitions that don't have an explicit function (e.g., direct DB updates by admin), while the function entry provides the notes. Don't collapse them into one without understanding all code paths that might trigger the `status_change` trigger.

---

### 7. DO NOT TOUCH LIST

- Do NOT refactor the BLoC/Cubit pattern to any other state management approach.
- Do NOT modify `order_status` enum values or names — they are stored in the DB and referenced everywhere.
- Do NOT change `orders.notes` semantics — it is now the verifier's creation note only. Any RPC that updates order data must NOT include `notes = COALESCE(p_notes, notes)`.
- Do NOT remove the `orders_log_creation` trigger — it is what feeds verifier notes into the timeline.
- Do NOT merge or deduplicate `status_change` + function audit_log entries without fully understanding all consumers.
- Do NOT change the `audit_log_performed_by_fkey` FK name — it is hardcoded in all three `fetchAuditLog` queries.
- Do NOT introduce new state management libraries, routing libraries, or DI frameworks.
- Do NOT bypass PostgREST / direct Supabase SDK calls for data mutations — always use the designated RPC or table access pattern.
- Do NOT modify the `auto_post_order_status_message` CASE expression without remembering the `::text` cast on the ELSE branch.

---

### 8. CONFIDENCE & FRESHNESS

| Section | Confidence | Notes |
|---|---|---|
| DB schema (tables, enums, columns) | ✅ HIGH | Queried directly this session |
| All DB trigger and function bodies | ✅ HIGH | Read and modified this session |
| `OrderStatusTimeline` widget | ✅ HIGH | Written this session |
| Rep/storage cubit+repository changes | ✅ HIGH | Written this session |
| `task_detail_cubit.dart` isClosed fix | ✅ HIGH | Applied this session |
| `task_detail_screen.dart` layout fix | ✅ HIGH | Applied this session |
| `orders.notes` invariant behavior | ✅ HIGH | Tested via DB queries |
| Urgent notes UI integration | ⚠️ MEDIUM | DB functions exist, assumed UI wired, not verified this session |
| `approve_transaction` vs `storage_confirm_pickup` | ❓ LOW | Both exist, unclear which path is active in full production flow |
| inboundRep `delivered_to_storage` full flow | ❓ LOW | DB path exists, Flutter handling partially traced, not tested end-to-end |
| Push notification edge function behavior | ⚠️ MEDIUM | Triggers wired, assumed working, not tested this session |
| Phase 2 overall completion % | ⚠️ MEDIUM | Core flows done, edge flows (inboundRep storage confirmation) need verification |
