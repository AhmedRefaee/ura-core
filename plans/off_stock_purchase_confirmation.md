# Plan: confirm purchase of خارج المخزون (outside-inventory) items on outbound orders

## Context — why this exists

An outbound order can contain two kinds of `order_items`:

- real inventory rows (`inventory_id IS NOT NULL`) — come from the warehouse, deducted from stock
- "خارج المخزون" / outside-inventory rows (`is_custom = true`) — not stocked at all; someone has to go buy them specially for this order (renamed from "صنف مخصص" in a prior session — see `lib/shared/widgets/off_stock.dart`)

**The gap:** nothing in the current flow ever explicitly confirms that the خارج المخزون items were actually purchased. It's silently assumed to happen somewhere inside the existing pickup step, with no record of it.

**Decision (already made with the user, do not re-litigate):**
- **Not blocking.** This does not gate `mark_picked_up`, `confirm_pickup`, or any other transition. It's a tracked fact, not a new required stage.
- **The rep confirms it**, not the verifier or storage actor.
- Applies to **any outbound order that has at least one `is_custom = true` item** — including mixed orders that also have real inventory items (not just orders that are 100% outside-inventory).

## Current state (as of this plan, verified by reading the code)

### The two outbound flows

Both live under `OrderDirection.outbound`. Which one an order follows is decided by `Order.involvesStorage` (`lib/shared/models/order.dart:75`): `items.any((i) => i.inventoryId != null)`.

**Flow 1 — order has ≥1 real inventory item** (may also have خارج المخزون items mixed in):
```
assigned → [storage actor: "تأكيد الإرسال" / confirmPickup, stock deducted] → picked_up
         → [rep: "ابدأ التنقل" / startMove] → on_the_move
         → [rep: confirm / markDelivered] → delivered
```

**Flow 2 — order is 100% خارج المخزون, no real inventory at all**
```
assigned → [rep: "تأكيد الاستلام" / markPickedUp — no storage actor involved] → picked_up
         → [rep: "ابدأ التنقل" / startMove] → on_the_move
         → [rep: confirm / markDelivered] → delivered
```

Neither flow has a dedicated step for confirming خارج المخزون items were bought. In Flow 1, storage's "تأكيد الإرسال" only covers releasing real stock. In Flow 2, "تأكيد الاستلام" is a generic label that happens to also cover the (unconfirmed) purchase.

### The transition mechanism (must be mirrored exactly)

Every status transition goes through a Postgres `SECURITY DEFINER` RPC function, defined in `supabase/migrations/20260624130000_baseline.sql`. Example — `mark_picked_up` (line 1586):

```sql
CREATE OR REPLACE FUNCTION "public"."mark_picked_up"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order RECORD;
  ...
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Order not found'); END IF;
  ...
  IF v_order.status != 'assigned' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order must be in assigned status');
  END IF;
  IF v_order.rep_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;
  ...
  UPDATE orders SET status = 'picked_up', picked_up_at = NOW() WHERE id = target_order_id;
  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes, server_timestamp)
  VALUES (target_order_id, 'mark_picked_up', 'assigned', 'picked_up', auth.uid(), p_notes, NOW());
  RETURN jsonb_build_object('success', true);
END;
$$;
```

Dart side calls it via `.rpc('mark_picked_up', params: {...})` — see `lib/features/rep/data/rep_orders_repository.dart:70-86`. The cubit (`lib/features/rep/logic/rep_order_detail_cubit.dart:126-139`) just calls the repo and reloads on success.

### Schema facts that matter

