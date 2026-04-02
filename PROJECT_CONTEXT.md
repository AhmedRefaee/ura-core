# URA CORE — Project Context & Architecture Bible

> **Last updated:** April 2, 2026
> **Developer:** Ahmed Refaee (Flutter Developer, solo on this project)
> **Stack:** Flutter + Supabase (Postgres, Auth, Storage, Realtime)
> **Repo:** Private GitHub repo `ura-core`

---

## 1. What This Project Is

URA CORE is an inventory & logistics management system for a company that currently handles orders via WhatsApp and Excel. The app digitizes this into a strict 4-stage workflow with three user roles.

The system turns messy WhatsApp messages into a 4-step digital journey:
1. **Intake:** An order comes in via WhatsApp. The Verifier types it into the app.
2. **Hand-off:** The Verifier picks a Representative (Rep) to handle it.
3. **Warehouse:** The Rep goes to storage. The Storage Actor checks items and clicks "Approve." This is the ONLY moment stock numbers change in the database.
4. **Delivery:** The Rep delivers the goods. If they had to buy extra "Custom Items" from a store, they must snap a photo of the receipt for EACH custom item, or the app won't let them finish.

---

## 2. User Roles

### Verifier (Desktop/Tablet — the admin)
- Creates orders from WhatsApp messages
- Assigns entities (customers/suppliers) and Reps to orders
- Sees ALL orders and their progress
- Approves new user registrations and assigns roles
- Manages entities and inventory items

### Representative / Rep (Mobile — the driver)
- Sees only orders assigned to them
- Confirms arrival at warehouse
- Clicks "Start Move" when they begin driving (separated from loading time)
- Uploads receipt photos for custom items
- Marks orders as delivered

### Storage Actor (Mobile/Industrial Handheld — warehouse staff)
- Sees orders at the warehouse gate (status: assigned or picked_up)
- Goes through each item with a checkmark (✓ checked / ✗ rejected)
- Clicks "Approve Transaction" — this triggers inventory math
- Can do ad-hoc "Quick Receipt" for unexpected deliveries

---

## 3. The Dual-Flow Logic

### Outbound (To Customer)
Storage → Rep → Customer. Inventory decrements (−).

### Inbound Case A (Via our Rep)
Supplier → Rep → Storage. Inventory increments (+).
Both the Rep and Storage Actor see this order immediately upon assignment.

### Inbound Case B (Via External Company)
Supplier → Storage. Inventory increments (+).
No Rep is assigned. Only the Verifier and Storage Actor see/manage this.

---

## 4. The 4-Stage State Machine

```
assigned → picked_up → on_the_move → delivered
```

1. **Assigned:** Order created, Rep linked to task.
2. **Picked Up:** Storage Actor verified all items and approved. Inventory math happens HERE.
3. **On the Move:** Rep manually toggles this when they start driving.
4. **Delivered:** Rep confirms delivery. Blocked if custom items lack receipts.

---

## 5. The Two-Checkpoint System

### Checkpoint 1 — Storage Actor (at the warehouse)
- Sees every item in the order with a checkmark next to each
- Marks each item as ✓ (checked) or ✗ (rejected)
- Can only hit "Approve" when ALL inventory items are marked "checked"
- Approval triggers inventory math (decrement for outbound, increment for inbound)

### Checkpoint 2 — Rep (on the road)
- For custom/external items that the Rep buys from stores
- Must attach a receipt photo to EACH individual custom item
- "Delivered" button is disabled until every custom item has a receipt

---

## 6. Hard Guardrails

- **No Shortcuts:** A Rep cannot click "Delivered" if Storage Actor hasn't approved pickup.
- **Receipt Lockdown:** If order has custom items, "Delivered" button disabled until each custom item has a receipt photo.
- **Insufficient Stock:** Storage Actor's "Approve" button throws error if requested quantity exceeds inventory.
- **Server Timestamps:** Every status change logs a server timestamp — never trust client time.
- **Approval Required:** New users must be approved by a Verifier before accessing any data.

---

## 7. Backend — Supabase (COMPLETE)

### Region: South Asia (Mumbai)
### Project: URA FLOW

