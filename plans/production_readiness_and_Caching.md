# URA Core — Production Readiness & Caching Plan

## Context

The app is a Flutter ERP system using Supabase as backend, BLoC/Cubit state management, GoRouter for navigation, and GetIt for DI. The codebase is well-architected (clean widget decomposition, proper stream cleanup, centralized error handling, correct singleton/factory DI split). However, three categories of issues will cause real failures after release:

1. **No caching** — every screen navigation triggers a fresh network call; users on slow connections will be stalled on every tap
2. **No pagination** — lists load entire datasets; inventory, orders, and notifications will become unusable as data grows
3. **Minor performance gaps** — a few query and rebuild inefficiencies that compound under load

This plan addresses them in priority order, from lowest effort/highest impact to highest effort.

---

## Phase 1 — In-Memory Cache Layer (Layer 1)

**Impact: High | Effort: Low | Risk: Low**

Add a single reusable TTL cache class used by all singleton repositories.

### New file: `lib/core/cache/memory_cache.dart`

```dart
class MemoryCache<K, V> {
  final Duration ttl;
  final Map<K, (DateTime, V)> _store = {};

  MemoryCache({this.ttl = const Duration(minutes: 5)});

  V? get(K key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.$1) > ttl) {
      _store.remove(key);
      return null;
    }
    return entry.$2;
  }

  void set(K key, V value) => _store[key] = (DateTime.now(), value);
  void invalidate(K key) => _store.remove(key);
  void clear() => _store.clear();
}
```

### Apply to these singleton repositories:

| Repository | Cache key | TTL | Invalidate on |
|---|---|---|---|
| `auth_repository.dart` | `profile:{userId}` | 10 min | sign-out, profile update |
| `manager_repository.dart` | `rep_list`, `pending_users` | 3 min | user approval action |
| `inventory_management_repository.dart` | `inventory:{search}:{category}` | 2 min | any inventory write |
| `entities repository` (if exists) | `entities` | 10 min | entity create/update |

**Pattern to apply in each repository:**
```dart
final _cache = MemoryCache<String, List<X>>(ttl: Duration(minutes: 3));

Future<AppResult<List<X>>> fetchX() async {
  final cached = _cache.get('key');
  if (cached != null) return AppSuccess(cached);
  // ... Supabase query ...
  _cache.set('key', result);
  return AppSuccess(result);
}
```

---

## Phase 2 — Fix Query Issues

**Impact: Medium | Effort: Very Low | Risk: Very Low**

### 2a. Fix bare `.select()` calls

**File:** `lib/features/auth/data/auth_repository.dart`  
Replace `.select()` with explicit columns matching `Profile.fromMap()` fields.

```dart
// Before
.select()
// After
.select('id, full_name, role, status, avatar_url, created_at')
```

### 2b. Fix notification over-fetch

**File:** `lib/features/notifications/data/` (notifications repository)  
Replace:
```dart
.limit(100)
// then client-side filter to 50
```
With:
```dart
.eq('user_id', uid)
.order('created_at', ascending: false)
.limit(50)
```

### 2c. Fix `select *` in join queries

Audit all queries with `.select('*, entity:entities(*), creator:profiles(*)')` pattern.  
Replace wildcard joins with explicit column lists that match the model constructors.

---

## Phase 3 — Pagination

**Impact: Critical for scale | Effort: Medium | Risk: Low**

Without this, the app will break at ~200+ rows. Add offset-based pagination to the 3 heaviest lists.

### Pattern (apply to each feature):

**Repository layer** — add `page` and `pageSize` parameters:
```dart
Future<AppResult<List<T>>> fetchItems({int page = 0, int pageSize = 25}) async {
  final from = page * pageSize;
  final to = from + pageSize - 1;
  final data = await _supabase
      .from('table')
      .select('...')
      .order('created_at', ascending: false)
      .range(from, to);
  return AppSuccess(...);
}
```

