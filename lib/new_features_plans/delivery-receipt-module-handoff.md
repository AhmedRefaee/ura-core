# سند استلام (Delivery Receipt) Module — Handoff Spec

## Context

URA-CORE is Ahmed's existing multi-tenant inventory/order management platform (Flutter/BLoC + Supabase, RLS-enforced multi-tenant Postgres, four-stage order lifecycle, multiple user roles). This spec is for a **new module inside URA-CORE**, not a standalone app — before touching anything, read the actual current schema, role definitions, and RLS setup in the codebase. This doc describes what needs to exist, not what's already there.

## The problem being solved

Reps deliver goods to client entities and currently hand over a handwritten receipt. Some entities don't accept the handwritten version. Goal: a rep picks items + quantities from a project's catalog and the app generates a proper PDF on that project's letterhead.

## Missing layer: Entity → Project → Order

Orders currently connect directly to an entity. That's incomplete: one entity can run multiple projects at the same time, and an order actually belongs to a project, not straight to the entity. Needs:

- New `projects` table, connected to `entity_id`
- `project_id` wired in wherever orders currently only carry `entity_id`

## New table: project_items

This is the digitized version of the خطاب العرض (quotation) Ahmed already produces per project by hand. Columns: item name, description, quantity, unit, unit price, total price. Connected to `project_id` (and transitively to the entity).

Two audiences, different visibility needs:
- **Commercial** (management): full pricing + totals — this table IS the quotation data.
- **Operational** (reps, others tracking physical goods): item / description / unit, no pricing.

**Open, not decided — ask Ahmed before implementing:** the exact permission matrix (who sees price/totals vs. item/unit only). Column-level RLS vs. a view-based split are both on the table. Don't guess the boundary, confirm it first.

## New table: سندات الاستلام (delivery receipts)

- Keys off `entity_id` + `project_id`. Deliberately **not** a required `order_id` — reps sometimes create these later in the day as a standalone logistics step, disconnected from any specific order, so the receipt has to stand on its own.
- Optional nullable `order_id` is fine for traceability when a receipt is triggered from an order's last step, but it must never be required.
- Fields: items + quantities delivered, date, rep, generated PDF reference, which project letterhead/logo was used.

## UX flow

**Reps (primary creators):**
- Optional action after an order's last step, pre-filling entity/project from that order's context — never forced.
- Must also be reachable standalone, independent of any order, for the "did it later as cleanup" case: pick entity → project → items/quantities → generate PDF.

**Verifier / storage / manager roles (viewers, mostly later):**
- No separate top-level "Delivery Notes" menu. سندات should live attached to the project/order record these roles already open — part of that record's history, not a parallel section.
- These roles need a project-selection step of their own, since they're not arriving from "my current order" the way a rep is.
- **Open, not decided:** view-only, or can these roles act on a سند (approve it, flag a mismatch)? Changes whether this is a display feature or another order-lifecycle step. Build view-only first unless Ahmed confirms otherwise.

## PDF generation

- Rendered from a per-project letterhead/logo template.
- Flutter `pdf` + `printing` packages. Needs to work on mobile and web — this lives inside the main URA-CORE app (mobile + web, one Flutter build), not a separate build.

## Also still open, unresolved before this spec was written

- Whether URA-CORE currently does any offline caching / queued writes, or is fully live against Supabase. Decides whether the سند creation flow (reps may do this in the field) needs its own offline-write handling or can lean on whatever already exists. Check the codebase — don't assume either way.

## Suggested build order

1. Read existing schema, roles, and RLS setup in the codebase first.
2. `projects` table + `project_id` wired into orders.
3. `project_items` table (hold off on permission split until step 4 is answered).
4. Confirm the price-visibility matrix with Ahmed, then apply role-based visibility on `project_items`.
5. سندات table + rep creation flow (both the post-order optional action and the standalone path).
6. PDF generation from project letterhead.
7. View surfaced on project/order records for verifier/storage/manager roles (view-only first).
8. Approve/flag actions on سندات — only if Ahmed confirms it's needed.