### Database Tables (all created)

#### `profiles`
- `id` UUID (PK, references auth.users)
- `full_name` TEXT NOT NULL
- `phone` TEXT
- `role` user_role ENUM ('verifier', 'rep', 'storage_actor')
- `is_approved` BOOLEAN DEFAULT FALSE
- `created_at` TIMESTAMPTZ

#### `entities`
- `id` UUID (PK)
- `name` TEXT NOT NULL
- `type` entity_type ENUM ('customer', 'supplier')
- `contact_name` TEXT
- `contact_phone` TEXT
- `address` TEXT
- `created_at` TIMESTAMPTZ

#### `inventory`
- `id` UUID (PK)
- `item_name` TEXT NOT NULL
- `sku` TEXT UNIQUE
- `quantity` INTEGER NOT NULL DEFAULT 0 CHECK (>= 0)
- `min_threshold` INTEGER DEFAULT 0
- `unit` TEXT DEFAULT 'piece'
- `created_at` TIMESTAMPTZ
- `updated_at` TIMESTAMPTZ (auto-updated via trigger)

#### `orders`
- `id` UUID (PK)
- `direction` order_direction ENUM ('outbound', 'inbound_rep', 'inbound_external')
- `entity_id` UUID FK → entities
- `rep_id` UUID FK → profiles (nullable for inbound_external)
- `status` order_status ENUM ('assigned', 'picked_up', 'on_the_move', 'delivered')
- `notes` TEXT
- `created_by` UUID FK → profiles
- `created_at`, `assigned_at`, `picked_up_at`, `move_started_at`, `delivered_at` TIMESTAMPTZ
- CONSTRAINT: inbound_external must have rep_id NULL; all others must have rep_id NOT NULL

#### `order_items`
- `id` UUID (PK)
- `order_id` UUID FK → orders (CASCADE)
- `inventory_id` UUID FK → inventory (nullable for custom items)
- `quantity` INTEGER NOT NULL CHECK (> 0)
- `is_custom` BOOLEAN DEFAULT FALSE
- `custom_description` TEXT
- `check_status` item_check_status ENUM ('pending', 'checked', 'rejected') DEFAULT 'pending'
- `checked_by` UUID FK → profiles
- `checked_at` TIMESTAMPTZ
- `created_at` TIMESTAMPTZ
- CONSTRAINT: custom items must have description and no inventory_id; non-custom must have inventory_id and no description

#### `receipts`
- `id` UUID (PK)
- `order_id` UUID FK → orders (CASCADE)
- `order_item_id` UUID FK → order_items (links receipt to specific custom item)
- `image_url` TEXT NOT NULL
- `uploaded_by` UUID FK → profiles
- `uploaded_at` TIMESTAMPTZ

#### `audit_log`
- `id` UUID (PK)
- `order_id` UUID FK → orders (CASCADE)
- `action` TEXT NOT NULL
- `old_status` order_status
- `new_status` order_status
- `performed_by` UUID FK → profiles
- `details` TEXT
- `server_timestamp` TIMESTAMPTZ

### Enums
- `user_role`: verifier, rep, storage_actor
- `entity_type`: customer, supplier
- `order_direction`: outbound, inbound_rep, inbound_external
- `order_status`: assigned, picked_up, on_the_move, delivered
- `item_check_status`: pending, checked, rejected

### Database Functions (callable via supabase.rpc())

#### `approve_transaction(target_order_id UUID)` → JSONB
- Only storage_actor can call
- Checks ALL non-custom items have check_status = 'checked'
- Processes inventory math (subtract for outbound, add for inbound)
- Checks sufficient stock for outbound
- Updates order status to 'picked_up'
- Logs to audit_log
- Returns {success: bool, error/message: string}

#### `start_move(target_order_id UUID)` → JSONB
- Only the assigned rep can call
- Order must be in 'picked_up' status (Storage Actor must have approved)
- Updates status to 'on_the_move'
- Returns {success: bool, error/message: string}