- `orders` table (`supabase/migrations/20260624130000_baseline.sql:2547`): has `assigned_at`, `picked_up_at`, `move_started_at`, `delivered_at` as nullable `timestamptz` columns, one per stage. **Follow this exact naming convention.**
- `order_status` is a fixed Postgres ENUM: `assigned, picked_up, on_the_move, delivered, delivered_to_storage` (line 65). **Do not touch this enum** — this feature is deliberately not a new status.
- `audit_log` table (line 2309): `old_status` and `new_status` are **nullable**. A non-status-changing event can leave both null — no schema change needed there for this feature specifically (contrast with the location-capture plan, which does need new columns on `audit_log`).
- RLS: `"Role-based order updates"` policy (line 3265) actually lets a rep `UPDATE` their own order row directly (`rep_id = auth.uid()`). **Do not use this** — go through an RPC anyway, to match the established pattern (server-side guards, automatic audit trail, consistent with every other transition) and because the audit_log INSERT needs the same SECURITY DEFINER treatment as everywhere else.

### UI pieces already built (from a prior session)

- `lib/shared/widgets/off_stock.dart` — `OffStock.label` ("خارج المخزون"), `OffStock.color` (deep purple, deliberately not orange — orange already means "over available stock" elsewhere), `OffStock.badge()`, `OffStock.section()`.
- `lib/shared/models/off_stock_label.dart` — the bare string constant, kept separate so plain-Dart models (no Flutter import) can use it as a fallback name.
- `lib/shared/widgets/order_status_timeline.dart` — the per-order history view. Already has the machinery to render one event per row (`_TimelineStep`, `_entryFor(status)` which pulls the matching `audit_log` row for performer/notes/timestamp). **This is where the new confirmation shows up** — NOT `order_status_stepper.dart`, which is a fixed-length progress bar over the 4/2 canonical statuses and shouldn't grow a conditional step.
- `lib/features/rep/ui/rep_order_detail_screen.dart:460-511` — where the rep's action buttons live today (`markPickedUp` around line 479, `startMove` around line 490 and 501). The new button goes in this same screen/build method.

## Implementation steps

### 1. Migration

New file `supabase/migrations/<timestamp>_off_stock_purchase_confirmation.sql`:

```sql
ALTER TABLE public.orders
  ADD COLUMN off_stock_purchased_at timestamptz;

CREATE OR REPLACE FUNCTION public.mark_off_stock_purchased(
  target_order_id uuid,
  p_notes text DEFAULT NULL
) RETURNS jsonb
  LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_order RECORD;
  v_has_off_stock BOOLEAN;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  IF v_order.direction != 'outbound' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not an outbound order');
  END IF;

  IF v_order.rep_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;

  IF v_order.status = 'delivered' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order already delivered');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM order_items WHERE order_id = target_order_id AND is_custom = true
  ) INTO v_has_off_stock;
  IF NOT v_has_off_stock THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order has no outside-inventory items');
  END IF;

  IF v_order.off_stock_purchased_at IS NOT NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Already confirmed');
  END IF;

  UPDATE orders SET off_stock_purchased_at = NOW() WHERE id = target_order_id;

  -- Deliberately no old_status/new_status: this event does not change order.status.
  INSERT INTO audit_log (order_id, action, performed_by, notes, server_timestamp)
  VALUES (target_order_id, 'mark_off_stock_purchased', auth.uid(), p_notes, NOW());

  RETURN jsonb_build_object('success', true);
END;
$$;

ALTER FUNCTION public.mark_off_stock_purchased(uuid, text) OWNER TO postgres;

GRANT ALL ON FUNCTION public.mark_off_stock_purchased(uuid, text) TO anon;
GRANT ALL ON FUNCTION public.mark_off_stock_purchased(uuid, text) TO authenticated;
GRANT ALL ON FUNCTION public.mark_off_stock_purchased(uuid, text) TO service_role;
```

