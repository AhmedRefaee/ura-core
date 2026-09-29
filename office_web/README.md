# office_web

Verifier-facing web app for URA Core's order and سند workflows (React + Vite + TypeScript + Supabase).

## Setup

1. `npm install`
2. Copy `.env.example` to `.env.local` and fill in `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` (same project as the Flutter app's `lib/config/supabase_config.dart`).

## Commands

- `npm run dev` — start the dev server
- `npm test` — run the test suite (Vitest + Testing Library)
- `npm run build` — type-check and build for production
- `npm run lint` — lint the project
- `npm run preview` — preview a production build locally

## Notes

- Linting uses **ESLint**, not the Vite template's default Oxlint — the tool version available during setup didn't support Oxlint, so ESLint (`eslint.config.js`) was swapped in instead.
- `src/components/OrdersTable.tsx` is a plain-React table, not TanStack Table — a v8→v9 breaking API change was discovered during implementation, so the table was hand-rolled instead of adding the dependency back.