#### `mark_delivered(target_order_id UUID)` → JSONB
- Only the assigned rep can call
- Order must be in 'on_the_move' status
- Checks every custom item has a receipt linked via order_item_id
- Updates status to 'delivered'
- Returns {success: bool, error/message: string}

#### `check_order_item(target_item_id UUID, new_status item_check_status)` → JSONB
- Only storage_actor can call
- Order must still be in 'assigned' status
- Updates the item's check_status, checked_by, checked_at
- Returns {success: bool, error/message: string}

#### `approve_user(target_user_id UUID, assigned_role user_role)` → JSONB
- Only verifier can call
- Sets user's role and is_approved = true
- Returns {success: bool, error/message: string}

#### `get_user_role()` → user_role
- Helper function used internally by RLS policies
- Returns the role of the currently authenticated user

### Row-Level Security (RLS) — All Enabled

- **profiles:** Approved users see all profiles; unapproved see only their own. Users update own profile. Verifiers can update any profile.
- **entities:** Only approved users can view. Only verifiers can create/update.
- **inventory:** Only approved users can view. Verifiers and storage_actors can create/update.
- **orders:** Verifiers see all. Reps see only their assigned orders. Storage actors see assigned/picked_up orders. All must be approved.
- **order_items:** Visible if user can see the parent order. Verifiers can add/update. Storage actors can update check_status on assigned orders.
- **receipts:** Visible if user can see the parent order. Reps can upload for their own orders.
- **audit_log:** Verifiers see all. Others see logs for orders they can access. System inserts via trigger.

### Automatic Triggers
- `inventory_updated_at` — auto-updates `updated_at` on inventory changes
- `order_status_audit` — auto-logs to audit_log on every order status change

### Seed Data (loaded from real Excel file)
- 27 customers (government entities, projects)
- 83 suppliers
- 190 inventory items with real current stock quantities
- Data is in Arabic (item names, entity names, etc.)

---

## 8. Frontend — Flutter (TO BUILD)

### Tech Stack
- **Framework:** Flutter (cross-platform: Android, iOS, tablet, desktop)
- **State Management:** BLoC/Cubit (flutter_bloc)
- **Routing:** go_router (declarative, role-based)
- **Packages:** supabase_flutter, flutter_bloc, equatable, go_router, image_picker, cached_network_image

### Folder Structure
```
lib/
├── main.dart
├── app.dart
├── config/
│   └── supabase_config.dart
├── router/
│   └── app_router.dart
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   └── auth_repository.dart
│   │   ├── logic/
│   │   │   ├── auth_cubit.dart
│   │   │   └── auth_state.dart
│   │   └── ui/
│   │       ├── login_screen.dart
│   │       ├── register_screen.dart
│   │       └── pending_approval_screen.dart
│   ├── verifier/
│   │   └── ui/
│   │       └── verifier_home_screen.dart
│   ├── rep/
│   │   └── ui/
│   │       └── rep_home_screen.dart
│   └── storage/
│       └── ui/
│           └── storage_home_screen.dart
└── shared/
    ├── models/
    │   └── profile.dart
    └── widgets/
```

### Auth Flow
1. User opens app → checks if session exists
2. No session → Login/Register screen
3. Session exists → fetch profile from `profiles` table
4. If `is_approved == false` → Pending Approval screen
5. If approved → route based on `role`:
   - verifier → Verifier Home
   - rep → Rep Home
   - storage_actor → Storage Home

### Registration Flow
1. User signs up with email + password + full name
2. Profile created with `is_approved = false` and `role = 'rep'` (default, will be changed by verifier)
3. User sees "Waiting for approval" screen
4. Verifier sees pending users → approves and assigns correct role
5. User restarts app or refreshes → routed to their role dashboard

### IMPORTANT: First User Bootstrap
After the very first signup, manually run in Supabase SQL Editor:
```sql
UPDATE profiles SET role = 'verifier', is_approved = true WHERE id = 'YOUR_USER_ID';
```
This creates the first Verifier who can then approve everyone else.

---

## 9. Build Phases (Roadmap)

