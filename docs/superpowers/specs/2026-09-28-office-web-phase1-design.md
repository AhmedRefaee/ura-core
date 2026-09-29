# Office Web — Phase 1: Foundation + Verifier Order Review

Branch: `feat/office-web`. Status: design approved in chat, spec written for review.

## Context

The Flutter app (Android + its web build) works well for reps on the move, but is unusable
as a real desktop tool: Flutter web paints to a canvas, so the browser gets no native text
selection, and Flutter's own scroll handling fights the browser's native scroll/ctrl+zoom.
That's a platform limitation, not a layout bug — no amount of responsive tuning inside
Flutter fixes it.

Decision: build a second, separate, framework-native website for desktop office users
(verifier, manager, admin), talking to the *same* Supabase project — no backend changes.
The Flutter app stays exactly as is for reps/mobile. Rep and storage-actor roles are
explicitly out of scope for this website (storage is assumed floor/warehouse work; revisit
if that assumption is wrong).

The project is too large for one spec, so it's phased, each phase its own
spec → plan → build cycle:

1. **This phase** — foundation (auth, shell, routing) + verifier order review (list + detail).
2. Inventory management.
3. Manager dashboards/stats.
4. Admin workflows (entities, projects/سندات, templates, settings).
5. Storage role — tentative, only if floor-work assumption turns out wrong.

## Visual language — from Stitch, tokens only

Two rounds of Google Stitch mockups were generated to explore the visual direction. They
are a **style reference only** — colors, borders, shadows, radii, type scale, spacing. Their
screen *content* (KPI gauges, "PO number", customs/fleet-tracking language, SSO login
buttons) is invented by the tool and does not match this app's real domain or data, and is
discarded. The real screens are specified below, driven by what `verifier_home_screen.dart`
and `task_detail_screen.dart` already do today.

Tokens taken from the corrected round (`stitch_ui/light mode/rouh_alnomu_enterprise_system/DESIGN.md`),
which matches the company's actual logo (`assets/splash/splash_logo.png` — gold "URA"
wordmark, green leaf accent):

- Primary: `#D97706` (text/borders), `#F59E0B` (fills/highlights)
- Secondary/foliage accent: `#65A30D` / `#16A34A`
- Surfaces: canvas `#F8FAFC`, card `#FFFFFF`, inset `#F1F5F9`, border `#E2E8F0`
- Text: high `#0F172A`, medium `#334155`, low `#64748B`
- Semantic: success `#15803D`/`#F0FDF4`, warning `#B45309`/`#FEF3C7`, error `#B91C1C`/`#FEF2F2`
- Font: IBM Plex Sans + IBM Plex Sans Arabic, RTL, zero letter-spacing, tabular numerals for figures
- Radii: 4px inputs/chips, 6px buttons, 8px cards/panels
- Shadows: flat/hairline-border first; shadow only on dropdowns/menus (Tier 2) and
  modals/drawers (Tier 3) — see DESIGN.md "Elevation & Depth" for exact values
- Dense table conventions: 34px header / 36px row height, `#F8FAFC` header background,
  right-aligned Arabic text, hover row tint `#FAFBFD`

Dark mode tokens exist in the same DESIGN.md but are **not built in phase 1** (see
Deferrals). Login's Nafath/Azure AD SSO buttons are dropped — auth is Supabase
email/password only.

## Architecture

- New folder `office_web/` in this repo (monorepo, not a separate repo — keeps one CI,
  one git history, reuses the Firebase project).
- Vite + React 18 + TypeScript + Tailwind CSS. Tailwind config ports the tokens above
  directly (`theme.extend.colors`, `borderRadius`, `fontFamily`). Stitch's exported
  `code.html` markup is the starting point for JSX, not a from-scratch rebuild.
- `@supabase/supabase-js`, pointed at the same Supabase project URL/anon key as the
  Flutter app (new env vars in `office_web`, same backend). Every read/write goes through
  the same RLS policies and RPCs the Flutter app already uses — zero backend changes.
- No general UI kit (e.g. shadcn/ui) yet — only TanStack Query and TanStack Table (see
  Data layer), since those are load-bearing for the actual features (data fetching, the
  dense sortable table). YAGNI on a full design-system package until phase 2+ needs more
  surface.
- Deployment: a second Firebase Hosting site in the existing `ura-core-9981c` Firebase
  project (`firebase hosting:sites:create`, added as a second entry in `firebase.json`'s
  `hosting` array with its own `target` and `public: office_web/dist`). A new CI job builds
  and deploys only `office_web`; the existing Flutter build/deploy job is untouched.

## Routing & auth