(Match whatever exact GRANT pattern the baseline uses for `mark_picked_up` at time of implementation — copy it, don't reinvent.)

### 2. `Order` model — `lib/shared/models/order.dart`

Add `final DateTime? offStockPurchasedAt;` alongside `pickedUpAt` etc., parsed in `Order.fromMap` the same way. Add a getter:

```dart
bool get hasOffStockItems => items.any((i) => i.isCustom);
```

(`items` is already on `Order` per the existing `involvesStorage` getter at line 75 — reuse that pattern.)

### 3. Repository — `lib/features/rep/data/rep_orders_repository.dart`

Add `markOffStockPurchased(String orderId, {String? notes})`, copying the exact shape of `markPickedUp` (lines 70-86): calls `.rpc('mark_off_stock_purchased', params: {...})`, checks `result['success']`, returns `AppResult<void>`.

### 4. Cubit — `lib/features/rep/logic/rep_order_detail_cubit.dart`

Add `markOffStockPurchased({String? notes})`, copying `markPickedUp` (lines 126-139) exactly: `safeEmit(isActing: true)`, call repo, `await load()` on success, error state on failure.

### 5. UI button — `lib/features/rep/ui/rep_order_detail_screen.dart`

New action button, shown when:
```dart
order.direction == OrderDirection.outbound &&
order.hasOffStockItems &&
order.offStockPurchasedAt == null &&
order.status != OrderStatus.delivered
```
Label: **"تم شراء أصناف خارج المخزون"**. Style with `OffStock.color` / `OffStock.icon` (from `lib/shared/widgets/off_stock.dart`) for visual consistency with every other خارج المخزون treatment in the app. Insert this near the existing action buttons (~line 460-511), not replacing any of them — it's an additional, independent action a rep can tap at any point before delivery, in any order relative to the main pickup/move/deliver sequence.

### 6. Timeline — `lib/shared/widgets/order_status_timeline.dart`

Add one more `_TimelineStep` to the `outbound` branch (~line 140-184), conditional on `order.hasOffStockItems`:

```dart
if (order.hasOffStockItems)
  _TimelineStep(
    label: 'تم شراء أصناف خارج المخزون',
    icon: OffStock.icon,
    color: OffStock.color,
    timestamp: order.offStockPurchasedAt,
    performer: _entryFor(...)?.performer,  // need an action-keyed lookup, not status-keyed — see note below
    notes: ...,
    reached: order.offStockPurchasedAt != null,
  ),
```

**Note:** `_entryFor(OrderStatus status)` (line 18) currently looks up `audit_log` by `newStatus`. This event has no `new_status` (it's null in the DB row per step 1), so `_entryFor` as written won't find it. Add a second lookup, e.g. `_entryForAction(String action)` that matches on `audit_log.action == 'mark_off_stock_purchased'` instead, and use that here instead of `_entryFor`.

Position it **right after** the "تم الإنشاء" tile and before "تم الاستلام" — it's logically something that happens early, independent of the main sequence. Do **not** add anything to `order_status_stepper.dart` (that widget is a fixed progress bar over the canonical statuses only).

## Testing

- Cubit test: `markOffStockPurchased` success/failure paths, mirroring existing `rep_order_detail_cubit_test.dart` patterns for `markPickedUp`.
- Widget test: the button appears only when `hasOffStockItems && offStockPurchasedAt == null && status != delivered`, and disappears once purchased.
- Timeline test: the new tile renders when `hasOffStockItems` is true, shows "لم يتم بعد" when `offStockPurchasedAt` is null, and shows the timestamp/performer once set.
- No RPC/migration test harness exists in this repo currently (Supabase migrations aren't unit-tested here) — verify the migration manually against a local/staging Supabase instance before deploying: create an outbound order with a custom item as a different role, confirm `mark_off_stock_purchased` succeeds only for the assigned rep, only once, and only when the order actually has an `is_custom` item.

## Explicitly out of scope for this plan

- No change to `mark_picked_up`, `confirm_pickup`, or any existing transition's guards — this never blocks them.
- No change to the `order_status` enum.
- Storage actor's screens/cubits are untouched — this is a rep-only action.
- Does not depend on and is not blocked by the location-capture plan (`plans/rep_action_location_capture.md`), but if that lands first, `mark_off_stock_purchased` should also require `p_lat`/`p_lng` like the other 3 rep RPCs — check that plan's status before finalizing this migration's SQL.