**Cubit layer** — add pagination state:
```dart
// In state
final int page;
final bool hasMore;
final bool isLoadingMore;

// In cubit
Future<void> loadMore() async { ... }
```

**UI layer** — add scroll listener:
```dart
_scrollController.addListener(() {
  if (_scrollController.position.pixels >= 
      _scrollController.position.maxScrollExtent - 200) {
    context.read<XCubit>().loadMore();
  }
});
```

### Priority order:

1. **`lib/features/inventory/`** — `inventory_management_repository.dart` + `inventory_list_cubit.dart` + `inventory_management_screen.dart`
2. **`lib/features/notifications/`** — notifications repo + cubit + screen
3. **`lib/features/manager/`** — `monitor_orders_cubit.dart` + screen (orders list for manager)
4. **`lib/features/rep/`** — rep orders list

---

## Phase 4 — Local Persistence with Hive (Layer 2 Cache)

**Impact: High for UX | Effort: Medium | Risk: Low**

Gives users instant data on screen open even after restarting the app.

### Add dependency to `pubspec.yaml`:
```yaml
hive_flutter: ^1.1.0
```

### Initialize in `main.dart`:
```dart
await Hive.initFlutter();
```

### What to persist (boxes):

| Box name | Data | Expiry strategy |
|---|---|---|
| `user_profile` | `Profile` object (JSON) | Invalidate on sign-out |
| `inventory_cache` | Last fetched inventory page | Invalidate after 5 min via stored timestamp |
| `app_settings` | (already in SharedPreferences — keep as is) | N/A |

### Show-stale-then-refresh pattern:

```dart
// In cubit load():
final cached = await _localSource.getProfile();
if (cached != null) emit(ProfileLoaded(cached, isStale: true));
final fresh = await _repo.fetchProfile();
emit(ProfileLoaded(fresh, isStale: false));
```

**Files to create:**
- `lib/core/cache/hive_profile_source.dart`
- `lib/core/cache/hive_inventory_source.dart`

---

## Phase 5 — Performance Fixes

**Impact: Medium | Effort: Low-Medium**

### 5a. Fix `create_order_screen.dart` item list rebuild

**File:** `lib/features/verifier/ui/create_order_screen.dart`

The items list currently uses:
```dart
...ready.items.asMap().entries.map((e) => ListTile(...)).toList()
```
inside a `Column` — this rebuilds every item on every state change.

Replace with a `ListView.builder` with `shrinkWrap: true` and `physics: NeverScrollableScrollPhysics()` inside the parent `SingleChildScrollView`.

### 5b. Reduce setState bloat in `chat_thread_screen.dart`

**File:** `lib/features/chat/ui/chat_thread_screen.dart`

Extract mention picker state, reply target state, and urgent toggle into a separate `ValueNotifier` or small local `StatefulWidget` so they don't trigger rebuilds of the entire `ListView`.

**Approach:** Create `_ChatInputBar` as its own `StatefulWidget` that owns all the local UI state (mention text, reply target, isUrgent). The parent `ChatThreadView` only rebuilds when the cubit emits new messages.

### 5c. Fix `ChatMessageBubble` rebuild overhead

**File:** `lib/features/chat/ui/widgets/chat_message_bubble.dart`

Currently a `StatefulWidget`. If drag gesture state is the only reason, keep it — but verify the gesture handling actually requires it. If it's only for reaction display (which comes from cubit), convert to `StatelessWidget`.

### 5d. Add skeleton loaders

Add `shimmer: ^3.0.0` to `pubspec.yaml`.

Replace `CircularProgressIndicator` on the 3 heaviest screens with shimmer placeholders:
- `inventory_management_screen.dart` — shimmer card list
- `chat_hub_screen.dart` — shimmer thread list  
- Manager home screen — shimmer stats cards

---

## Phase 6 — Offline / Poor Network Resilience

