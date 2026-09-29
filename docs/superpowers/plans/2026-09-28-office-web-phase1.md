# Office Web Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the foundation (auth, shell, routing) plus the verifier orders list and order-detail panel of the new office desktop website, in a new `office_web/` project inside this repo.

**Architecture:** Vite + React 18 + TypeScript SPA, Tailwind CSS styled from the Stitch-derived design tokens, `@supabase/supabase-js` talking to the exact same Supabase project/tables/RLS the Flutter app already uses (zero backend changes), TanStack Query for data fetching and TanStack Table for the dense orders grid, React Router for `/login`, `/orders`, `/orders/:id`.

**Tech Stack:** React 18, TypeScript, Vite, Tailwind CSS, react-router-dom, @supabase/supabase-js, @tanstack/react-query, @tanstack/react-table, Vitest, @testing-library/react, @testing-library/jest-dom, @testing-library/user-event.

**Spec:** `docs/superpowers/specs/2026-09-28-office-web-phase1-design.md`

## Global Constraints

- Branch `feat/office-web` (already created off `main`). All work in this plan happens inside a new `office_web/` folder at the repo root — never touch `lib/` (the Flutter app).
- No backend changes: no new tables, columns, RPCs, or migrations. Every query mirrors an existing Flutter query's exact `select` shape.
- RTL throughout: `<html dir="rtl" lang="ar">`, right-anchored sidebar, all Arabic copy exactly as specified (this app's real domain vocabulary, never invented logistics jargon).
- View-only in phase 1: no create/edit/delete actions on orders from the website.
- Only `profiles.role === 'verifier'` may reach `/orders`; other authenticated roles see a "not available" screen, not a redirect loop.
- Visual tokens come from `stitch_ui/light mode/rouh_alnomu_enterprise_system/DESIGN.md` (primary `#D97706`/`#F59E0B`, secondary `#65A30D`/`#16A34A`, surfaces/text/semantic colors as listed there) — but status colors specifically reuse the app's existing traffic-light values from `lib/core/design_system/theme/colors/order_status_colors.dart` (`assigned` #E53935, `pickedUp` #FB8C00, `onTheMove` #FBC02D, `delivered`/`deliveredToStorage` #43A047), so the website and the Flutter app agree on what each order status looks like.
- Every task ends green: `npm run build`, `npm test`, and (once configured in Task 1) `npm run lint` all pass before its commit.

## Review Focus

- An order with zero `audit_log` rows yet (just created, nothing beyond `order_created`) — the timeline and stepper must render sensibly, not crash or show a blank gap. Covered in Task 12.
- An authenticated user whose `profiles.role` is not `verifier` (e.g. a rep signs into the website by mistake) — must see a plain "not available for your role" screen, never a redirect loop or a blank page. Covered in Task 7.
- Wrong password / expired session on login — the error must surface inline on the form, never a silent failure or an uncaught promise rejection. Covered in Task 6.
- An order with no سند استلام attached — the receipts section must show an empty state, not an error or a missing section that looks broken. Covered in Task 11 and Task 12.
- An empty orders list (new org, or every filter combination excludes everything) — the table must show a real empty state with the search/filter values visible, not a blank white table. Covered in Task 10.

---

## Task 1: Project scaffold, Tailwind tokens, test harness

**Files:**
- Create: `office_web/` (via `npm create vite@latest`)
- Create: `office_web/tailwind.config.ts`
- Create: `office_web/postcss.config.js`
- Create: `office_web/src/index.css`
- Modify: `office_web/index.html`
- Create: `office_web/vitest.config.ts`
- Create: `office_web/src/test/setup.ts`
- Create: `office_web/src/App.test.tsx`
- Modify: `office_web/package.json` (scripts, deps)

**Interfaces:**
- Produces: Tailwind color tokens `primary`, `primary-fill`, `secondary`, `surface`, `surface-card`, `surface-inset`, `border-subtle`, `text-high`, `text-medium`, `text-low`, `success`, `success-bg`, `warning`, `warning-bg`, `error`, `error-bg` (used by every later task's markup).
- Produces: `npm run dev`, `npm run build`, `npm test`, `npm run lint` scripts.

- [ ] **Step 1: Scaffold the Vite project**

```bash
cd /c/MSOC/flutter_projects/ura_core
npm create vite@latest office_web -- --template react-ts
cd office_web
npm install
```

- [ ] **Step 2: Install runtime and dev dependencies**

```bash
npm install react-router-dom @supabase/supabase-js @tanstack/react-query @tanstack/react-table
npm install -D tailwindcss postcss autoprefixer vitest jsdom @testing-library/react @testing-library/jest-dom @testing-library/user-event eslint-plugin-react-hooks
npx tailwindcss init -p
```

- [ ] **Step 3: Write the Tailwind config with the design tokens**

Replace `office_web/tailwind.config.ts` with:

```ts
import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        primary: '#D97706',
        'primary-fill': '#F59E0B',
        secondary: '#65A30D',
        'secondary-light': '#16A34A',
        surface: '#F8FAFC',
        'surface-card': '#FFFFFF',
        'surface-inset': '#F1F5F9',
        'border-subtle': '#E2E8F0',
        'text-high': '#0F172A',
        'text-medium': '#334155',
        'text-low': '#64748B',
        success: '#15803D',
        'success-bg': '#F0FDF4',
        warning: '#B45309',
        'warning-bg': '#FEF3C7',
        error: '#B91C1C',
        'error-bg': '#FEF2F2',
      },
      fontFamily: {
        sans: ['"IBM Plex Sans Arabic"', '"IBM Plex Sans"', 'sans-serif'],
      },
      borderRadius: {
        input: '4px',
        button: '6px',
        card: '8px',
      },
    },
  },
  plugins: [],
} satisfies Config;
```

- [ ] **Step 4: Write the base stylesheet**

Replace `office_web/src/index.css` with:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  @apply bg-surface text-text-high font-sans;
  font-feature-settings: 'tnum' 1;
}
```

- [ ] **Step 5: Set RTL and the font link on the HTML shell**

Replace `office_web/index.html` with:

```html
<!doctype html>
<html lang="ar" dir="rtl">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link
      href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap"
      rel="stylesheet"
    />
    <title>روح النمو المتحدة — منظومة العمليات</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

- [ ] **Step 6: Configure Vitest**

Create `office_web/vitest.config.ts`:

```ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    setupFiles: './src/test/setup.ts',
    globals: true,
  },
});
```

Create `office_web/src/test/setup.ts`:

```ts
import '@testing-library/jest-dom/vitest';
```

- [ ] **Step 7: Add npm scripts**

In `office_web/package.json`, under `"scripts"`, add:

```json
"test": "vitest run",
"lint": "eslint ."
```

- [ ] **Step 8: Write a smoke test proving the harness works**

Create `office_web/src/App.test.tsx`:

```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import App from './App';

describe('App', () => {
  it('renders without crashing', () => {
    render(<App />);
    expect(document.body).toBeInTheDocument();
  });
});
```

Replace `office_web/src/App.tsx` with a placeholder that will be filled in by Task 8:

```tsx
export default function App() {
  return <div>روح النمو المتحدة</div>;
}
```

- [ ] **Step 9: Run the test suite to verify it passes**

Run: `cd office_web && npm test`
Expected: 1 test passed (`App renders without crashing`)

- [ ] **Step 10: Verify the production build works**

Run: `cd office_web && npm run build`
Expected: exits 0, produces `office_web/dist/`

- [ ] **Step 11: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web
git commit -m "feat(office-web): scaffold Vite/React/Tailwind project with design tokens"
```

---

## Task 2: Supabase client and environment config

**Files:**
- Create: `office_web/.env.local` (gitignored)
- Create: `office_web/.env.example`
- Modify: `office_web/.gitignore`
- Create: `office_web/src/lib/supabase.ts`
- Test: `office_web/src/lib/supabase.test.ts`

**Interfaces:**
- Produces: `supabase: SupabaseClient` (default export-free named export) from `src/lib/supabase.ts`, imported by every later data-layer file as `import { supabase } from '../lib/supabase'`.

- [ ] **Step 1: Write the failing test**

Create `office_web/src/lib/supabase.test.ts`:

```ts
import { describe, it, expect, vi, beforeEach } from 'vitest';

describe('supabase client', () => {
  beforeEach(() => {
    vi.stubEnv('VITE_SUPABASE_URL', 'https://musaqyislgvshurfrjwx.supabase.co');
    vi.stubEnv(
      'VITE_SUPABASE_ANON_KEY',
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im11c2FxeWlzbGd2c2h1cmZyand4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNDcwODgsImV4cCI6MjA5MDYyMzA4OH0.gR2k3UkW70GuBIZ69qz6WXvlFT1EMOpYlJCOtwBLF_M',
    );
  });

  it('creates a client pointed at the configured URL', async () => {
    vi.resetModules();
    const { supabase } = await import('./supabase');
    expect(supabase.supabaseUrl).toBe('https://musaqyislgvshurfrjwx.supabase.co');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/lib/supabase.test.ts`
Expected: FAIL — `Cannot find module './supabase'`

- [ ] **Step 3: Write the client module**

Create `office_web/src/lib/supabase.ts`:

```ts
import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL as string;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string;

if (!url || !anonKey) {
  throw new Error('Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY');
}

export const supabase = createClient(url, anonKey);
```

- [ ] **Step 4: Create the real env file and the example file**

Create `office_web/.env.local` (this file is gitignored — same publicly-embeddable anon key already committed in `lib/config/supabase_config.dart`; RLS, not key secrecy, is the security boundary):

```
VITE_SUPABASE_URL=https://musaqyislgvshurfrjwx.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im11c2FxeWlzbGd2c2h1cmZyand4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNDcwODgsImV4cCI6MjA5MDYyMzA4OH0.gR2k3UkW70GuBIZ69qz6WXvlFT1EMOpYlJCOtwBLF_M
```

Create `office_web/.env.example`:

```
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
```

Add to `office_web/.gitignore`:

```
.env.local
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/lib/supabase.test.ts`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/.env.example office_web/.gitignore office_web/src/lib/supabase.ts office_web/src/lib/supabase.test.ts
git commit -m "feat(office-web): add Supabase client"
```

---

## Task 3: Domain types and row mappers

**Files:**
- Create: `office_web/src/types/domain.ts`
- Create: `office_web/src/lib/mappers.ts`
- Test: `office_web/src/lib/mappers.test.ts`

**Interfaces:**
- Produces: types `Profile`, `Entity`, `OrderItem`, `Order`, `AuditLogEntry`, `DeliveryReceipt`, `DeliveryReceiptItem` and their status/direction string unions, from `src/types/domain.ts`.
- Produces: `mapProfile(row): Profile`, `mapEntity(row): Entity`, `mapOrderItem(row): OrderItem`, `mapOrder(row): Order`, `mapAuditLogEntry(row): AuditLogEntry`, `mapDeliveryReceipt(row): DeliveryReceipt` from `src/lib/mappers.ts`, consumed by Tasks 4 and 11.

- [ ] **Step 1: Write the domain types**

Create `office_web/src/types/domain.ts`:

```ts
export type OrderDirection = 'outbound' | 'inbound_rep' | 'inbound_external';
export type OrderStatus = 'assigned' | 'picked_up' | 'on_the_move' | 'delivered' | 'delivered_to_storage';
export type ItemCheckStatus = 'pending' | 'checked' | 'rejected';
export type UserRole = 'verifier' | 'rep' | 'storage_actor' | 'manager' | 'admin';

export const orderDirectionLabel: Record<OrderDirection, string> = {
  outbound: 'توريد',
  inbound_rep: 'مشتريات مندوب داخلي',
  inbound_external: 'مشتريات مندوب خارجي',
};

export const orderStatusLabel: Record<OrderStatus, string> = {
  assigned: 'معين',
  picked_up: 'تم الاستلام',
  on_the_move: 'في الطريق',
  delivered: 'تم التسليم',
  delivered_to_storage: 'تم الاستلام في المخزن',
};

export interface Profile {
  id: string;
  fullName: string;
  phone: string | null;
  role: UserRole | null;
  isApproved: boolean;
}

export interface Entity {
  id: string;
  name: string;
  category: string;
  contactName: string | null;
  contactPhone: string | null;
  address: string | null;
}

export interface OrderItem {
  id: string;
  orderId: string;
  inventoryId: string | null;
  inventoryName: string | null;
  quantity: number;
  finalQuantity: number | null;
  isCustom: boolean;
  customDescription: string | null;
  checkStatus: ItemCheckStatus;
  checkedBy: string | null;
  checker: Profile | null;
  wasUnavailableAtCreation: boolean;
}

export interface Order {
  id: string;
  referenceCode: string | null;
  direction: OrderDirection;
  entityId: string;
  entity: Entity | null;
  repId: string | null;
  rep: Profile | null;
  creator: Profile | null;
  status: OrderStatus;
  notes: string | null;
  storageActorId: string | null;
  createdAt: string | null;
  assignedAt: string | null;
  pickedUpAt: string | null;
  moveStartedAt: string | null;
  deliveredAt: string | null;
  items: OrderItem[];
}

export interface AuditLogEntry {
  id: string;
  orderId: string;
  action: string;
  oldStatus: OrderStatus | null;
  newStatus: OrderStatus | null;
  performer: Profile | null;
  notes: string | null;
  serverTimestamp: string | null;
}

export interface DeliveryReceiptItem {
  id: string;
  itemNameSnapshot: string;
  unitSnapshot: string;
  quantityDelivered: number;
}

export interface DeliveryReceipt {
  id: string;
  orderId: string | null;
  rep: Profile | null;
  deliveredAt: string | null;
  pdfUrl: string | null;
  notes: string | null;
  createdAt: string | null;
  items: DeliveryReceiptItem[];
}
```

- [ ] **Step 2: Write the failing mapper tests**

Create `office_web/src/lib/mappers.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { mapProfile, mapEntity, mapOrderItem, mapOrder, mapAuditLogEntry, mapDeliveryReceipt } from './mappers';

describe('mapProfile', () => {
  it('maps a profile row', () => {
    const p = mapProfile({ id: 'u1', full_name: 'أحمد', phone: '0500000000', role: 'verifier', is_approved: true });
    expect(p).toEqual({ id: 'u1', fullName: 'أحمد', phone: '0500000000', role: 'verifier', isApproved: true });
  });

  it('returns null role for an unknown value', () => {
    const p = mapProfile({ id: 'u1', full_name: 'أحمد', phone: null, role: null, is_approved: false });
    expect(p.role).toBeNull();
  });
});

describe('mapEntity', () => {
  it('maps an entity row', () => {
    const e = mapEntity({ id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contact_name: null, contact_phone: null, address: null });
    expect(e).toEqual({ id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contactName: null, contactPhone: null, address: null });
  });
});

describe('mapOrderItem', () => {
  it('maps a non-custom item with its inventory join', () => {
    const item = mapOrderItem({
      id: 'i1',
      order_id: 'o1',
      inventory_id: 'inv1',
      quantity: 5,
      final_quantity: null,
      is_custom: false,
      custom_description: null,
      check_status: 'checked',
      checked_by: 'u2',
      was_unavailable_at_creation: false,
      inventory: { id: 'inv1', item_name: 'أكياس أرز' },
      checker: null,
    });
    expect(item.inventoryName).toBe('أكياس أرز');
    expect(item.checkStatus).toBe('checked');
  });

  it('defaults check_status to pending when null', () => {
    const item = mapOrderItem({
      id: 'i1', order_id: 'o1', inventory_id: null, quantity: 1, final_quantity: null,
      is_custom: true, custom_description: 'صنف خاص', check_status: null,
      checked_by: null, was_unavailable_at_creation: false, inventory: null, checker: null,
    });
    expect(item.checkStatus).toBe('pending');
  });
});

describe('mapOrder', () => {
  it('maps an order row with nested entity/rep/items', () => {
    const order = mapOrder({
      id: 'o1', reference_code: 'RN-1', direction: 'outbound', entity_id: 'e1',
      entity: { id: 'e1', name: 'وزارة', category: 'outgoing', contact_name: null, contact_phone: null, address: null },
      rep_id: 'u1', rep: { id: 'u1', full_name: 'مندوب', phone: null, role: 'rep', is_approved: true },
      creator: null, status: 'delivered', notes: null, storage_actor_id: null,
      created_at: '2026-09-28T10:00:00Z', assigned_at: null, picked_up_at: null, move_started_at: null,
      delivered_at: '2026-09-28T12:00:00Z',
      order_items: [{
        id: 'i1', order_id: 'o1', inventory_id: null, quantity: 2, final_quantity: null,
        is_custom: true, custom_description: 'صنف', check_status: 'pending', checked_by: null,
        was_unavailable_at_creation: false, inventory: null, checker: null,
      }],
    });
    expect(order.entity?.name).toBe('وزارة');
    expect(order.items).toHaveLength(1);
    expect(order.status).toBe('delivered');
  });

  it('defaults status to assigned for an unknown value and items to an empty array when absent', () => {
    const order = mapOrder({
      id: 'o1', reference_code: null, direction: 'outbound', entity_id: 'e1', entity: null,
      rep_id: null, rep: null, creator: null, status: 'unknown_status', notes: null,
      storage_actor_id: null, created_at: null, assigned_at: null, picked_up_at: null,
      move_started_at: null, delivered_at: null, order_items: null,
    });
    expect(order.status).toBe('assigned');
    expect(order.items).toEqual([]);
  });
});

describe('mapAuditLogEntry', () => {
  it('maps an audit log row', () => {
    const entry = mapAuditLogEntry({
      id: 'a1', order_id: 'o1', action: 'status_changed', old_status: 'assigned', new_status: 'picked_up',
      performer: { id: 'u1', full_name: 'مندوب', phone: null, role: 'rep', is_approved: true },
      notes: null, server_timestamp: '2026-09-28T10:05:00Z',
    });
    expect(entry.newStatus).toBe('picked_up');
    expect(entry.performer?.fullName).toBe('مندوب');
  });
});

describe('mapDeliveryReceipt', () => {
  it('maps a delivery receipt row with its items', () => {
    const receipt = mapDeliveryReceipt({
      id: 'r1', order_id: 'o1', rep: { id: 'u1', full_name: 'مندوب', phone: null, role: 'rep', is_approved: true },
      delivered_at: null, pdf_url: 'org/u1/1.pdf', notes: null, created_at: '2026-09-28T09:00:00Z',
      delivery_receipt_items: [{ id: 'di1', item_name_snapshot: 'كرسي', unit_snapshot: 'حبة', quantity_delivered: 3 }],
    });
    expect(receipt.pdfUrl).toBe('org/u1/1.pdf');
    expect(receipt.items[0].itemNameSnapshot).toBe('كرسي');
  });
});
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd office_web && npx vitest run src/lib/mappers.test.ts`
Expected: FAIL — `Cannot find module './mappers'`

- [ ] **Step 4: Write the mappers**

Create `office_web/src/lib/mappers.ts`:

```ts
import type {
  Profile, Entity, OrderItem, Order, AuditLogEntry, DeliveryReceipt,
  OrderStatus, OrderDirection, ItemCheckStatus, UserRole,
} from '../types/domain';

const VALID_STATUSES: OrderStatus[] = ['assigned', 'picked_up', 'on_the_move', 'delivered', 'delivered_to_storage'];
const VALID_DIRECTIONS: OrderDirection[] = ['outbound', 'inbound_rep', 'inbound_external'];
const VALID_CHECK_STATUSES: ItemCheckStatus[] = ['pending', 'checked', 'rejected'];
const VALID_ROLES: UserRole[] = ['verifier', 'rep', 'storage_actor', 'manager', 'admin'];

function asStatus(value: string | null): OrderStatus {
  return VALID_STATUSES.includes(value as OrderStatus) ? (value as OrderStatus) : 'assigned';
}

function asDirection(value: string): OrderDirection {
  return VALID_DIRECTIONS.includes(value as OrderDirection) ? (value as OrderDirection) : 'outbound';
}

function asCheckStatus(value: string | null): ItemCheckStatus {
  return VALID_CHECK_STATUSES.includes(value as ItemCheckStatus) ? (value as ItemCheckStatus) : 'pending';
}

function asRole(value: string | null): UserRole | null {
  return VALID_ROLES.includes(value as UserRole) ? (value as UserRole) : null;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapProfile(row: any): Profile {
  return {
    id: row.id,
    fullName: row.full_name,
    phone: row.phone ?? null,
    role: asRole(row.role ?? null),
    isApproved: row.is_approved ?? false,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapEntity(row: any): Entity {
  return {
    id: row.id,
    name: row.name,
    category: row.category,
    contactName: row.contact_name ?? null,
    contactPhone: row.contact_phone ?? null,
    address: row.address ?? null,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapOrderItem(row: any): OrderItem {
  return {
    id: row.id,
    orderId: row.order_id,
    inventoryId: row.inventory_id ?? null,
    inventoryName: row.inventory?.item_name ?? null,
    quantity: Number(row.quantity),
    finalQuantity: row.final_quantity != null ? Number(row.final_quantity) : null,
    isCustom: !!row.is_custom,
    customDescription: row.custom_description ?? null,
    checkStatus: asCheckStatus(row.check_status ?? null),
    checkedBy: row.checked_by ?? null,
    checker: row.checker ? mapProfile(row.checker) : null,
    wasUnavailableAtCreation: !!row.was_unavailable_at_creation,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapOrder(row: any): Order {
  return {
    id: row.id,
    referenceCode: row.reference_code ?? null,
    direction: asDirection(row.direction),
    entityId: row.entity_id,
    entity: row.entity ? mapEntity(row.entity) : null,
    repId: row.rep_id ?? null,
    rep: row.rep ? mapProfile(row.rep) : null,
    creator: row.creator ? mapProfile(row.creator) : null,
    status: asStatus(row.status),
    notes: row.notes ?? null,
    storageActorId: row.storage_actor_id ?? null,
    createdAt: row.created_at ?? null,
    assignedAt: row.assigned_at ?? null,
    pickedUpAt: row.picked_up_at ?? null,
    moveStartedAt: row.move_started_at ?? null,
    deliveredAt: row.delivered_at ?? null,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    items: (row.order_items ?? []).map((i: any) => mapOrderItem(i)),
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapAuditLogEntry(row: any): AuditLogEntry {
  return {
    id: row.id,
    orderId: row.order_id,
    action: row.action,
    oldStatus: row.old_status ? asStatus(row.old_status) : null,
    newStatus: row.new_status ? asStatus(row.new_status) : null,
    performer: row.performer ? mapProfile(row.performer) : null,
    notes: row.notes ?? null,
    serverTimestamp: row.server_timestamp ?? null,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function mapDeliveryReceipt(row: any): DeliveryReceipt {
  return {
    id: row.id,
    orderId: row.order_id ?? null,
    rep: row.rep ? mapProfile(row.rep) : null,
    deliveredAt: row.delivered_at ?? null,
    pdfUrl: row.pdf_url ?? null,
    notes: row.notes ?? null,
    createdAt: row.created_at ?? null,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    items: (row.delivery_receipt_items ?? []).map((i: any) => ({
      id: i.id,
      itemNameSnapshot: i.item_name_snapshot,
      unitSnapshot: i.unit_snapshot,
      quantityDelivered: Number(i.quantity_delivered),
    })),
  };
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd office_web && npx vitest run src/lib/mappers.test.ts`
Expected: PASS — 8 tests

- [ ] **Step 6: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/src/types/domain.ts office_web/src/lib/mappers.ts office_web/src/lib/mappers.test.ts
git commit -m "feat(office-web): add domain types and Supabase row mappers"
```

---

## Task 4: Orders query and hook

**Files:**
- Create: `office_web/src/api/orders.ts`
- Test: `office_web/src/api/orders.test.ts`
- Create: `office_web/src/hooks/useOrders.ts`

**Interfaces:**
- Consumes: `mapOrder` from `../lib/mappers`, `supabase` from `../lib/supabase`.
- Produces: `ORDER_SELECT: string`, `async function fetchOrders(): Promise<Order[]>` from `src/api/orders.ts`. `function useOrders()` (TanStack Query hook returning `{ data, isLoading, isError, error, refetch }`) from `src/hooks/useOrders.ts`, consumed by Task 10.

- [ ] **Step 1: Write the failing test**

Create `office_web/src/api/orders.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest';
import { fetchOrders, ORDER_SELECT } from './orders';

vi.mock('../lib/supabase', () => {
  const order = vi.fn().mockResolvedValue({
    data: [{
      id: 'o1', reference_code: null, direction: 'outbound', entity_id: 'e1', entity: null,
      rep_id: null, rep: null, creator: null, status: 'assigned', notes: null,
      storage_actor_id: null, created_at: '2026-09-28T10:00:00Z', assigned_at: null,
      picked_up_at: null, move_started_at: null, delivered_at: null, order_items: [],
    }],
    error: null,
  });
  const select = vi.fn().mockReturnValue({ order });
  const from = vi.fn().mockReturnValue({ select });
  return { supabase: { from } };
});

describe('fetchOrders', () => {
  it('queries the orders table with the full join select and maps rows', async () => {
    const { supabase } = await import('../lib/supabase');
    const orders = await fetchOrders();
    expect(supabase.from).toHaveBeenCalledWith('orders');
    expect(supabase.from('orders').select).toHaveBeenCalledWith(ORDER_SELECT);
    expect(orders).toHaveLength(1);
    expect(orders[0].id).toBe('o1');
  });
});

describe('fetchOrders error handling', () => {
  it('throws when Supabase returns an error', async () => {
    vi.resetModules();
    vi.doMock('../lib/supabase', () => {
      const order = vi.fn().mockResolvedValue({ data: null, error: { message: 'network down' } });
      const select = vi.fn().mockReturnValue({ order });
      const from = vi.fn().mockReturnValue({ select });
      return { supabase: { from } };
    });
    const { fetchOrders: fetchOrdersFresh } = await import('./orders');
    await expect(fetchOrdersFresh()).rejects.toThrow('network down');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/api/orders.test.ts`
Expected: FAIL — `Cannot find module './orders'`

- [ ] **Step 3: Write the query module**

Create `office_web/src/api/orders.ts`:

```ts
import { supabase } from '../lib/supabase';
import { mapOrder } from '../lib/mappers';
import type { Order } from '../types/domain';

// Mirrors OrderRepository._orderSelect in lib/features/verifier/data/order_repository.dart
export const ORDER_SELECT =
  '*, ' +
  'entity:entities(*), ' +
  'rep:profiles!orders_rep_id_fkey(id, full_name, role, is_approved, phone, created_at), ' +
  'creator:profiles!orders_created_by_fkey(id, full_name, role, is_approved, phone, created_at), ' +
  'order_items(*, inventory:inventory!order_items_inventory_id_fkey(id, item_name))';

export async function fetchOrders(): Promise<Order[]> {
  const { data, error } = await supabase.from('orders').select(ORDER_SELECT).order('created_at', { ascending: false });
  if (error) throw new Error(error.message);
  return (data ?? []).map(mapOrder);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/api/orders.test.ts`
Expected: PASS — 2 tests

- [ ] **Step 5: Write the TanStack Query hook**

Create `office_web/src/hooks/useOrders.ts`:

```ts
import { useQuery } from '@tanstack/react-query';
import { fetchOrders } from '../api/orders';

export function useOrders() {
  return useQuery({ queryKey: ['orders'], queryFn: fetchOrders });
}
```

- [ ] **Step 6: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/src/api/orders.ts office_web/src/api/orders.test.ts office_web/src/hooks/useOrders.ts
git commit -m "feat(office-web): add orders query and useOrders hook"
```

---

## Task 5: Order filter/sort/group pure functions

**Files:**
- Create: `office_web/src/lib/orderFilters.ts`
- Test: `office_web/src/lib/orderFilters.test.ts`

**Interfaces:**
- Consumes: `Order`, `OrderDirection` from `../types/domain`.
- Produces: `type SortMode = 'most_recent' | 'oldest' | 'frequent'`, `type DirectionFilter = 'all' | 'outbound' | 'inbound_rep' | 'inbound_external'`, `type GroupMode = 'entity' | 'rep'`, `interface OrderGroup { key: string; label: string; orders: Order[] }`, `filterOrdersByQuery(orders, query): Order[]`, `filterOrdersByDirection(orders, filter): Order[]`, `sortOrders(orders, mode): Order[]`, `groupOrders(orders, mode, sortMode): OrderGroup[]`, all from `src/lib/orderFilters.ts`, consumed by Task 10.

Ported from `lib/shared/widgets/order_sort_filter_bar.dart` (`prepareOrders`, `sortOrders`, `groupOrders`, single-level grouping only — phase 1 doesn't need the Dart version's nested multi-mode grouping).

- [ ] **Step 1: Write the failing tests**

Create `office_web/src/lib/orderFilters.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { filterOrdersByQuery, filterOrdersByDirection, sortOrders, groupOrders } from './orderFilters';
import type { Order } from '../types/domain';

function order(overrides: Partial<Order>): Order {
  return {
    id: 'o1', referenceCode: null, direction: 'outbound', entityId: 'e1', entity: null,
    repId: null, rep: null, creator: null, status: 'assigned', notes: null,
    storageActorId: null, createdAt: '2026-09-28T10:00:00Z', assignedAt: null,
    pickedUpAt: null, moveStartedAt: null, deliveredAt: null, items: [],
    ...overrides,
  };
}

describe('filterOrdersByQuery', () => {
  it('matches by entity name, rep name, or reference code, case-insensitively', () => {
    const orders = [
      order({ id: 'a', entity: { id: 'e1', name: 'Ministry of Health', category: 'outgoing', contactName: null, contactPhone: null, address: null } }),
      order({ id: 'b', rep: { id: 'u1', fullName: 'Ahmed Refaee', phone: null, role: 'rep', isApproved: true } }),
      order({ id: 'c', referenceCode: 'RN-9821' }),
      order({ id: 'd' }),
    ];
    expect(filterOrdersByQuery(orders, 'ministry').map((o) => o.id)).toEqual(['a']);
    expect(filterOrdersByQuery(orders, 'AHMED').map((o) => o.id)).toEqual(['b']);
    expect(filterOrdersByQuery(orders, 'rn-9821').map((o) => o.id)).toEqual(['c']);
  });

  it('returns everything unchanged for an empty query', () => {
    const orders = [order({ id: 'a' }), order({ id: 'b' })];
    expect(filterOrdersByQuery(orders, '  ')).toHaveLength(2);
  });
});

describe('filterOrdersByDirection', () => {
  it('filters by direction, or returns everything for "all"', () => {
    const orders = [order({ id: 'a', direction: 'outbound' }), order({ id: 'b', direction: 'inbound_rep' })];
    expect(filterOrdersByDirection(orders, 'outbound').map((o) => o.id)).toEqual(['a']);
    expect(filterOrdersByDirection(orders, 'all')).toHaveLength(2);
  });
});

describe('sortOrders', () => {
  it('sorts most_recent first by createdAt descending', () => {
    const orders = [
      order({ id: 'old', createdAt: '2026-01-01T00:00:00Z' }),
      order({ id: 'new', createdAt: '2026-09-01T00:00:00Z' }),
    ];
    expect(sortOrders(orders, 'most_recent').map((o) => o.id)).toEqual(['new', 'old']);
    expect(sortOrders(orders, 'oldest').map((o) => o.id)).toEqual(['old', 'new']);
  });

  it('sorts frequent by how many orders share the same entity, ties broken by recency', () => {
    const orders = [
      order({ id: 'a', entityId: 'e1', createdAt: '2026-01-01T00:00:00Z' }),
      order({ id: 'b', entityId: 'e1', createdAt: '2026-02-01T00:00:00Z' }),
      order({ id: 'c', entityId: 'e2', createdAt: '2026-03-01T00:00:00Z' }),
    ];
    expect(sortOrders(orders, 'frequent').map((o) => o.id)).toEqual(['b', 'a', 'c']);
  });
});

describe('groupOrders', () => {
  it('groups by entity, each group internally sorted', () => {
    const orders = [
      order({ id: 'a', entityId: 'e1', entity: { id: 'e1', name: 'وزارة', category: 'outgoing', contactName: null, contactPhone: null, address: null }, createdAt: '2026-01-01T00:00:00Z' }),
      order({ id: 'b', entityId: 'e1', entity: { id: 'e1', name: 'وزارة', category: 'outgoing', contactName: null, contactPhone: null, address: null }, createdAt: '2026-02-01T00:00:00Z' }),
      order({ id: 'c', entityId: 'e2', entity: { id: 'e2', name: 'بلدية', category: 'outgoing', contactName: null, contactPhone: null, address: null }, createdAt: '2026-03-01T00:00:00Z' }),
    ];
    const groups = groupOrders(orders, 'entity', 'most_recent');
    expect(groups.map((g) => g.label)).toEqual(['بلدية', 'وزارة']);
    expect(groups.find((g) => g.label === 'وزارة')?.orders.map((o) => o.id)).toEqual(['b', 'a']);
  });

  it('labels a missing rep as بدون مندوب', () => {
    const orders = [order({ id: 'a', repId: null, rep: null })];
    const groups = groupOrders(orders, 'rep', 'most_recent');
    expect(groups[0].label).toBe('بدون مندوب');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd office_web && npx vitest run src/lib/orderFilters.test.ts`
Expected: FAIL — `Cannot find module './orderFilters'`

- [ ] **Step 3: Write the implementation**

Create `office_web/src/lib/orderFilters.ts`:

```ts
import type { Order, OrderDirection } from '../types/domain';

export type SortMode = 'most_recent' | 'oldest' | 'frequent';
export type DirectionFilter = 'all' | OrderDirection;
export type GroupMode = 'entity' | 'rep';

export interface OrderGroup {
  key: string;
  label: string;
  orders: Order[];
}

function sortDate(order: Order): number {
  return order.createdAt ? new Date(order.createdAt).getTime() : 0;
}

export function filterOrdersByQuery(orders: Order[], query: string): Order[] {
  const q = query.trim().toLowerCase();
  if (!q) return orders;
  return orders.filter((order) =>
    (order.entity?.name ?? '').toLowerCase().includes(q) ||
    (order.rep?.fullName ?? '').toLowerCase().includes(q) ||
    (order.referenceCode ?? '').toLowerCase().includes(q),
  );
}

export function filterOrdersByDirection(orders: Order[], filter: DirectionFilter): Order[] {
  if (filter === 'all') return orders;
  return orders.filter((order) => order.direction === filter);
}

export function sortOrders(orders: Order[], mode: SortMode): Order[] {
  const entityCounts = new Map<string, number>();
  for (const order of orders) entityCounts.set(order.entityId, (entityCounts.get(order.entityId) ?? 0) + 1);

  return [...orders].sort((a, b) => {
    let result = 0;
    if (mode === 'most_recent') result = sortDate(b) - sortDate(a);
    else if (mode === 'oldest') result = sortDate(a) - sortDate(b);
    else result = (entityCounts.get(b.entityId) ?? 0) - (entityCounts.get(a.entityId) ?? 0);
    return result !== 0 ? result : sortDate(b) - sortDate(a);
  });
}

export function groupOrders(orders: Order[], mode: GroupMode, sortMode: SortMode): OrderGroup[] {
  const groups = new Map<string, Order[]>();
  const labels = new Map<string, string>();

  for (const order of orders) {
    const key = mode === 'entity' ? order.entityId : order.repId ?? 'unassigned';
    const label = mode === 'entity' ? order.entity?.name ?? 'بدون جهة' : order.rep?.fullName ?? 'بدون مندوب';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(order);
    labels.set(key, label);
  }

  const result: OrderGroup[] = Array.from(groups.entries()).map(([key, groupOrders]) => ({
    key,
    label: labels.get(key) ?? '—',
    orders: sortOrders(groupOrders, sortMode),
  }));

  result.sort((a, b) => a.label.localeCompare(b.label, 'ar'));
  return result;
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd office_web && npx vitest run src/lib/orderFilters.test.ts`
Expected: PASS — 6 tests

- [ ] **Step 5: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/src/lib/orderFilters.ts office_web/src/lib/orderFilters.test.ts
git commit -m "feat(office-web): port order search/sort/group logic"
```

---

## Task 6: Auth hook and Login page

**Files:**
- Create: `office_web/src/hooks/useAuth.ts`
- Test: `office_web/src/hooks/useAuth.test.tsx`
- Create: `office_web/src/pages/Login.tsx`
- Test: `office_web/src/pages/Login.test.tsx`

**Interfaces:**
- Consumes: `supabase` from `../lib/supabase`.
- Produces: `function useAuth(): { session: Session | null; loading: boolean }` and `function signIn(email, password): Promise<{ error: string | null }>` and `function signOut(): Promise<void>` from `src/hooks/useAuth.ts`, consumed by Task 7 and Task 8.
- Produces: `<Login />` component from `src/pages/Login.tsx`, consumed by Task 8's router.

- [ ] **Step 1: Write the failing auth hook test**

Create `office_web/src/hooks/useAuth.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { useAuth, signIn } from './useAuth';

const mockSession = { user: { id: 'u1' } };

vi.mock('../lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: vi.fn().mockResolvedValue({ data: { session: mockSession } }),
      onAuthStateChange: vi.fn().mockReturnValue({ data: { subscription: { unsubscribe: vi.fn() } } }),
      signInWithPassword: vi.fn(),
    },
  },
}));

describe('useAuth', () => {
  it('resolves the current session on mount', async () => {
    const { result } = renderHook(() => useAuth());
    expect(result.current.loading).toBe(true);
    await waitFor(() => expect(result.current.loading).toBe(false));
    expect(result.current.session).toEqual(mockSession);
  });
});

describe('signIn', () => {
  it('returns no error on success', async () => {
    const { supabase } = await import('../lib/supabase');
    vi.mocked(supabase.auth.signInWithPassword).mockResolvedValue({ data: {}, error: null } as never);
    const result = await signIn('a@b.com', 'pw');
    expect(result.error).toBeNull();
  });

  it('returns the Supabase error message on failure', async () => {
    const { supabase } = await import('../lib/supabase');
    vi.mocked(supabase.auth.signInWithPassword).mockResolvedValue({
      data: {}, error: { message: 'Invalid login credentials' },
    } as never);
    const result = await signIn('a@b.com', 'wrong');
    expect(result.error).toBe('Invalid login credentials');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/hooks/useAuth.test.tsx`
Expected: FAIL — `Cannot find module './useAuth'`

- [ ] **Step 3: Write the auth hook**

Create `office_web/src/hooks/useAuth.ts`:

```ts
import { useEffect, useState } from 'react';
import type { Session } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';

export function useAuth() {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session);
      setLoading(false);
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_event, newSession) => {
      setSession(newSession);
    });
    return () => sub.subscription.unsubscribe();
  }, []);

  return { session, loading };
}

export async function signIn(email: string, password: string): Promise<{ error: string | null }> {
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  return { error: error ? error.message : null };
}

export async function signOut(): Promise<void> {
  await supabase.auth.signOut();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/hooks/useAuth.test.tsx`
Expected: PASS — 3 tests

- [ ] **Step 5: Write the failing Login page test**

Create `office_web/src/pages/Login.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import Login from './Login';

vi.mock('../hooks/useAuth', () => ({ signIn: vi.fn() }));

describe('Login', () => {
  it('shows an inline error on invalid credentials, not a silent failure', async () => {
    const { signIn } = await import('../hooks/useAuth');
    vi.mocked(signIn).mockResolvedValue({ error: 'Invalid login credentials' });

    render(<MemoryRouter><Login /></MemoryRouter>);
    fireEvent.change(screen.getByLabelText('اسم المستخدم أو البريد المؤسسي'), { target: { value: 'a@b.com' } });
    fireEvent.change(screen.getByLabelText('كلمة المرور'), { target: { value: 'wrong' } });
    fireEvent.click(screen.getByRole('button', { name: 'دخول إلى النظام' }));

    await waitFor(() => expect(screen.getByText('Invalid login credentials')).toBeInTheDocument());
  });

  it('submits the typed email and password', async () => {
    const { signIn } = await import('../hooks/useAuth');
    vi.mocked(signIn).mockResolvedValue({ error: null });

    render(<MemoryRouter><Login /></MemoryRouter>);
    fireEvent.change(screen.getByLabelText('اسم المستخدم أو البريد المؤسسي'), { target: { value: 'a@b.com' } });
    fireEvent.change(screen.getByLabelText('كلمة المرور'), { target: { value: 'right-pw' } });
    fireEvent.click(screen.getByRole('button', { name: 'دخول إلى النظام' }));

    await waitFor(() => expect(signIn).toHaveBeenCalledWith('a@b.com', 'right-pw'));
  });
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/pages/Login.test.tsx`
Expected: FAIL — `Cannot find module './Login'`

- [ ] **Step 7: Write the Login page**

Create `office_web/src/pages/Login.tsx`:

```tsx
import { useState, type FormEvent } from 'react';
import { signIn } from '../hooks/useAuth';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    const { error } = await signIn(email, password);
    setSubmitting(false);
    if (error) setError(error);
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-surface">
      <form onSubmit={handleSubmit} className="w-full max-w-md bg-surface-card rounded-card border border-border-subtle p-8 shadow-sm">
        <h1 className="text-xl font-semibold text-text-high mb-1">تسجيل الدخول إلى النظام</h1>
        <p className="text-sm text-text-low mb-6">منظومة إدارة التوريد والطلبات والمستودعات</p>

        <label htmlFor="email" className="block text-sm text-text-medium mb-1">اسم المستخدم أو البريد المؤسسي</label>
        <input
          id="email"
          type="text"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="w-full h-9 px-3 mb-4 rounded-input border border-border-subtle focus:border-primary focus:outline-none"
        />

        <label htmlFor="password" className="block text-sm text-text-medium mb-1">كلمة المرور</label>
        <input
          id="password"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="w-full h-9 px-3 mb-4 rounded-input border border-border-subtle focus:border-primary focus:outline-none"
        />

        {error && <p className="text-error text-sm mb-4">{error}</p>}

        <button
          type="submit"
          disabled={submitting}
          className="w-full h-11 rounded-button bg-primary-fill text-white font-semibold disabled:opacity-60"
        >
          دخول إلى النظام
        </button>
      </form>
    </div>
  );
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/pages/Login.test.tsx`
Expected: PASS — 2 tests

- [ ] **Step 9: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/src/hooks/useAuth.ts office_web/src/hooks/useAuth.test.tsx office_web/src/pages/Login.tsx office_web/src/pages/Login.test.tsx
git commit -m "feat(office-web): add auth hook and login page"
```

---

## Task 7: Profile/role hook and ProtectedRoute

**Files:**
- Create: `office_web/src/hooks/useProfile.ts`
- Test: `office_web/src/hooks/useProfile.test.tsx`
- Create: `office_web/src/components/ProtectedRoute.tsx`
- Test: `office_web/src/components/ProtectedRoute.test.tsx`

**Interfaces:**
- Consumes: `useAuth` from `../hooks/useAuth`, `supabase` from `../lib/supabase`, `mapProfile` from `../lib/mappers`.
- Produces: `function useProfile()` (TanStack Query hook keyed on the session user id, returns `{ data: Profile | undefined, isLoading }`) from `src/hooks/useProfile.ts`.
- Produces: `<ProtectedRoute>{children}</ProtectedRoute>` from `src/components/ProtectedRoute.tsx`, consumed by Task 8's router.

- [ ] **Step 1: Write the failing useProfile test**

Create `office_web/src/hooks/useProfile.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useProfile } from './useProfile';

vi.mock('./useAuth', () => ({
  useAuth: () => ({ session: { user: { id: 'u1' } }, loading: false }),
}));

vi.mock('../lib/supabase', () => {
  const single = vi.fn().mockResolvedValue({
    data: { id: 'u1', full_name: 'مشرف', phone: null, role: 'verifier', is_approved: true },
    error: null,
  });
  const eq = vi.fn().mockReturnValue({ single });
  const select = vi.fn().mockReturnValue({ eq });
  const from = vi.fn().mockReturnValue({ select });
  return { supabase: { from } };
});

function wrapper({ children }: { children: React.ReactNode }) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}

describe('useProfile', () => {
  it('fetches the profile row for the logged-in user', async () => {
    const { result } = renderHook(() => useProfile(), { wrapper });
    await waitFor(() => expect(result.current.isLoading).toBe(false));
    expect(result.current.data?.role).toBe('verifier');
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/hooks/useProfile.test.tsx`
Expected: FAIL — `Cannot find module './useProfile'`

- [ ] **Step 3: Write the hook**

Create `office_web/src/hooks/useProfile.ts`:

```ts
import { useQuery } from '@tanstack/react-query';
import { supabase } from '../lib/supabase';
import { mapProfile } from '../lib/mappers';
import { useAuth } from './useAuth';

export function useProfile() {
  const { session } = useAuth();
  const userId = session?.user.id;

  return useQuery({
    queryKey: ['profile', userId],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, full_name, phone, role, is_approved')
        .eq('id', userId)
        .single();
      if (error) throw new Error(error.message);
      return mapProfile(data);
    },
    enabled: !!userId,
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/hooks/useProfile.test.tsx`
Expected: PASS

- [ ] **Step 5: Write the failing ProtectedRoute tests**

Create `office_web/src/components/ProtectedRoute.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { ProtectedRoute } from './ProtectedRoute';

const authMock = vi.fn();
const profileMock = vi.fn();
vi.mock('../hooks/useAuth', () => ({ useAuth: () => authMock() }));
vi.mock('../hooks/useProfile', () => ({ useProfile: () => profileMock() }));

describe('ProtectedRoute', () => {
  it('shows a loading state while auth resolves', () => {
    authMock.mockReturnValue({ session: null, loading: true });
    profileMock.mockReturnValue({ data: undefined, isLoading: true });
    render(<MemoryRouter><ProtectedRoute><p>محتوى</p></ProtectedRoute></MemoryRouter>);
    expect(screen.queryByText('محتوى')).not.toBeInTheDocument();
  });

  it('renders children for an authenticated verifier', () => {
    authMock.mockReturnValue({ session: { user: { id: 'u1' } }, loading: false });
    profileMock.mockReturnValue({ data: { id: 'u1', fullName: 'م', phone: null, role: 'verifier', isApproved: true }, isLoading: false });
    render(<MemoryRouter><ProtectedRoute><p>محتوى</p></ProtectedRoute></MemoryRouter>);
    expect(screen.getByText('محتوى')).toBeInTheDocument();
  });

  it('shows "not available for your role" instead of the content for a non-verifier role', () => {
    authMock.mockReturnValue({ session: { user: { id: 'u1' } }, loading: false });
    profileMock.mockReturnValue({ data: { id: 'u1', fullName: 'م', phone: null, role: 'rep', isApproved: true }, isLoading: false });
    render(<MemoryRouter><ProtectedRoute><p>محتوى</p></ProtectedRoute></MemoryRouter>);
    expect(screen.queryByText('محتوى')).not.toBeInTheDocument();
    expect(screen.getByText(/هذا النظام غير متاح حالياً لدورك/)).toBeInTheDocument();
  });
});
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `cd office_web && npx vitest run src/components/ProtectedRoute.test.tsx`
Expected: FAIL — `Cannot find module './ProtectedRoute'`

- [ ] **Step 7: Write the component**

Create `office_web/src/components/ProtectedRoute.tsx`:

```tsx
import type { ReactNode } from 'react';
import { Navigate } from 'react-router-dom';
import { useAuth } from '../hooks/useAuth';
import { useProfile } from '../hooks/useProfile';

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const { session, loading: authLoading } = useAuth();
  const { data: profile, isLoading: profileLoading } = useProfile();

  if (authLoading || (session && profileLoading)) {
    return <div className="min-h-screen flex items-center justify-center text-text-low">جارٍ التحميل...</div>;
  }

  if (!session) return <Navigate to="/login" replace />;

  if (profile?.role !== 'verifier') {
    return (
      <div className="min-h-screen flex items-center justify-center text-center px-6">
        <p className="text-text-medium">هذا النظام غير متاح حالياً لدورك في المنظومة.</p>
      </div>
    );
  }

  return <>{children}</>;
}
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `cd office_web && npx vitest run src/components/ProtectedRoute.test.tsx`
Expected: PASS — 3 tests

- [ ] **Step 9: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/src/hooks/useProfile.ts office_web/src/hooks/useProfile.test.tsx office_web/src/components/ProtectedRoute.tsx office_web/src/components/ProtectedRoute.test.tsx
git commit -m "feat(office-web): add profile hook and role-gated ProtectedRoute"
```

---

## Task 8: App shell — sidebar, top bar, routing

**Files:**
- Create: `office_web/src/components/Sidebar.tsx`
- Test: `office_web/src/components/Sidebar.test.tsx`
- Create: `office_web/src/components/Topbar.tsx`
- Test: `office_web/src/components/Topbar.test.tsx`
- Create: `office_web/src/components/Shell.tsx`
- Create: `office_web/src/pages/Orders.tsx` (placeholder body, filled in by Task 10)
- Modify: `office_web/src/App.tsx`
- Modify: `office_web/src/App.test.tsx`
- Create: `office_web/src/main.tsx` (add QueryClientProvider)

**Interfaces:**
- Produces: `<Sidebar activeItem="orders" />`, `<Topbar userName={string} onLogout={() => void} searchValue={string} onSearchChange={(v: string) => void} />`, `<Shell>{children}</Shell>` (renders Sidebar + Topbar + children, holds no state itself — search value lives in the page that needs it, passed down), all from their respective files.
- Produces: routes `/login`, `/orders`, `/orders/:id`, `/` in `App.tsx`, consumed by Task 10.

- [ ] **Step 1: Write the failing Sidebar test**

Create `office_web/src/components/Sidebar.test.tsx`:

```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { Sidebar } from './Sidebar';

describe('Sidebar', () => {
  it('shows الطلبات as enabled and the rest as قريباً', () => {
    render(<MemoryRouter><Sidebar /></MemoryRouter>);
    const orders = screen.getByRole('link', { name: /الطلبات/ });
    expect(orders).toHaveAttribute('href', '/orders');

    for (const label of ['المخزون', 'المناديب', 'الإحصائيات', 'الإعدادات']) {
      expect(screen.getByText(label).closest('div')).toHaveTextContent('قريباً');
    }
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/components/Sidebar.test.tsx`
Expected: FAIL — `Cannot find module './Sidebar'`

- [ ] **Step 3: Write the Sidebar**

Create `office_web/src/components/Sidebar.tsx`:

```tsx
import { Link } from 'react-router-dom';

const comingSoon = [
  { key: 'inventory', label: 'المخزون' },
  { key: 'reps', label: 'المناديب' },
  { key: 'stats', label: 'الإحصائيات' },
  { key: 'settings', label: 'الإعدادات' },
];

export function Sidebar() {
  return (
    <aside className="w-64 shrink-0 bg-surface-card border-l border-border-subtle flex flex-col py-4">
      <div className="px-4 mb-6">
        <p className="font-semibold text-text-high">روح النمو المتحدة</p>
        <p className="text-xs text-text-low">منظومة العمليات</p>
      </div>
      <nav className="flex-1 px-2 space-y-1">
        <Link
          to="/orders"
          className="block px-3 py-2 rounded-button bg-primary-fill text-white font-medium"
        >
          الطلبات
        </Link>
        {comingSoon.map((item) => (
          <div
            key={item.key}
            className="flex items-center justify-between px-3 py-2 rounded-button text-text-low cursor-not-allowed"
          >
            <span>{item.label}</span>
            <span className="text-xs bg-surface-inset px-2 py-0.5 rounded-full">قريباً</span>
          </div>
        ))}
      </nav>
    </aside>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/components/Sidebar.test.tsx`
Expected: PASS

- [ ] **Step 5: Write the failing Topbar test**

Create `office_web/src/components/Topbar.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { Topbar } from './Topbar';

describe('Topbar', () => {
  it('calls onLogout when the logout button is clicked', () => {
    const onLogout = vi.fn();
    render(<Topbar userName="أحمد" searchValue="" onSearchChange={() => {}} onLogout={onLogout} />);
    fireEvent.click(screen.getByRole('button', { name: 'تسجيل الخروج' }));
    expect(onLogout).toHaveBeenCalled();
  });

  it('calls onSearchChange as the user types', () => {
    const onSearchChange = vi.fn();
    render(<Topbar userName="أحمد" searchValue="" onSearchChange={onSearchChange} onLogout={() => {}} />);
    fireEvent.change(screen.getByPlaceholderText('بحث شامل في الطلبات...'), { target: { value: 'وزارة' } });
    expect(onSearchChange).toHaveBeenCalledWith('وزارة');
  });
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/components/Topbar.test.tsx`
Expected: FAIL — `Cannot find module './Topbar'`

- [ ] **Step 7: Write the Topbar**

Create `office_web/src/components/Topbar.tsx`:

```tsx
interface TopbarProps {
  userName: string;
  searchValue: string;
  onSearchChange: (value: string) => void;
  onLogout: () => void;
}

export function Topbar({ userName, searchValue, onSearchChange, onLogout }: TopbarProps) {
  return (
    <header className="h-14 shrink-0 bg-surface-card border-b border-border-subtle flex items-center px-4 gap-4">
      <input
        type="text"
        value={searchValue}
        onChange={(e) => onSearchChange(e.target.value)}
        placeholder="بحث شامل في الطلبات..."
        className="w-80 h-9 px-3 rounded-input border border-border-subtle focus:border-primary focus:outline-none text-sm"
      />
      <div className="flex-1" />
      <span className="text-sm text-text-medium">{userName}</span>
      <button
        type="button"
        onClick={onLogout}
        className="text-sm text-text-low hover:text-error"
      >
        تسجيل الخروج
      </button>
    </header>
  );
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/components/Topbar.test.tsx`
Expected: PASS

- [ ] **Step 9: Write the Shell layout**

Create `office_web/src/components/Shell.tsx`:

```tsx
import type { ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { Sidebar } from './Sidebar';
import { Topbar } from './Topbar';
import { useProfile } from '../hooks/useProfile';
import { signOut } from '../hooks/useAuth';

interface ShellProps {
  children: ReactNode;
  searchValue: string;
  onSearchChange: (value: string) => void;
}

export function Shell({ children, searchValue, onSearchChange }: ShellProps) {
  const { data: profile } = useProfile();
  const navigate = useNavigate();

  async function handleLogout() {
    await signOut();
    navigate('/login');
  }

  return (
    <div className="h-screen flex flex-row-reverse">
      <Sidebar />
      <div className="flex-1 flex flex-col min-w-0">
        <Topbar
          userName={profile?.fullName ?? ''}
          searchValue={searchValue}
          onSearchChange={onSearchChange}
          onLogout={handleLogout}
        />
        <main className="flex-1 min-h-0 overflow-hidden">{children}</main>
      </div>
    </div>
  );
}
```

- [ ] **Step 10: Create the Orders page placeholder**

Create `office_web/src/pages/Orders.tsx` (this is filled in by Task 10):

```tsx
export default function Orders() {
  return <div className="p-6 text-text-low">قائمة الطلبات — قيد الإنشاء</div>;
}
```

- [ ] **Step 11: Wire the router in App.tsx**

Replace `office_web/src/App.tsx`:

```tsx
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { ProtectedRoute } from './components/ProtectedRoute';
import Login from './pages/Login';
import Orders from './pages/Orders';

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route
          path="/orders/:orderId?"
          element={
            <ProtectedRoute>
              <Orders />
            </ProtectedRoute>
          }
        />
        <Route path="/" element={<Navigate to="/orders" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
```

- [ ] **Step 12: Add QueryClientProvider in main.tsx**

Replace `office_web/src/main.tsx`:

```tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import App from './App';
import './index.css';

const queryClient = new QueryClient();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <App />
    </QueryClientProvider>
  </StrictMode>,
);
```

- [ ] **Step 13: Update the App smoke test for the new router**

Replace `office_web/src/App.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import App from './App';

vi.mock('./hooks/useAuth', () => ({
  useAuth: () => ({ session: null, loading: false }),
  signIn: vi.fn(),
  signOut: vi.fn(),
}));
vi.mock('./hooks/useProfile', () => ({ useProfile: () => ({ data: undefined, isLoading: false }) }));

describe('App', () => {
  it('redirects an unauthenticated visitor to the login page', () => {
    render(<App />);
    expect(screen.getByRole('button', { name: 'دخول إلى النظام' })).toBeInTheDocument();
  });
});
```

- [ ] **Step 14: Run the full test suite and the build**

Run: `cd office_web && npm test`
Expected: all tests pass

Run: `cd office_web && npm run build`
Expected: exits 0

- [ ] **Step 15: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/src
git commit -m "feat(office-web): add app shell, routing, and role-gated navigation"
```

---

## Task 9: StatusChip component

**Files:**
- Create: `office_web/src/components/StatusChip.tsx`
- Test: `office_web/src/components/StatusChip.test.tsx`

**Interfaces:**
- Consumes: `OrderStatus`, `orderStatusLabel` from `../types/domain`.
- Produces: `<StatusChip status={OrderStatus} />` from `src/components/StatusChip.tsx`, consumed by Task 10 and Task 12.

Colors reuse `lib/core/design_system/theme/colors/order_status_colors.dart`'s exact traffic-light values, so the website agrees with the Flutter app on what each status looks like (see Global Constraints).

- [ ] **Step 1: Write the failing test**

Create `office_web/src/components/StatusChip.test.tsx`:

```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { StatusChip } from './StatusChip';

describe('StatusChip', () => {
  it.each([
    ['assigned', 'معين'],
    ['picked_up', 'تم الاستلام'],
    ['on_the_move', 'في الطريق'],
    ['delivered', 'تم التسليم'],
    ['delivered_to_storage', 'تم الاستلام في المخزن'],
  ] as const)('renders the Arabic label for %s', (status, label) => {
    render(<StatusChip status={status} />);
    expect(screen.getByText(label)).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/components/StatusChip.test.tsx`
Expected: FAIL — `Cannot find module './StatusChip'`

- [ ] **Step 3: Write the component**

Create `office_web/src/components/StatusChip.tsx`:

```tsx
import type { OrderStatus } from '../types/domain';
import { orderStatusLabel } from '../types/domain';

// Exact hex values from lib/core/design_system/theme/colors/order_status_colors.dart
const statusStyle: Record<OrderStatus, { bg: string; text: string }> = {
  assigned: { bg: '#E5393520', text: '#E53935' },
  picked_up: { bg: '#FB8C0020', text: '#FB8C00' },
  on_the_move: { bg: '#FBC02D20', text: '#8A6D00' },
  delivered: { bg: '#43A04720', text: '#2E7D32' },
  delivered_to_storage: { bg: '#43A04720', text: '#2E7D32' },
};

export function StatusChip({ status }: { status: OrderStatus }) {
  const style = statusStyle[status];
  return (
    <span
      className="inline-flex items-center px-2 py-0.5 rounded-input text-xs font-medium"
      style={{ backgroundColor: style.bg, color: style.text }}
    >
      {orderStatusLabel[status]}
    </span>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/components/StatusChip.test.tsx`
Expected: PASS — 5 tests

- [ ] **Step 5: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/src/components/StatusChip.tsx office_web/src/components/StatusChip.test.tsx
git commit -m "feat(office-web): add StatusChip with the app's traffic-light colors"
```

---

## Task 10: Orders table, toolbar, and page

**Files:**
- Create: `office_web/src/components/OrdersTable.tsx`
- Test: `office_web/src/components/OrdersTable.test.tsx`
- Create: `office_web/src/components/OrdersToolbar.tsx`
- Test: `office_web/src/components/OrdersToolbar.test.tsx`
- Create: `office_web/src/components/StatesPanel.tsx`
- Modify: `office_web/src/pages/Orders.tsx`
- Test: `office_web/src/pages/Orders.test.tsx`

**Interfaces:**
- Consumes: `useOrders` (Task 4), `filterOrdersByQuery`/`filterOrdersByDirection`/`sortOrders`/`groupOrders` and their types (Task 5), `StatusChip` (Task 9), `Shell` (Task 8).
- Produces: `<OrdersTable orders={Order[]} onSelect={(id: string) => void} selectedId={string | null} />`, `<OrdersToolbar sortMode directionFilter groupMode activeTab onSortModeChange onDirectionFilterChange onGroupModeChange onTabChange />`, `<StatesPanel kind="loading" | "error" | "empty" message? onRetry? />`.

Note on sorting: the table renders columns only — it does not add its own click-to-sort, since the toolbar's sort-mode dropdown (مirroring the Flutter app's actual UX) is the single source of truth for order. Mixing a second, column-header sort would let the two disagree.

- [ ] **Step 1: Write the failing OrdersTable test**

Create `office_web/src/components/OrdersTable.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { OrdersTable } from './OrdersTable';
import type { Order } from '../types/domain';

function order(overrides: Partial<Order>): Order {
  return {
    id: 'o1', referenceCode: 'RN-1', direction: 'outbound', entityId: 'e1',
    entity: { id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contactName: null, contactPhone: null, address: null },
    repId: null, rep: null, creator: null, status: 'assigned', notes: null,
    storageActorId: null, createdAt: '2026-09-28T10:00:00Z', assignedAt: null,
    pickedUpAt: null, moveStartedAt: null, deliveredAt: null, items: [],
    ...overrides,
  };
}

describe('OrdersTable', () => {
  it('renders one row per order with its entity, direction and status', () => {
    render(<OrdersTable orders={[order({})]} onSelect={() => {}} selectedId={null} />);
    expect(screen.getByText('وزارة الصحة')).toBeInTheDocument();
    expect(screen.getByText('توريد')).toBeInTheDocument();
    expect(screen.getByText('معين')).toBeInTheDocument();
  });

  it('calls onSelect with the order id when a row is clicked', () => {
    const onSelect = vi.fn();
    render(<OrdersTable orders={[order({ id: 'o42' })]} onSelect={onSelect} selectedId={null} />);
    fireEvent.click(screen.getByText('وزارة الصحة'));
    expect(onSelect).toHaveBeenCalledWith('o42');
  });

  it('shows an empty message when there are no orders', () => {
    render(<OrdersTable orders={[]} onSelect={() => {}} selectedId={null} />);
    expect(screen.getByText('لا توجد طلبات مطابقة')).toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/components/OrdersTable.test.tsx`
Expected: FAIL — `Cannot find module './OrdersTable'`

- [ ] **Step 3: Write the table**

Create `office_web/src/components/OrdersTable.tsx`:

```tsx
import { useReactTable, getCoreRowModel, flexRender, createColumnHelper } from '@tanstack/react-table';
import type { Order } from '../types/domain';
import { orderDirectionLabel } from '../types/domain';
import { StatusChip } from './StatusChip';

const columnHelper = createColumnHelper<Order>();

const columns = [
  columnHelper.accessor((o) => o.referenceCode ?? o.id.slice(0, 8), {
    id: 'reference',
    header: 'رقم الطلب',
  }),
  columnHelper.accessor((o) => o.entity?.name ?? '—', {
    id: 'entity',
    header: 'الجهة',
  }),
  columnHelper.accessor((o) => orderDirectionLabel[o.direction], {
    id: 'direction',
    header: 'نوع العملية',
  }),
  columnHelper.accessor('status', {
    id: 'status',
    header: 'الحالة',
    cell: (info) => <StatusChip status={info.getValue()} />,
  }),
  columnHelper.accessor((o) => o.rep?.fullName ?? '—', {
    id: 'rep',
    header: 'المندوب',
  }),
  columnHelper.accessor((o) => (o.createdAt ? new Date(o.createdAt).toLocaleString('ar') : '—'), {
    id: 'date',
    header: 'التاريخ',
  }),
];

interface OrdersTableProps {
  orders: Order[];
  onSelect: (id: string) => void;
  selectedId: string | null;
}

export function OrdersTable({ orders, onSelect, selectedId }: OrdersTableProps) {
  const table = useReactTable({ data: orders, columns, getCoreRowModel: getCoreRowModel() });

  if (orders.length === 0) {
    return <div className="p-8 text-center text-text-low">لا توجد طلبات مطابقة</div>;
  }

  return (
    <table className="w-full text-sm text-right border-collapse">
      <thead className="sticky top-0 bg-surface-inset">
        {table.getHeaderGroups().map((headerGroup) => (
          <tr key={headerGroup.id}>
            {headerGroup.headers.map((header) => (
              <th key={header.id} className="h-9 px-3 text-xs font-medium text-text-low border-b border-border-subtle">
                {flexRender(header.column.columnDef.header, header.getContext())}
              </th>
            ))}
          </tr>
        ))}
      </thead>
      <tbody>
        {table.getRowModel().rows.map((row) => (
          <tr
            key={row.id}
            onClick={() => onSelect(row.original.id)}
            className={`h-9 cursor-pointer border-b border-surface-inset hover:bg-surface-inset ${
              selectedId === row.original.id ? 'bg-surface-inset' : ''
            }`}
          >
            {row.getVisibleCells().map((cell) => (
              <td key={cell.id} className="px-3">
                {flexRender(cell.column.columnDef.cell, cell.getContext())}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/components/OrdersTable.test.tsx`
Expected: PASS — 3 tests

- [ ] **Step 5: Write the failing OrdersToolbar test**

Create `office_web/src/components/OrdersToolbar.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { OrdersToolbar } from './OrdersToolbar';

describe('OrdersToolbar', () => {
  it('calls onTabChange when switching between نشطة and مكتملة', () => {
    const onTabChange = vi.fn();
    render(
      <OrdersToolbar
        sortMode="most_recent" directionFilter="all" groupMode={null} activeTab="active"
        onSortModeChange={() => {}} onDirectionFilterChange={() => {}} onGroupModeChange={() => {}}
        onTabChange={onTabChange}
      />,
    );
    fireEvent.click(screen.getByRole('button', { name: 'مكتملة' }));
    expect(onTabChange).toHaveBeenCalledWith('completed');
  });

  it('calls onDirectionFilterChange with the selected direction', () => {
    const onDirectionFilterChange = vi.fn();
    render(
      <OrdersToolbar
        sortMode="most_recent" directionFilter="all" groupMode={null} activeTab="active"
        onSortModeChange={() => {}} onDirectionFilterChange={onDirectionFilterChange} onGroupModeChange={() => {}}
        onTabChange={() => {}}
      />,
    );
    fireEvent.change(screen.getByLabelText('نوع العملية'), { target: { value: 'outbound' } });
    expect(onDirectionFilterChange).toHaveBeenCalledWith('outbound');
  });
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/components/OrdersToolbar.test.tsx`
Expected: FAIL — `Cannot find module './OrdersToolbar'`

- [ ] **Step 7: Write the toolbar**

Create `office_web/src/components/OrdersToolbar.tsx`:

```tsx
import type { SortMode, DirectionFilter, GroupMode } from '../lib/orderFilters';

interface OrdersToolbarProps {
  sortMode: SortMode;
  directionFilter: DirectionFilter;
  groupMode: GroupMode | null;
  activeTab: 'active' | 'completed';
  onSortModeChange: (mode: SortMode) => void;
  onDirectionFilterChange: (filter: DirectionFilter) => void;
  onGroupModeChange: (mode: GroupMode | null) => void;
  onTabChange: (tab: 'active' | 'completed') => void;
}

export function OrdersToolbar({
  sortMode, directionFilter, groupMode, activeTab,
  onSortModeChange, onDirectionFilterChange, onGroupModeChange, onTabChange,
}: OrdersToolbarProps) {
  return (
    <div className="flex items-center gap-3 px-4 py-2 border-b border-border-subtle bg-surface-card">
      <div className="flex rounded-button overflow-hidden border border-border-subtle">
        <button
          type="button"
          onClick={() => onTabChange('active')}
          className={`px-3 py-1.5 text-sm ${activeTab === 'active' ? 'bg-primary-fill text-white' : 'text-text-medium'}`}
        >
          نشطة
        </button>
        <button
          type="button"
          onClick={() => onTabChange('completed')}
          className={`px-3 py-1.5 text-sm ${activeTab === 'completed' ? 'bg-primary-fill text-white' : 'text-text-medium'}`}
        >
          مكتملة
        </button>
      </div>

      <label className="text-sm text-text-low" htmlFor="direction-filter">نوع العملية</label>
      <select
        id="direction-filter"
        value={directionFilter}
        onChange={(e) => onDirectionFilterChange(e.target.value as DirectionFilter)}
        className="h-8 px-2 rounded-input border border-border-subtle text-sm"
      >
        <option value="all">الكل</option>
        <option value="outbound">توريد</option>
        <option value="inbound_rep">مشتريات مندوب داخلي</option>
        <option value="inbound_external">مشتريات مندوب خارجي</option>
      </select>

      <label className="text-sm text-text-low" htmlFor="sort-mode">الترتيب</label>
      <select
        id="sort-mode"
        value={sortMode}
        onChange={(e) => onSortModeChange(e.target.value as SortMode)}
        className="h-8 px-2 rounded-input border border-border-subtle text-sm"
      >
        <option value="most_recent">الأحدث</option>
        <option value="oldest">الأقدم</option>
        <option value="frequent">الأكثر تكراراً</option>
      </select>

      <label className="text-sm text-text-low" htmlFor="group-mode">التجميع</label>
      <select
        id="group-mode"
        value={groupMode ?? ''}
        onChange={(e) => onGroupModeChange(e.target.value ? (e.target.value as GroupMode) : null)}
        className="h-8 px-2 rounded-input border border-border-subtle text-sm"
      >
        <option value="">بلا</option>
        <option value="entity">حسب الجهة</option>
        <option value="rep">حسب المندوب</option>
      </select>
    </div>
  );
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/components/OrdersToolbar.test.tsx`
Expected: PASS — 2 tests

- [ ] **Step 9: Write the states panel (no test — pure presentational, exercised via Orders.test.tsx in Step 12)**

Create `office_web/src/components/StatesPanel.tsx`:

```tsx
interface StatesPanelProps {
  kind: 'loading' | 'error';
  message?: string;
  onRetry?: () => void;
}

export function StatesPanel({ kind, message, onRetry }: StatesPanelProps) {
  if (kind === 'loading') {
    return <div className="p-8 text-center text-text-low">جارٍ التحميل...</div>;
  }
  return (
    <div className="p-8 text-center">
      <p className="text-error mb-3">{message ?? 'حدث خطأ غير متوقع'}</p>
      {onRetry && (
        <button type="button" onClick={onRetry} className="px-4 py-1.5 rounded-button border border-border-subtle text-sm">
          إعادة المحاولة
        </button>
      )}
    </div>
  );
}
```

- [ ] **Step 10: Write the failing Orders page test**

Create `office_web/src/pages/Orders.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import Orders from './Orders';
import type { Order } from '../types/domain';

function order(overrides: Partial<Order>): Order {
  return {
    id: 'o1', referenceCode: 'RN-1', direction: 'outbound', entityId: 'e1',
    entity: { id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contactName: null, contactPhone: null, address: null },
    repId: null, rep: null, creator: null, status: 'assigned', notes: null,
    storageActorId: null, createdAt: '2026-09-28T10:00:00Z', assignedAt: null,
    pickedUpAt: null, moveStartedAt: null, deliveredAt: null, items: [],
    ...overrides,
  };
}

const ordersMock = vi.fn();
vi.mock('../hooks/useOrders', () => ({ useOrders: () => ordersMock() }));
vi.mock('../hooks/useProfile', () => ({ useProfile: () => ({ data: { id: 'u1', fullName: 'مشرف', phone: null, role: 'verifier', isApproved: true } }) }));
vi.mock('../hooks/useAuth', () => ({ signOut: vi.fn() }));

function renderOrders() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <MemoryRouter initialEntries={['/orders']}>
        <Orders />
      </MemoryRouter>
    </QueryClientProvider>,
  );
}

describe('Orders page', () => {
  it('shows the loading state while orders are fetching', () => {
    ordersMock.mockReturnValue({ data: undefined, isLoading: true, isError: false, refetch: vi.fn() });
    renderOrders();
    expect(screen.getByText('جارٍ التحميل...')).toBeInTheDocument();
  });

  it('shows the error state with a retry button on failure', () => {
    const refetch = vi.fn();
    ordersMock.mockReturnValue({ data: undefined, isLoading: false, isError: true, error: new Error('تعذر الاتصال'), refetch });
    renderOrders();
    fireEventClickRetry();
    expect(refetch).toHaveBeenCalled();

    function fireEventClickRetry() {
      screen.getByRole('button', { name: 'إعادة المحاولة' }).click();
    }
  });

  it('filters delivered orders out of the نشطة tab and lists undelivered ones', async () => {
    ordersMock.mockReturnValue({
      data: [order({ id: 'a', status: 'assigned' }), order({ id: 'b', status: 'delivered' })],
      isLoading: false, isError: false, refetch: vi.fn(),
    });
    renderOrders();
    await waitFor(() => expect(screen.getByText('وزارة الصحة')).toBeInTheDocument());
  });
});
```

- [ ] **Step 11: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/pages/Orders.test.tsx`
Expected: FAIL — the placeholder `Orders.tsx` doesn't render any of this

- [ ] **Step 12: Write the real Orders page**

Replace `office_web/src/pages/Orders.tsx`:

```tsx
import { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { Shell } from '../components/Shell';
import { OrdersToolbar } from '../components/OrdersToolbar';
import { OrdersTable } from '../components/OrdersTable';
import { StatesPanel } from '../components/StatesPanel';
import { useOrders } from '../hooks/useOrders';
import { filterOrdersByQuery, filterOrdersByDirection, sortOrders, groupOrders } from '../lib/orderFilters';
import type { SortMode, DirectionFilter, GroupMode } from '../lib/orderFilters';
import type { Order } from '../types/domain';

const DONE_STATUSES = new Set<Order['status']>(['delivered', 'delivered_to_storage']);

export default function Orders() {
  const { orderId } = useParams();
  const navigate = useNavigate();
  const { data: orders, isLoading, isError, error, refetch } = useOrders();

  const [search, setSearch] = useState('');
  const [sortMode, setSortMode] = useState<SortMode>('most_recent');
  const [directionFilter, setDirectionFilter] = useState<DirectionFilter>('all');
  const [groupMode, setGroupMode] = useState<GroupMode | null>(null);
  const [activeTab, setActiveTab] = useState<'active' | 'completed'>('active');

  if (isLoading) {
    return (
      <Shell searchValue={search} onSearchChange={setSearch}>
        <StatesPanel kind="loading" />
      </Shell>
    );
  }

  if (isError) {
    return (
      <Shell searchValue={search} onSearchChange={setSearch}>
        <StatesPanel kind="error" message={(error as Error)?.message} onRetry={() => refetch()} />
      </Shell>
    );
  }

  const byTab = (orders ?? []).filter((o) => (activeTab === 'active' ? !DONE_STATUSES.has(o.status) : DONE_STATUSES.has(o.status)));
  const prepared = filterOrdersByDirection(filterOrdersByQuery(byTab, search), directionFilter);
  const visible = groupMode ? groupOrders(prepared, groupMode, sortMode).flatMap((g) => g.orders) : sortOrders(prepared, sortMode);

  return (
    <Shell searchValue={search} onSearchChange={setSearch}>
      <div className="h-full flex flex-row-reverse">
        <div className="flex-1 min-w-0 flex flex-col">
          <OrdersToolbar
            sortMode={sortMode}
            directionFilter={directionFilter}
            groupMode={groupMode}
            activeTab={activeTab}
            onSortModeChange={setSortMode}
            onDirectionFilterChange={setDirectionFilter}
            onGroupModeChange={setGroupMode}
            onTabChange={setActiveTab}
          />
          <div className="flex-1 overflow-auto">
            <OrdersTable orders={visible} selectedId={orderId ?? null} onSelect={(id) => navigate(`/orders/${id}`)} />
          </div>
        </div>
      </div>
    </Shell>
  );
}
```

- [ ] **Step 13: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/pages/Orders.test.tsx`
Expected: PASS — 3 tests

- [ ] **Step 14: Run the full suite and the build**

Run: `cd office_web && npm test && npm run build`
Expected: all green

- [ ] **Step 15: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/src
git commit -m "feat(office-web): add orders table, toolbar, and the real Orders page"
```

---

## Task 11: Order detail data — audit log and سند queries

**Files:**
- Create: `office_web/src/api/orderDetail.ts`
- Test: `office_web/src/api/orderDetail.test.ts`
- Create: `office_web/src/hooks/useOrderDetail.ts`

**Interfaces:**
- Consumes: `mapOrder`, `mapAuditLogEntry`, `mapDeliveryReceipt` from `../lib/mappers`, `supabase` from `../lib/supabase`.
- Produces: `ORDER_DETAIL_SELECT: string`, `fetchOrderDetail(id): Promise<Order>`, `fetchAuditLog(orderId): Promise<AuditLogEntry[]>`, `fetchDeliveryReceipts(orderId): Promise<DeliveryReceipt[]>` from `src/api/orderDetail.ts`. `useOrderDetail(orderId: string | null)` returning `{ order, auditLog, receipts, isLoading, isError, error, refetch }` from `src/hooks/useOrderDetail.ts`, consumed by Task 12.

- [ ] **Step 1: Write the failing tests**

Create `office_web/src/api/orderDetail.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest';
import { fetchOrderDetail, fetchAuditLog, fetchDeliveryReceipts, ORDER_DETAIL_SELECT } from './orderDetail';

function chain(resolvedValue: unknown) {
  const order = vi.fn().mockResolvedValue(resolvedValue);
  const eq = vi.fn().mockReturnValue({ order, single: vi.fn().mockResolvedValue(resolvedValue) });
  const select = vi.fn().mockReturnValue({ eq });
  return { select, eq, order };
}

describe('fetchOrderDetail', () => {
  it('queries orders by id with the detail select and maps the row', async () => {
    const single = vi.fn().mockResolvedValue({
      data: {
        id: 'o1', reference_code: null, direction: 'outbound', entity_id: 'e1', entity: null,
        rep_id: null, rep: null, creator: null, status: 'assigned', notes: null,
        storage_actor_id: null, created_at: null, assigned_at: null, picked_up_at: null,
        move_started_at: null, delivered_at: null, order_items: [],
      },
      error: null,
    });
    const eq = vi.fn().mockReturnValue({ single });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });
    vi.doMock('../lib/supabase', () => ({ supabase: { from } }));
    vi.resetModules();
    const mod = await import('./orderDetail');

    const order = await mod.fetchOrderDetail('o1');
    expect(from).toHaveBeenCalledWith('orders');
    expect(select).toHaveBeenCalledWith(mod.ORDER_DETAIL_SELECT);
    expect(eq).toHaveBeenCalledWith('id', 'o1');
    expect(order.id).toBe('o1');
  });
});

describe('fetchAuditLog', () => {
  it('queries audit_log for the order, oldest first', async () => {
    const order = vi.fn().mockResolvedValue({
      data: [{ id: 'a1', order_id: 'o1', action: 'order_created', old_status: null, new_status: 'assigned', performer: null, notes: null, server_timestamp: '2026-09-28T10:00:00Z' }],
      error: null,
    });
    const eq = vi.fn().mockReturnValue({ order });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });
    vi.doMock('../lib/supabase', () => ({ supabase: { from } }));
    vi.resetModules();
    const mod = await import('./orderDetail');

    const entries = await mod.fetchAuditLog('o1');
    expect(from).toHaveBeenCalledWith('audit_log');
    expect(eq).toHaveBeenCalledWith('order_id', 'o1');
    expect(order).toHaveBeenCalledWith('server_timestamp', { ascending: true });
    expect(entries).toHaveLength(1);
  });
});

describe('fetchDeliveryReceipts', () => {
  it('queries delivery_receipts for the order, newest first', async () => {
    const order = vi.fn().mockResolvedValue({ data: [], error: null });
    const eq = vi.fn().mockReturnValue({ order });
    const select = vi.fn().mockReturnValue({ eq });
    const from = vi.fn().mockReturnValue({ select });
    vi.doMock('../lib/supabase', () => ({ supabase: { from } }));
    vi.resetModules();
    const mod = await import('./orderDetail');

    const receipts = await mod.fetchDeliveryReceipts('o1');
    expect(from).toHaveBeenCalledWith('delivery_receipts');
    expect(eq).toHaveBeenCalledWith('order_id', 'o1');
    expect(receipts).toEqual([]);
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd office_web && npx vitest run src/api/orderDetail.test.ts`
Expected: FAIL — `Cannot find module './orderDetail'`

- [ ] **Step 3: Write the implementation**

Create `office_web/src/api/orderDetail.ts`:

```ts
import { supabase } from '../lib/supabase';
import { mapOrder, mapAuditLogEntry, mapDeliveryReceipt } from '../lib/mappers';
import type { Order, AuditLogEntry, DeliveryReceipt } from '../types/domain';

// Mirrors OrderRepository._orderDetailSelect in lib/features/verifier/data/order_repository.dart
export const ORDER_DETAIL_SELECT =
  'id, reference_code, direction, entity_id, rep_id, created_by, storage_actor_id, status, notes, ' +
  'created_at, assigned_at, picked_up_at, move_started_at, delivered_at, ' +
  'entity:entities(id, name, category, contact_name, contact_phone, address), ' +
  'rep:profiles!orders_rep_id_fkey(id, full_name, phone, role, is_approved, created_at), ' +
  'creator:profiles!orders_created_by_fkey(id, full_name, phone, role, is_approved, created_at), ' +
  'order_items(id, order_id, inventory_id, quantity, final_quantity, is_custom, custom_description, ' +
  'check_status, checked_by, was_unavailable_at_creation, ' +
  'inventory:inventory!order_items_inventory_id_fkey(id, item_name), ' +
  'checker:profiles!order_items_checked_by_fkey(id, full_name, phone, role, is_approved, created_at))';

export async function fetchOrderDetail(id: string): Promise<Order> {
  const { data, error } = await supabase.from('orders').select(ORDER_DETAIL_SELECT).eq('id', id).single();
  if (error) throw new Error(error.message);
  return mapOrder(data);
}

const AUDIT_LOG_SELECT =
  'id, order_id, action, old_status, new_status, notes, server_timestamp, ' +
  'performer:profiles!audit_log_performed_by_fkey(id, full_name, phone, role, is_approved, created_at)';

export async function fetchAuditLog(orderId: string): Promise<AuditLogEntry[]> {
  const { data, error } = await supabase
    .from('audit_log')
    .select(AUDIT_LOG_SELECT)
    .eq('order_id', orderId)
    .order('server_timestamp', { ascending: true });
  if (error) throw new Error(error.message);
  return (data ?? []).map(mapAuditLogEntry);
}

const DELIVERY_RECEIPT_SELECT =
  'id, order_id, pdf_url, notes, delivered_at, created_at, ' +
  'rep:profiles!delivery_receipts_rep_id_fkey(id, full_name, phone, role, is_approved, created_at), ' +
  'delivery_receipt_items(id, item_name_snapshot, unit_snapshot, quantity_delivered)';

export async function fetchDeliveryReceipts(orderId: string): Promise<DeliveryReceipt[]> {
  const { data, error } = await supabase
    .from('delivery_receipts')
    .select(DELIVERY_RECEIPT_SELECT)
    .eq('order_id', orderId)
    .order('created_at', { ascending: false });
  if (error) throw new Error(error.message);
  return (data ?? []).map(mapDeliveryReceipt);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd office_web && npx vitest run src/api/orderDetail.test.ts`
Expected: PASS — 3 tests

- [ ] **Step 5: Write the combined hook**

Create `office_web/src/hooks/useOrderDetail.ts`:

```ts
import { useQuery } from '@tanstack/react-query';
import { fetchOrderDetail, fetchAuditLog, fetchDeliveryReceipts } from '../api/orderDetail';

export function useOrderDetail(orderId: string | null) {
  const orderQuery = useQuery({
    queryKey: ['order', orderId],
    queryFn: () => fetchOrderDetail(orderId as string),
    enabled: !!orderId,
  });
  const auditLogQuery = useQuery({
    queryKey: ['auditLog', orderId],
    queryFn: () => fetchAuditLog(orderId as string),
    enabled: !!orderId,
  });
  const receiptsQuery = useQuery({
    queryKey: ['deliveryReceipts', orderId],
    queryFn: () => fetchDeliveryReceipts(orderId as string),
    enabled: !!orderId,
  });

  return {
    order: orderQuery.data,
    auditLog: auditLogQuery.data ?? [],
    receipts: receiptsQuery.data ?? [],
    isLoading: orderQuery.isLoading || auditLogQuery.isLoading || receiptsQuery.isLoading,
    isError: orderQuery.isError,
    error: orderQuery.error,
    refetch: () => {
      orderQuery.refetch();
      auditLogQuery.refetch();
      receiptsQuery.refetch();
    },
  };
}
```

- [ ] **Step 6: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/src/api/orderDetail.ts office_web/src/api/orderDetail.test.ts office_web/src/hooks/useOrderDetail.ts
git commit -m "feat(office-web): add order detail, audit log, and سند queries"
```

---

## Task 12: Order detail panel — stepper, timeline, items, سند section

**Files:**
- Create: `office_web/src/lib/statusSteps.ts`
- Test: `office_web/src/lib/statusSteps.test.ts`
- Create: `office_web/src/api/storage.ts`
- Test: `office_web/src/api/storage.test.ts`
- Create: `office_web/src/components/OrderDetailPanel.tsx`
- Test: `office_web/src/components/OrderDetailPanel.test.tsx`

**Interfaces:**
- Consumes: `Order`, `OrderStatus`, `OrderDirection`, `AuditLogEntry`, `DeliveryReceipt`, `orderStatusLabel` from `../types/domain`; `StatusChip` from `./StatusChip`; `supabase` from `../lib/supabase`.
- Produces: `getStatusSteps(order): { status: OrderStatus; label: string }[]` and `getCurrentStepIndex(steps, order): number` from `src/lib/statusSteps.ts`.
- Produces: `resolveSignedUrl(bucket, path): Promise<string | null>` from `src/api/storage.ts` (ported from `lib/core/storage/signed_storage_url.dart`, no in-memory cache in phase 1 — YAGNI until repeated opens of the same PDF in one session prove it matters).
- Produces: `<OrderDetailPanel orderId={string} onClose={() => void} />` from `src/components/OrderDetailPanel.tsx`, consumed by Task 13.

- [ ] **Step 1: Write the failing statusSteps tests**

Create `office_web/src/lib/statusSteps.test.ts`:

```ts
import { describe, it, expect } from 'vitest';
import { getStatusSteps, getCurrentStepIndex } from './statusSteps';
import type { Order } from '../types/domain';

function order(overrides: Partial<Order>): Order {
  return {
    id: 'o1', referenceCode: null, direction: 'outbound', entityId: 'e1', entity: null,
    repId: null, rep: null, creator: null, status: 'assigned', notes: null,
    storageActorId: null, createdAt: null, assignedAt: null, pickedUpAt: null,
    moveStartedAt: null, deliveredAt: null, items: [],
    ...overrides,
  };
}

describe('getStatusSteps', () => {
  it('returns the two-step sequence for an inbound_external order', () => {
    const steps = getStatusSteps(order({ direction: 'inbound_external' }));
    expect(steps.map((s) => s.status)).toEqual(['assigned', 'delivered_to_storage']);
  });

  it('returns the four-step sequence for an inbound_rep order', () => {
    const steps = getStatusSteps(order({ direction: 'inbound_rep' }));
    expect(steps.map((s) => s.status)).toEqual(['assigned', 'picked_up', 'on_the_move', 'delivered_to_storage']);
  });

  it('returns the four-step outbound sequence ending in delivered', () => {
    const steps = getStatusSteps(order({ direction: 'outbound' }));
    expect(steps.map((s) => s.status)).toEqual(['assigned', 'picked_up', 'on_the_move', 'delivered']);
  });
});

describe('getCurrentStepIndex', () => {
  it('finds the index matching the order\'s current status', () => {
    const o = order({ direction: 'outbound', status: 'on_the_move' });
    const steps = getStatusSteps(o);
    expect(getCurrentStepIndex(steps, o)).toBe(2);
  });

  it('defaults to the first step when nothing matches', () => {
    const o = order({ direction: 'outbound', status: 'assigned' });
    const steps = getStatusSteps(o);
    expect(getCurrentStepIndex(steps, o)).toBe(0);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/lib/statusSteps.test.ts`
Expected: FAIL — `Cannot find module './statusSteps'`

- [ ] **Step 3: Write the implementation**

Ported from `lib/shared/widgets/order_status_stepper.dart`.

Create `office_web/src/lib/statusSteps.ts`:

```ts
import type { Order, OrderStatus } from '../types/domain';

export interface StatusStep {
  status: OrderStatus;
  label: string;
}

export function getStatusSteps(order: Order): StatusStep[] {
  switch (order.direction) {
    case 'inbound_external':
      return [
        { status: 'assigned', label: 'تم الإنشاء' },
        { status: 'delivered_to_storage', label: 'تم الاستلام في المخزن' },
      ];
    case 'inbound_rep':
      return [
        { status: 'assigned', label: 'تم الإنشاء' },
        { status: 'picked_up', label: 'تم الشراء' },
        { status: 'on_the_move', label: 'في الطريق' },
        { status: 'delivered_to_storage', label: 'استلام المخزن' },
      ];
    case 'outbound':
    default:
      return [
        { status: 'assigned', label: 'معين' },
        { status: 'picked_up', label: 'تم الاستلام' },
        { status: 'on_the_move', label: 'في الطريق' },
        { status: 'delivered', label: 'تم التسليم' },
      ];
  }
}

export function getCurrentStepIndex(steps: StatusStep[], order: Order): number {
  const index = steps.findIndex((step) => step.status === order.status);
  if (index >= 0) return index;
  if (order.status === 'delivered' || order.status === 'delivered_to_storage') return steps.length - 1;
  return 0;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/lib/statusSteps.test.ts`
Expected: PASS — 5 tests

- [ ] **Step 5: Write the failing storage test**

Create `office_web/src/api/storage.test.ts`:

```ts
import { describe, it, expect, vi } from 'vitest';

describe('resolveSignedUrl', () => {
  it('returns null for a missing path', async () => {
    vi.doMock('../lib/supabase', () => ({ supabase: { storage: { from: vi.fn() } } }));
    vi.resetModules();
    const { resolveSignedUrl } = await import('./storage');
    expect(await resolveSignedUrl('delivery-receipts', null)).toBeNull();
  });

  it('requests a signed URL for a stored path', async () => {
    const createSignedUrl = vi.fn().mockResolvedValue({ data: { signedUrl: 'https://signed.example/x.pdf' }, error: null });
    const from = vi.fn().mockReturnValue({ createSignedUrl });
    vi.doMock('../lib/supabase', () => ({ supabase: { storage: { from } } }));
    vi.resetModules();
    const { resolveSignedUrl } = await import('./storage');

    const url = await resolveSignedUrl('delivery-receipts', 'org1/u1/1.pdf');
    expect(from).toHaveBeenCalledWith('delivery-receipts');
    expect(createSignedUrl).toHaveBeenCalledWith('org1/u1/1.pdf', 3600);
    expect(url).toBe('https://signed.example/x.pdf');
  });

  it('extracts the storage path out of a legacy full public URL', async () => {
    const createSignedUrl = vi.fn().mockResolvedValue({ data: { signedUrl: 'https://signed.example/x.pdf' }, error: null });
    const from = vi.fn().mockReturnValue({ createSignedUrl });
    vi.doMock('../lib/supabase', () => ({ supabase: { storage: { from } } }));
    vi.resetModules();
    const { resolveSignedUrl } = await import('./storage');

    await resolveSignedUrl('delivery-receipts', 'https://x.supabase.co/storage/v1/object/public/delivery-receipts/org1/u1/1.pdf');
    expect(createSignedUrl).toHaveBeenCalledWith('org1/u1/1.pdf', 3600);
  });
});
```

- [ ] **Step 6: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/api/storage.test.ts`
Expected: FAIL — `Cannot find module './storage'`

- [ ] **Step 7: Write the implementation**

Ported from `lib/core/storage/signed_storage_url.dart` (no cache in phase 1 — see task header).

Create `office_web/src/api/storage.ts`:

```ts
import { supabase } from '../lib/supabase';

const LIFETIME_SECONDS = 3600;

export function pathOf(bucket: string, stored: string): string {
  if (!stored.startsWith('http')) return stored;
  const marker = `/${bucket}/`;
  const i = stored.indexOf(marker);
  if (i < 0) return stored;
  return decodeURIComponent(stored.slice(i + marker.length).split('?')[0]);
}

export async function resolveSignedUrl(bucket: string, stored: string | null): Promise<string | null> {
  if (!stored) return null;
  const path = pathOf(bucket, stored);
  const { data, error } = await supabase.storage.from(bucket).createSignedUrl(path, LIFETIME_SECONDS);
  if (error || !data) return null;
  return data.signedUrl;
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/api/storage.test.ts`
Expected: PASS — 3 tests

- [ ] **Step 9: Write the failing OrderDetailPanel tests**

Create `office_web/src/components/OrderDetailPanel.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import type { Order, AuditLogEntry, DeliveryReceipt } from '../types/domain';

const detailMock = vi.fn();
vi.mock('../hooks/useOrderDetail', () => ({ useOrderDetail: () => detailMock() }));
vi.mock('../api/storage', () => ({ resolveSignedUrl: vi.fn().mockResolvedValue('https://signed.example/x.pdf') }));

import { OrderDetailPanel } from './OrderDetailPanel';

function order(overrides: Partial<Order>): Order {
  return {
    id: 'o1', referenceCode: 'RN-1', direction: 'outbound', entityId: 'e1',
    entity: { id: 'e1', name: 'وزارة الصحة', category: 'outgoing', contactName: null, contactPhone: null, address: null },
    repId: null, rep: { id: 'u1', fullName: 'مندوب أحمد', phone: null, role: 'rep', isApproved: true },
    creator: null, status: 'assigned', notes: null, storageActorId: null,
    createdAt: '2026-09-28T10:00:00Z', assignedAt: null, pickedUpAt: null, moveStartedAt: null,
    deliveredAt: null,
    items: [{
      id: 'i1', orderId: 'o1', inventoryId: null, inventoryName: 'أكياس أرز', quantity: 5,
      finalQuantity: null, isCustom: false, customDescription: null, checkStatus: 'pending',
      checkedBy: null, checker: null, wasUnavailableAtCreation: false,
    }],
    ...overrides,
  };
}

describe('OrderDetailPanel', () => {
  it('renders order info, the current step, and each item', () => {
    detailMock.mockReturnValue({
      order: order({}), auditLog: [] as AuditLogEntry[], receipts: [] as DeliveryReceipt[],
      isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText('وزارة الصحة')).toBeInTheDocument();
    expect(screen.getByText('مندوب أحمد')).toBeInTheDocument();
    expect(screen.getByText('أكياس أرز')).toBeInTheDocument();
  });

  it('renders the "no history yet" message instead of crashing when audit log is empty', () => {
    detailMock.mockReturnValue({
      order: order({}), auditLog: [] as AuditLogEntry[], receipts: [] as DeliveryReceipt[],
      isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText('لا يوجد سجل بعد')).toBeInTheDocument();
  });

  it('renders a chronological entry per audit log row, even with just order_created', () => {
    const entry: AuditLogEntry = {
      id: 'a1', orderId: 'o1', action: 'order_created', oldStatus: null, newStatus: 'assigned',
      performer: null, notes: null, serverTimestamp: '2026-09-28T10:00:00Z',
    };
    detailMock.mockReturnValue({
      order: order({}), auditLog: [entry], receipts: [], isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText('تم إنشاء الطلب')).toBeInTheDocument();
  });

  it('shows an empty message when there is no سند attached, not an error', () => {
    detailMock.mockReturnValue({
      order: order({}), auditLog: [], receipts: [], isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    expect(screen.getByText('لا توجد سندات استلام لهذا الطلب')).toBeInTheDocument();
  });

  it('renders a سند row with a link once a PDF URL resolves', async () => {
    const receipt: DeliveryReceipt = {
      id: 'r1', orderId: 'o1', rep: { id: 'u1', fullName: 'مندوب أحمد', phone: null, role: 'rep', isApproved: true },
      deliveredAt: null, pdfUrl: 'org1/u1/1.pdf', notes: null, createdAt: '2026-09-28T09:00:00Z', items: [],
    };
    detailMock.mockReturnValue({
      order: order({}), auditLog: [], receipts: [receipt], isLoading: false, isError: false, refetch: vi.fn(),
    });
    render(<OrderDetailPanel orderId="o1" onClose={() => {}} />);
    await waitFor(() => expect(screen.getByRole('link', { name: /فتح السند/ })).toHaveAttribute('href', 'https://signed.example/x.pdf'));
  });
});
```

- [ ] **Step 10: Run tests to verify they fail**

Run: `cd office_web && npx vitest run src/components/OrderDetailPanel.test.tsx`
Expected: FAIL — `Cannot find module './OrderDetailPanel'`

- [ ] **Step 11: Write the component**

Create `office_web/src/components/OrderDetailPanel.tsx`:

```tsx
import { useEffect, useState } from 'react';
import { useOrderDetail } from '../hooks/useOrderDetail';
import { resolveSignedUrl } from '../api/storage';
import { getStatusSteps, getCurrentStepIndex } from '../lib/statusSteps';
import { StatusChip } from './StatusChip';
import { StatesPanel } from './StatesPanel';
import { orderDirectionLabel } from '../types/domain';
import type { AuditLogEntry, DeliveryReceipt } from '../types/domain';

const ACTION_LABEL: Record<string, string> = {
  order_created: 'تم إنشاء الطلب',
  status_changed: 'تغيير حالة الطلب',
};

function auditEntryLabel(entry: AuditLogEntry): string {
  return ACTION_LABEL[entry.action] ?? entry.action;
}

function formatDate(iso: string | null): string {
  return iso ? new Date(iso).toLocaleString('ar') : '—';
}

function ReceiptRow({ receipt }: { receipt: DeliveryReceipt }) {
  const [url, setUrl] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    resolveSignedUrl('delivery-receipts', receipt.pdfUrl).then((u) => {
      if (!cancelled) setUrl(u);
    });
    return () => {
      cancelled = true;
    };
  }, [receipt.pdfUrl]);

  return (
    <li className="flex items-center justify-between py-1.5 text-sm">
      <span className="text-text-medium">{formatDate(receipt.createdAt)} — {receipt.rep?.fullName ?? '—'}</span>
      {url && (
        <a href={url} target="_blank" rel="noreferrer" className="text-primary underline">
          فتح السند
        </a>
      )}
    </li>
  );
}

export function OrderDetailPanel({ orderId, onClose }: { orderId: string; onClose: () => void }) {
  const { order, auditLog, receipts, isLoading, isError, error, refetch } = useOrderDetail(orderId);

  if (isLoading) return <StatesPanel kind="loading" />;
  if (isError || !order) return <StatesPanel kind="error" message={(error as Error)?.message} onRetry={refetch} />;

  const steps = getStatusSteps(order);
  const currentIndex = getCurrentStepIndex(steps, order);

  return (
    <div className="w-[420px] shrink-0 border-r border-border-subtle bg-surface-card overflow-y-auto">
      <div className="flex items-center justify-between p-4 border-b border-border-subtle">
        <span className="font-mono text-sm text-text-medium">{order.referenceCode ?? order.id}</span>
        <button type="button" onClick={onClose} className="text-text-low hover:text-text-high">✕</button>
      </div>

      <div className="p-4 space-y-1 text-sm border-b border-border-subtle">
        <p><span className="text-text-low">الجهة: </span>{order.entity?.name ?? '—'}</p>
        <p><span className="text-text-low">الاتجاه: </span>{orderDirectionLabel[order.direction]}</p>
        <p><span className="text-text-low">المندوب: </span>{order.rep?.fullName ?? 'لا يوجد'}</p>
        <p><span className="text-text-low">الحالة: </span><StatusChip status={order.status} /></p>
        {order.notes && <p><span className="text-text-low">ملاحظات: </span>{order.notes}</p>}
      </div>

      <div className="p-4 border-b border-border-subtle">
        <h3 className="text-sm font-semibold mb-2">تقدم الطلب</h3>
        <ol className="flex flex-col gap-1">
          {steps.map((step, i) => (
            <li key={step.status} className={`text-sm ${i <= currentIndex ? 'text-text-high font-medium' : 'text-text-low'}`}>
              {i + 1}. {step.label}
            </li>
          ))}
        </ol>
      </div>

      <div className="p-4 border-b border-border-subtle">
        <h3 className="text-sm font-semibold mb-2">السجل الزمني</h3>
        {auditLog.length === 0 ? (
          <p className="text-sm text-text-low">لا يوجد سجل بعد</p>
        ) : (
          <ul className="space-y-1">
            {auditLog.map((entry) => (
              <li key={entry.id} className="text-sm text-text-medium">
                {formatDate(entry.serverTimestamp)} — {auditEntryLabel(entry)}
                {entry.performer && ` — ${entry.performer.fullName}`}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="p-4 border-b border-border-subtle">
        <h3 className="text-sm font-semibold mb-2">سندات الاستلام</h3>
        {receipts.length === 0 ? (
          <p className="text-sm text-text-low">لا توجد سندات استلام لهذا الطلب</p>
        ) : (
          <ul>
            {receipts.map((r) => <ReceiptRow key={r.id} receipt={r} />)}
          </ul>
        )}
      </div>

      <div className="p-4">
        <h3 className="text-sm font-semibold mb-2">الأصناف</h3>
        <ul className="space-y-2">
          {order.items.map((item) => (
            <li key={item.id} className="text-sm">
              <p className="font-medium text-text-high">{item.isCustom ? (item.customDescription ?? 'صنف مخصص') : (item.inventoryName ?? '—')}</p>
              <p className="text-text-low">
                الكمية: {item.finalQuantity ?? item.quantity}
                {item.finalQuantity != null && ` (مطلوب: ${item.quantity})`}
              </p>
              {item.wasUnavailableAtCreation && (
                <span className="inline-block text-xs text-warning bg-warning-bg px-2 py-0.5 rounded-input mt-1">غير متوفر</span>
              )}
            </li>
          ))}
        </ul>
      </div>
    </div>
  );
}
```

- [ ] **Step 12: Run tests to verify they pass**

Run: `cd office_web && npx vitest run src/components/OrderDetailPanel.test.tsx`
Expected: PASS — 5 tests

- [ ] **Step 13: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/src/lib/statusSteps.ts office_web/src/lib/statusSteps.test.ts office_web/src/api/storage.ts office_web/src/api/storage.test.ts office_web/src/components/OrderDetailPanel.tsx office_web/src/components/OrderDetailPanel.test.tsx
git commit -m "feat(office-web): add order detail panel with stepper, timeline, items, and سند section"
```

---

## Task 13: Wire the detail panel into the Orders page

**Files:**
- Modify: `office_web/src/pages/Orders.tsx`
- Modify: `office_web/src/pages/Orders.test.tsx`

**Interfaces:**
- Consumes: `OrderDetailPanel` from `../components/OrderDetailPanel` (Task 12).

- [ ] **Step 1: Add the failing test for panel wiring**

Add to `office_web/src/pages/Orders.test.tsx` (append inside the existing `describe('Orders page', ...)` block, alongside a new mock at the top of the file):

```tsx
vi.mock('../components/OrderDetailPanel', () => ({
  OrderDetailPanel: ({ orderId, onClose }: { orderId: string; onClose: () => void }) => (
    <div>
      <span>لوحة تفاصيل الطلب {orderId}</span>
      <button onClick={onClose}>إغلاق</button>
    </div>
  ),
}));
```

Add this test case inside `describe('Orders page', ...)`:

```tsx
  it('shows the detail panel beside the table when the URL has an order id', async () => {
    ordersMock.mockReturnValue({
      data: [order({ id: 'a' })], isLoading: false, isError: false, refetch: vi.fn(),
    });
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    render(
      <QueryClientProvider client={client}>
        <MemoryRouter initialEntries={['/orders/a']}>
          <Routes>
            <Route path="/orders/:orderId?" element={<Orders />} />
          </Routes>
        </MemoryRouter>
      </QueryClientProvider>,
    );
    await waitFor(() => expect(screen.getByText('لوحة تفاصيل الطلب a')).toBeInTheDocument());
    expect(screen.getByText('وزارة الصحة')).toBeInTheDocument();
  });
```

Replace the existing `react-router-dom` import at the top of `office_web/src/pages/Orders.test.tsx`:

```tsx
import { MemoryRouter, Routes, Route } from 'react-router-dom';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd office_web && npx vitest run src/pages/Orders.test.tsx`
Expected: FAIL — the panel never renders

- [ ] **Step 3: Wire the panel into the page**

In `office_web/src/pages/Orders.tsx`, add the import and render the panel conditionally. Replace the closing `<div className="h-full flex flex-row-reverse">...</div>` block with:

```tsx
      <div className="h-full flex flex-row-reverse">
        <div className="flex-1 min-w-0 flex flex-col">
          <OrdersToolbar
            sortMode={sortMode}
            directionFilter={directionFilter}
            groupMode={groupMode}
            activeTab={activeTab}
            onSortModeChange={setSortMode}
            onDirectionFilterChange={setDirectionFilter}
            onGroupModeChange={setGroupMode}
            onTabChange={setActiveTab}
          />
          <div className="flex-1 overflow-auto">
            <OrdersTable orders={visible} selectedId={orderId ?? null} onSelect={(id) => navigate(`/orders/${id}`)} />
          </div>
        </div>
        {orderId && <OrderDetailPanel orderId={orderId} onClose={() => navigate('/orders')} />}
      </div>
```

And add the import at the top:

```tsx
import { OrderDetailPanel } from '../components/OrderDetailPanel';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd office_web && npx vitest run src/pages/Orders.test.tsx`
Expected: PASS — 4 tests

- [ ] **Step 5: Run the full suite and the build**

Run: `cd office_web && npm test && npm run build`
Expected: all green

- [ ] **Step 6: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add office_web/src/pages/Orders.tsx office_web/src/pages/Orders.test.tsx
git commit -m "feat(office-web): open the order detail panel beside the list from the URL"
```

---

## Task 14: Firebase Hosting site and CI build

**Files:**
- Modify: `firebase.json`
- Create: `.firebaserc` (if it doesn't already exist — check first)
- Create: `.github/workflows/office-web.yml`

**Interfaces:**
- Produces: a `office-web` Firebase Hosting target building from `office_web/dist`, and a CI job that runs `npm ci && npm test && npm run build` inside `office_web/` on every push/PR touching that folder. No production auto-deploy is wired in phase 1 — see Step 3.

- [ ] **Step 1: Check for an existing `.firebaserc`**

Run: `cat /c/MSOC/flutter_projects/ura_core/.firebaserc 2>/dev/null || echo "none"`

If it exists, note its `projects.default` value for Step 2. If it says "none", create it in Step 2 with just the default project.

- [ ] **Step 2: Add the second hosting site to firebase.json**

Modify `firebase.json`: change the existing `"hosting"` object into an array with two entries — the existing Flutter web app (add a `"target": "app"` key to it, keeping everything else the same) and a new one for `office_web`:

```json
{
  "flutter": {
    "platforms": {
      "android": {
        "default": {
          "projectId": "ura-core-9981c",
          "appId": "1:624182997032:android:4fe9a4c3a2ed1ce67c051d",
          "fileOutput": "android/app/google-services.json"
        }
      },
      "dart": {
        "lib/firebase_options.dart": {
          "projectId": "ura-core-9981c",
          "configurations": {
            "android": "1:624182997032:android:4fe9a4c3a2ed1ce67c051d",
            "web": "1:624182997032:web:7102d58e974ccfe57c051d"
          }
        }
      }
    }
  },
  "hosting": [
    {
      "target": "app",
      "public": "build/web",
      "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
      "rewrites": [{ "source": "**", "destination": "/index.html" }]
    },
    {
      "target": "office-web",
      "public": "office_web/dist",
      "ignore": ["firebase.json", "**/.*", "**/node_modules/**"],
      "rewrites": [{ "source": "**", "destination": "/index.html" }]
    }
  ]
}
```

This step only edits the JSON file — it does not run `firebase hosting:sites:create` or `firebase target:apply` against the live project (those require the Firebase CLI logged into the account that owns `ura-core-9981c`, which is the user's to run). Leave a note in the commit message that these two commands still need running by the project owner:

```bash
firebase hosting:sites:create office-web-ura-core --project ura-core-9981c
firebase target:apply hosting office-web office-web-ura-core --project ura-core-9981c
firebase target:apply hosting app ura-core-9981c --project ura-core-9981c
```

- [ ] **Step 3: Write the CI workflow (build-verification only, no deploy)**

A deploy step is deliberately left out of phase 1: wiring an auto-deploy to a real hosting site needs a Firebase service-account secret added to the repo, which is the project owner's call, not something to do silently inside an implementation task. This workflow only proves the site builds and tests pass on every push — deploy gets wired in a follow-up once the owner has created the hosting site (Step 2) and added the secret.

Create `.github/workflows/office-web.yml`:

```yaml
name: office-web

on:
  push:
    paths:
      - 'office_web/**'
      - '.github/workflows/office-web.yml'
  pull_request:
    paths:
      - 'office_web/**'
      - '.github/workflows/office-web.yml'

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: office_web
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: office_web/package-lock.json
      - run: npm ci
      - run: npm run lint
      - run: npm test
      - run: npm run build
        env:
          VITE_SUPABASE_URL: https://musaqyislgvshurfrjwx.supabase.co
          VITE_SUPABASE_ANON_KEY: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im11c2FxeWlzbGd2c2h1cmZyand4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNDcwODgsImV4cCI6MjA5MDYyMzA4OH0.gR2k3UkW70GuBIZ69qz6WXvlFT1EMOpYlJCOtwBLF_M
```

- [ ] **Step 4: Verify the build succeeds locally with the same command CI will run**

Run: `cd office_web && npm ci && npm run lint && npm test && npm run build`
Expected: all four steps exit 0

- [ ] **Step 5: Verify the existing Flutter CI job is untouched**

Run: `cat /c/MSOC/flutter_projects/ura_core/.github/workflows/ci.yml | head -5`
Expected: file unchanged — this task added a new workflow file, never touched the existing one

- [ ] **Step 6: Commit**

```bash
cd /c/MSOC/flutter_projects/ura_core
git add firebase.json .github/workflows/office-web.yml
git commit -m "$(cat <<'EOF'
ci(office-web): add build/test workflow and a second Firebase Hosting target

No auto-deploy yet: creating the actual hosting site and wiring a
deploy secret needs firebase hosting:sites:create + target:apply run
by the project owner (commands left in this commit for them):

firebase hosting:sites:create office-web-ura-core --project ura-core-9981c
firebase target:apply hosting office-web office-web-ura-core --project ura-core-9981c
firebase target:apply hosting app ura-core-9981c --project ura-core-9981c
EOF
)"
```

---

## Final verification (run once all 14 tasks are committed)

- [ ] Run `cd office_web && npm test` — expect all tests across all tasks passing (≈45 tests).
- [ ] Run `cd office_web && npm run build` — expect a clean `dist/` build.
- [ ] Run `cd office_web && npm run dev`, open the printed local URL, and manually walk through: login screen renders in RTL with the amber/green tokens → log in with a real verifier account → orders list loads, search/sort/direction-filter/group/tabs all work → click a row → detail panel opens beside the list with real order info, stepper, timeline, items, and سند section → click "✕" to close it → log out returns to `/login`.
- [ ] Confirm `lib/` (the Flutter app) has zero changes: `git diff main...feat/office-web -- lib/` prints nothing.
