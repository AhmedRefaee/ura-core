# Plan: capture the rep's location on every order-action button

## Context — why this exists

The user wants proof of where a rep physically was when they tapped each order-progressing action, for accountability on outbound deliveries.

**Decisions already made with the user (do not re-litigate):**
- **Blocking, not best-effort.** If location can't be obtained, the action must NOT proceed. No silently recording a null location and moving on.
- **Capture and store only, no UI viewer yet.** No map view, no coordinates shown anywhere in this pass — that's an explicit, separate follow-up.
- **Scope: the rep's buttons only.** Storage actor's `confirm_pickup` / `confirm_delivery` (in `lib/features/storage/`) are explicitly OUT of scope — the user said "the rep," this was flagged back to them, and they did not correct it. If that assumption turns out wrong, re-confirm before implementing storage-side changes.

The four buttons in scope, all in `lib/features/rep/`:
1. `markPickedUp` — "تأكيد الاستلام" (Flow 2 only — see `plans/off_stock_purchase_confirmation.md` for what Flow 1/2 means)
2. `startMove` — "ابدأ التنقل"
3. `markDelivered` — "تأكيد التسليم"
4. `markOffStockPurchased` — "تم شراء أصناف خارج المخزون" (new, being built per the sibling plan — **if that plan hasn't shipped yet when this one is implemented, build this feature into it from the start rather than retrofitting**)

## Current state (verified by reading the code)

- **No location capability exists anywhere in this app today.** Confirmed by checking: `pubspec.yaml` has no `geolocator` or similar; `android/app/src/main/AndroidManifest.xml` and `ios/Runner/Info.plist` have no location permission keys; no `lat`/`lng`/`latitude`/`longitude` column anywhere in `supabase/migrations/`. This is greenfield, not an extension.
- Every rep action routes through a `SECURITY DEFINER` Postgres RPC (see `plans/off_stock_purchase_confirmation.md` for the exact `mark_picked_up` example) called from `lib/features/rep/data/rep_orders_repository.dart`, invoked by `lib/features/rep/logic/rep_order_detail_cubit.dart`, triggered by buttons in `lib/features/rep/ui/rep_order_detail_screen.dart` (buttons currently around lines 460-520).
- `audit_log` table (`supabase/migrations/20260624130000_baseline.sql:2309`) already gets one row per action via each RPC — `order_id, action, old_status, new_status, performed_by, notes, server_timestamp`. This is where location belongs: one more fact about a row that already exists per action, not a new concept.
- Existing abstraction pattern to copy: `lib/core/logging/crash_reporter.dart` — an abstract class (`CrashReporter`) with a real implementation (`crashlytics_reporter.dart`) and a no-op/fake default, installed at startup, letting business logic depend on the abstraction and tests use a fake. **Follow this exact shape for location.**

## Design

### 1. Package + platform permissions

- Add `geolocator` to `pubspec.yaml` (has first-class Android/iOS/web support — this app builds for web too, per `firebase.json`, though the rep role is expected to be mobile-primary).
- `android/app/src/main/AndroidManifest.xml`: add `ACCESS_FINE_LOCATION` (and `ACCESS_COARSE_LOCATION` as fallback).
- `ios/Runner/Info.plist`: add `NSLocationWhenInUseUsageDescription` with a clear Arabic string (e.g. "يستخدم التطبيق موقعك لتوثيق مكان تنفيذ إجراءات الطلب"). **"When in use" only** — no background permission needed, this is a one-shot capture on an explicit button tap, never passive tracking.

### 2. `lib/core/location/location_capture.dart` — the abstraction

```dart
/// A single GPS fix, or the specific reason one couldn't be obtained.
sealed class LocationResult {
  const LocationResult();
}

class LocationFix extends LocationResult {
  final double lat;
  final double lng;
  const LocationFix(this.lat, this.lng);
}

/// Every distinct failure needs its own message and, for permanentlyDenied,
/// its own action (open Settings) — do not collapse these into one generic
/// "location unavailable" case.
enum LocationFailure {
  permissionDenied,      // denied once — asking again is possible
  permissionDeniedForever, // Android "don't ask again" / iOS "Never" — must open Settings
  serviceDisabled,       // GPS/location services off at the OS level
  timedOut,              // permission fine, but no fix within the deadline
}

class LocationUnavailable extends LocationResult {
  final LocationFailure reason;
  const LocationUnavailable(this.reason);
}

abstract class LocationCapture {
  const LocationCapture();
  Future<LocationResult> capture();
}
```

Real implementation `GeolocatorLocationCapture`:
- `Geolocator.isLocationServiceEnabled()` → if false, return `LocationUnavailable(serviceDisabled)`.
- `Geolocator.checkPermission()` → if `denied`, call `Geolocator.requestPermission()`; if still denied, return `LocationUnavailable(permissionDenied)`; if `deniedForever`, return `LocationUnavailable(permissionDeniedForever)`.
- `Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high).timeout(Duration(seconds: 15))` → on `TimeoutException`, return `LocationUnavailable(timedOut)`; on success, return `LocationFix(position.latitude, position.longitude)`.

A `FakeLocationCapture` for tests that returns a scripted `LocationResult` (mirrors how `direct_item_match_repository_test.dart`'s `ScriptedModel` works — script a list of results if a test needs to check a retry-after-failure path, otherwise a fixed constant is enough).

Register the real one in `lib/core/di/injection.dart` alongside how `CrashReporter` is wired.

### 3. UI: the permission/failure flow, once, reusable

Do not duplicate this dialog logic across 4 button handlers. Build one helper, e.g. `Future<LocationFix?> requireLocation(BuildContext context)` in a shared widget/util under `lib/features/rep/` (or `lib/shared/` if it turns out generic enough to reuse elsewhere later — start local to rep, promote only if needed):

- Shows a brief inline "جاري تحديد الموقع..." state on the button while capturing.
- On `permissionDenied`: a dialog explaining why location is needed, with a retry button that calls `capture()` again.
- On `permissionDeniedForever`: a dialog with a button that calls `Geolocator.openAppSettings()` (no-op gracefully on web — detect platform and show a plain "يرجى تفعيل إذن الموقع من إعدادات المتصفح/الجهاز" message instead if `openAppSettings` isn't meaningful there).
- On `serviceDisabled`: a dialog with a button that calls `Geolocator.openLocationSettings()` (Android/iOS only).
- On `timedOut`: a simple retry — GPS fix can genuinely take another attempt.
- Returns `null` if the user backs out without ever getting a fix; **the calling button handler must not proceed to call the RPC if this returns null.**

### 4. Wiring into each of the 4 actions

Each cubit method (`markPickedUp`, `startMove`, `markDelivered`, `markOffStockPurchased`) gets a `lat`/`lng` parameter. Each corresponding UI button's `onPressed`:

```dart
onPressed: () async {
  final fix = await requireLocation(context);
  if (fix == null) return; // user backed out or all retries exhausted — do NOT call the action
  context.read<RepOrderDetailCubit>().markPickedUp(notes: _notes, lat: fix.lat, lng: fix.lng);
},
```

Repository methods add `lat`/`lng` to the `.rpc(...)` params map, e.g.:
```dart
_supabase.rpc('mark_picked_up', params: {
  'target_order_id': orderId,
  'p_notes': notes,
  'p_lat': lat,
  'p_lng': lng,
});
```

### 5. Database

New migration, one file covering all four RPCs plus the schema change:

```sql
ALTER TABLE public.audit_log
  ADD COLUMN lat double precision,
  ADD COLUMN lng double precision;
```
(Nullable at the table level deliberately — other action types not in scope here, e.g. `order_created`, chat/urgent-note related audit rows, will never populate these and shouldn't be forced to.)

Then, for **each of the 3 existing RPCs** (`mark_picked_up`, `start_move`, `mark_delivered`) plus the new `mark_off_stock_purchased`:
- Add `p_lat double precision` and `p_lng double precision` as **required parameters with no default** — this is what makes the requirement a real server-side guarantee, not just a client-side UI nicety that a direct API call could skip.
- Thread them into that function's existing `INSERT INTO audit_log (...)` statement, adding `lat, lng` to the column list and `p_lat, p_lng` to the values.
- **Do not change any other guard logic** in these functions — this is purely additive to the audit trail, it does not gate the status transition itself (permission/GPS blocking happens client-side before the RPC is ever called; the RPC just now expects the values to be there).

**Ordering with the sibling plan:** if `plans/off_stock_purchase_confirmation.md` has already shipped by the time this is implemented, `mark_off_stock_purchased` already exists without `p_lat`/`p_lng` — this becomes a 4th `ALTER FUNCTION`-equivalent (in Postgres, changing required params means `CREATE OR REPLACE FUNCTION` with the new signature, which is fine since nothing else calls it directly). If it hasn't shipped yet, build it with `p_lat`/`p_lng` from day one to avoid two migrations touching the same function.

## Testing

- `LocationCapture` fake-backed unit tests for the UI helper: assert that `permissionDenied` shows the right dialog and retries correctly, `permissionDeniedForever` offers Settings, `serviceDisabled` offers location settings, `timedOut` offers retry, and — critically — that **no cubit method is ever called when `requireLocation` returns null** (this is the actual safety property; test it directly with a mock cubit, e.g. `verifyNever(() => cubit.markPickedUp(...))`).
- Cubit tests: `markPickedUp`/`startMove`/`markDelivered`/`markOffStockPurchased` now take `lat`/`lng` and forward them into the repository call — assert the repository receives exactly what was passed.
- No automated test can exercise real GPS or real OS permission dialogs — this is inherent, not a gap to close. Manual on-device verification is required before shipping: test all 5 states (granted-and-fast, granted-but-slow/timeout, denied-then-retry-granted, denied-forever→open-settings, services-disabled→open-settings) on both a real Android device and iOS if the app ships there.

## Explicitly out of scope for this plan

- No map/viewer UI for the captured coordinates — a clean, separate follow-up once there's a real need to look at them.
- No location capture on storage actor's actions (`confirm_pickup`, `confirm_delivery` in `lib/features/storage/`) — reconfirm with the user before extending there.
- No background/continuous location tracking — one-shot capture per button tap only.
- No change to any existing RPC's status-transition guard logic (the "must be in `assigned` status", "must be the assigned rep", etc. checks) — location is additive to the audit row only.
