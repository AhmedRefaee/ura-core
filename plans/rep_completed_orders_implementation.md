# Implementation Plan: Rep Completed Orders Tab

## Overview
Add a "Completed Orders" tab to the Rep home screen, matching the pattern used by Verifier and Storage users.

## Current State
- **Rep Home Screen**: Shows only active orders (filters out `delivered` and `deliveredToStorage` at repository level)
- **Verifier & Storage**: Both have "Active" and "Completed" tabs using `DefaultTabController`
- **Repository Filtering**: [`rep_orders_repository.dart:26-37`](../lib/features/rep/data/rep_orders_repository.dart:26-37) actively excludes completed orders

## Implementation Strategy

### Approach 1: UI-Level Filtering (Recommended)
**Pros:**
- Single API call to fetch all orders
- Consistent with Verifier implementation
- Better performance (one query instead of two)
- Easier to maintain

**Cons:**
- Slightly more data transferred (completed orders included)

### Approach 2: Repository-Level Split
**Pros:**
- Only fetches needed data per tab
- Cleaner separation of concerns

**Cons:**
- Two API calls (one for active, one for completed)
- More complex state management
- Inconsistent with existing patterns

**Decision: Use Approach 1 (UI-Level Filtering)** to maintain consistency with Verifier and Storage implementations.

---

## Implementation Steps

### Step 1: Update Repository Layer
**File**: [`lib/features/rep/data/rep_orders_repository.dart`](../lib/features/rep/data/rep_orders_repository.dart)

**Changes:**
- Modify [`fetchMyOrders()`](../lib/features/rep/data/rep_orders_repository.dart:15) to return ALL orders (remove the `.where()` filter)
- Keep the method signature the same
- Update log message to reflect all orders

**Before:**
```dart
final orders = (data as List)
    .map((e) => Order.fromMap(e as Map<String, dynamic>))
    .where((o) {
      // Exclude terminal states per direction
      if (o.direction == OrderDirection.inboundRep) {
        return o.status != OrderStatus.delivered &&
            o.status != OrderStatus.deliveredToStorage;
      }
      return o.status != OrderStatus.delivered &&
          o.status != OrderStatus.deliveredToStorage;
    })
    .toList();
logger.i('RepOrdersRepository → ${orders.length} active orders');
```

**After:**
```dart
final orders = (data as List)
    .map((e) => Order.fromMap(e as Map<String, dynamic>))
    .toList();
logger.i('RepOrdersRepository → ${orders.length} orders loaded');
```

---

### Step 2: Update UI Layer
**File**: [`lib/features/rep/ui/rep_home_screen.dart`](../lib/features/rep/ui/rep_home_screen.dart)

**Changes:**
1. Wrap the body in a `DefaultTabController` (similar to Verifier/Storage)
2. Add a `TabBar` with two tabs: "نشطة" (Active) and "مكتملة" (Completed)
3. Replace the single `ListView` with a `TabBarView` containing two order lists
4. Create a reusable `_RepOrderList` widget
5. Filter orders in the UI layer (active vs completed)

**New Structure:**
```dart
class _RepHomeView extends StatelessWidget {
  const _RepHomeView();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مهامي'),
          actions: [/* existing actions */],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'نشطة'),
              Tab(text: 'مكتملة'),
            ],
          ),
        ),
        body: BlocBuilder<RepOrdersCubit, RepOrdersState>(
          builder: (context, state) {
            if (state is RepOrdersLoaded) {
              final active = state.orders
                  .where((o) => o.status != OrderStatus.delivered &&
                              o.status != OrderStatus.deliveredToStorage)
                  .toList();
              final completed = state.orders
                  .where((o) => o.status == OrderStatus.delivered ||
                              o.status == OrderStatus.deliveredToStorage)
                  .toList();
              return TabBarView(
                children: [
                  _RepOrderList(
                    orders: active,
                    emptyMessage: 'لا توجد مهام معينة لك حالياً',
                    onTap: (id) => _openDetail(context, id),
                  ),
                  _RepOrderList(
                    orders: completed,
                    emptyMessage: 'لا توجد مهام مكتملة',
                    onTap: (id) => _openDetail(context, id),
                  ),
                ],
              );
            }
            // ... existing loading/error states
          },
        ),
      ),
    );
  }
}
```

---

### Step 3: Create Reusable Order List Widget
**File**: [`lib/features/rep/ui/rep_home_screen.dart`](../lib/features/rep/ui/rep_home_screen.dart)

**New Widget:**
```dart
class _RepOrderList extends StatelessWidget {
  final List<Order> orders;
  final String emptyMessage;
  final void Function(String orderId) onTap;

  const _RepOrderList({
    required this.orders,
    required this.emptyMessage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return RefreshIndicator(
      onRefresh: () => context.read<RepOrdersCubit>().loadOrders(),
      child: ListView.builder(
        itemCount: orders.length,
        itemBuilder: (_, i) => _RepOrderCard(
          order: orders[i],
          onTap: () => onTap(orders[i].id),
        ),
      ),
    );
  }
}
```

---

## Architecture Diagram

```mermaid
graph TD
    A[RepHomeScreen] --> B[DefaultTabController]
    B --> C[TabBar: Active | Completed]
    B --> D[TabBarView]
    D --> E[Active Orders Tab]
    D --> F[Completed Orders Tab]
    E --> G[RepOrdersCubit]
    F --> G
    G --> H[RepOrdersRepository]
    H --> I[Supabase: orders table]
    H --> J[Returns ALL orders]
    J --> K[UI filters: active vs completed]
    K --> E
    K --> F
```

---

## File Changes Summary

| File | Type | Changes |
|------|------|---------|
| `lib/features/rep/data/rep_orders_repository.dart` | Modify | Remove order filtering in `fetchMyOrders()` |
| `lib/features/rep/ui/rep_home_screen.dart` | Modify | Add `DefaultTabController`, `TabBar`, `TabBarView`, and `_RepOrderList` widget |

---

## Testing Checklist

- [ ] Active orders tab shows only non-delivered orders
- [ ] Completed orders tab shows only delivered/deliveredToStorage orders
- [ ] Empty states display correct messages for both tabs
- [ ] Pull-to-refresh works on both tabs
- [ ] Tapping an order opens detail screen correctly
- [ ] Order cards display correct status badges
- [ ] Navigation between tabs is smooth
- [ ] Back navigation from detail screen returns to correct tab

---

## Edge Cases to Consider

1. **No orders at all**: Both tabs should show empty states
2. **Only active orders**: Completed tab shows empty state
3. **Only completed orders**: Active tab shows empty state
4. **Large order lists**: Ensure performance with pagination if needed
5. **Order status changes**: Verify refresh after status update

---

## Future Enhancements (Optional)

1. **Date range filter** for completed orders
2. **Search functionality** within each tab
3. **Sort options** (by date, status, entity name)
4. **Order statistics** (count badges on tabs)
5. **Pull-to-refresh** indicator improvement

---

## Consistency with Existing Patterns

This implementation follows the exact same pattern as:
- [`VerifierHomeScreen`](../lib/features/verifier/ui/verifier_home_screen.dart:144-200) - Uses `DefaultTabController` with active/completed tabs
- [`StorageHomeScreen`](../lib/features/storage/ui/storage_home_screen.dart:30-111) - Uses `DefaultTabController` with active/completed tabs

Both filter orders at the UI level after fetching all data from the repository.