### Phase 1 — Foundation (Current)
- [x] Supabase project setup
- [x] Database schema (all tables)
- [x] RLS policies
- [x] Database functions (approve_transaction, start_move, mark_delivered, check_order_item, approve_user)
- [x] Two-checkpoint system (Storage Actor checkmarks + Rep per-item receipts)
- [x] User approval system
- [x] Seed data from real Excel
- [ ] Flutter project created with packages
- [ ] Supabase connection
- [ ] Auth flow (login, register, pending approval)
- [ ] Role-based routing

### Phase 2 — Verifier Flow
- [ ] Unassigned orders tab (gray orders waiting for rep)
- [ ] Order creation form
- [ ] Entity picker, Rep assignment
- [ ] Assigned orders tab with progress bars
- [ ] Pending users management (approve/assign roles)
- [ ] Desktop/tablet responsive layout

### Phase 3 — Rep Flow
- [ ] "My Tasks" list
- [ ] Phase-by-phase order detail view
- [ ] "Confirm Arrival at Warehouse" button
- [ ] "Start Move" button (locked until Storage Actor approves)
- [ ] Receipt camera upload per custom item
- [ ] "Mark as Delivered" button (locked until all receipts uploaded)

### Phase 4 — Storage Actor Flow
- [ ] Action feed (Reps at the warehouse gate)
- [ ] Order detail with item checklist (✓/✗ per item)
- [ ] "Approve Transaction" button (locked until all items checked)
- [ ] Inventory view
- [ ] Quick Receipt for ad-hoc deliveries

### Phase 5 — Real-Time & Polish
- [ ] Supabase Realtime subscriptions
- [ ] Live progress bar updates for Verifier
- [ ] Live feed refresh for Storage Actor
- [ ] Button unlock animations when approval happens
- [ ] Edge case handling
- [ ] Audit log viewer

### Phase 6 — Inbound Flows & Restocking
- [ ] Inbound via Rep (reversed flow)
- [ ] Inbound External (no Rep, Storage Actor + Verifier only)
- [ ] Ad-hoc Quick Receipt
- [ ] Restocking alerts (min_threshold)

---

## 10. Supabase Connection Details

**IMPORTANT:** Replace these with your actual values from Supabase Dashboard → Project Settings → API

```dart
// config/supabase_config.dart
class SupabaseConfig {
  static const String url = 'YOUR_SUPABASE_URL';      // e.g. https://xxxxx.supabase.co
  static const String anonKey = 'YOUR_ANON_KEY';       // starts with eyJ...
}
```

---

## 11. Key Supabase Calls Reference (for Flutter)

```dart
// AUTH
await supabase.auth.signUp(email: e, password: p);
await supabase.auth.signInWithPassword(email: e, password: p);
await supabase.auth.signOut();
final user = supabase.auth.currentUser;

// PROFILE
await supabase.from('profiles').insert({...});
await supabase.from('profiles').select().eq('id', userId).single();
await supabase.from('profiles').select().eq('is_approved', false);  // pending users

// ORDERS
await supabase.from('orders').select('*, entity:entities(*), rep:profiles(*)');
await supabase.from('orders').insert({...});

// ORDER ITEMS
await supabase.from('order_items').select().eq('order_id', orderId);

// RPC CALLS (database functions)
await supabase.rpc('approve_transaction', params: {'target_order_id': orderId});
await supabase.rpc('start_move', params: {'target_order_id': orderId});
await supabase.rpc('mark_delivered', params: {'target_order_id': orderId});
await supabase.rpc('check_order_item', params: {'target_item_id': itemId, 'new_status': 'checked'});
await supabase.rpc('approve_user', params: {'target_user_id': userId, 'assigned_role': 'rep'});

// STORAGE (receipt images)
await supabase.storage.from('receipts').upload(filePath, file);
final url = supabase.storage.from('receipts').getPublicUrl(filePath);

// REALTIME (for later)
supabase.from('orders').stream(primaryKey: ['id']).listen((data) { ... });
```

---

## 12. Data Context

The company deals with food/beverage inventory (coffee, tea, dates, nuts, chocolate, water, cups, filters, sugar, milk, etc.) serving government entities and organizations in Saudi Arabia. All data is in Arabic. The app UI should support Arabic (RTL) as the primary language.
