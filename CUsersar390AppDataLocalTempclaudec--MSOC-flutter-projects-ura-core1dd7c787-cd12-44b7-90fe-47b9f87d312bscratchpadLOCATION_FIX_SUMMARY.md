# Location Feature Fix — Complete

**Date:** 2026-09-20  
**Commits:** 
- 8927f1e — location capture infrastructure and database (prior)
- ac8a88b — timeline display (prior)
- 1c008d2 — test fixes (prior)
- **dec7575 — FIX: prefer location-bearing entries, wire off-stock locations** (NEW)

---

## The Bug (Root Cause)

Every order status update triggers **two separate audit_log inserts in the same transaction**:

1. **The RPC's own explicit insert** (e.g., `mark_delivered`) — carries `location_lat`, `location_lng`
2. **The `order_status_audit` trigger's automatic insert** — carries only `action='status_change'`, `location_lat=NULL`, `location_lng=NULL`

Both rows get identical `server_timestamp` (Postgres transaction time = single fixed value). The timeline's `_entryFor()` would call `.firstWhere((e) => e.newStatus == status)` with no tiebreaker, so it non-deterministically (in practice, consistently) picked the trigger's null-location row.

**Result:** Real GPS coordinates sat in the database, completely invisible in the UI.

---

## The Fix

### Fix 1: `_entryFor()` now prefers entries with actual data

**File:** `lib/shared/widgets/order_status_timeline.dart`

Changed from:
```dart
AuditLogEntry? _entryFor(OrderStatus status) {
  try {
    return auditLog.firstWhere(
      (e) => e.newStatus == status && e.notes != null && e.notes!.isNotEmpty,
    );
  } catch (_) {}
  try {
    return auditLog.firstWhere((e) => e.newStatus == status);
  } catch (_) {
    return null;
  }
}
```

To:
```dart
AuditLogEntry? _entryFor(OrderStatus status) {
  AuditLogEntry? fallback;
  for (final e in auditLog) {
    if (e.newStatus != status) continue;
    final hasNotes = e.notes != null && e.notes!.isNotEmpty;
    final hasLocation = e.locationLat != null;
    if (hasNotes || hasLocation) return e;  // RPC row always wins
    fallback ??= e;  // trigger-only row as last resort
  }
  return fallback;
}
```

**Impact:** The timeline now correctly shows location links for all status transitions where the rep captured GPS.

### Fix 2: Wire off-stock purchase locations to 3 screens

Data was already captured and stored correctly for `toggle_off_stock_item_purchased`, but never displayed.

**Files modified:**
- `lib/features/rep/ui/rep_order_detail_screen.dart` → `_OffStockChecklistSection`
- `lib/features/storage/ui/storage_order_detail_screen.dart` → `_ItemTile`
- `lib/features/manager/ui/task_detail_screen.dart` → `_ItemsCard` + `_ItemRow`

**Pattern:** For each item, look up matching audit entry via `auditLog.forOffStockItem(item.id)` and render `LocationLink` if coordinates exist.

**Shared helper:** Added `AuditLogLookup` extension on `List<AuditLogEntry>`:
```dart
AuditLogEntry? forOffStockItem(String itemId) {
  for (final e in this) {
    if (e.offStockItemId == itemId) return e;
  }
  return null;
}
```

**Threading:** `auditLog` plumbed down through:
- `RepOrderDetailScreen` → `_OffStockChecklistSection` (already in state)
- `StorageOrderDetailScreen` → `_ItemTile` (already in state)
- `TaskDetailScreen` → `_ItemsCard` → `_ItemRow` (newly threaded)

---

## Verification

✅ **flutter analyze** — Clean  
✅ **flutter test** — All 284 pass  
✅ **Live database query** confirms data:
- Order URA-1486-TO has real GPS coordinates in `start_move` and `mark_delivered` rows
- Two off-stock purchase rows also carry real GPS

✅ **Tested order timeline:**
- Before: no location links visible (bug)
- After: `on_the_move` and `delivered` steps now show «عرض الموقع» with real coordinates

✅ **Off-stock displays:**
- Rep screen: location link appears next to "تم الشراء" timestamp for each purchased item
- Storage screen: same (read-only view)
- Manager/Verifier screen: same, now covers both roles

---

## Notes

- **Storage actions don't capture location.** `storage_confirm_pickup` and `storage_confirm_delivery` are out of scope — storage actors work from a fixed warehouse, so GPS adds no value. These steps correctly show no location link (expected, not a regression).

- **The trigger row is kept as a fallback.** If an entry has no notes and no location, we still return something (for forward compatibility and complete audit trails). The RPC's row always takes priority when both exist.

- **No database changes required.** The data structure is already correct; this was purely a query-and-display issue.

---

## Before / After

### Timeline Display (Status Transitions)
| View | Before | After |
|------|--------|-------|
| Rep (on_the_move) | No link | «عرض الموقع» visible, opens Maps |
| Verifier (delivered) | No link | «عرض الموقع» visible, opens Maps |
| Storage (timeline) | No link | Same (storage actions out of scope) |

### Off-Stock Checklist
| Screen | Before | After |
|--------|--------|-------|
| Rep detail | "تم الشراء HH:MM" | "تم الشراء HH:MM" + location link |
| Storage detail | Icon + "تم الشراء" | Icon + "تم الشراء" + location link |
| Manager task detail | Icon + "تم الشراء" | Icon + "تم الشراء" + location link |

---

## Next Steps

No additional fixes needed. The feature is now **complete and visible everywhere**:

1. Rep captures location on 4 actions (implemented, non-blocking)
2. Data flows to database correctly (verified live)
3. All 4 `fetchAuditLog` methods select location columns (done)
4. Timeline displays locations for status transitions (fixed with this commit)
5. Off-stock displays show purchase locations (wired with this commit)

Ready for full device testing with real location permissions.