React Router:
- `/login`
- `/orders` — shell + orders table
- `/orders/:id` — same shell, table stays visible, detail panel opens beside it (URL-driven
  so it's a real, shareable/deep-linkable location, not just component state)
- `/` redirects to `/orders` if authenticated, `/login` otherwise

`<ProtectedRoute>`: checks the Supabase session, then `profiles.role`. Only `verifier` is
allowed through in phase 1; any other authenticated role sees a plain "not available for
your role yet" screen rather than a redirect loop — this keeps the same shell usable as
phase 3/4 add manager/admin without a routing rewrite.

Sidebar shows all eventual destinations (الطلبات, المخزون, المناديب, الإحصائيات,
الإعدادات) so later phases plug in without a nav redesign, but only الطلبات is enabled;
the rest render disabled with a "قريباً" badge.

## Data layer

TanStack Query wrapping `supabase-js` calls that mirror the Flutter app's existing queries
byte-for-byte — same select shape, same tables, same joins:

- **Orders list**: same shape as `OrderRepository._orderSelect` (`orders` + `entities` +
  `profiles` rep/creator + `order_items` + joined `inventory` name). Fetched once (existing
  app caps this at 2000 rows with no server pagination), filtered/sorted/grouped
  client-side — mirrors `order_sort_filter_bar.dart`'s real feature set exactly (see
  Screens below). No server-side pagination needed at this volume.
- **Order detail**: same shape as `OrderRepository._orderDetailSelect`.
- **Audit log**: `audit_log` rows for the order, same fields as `AuditLogEntry`
  (action, old/new status, performer, notes, timestamp) — powers the status timeline.
- **سند استلام (delivery receipts)**: reuses the already-built `delivery_receipts` /
  `delivery_receipt_items` tables and the existing signed-URL pattern for the PDF link —
  no changes to that module.

No realtime subscriptions in phase 1 (YAGNI) — refetch-on-window-focus (TanStack Query
default) plus a manual refresh button (already in the mockup's toolbar) is enough for a
desk workflow. Can add Supabase Realtime later if staring at a static screen turns out to
be a real problem.

TanStack Table drives the orders grid (sortable/filterable columns, virtualized rows) —
this is the piece Flutter's widgets fundamentally can't give a desktop user, and the actual
reason this website exists.

## Screens

### Login
Email/password form against Supabase `signInWithPassword`. On success, redirect to
`/orders`. Errors surface inline on the form. No SSO.

### Shell
Right-anchored sidebar (RTL) with the nav above; top bar with page title/breadcrumb,
a client-side search box that filters the currently-loaded orders list (not a real
cross-table `Cmd+K` search — that needs infrastructure this phase doesn't have), and a
user menu (name, role, logout). No notifications bell in phase 1 (the existing
`notifications` table/badge logic is app-specific and not yet scoped for this site).

### Orders list
The real feature set from `order_sort_filter_bar.dart`, not the mockup's invented KPI
gauges:
- Search (entity name, rep name, reference code)
- Sort: الأحدث / الأقدم / الأكثر تكراراً
- Direction filter: الكل / توريد / مشتريات مندوب داخلي / مشتريات مندوب خارجي
- Group by: بلا / حسب الجهة / حسب المندوب
- View: قائمة (table) / شبكة (cards) — table is the primary desktop view; grid kept for
  parity since the Flutter app already has both
- نشطة / مكتملة tabs
- Table columns: رقم الطلب (or reference code), الجهة, نوع العملية, الحالة (status chip),
  المندوب, التاريخ — **no value/price column**, the schema has no order-level money
- If a summary strip is included at all: plain counts (نشطة / معلقة ومتأخرة / مكتملة /
  الكل), computed from real `Order.status`/timestamps — no fabricated percentages or
  gauges

### Order detail panel
Opens beside the list at `/orders/:id`, mirrors `task_detail_screen.dart`:
- Reference code bar (copy-to-clipboard)
- Order info card: الجهة, الاتجاه, المندوب (linkable to their profile), ملاحظات
- Status stepper + status timeline, built from the real `audit_log` rows
- سند استلام section: reuses the existing `DeliveryReceiptsSection` read-only tile/PDF link
- Items list: each item's real state — pending/checked/rejected, أطلب خارج المخزون badge,
  requested vs. final quantity — no invented pricing/totals
- View-only in phase 1: no edit/copy/delete actions from the website yet (every other
  module in this app — سند included — started view-only and added actions later; same
  pattern here)

## Error handling

- TanStack Query's loading/error/empty states, styled with the skeleton/empty/error
  patterns from the Stitch "states" reference screen (`stitch_ui/_1` in round 1) — useful
  as a states *library*, not as a real page.
- Supabase auth errors surface inline on the login form.

## Testing

Vitest + React Testing Library for components/hooks. No browser e2e automation in phase 1
— nothing to regress-protect yet beyond one workflow.

## Explicit deferrals (not phase 1)

- Dark mode (tokens exist, UI/testing doesn't)
- Global `Cmd+K` cross-table search
- Notifications bell
- Realtime subscriptions
- Edit/create/delete actions on orders from the website
- Any role beyond `verifier`
- Storage role's own desktop site (pending confirmation it's actually needed)