**Impact: High for field users | Effort: Low**

### 6a. Add connectivity check

Add `connectivity_plus` to pubspec.yaml (it's not in pubspec but path_provider is — good base).

### 6b. Retry wrapper in core

Add to `lib/core/errors/error_handler.dart` or new `lib/core/network/retry_handler.dart`:

```dart
Future<AppResult<T>> withRetry<T>(Future<AppResult<T>> Function() fn, {int maxAttempts = 2}) async {
  for (int i = 0; i < maxAttempts; i++) {
    final result = await fn();
    if (result is AppSuccess) return result;
    if (i == maxAttempts - 1) return result; // return last failure
    await Future.delayed(Duration(seconds: 2 * (i + 1))); // exponential backoff
  }
  throw StateError('unreachable');
}
```

### 6c. Show cached data on network error

In cubits that have cached data (from Phase 1/4), when a refresh fails emit a `XLoaded(data: cachedData, isStale: true)` rather than `XError`. Display a subtle banner "Showing cached data" instead of a full error screen.

---

## Files Modified Summary

| File | Change |
|---|---|
| `pubspec.yaml` | Add: `hive_flutter`, `shimmer`, `connectivity_plus` |
| `lib/core/cache/memory_cache.dart` | **NEW** — TTL cache utility |
| `lib/core/cache/hive_profile_source.dart` | **NEW** — local profile persistence |
| `lib/core/cache/hive_inventory_source.dart` | **NEW** — local inventory page cache |
| `lib/core/network/retry_handler.dart` | **NEW** — retry + backoff utility |
| `lib/features/auth/data/auth_repository.dart` | Fix `.select()`, add profile cache |
| `lib/features/notifications/data/` | Fix over-fetch limit |
| `lib/features/inventory/data/inventory_management_repository.dart` | Add pagination params + memory cache |
| `lib/features/inventory/logic/inventory_list_cubit.dart` | Add pagination state + `loadMore()` |
| `lib/features/inventory/ui/inventory_management_screen.dart` | Add scroll listener for pagination |
| `lib/features/manager/data/manager_repository.dart` | Add memory cache for rep list |
| `lib/features/manager/logic/monitor_orders_cubit.dart` | Add pagination |
| `lib/features/verifier/ui/create_order_screen.dart` | Replace Column spread with ListView.builder |
| `lib/features/chat/ui/chat_thread_screen.dart` | Extract `_ChatInputBar` StatefulWidget |
| `main.dart` | Add `Hive.initFlutter()` |

---

## Verification

After implementation, test the following:

1. **Cache hit:** Navigate to inventory → back → re-open inventory → should load instantly (no spinner for cached data)
2. **Cache invalidation:** Edit an inventory item → go back to list → list should show fresh data
3. **Pagination:** Seed DB with 100+ inventory items → scroll to bottom → next page loads automatically
4. **Stale data:** Turn off network → open app → should show last cached profile/inventory
5. **Query size:** Use Supabase dashboard logs to confirm no wildcard `select *` queries on hot paths
6. **Flutter DevTools:** Enable performance overlay and repaint rainbow on `create_order_screen` while adding items — should see no full-screen repaints
7. **Chat rebuild:** Open chat thread → open mention picker → confirm message list does not repaint (use repaint rainbow)
8. **Long session:** Leave app open 2 hours → navigate through screens → no crashes, memory stable in DevTools

---

## Implementation Order

Execute phases in order — each builds on the previous:

1. Phase 2 (query fixes) — 30 min, zero risk
2. Phase 1 (memory cache) — 2 hours, immediate UX improvement
3. Phase 3 (pagination) — 4 hours, do inventory first then orders
4. Phase 5 (performance fixes) — 2 hours, focused changes
5. Phase 4 (Hive persistence) — 3 hours, requires testing restart behavior
6. Phase 6 (offline resilience) — 2 hours, wrap up
