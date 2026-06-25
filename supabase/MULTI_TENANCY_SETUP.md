# Multi-Tenancy — Status & Setup

**Status: applied to the live project (`musaqyislgvshurfrjwx`) via the Supabase
MCP server.** All 5 migrations below are live. `flutter analyze` is clean and
the unit test suite passes against the updated `Profile` model.

## What actually shipped (corrected from the original draft)

The first draft of these migrations assumed the live schema had flat
`USING (true)` RLS everywhere. It did not — the live database already had
detailed role-based RLS (`get_user_role()`, `is_current_user_approved()`,
per-role `CASE` policies). Before applying anything, the live schema was
inspected via MCP and the migrations were rewritten to **patch the existing
policies in place** (AND-ing in an org check) instead of replacing them, which
would have destroyed real role-based security. Concretely:

- `profiles.role` is a **NOT NULL** `user_role` enum, not nullable text —
  pending joiners get `role = 'rep'` (matching the old client behavior, since
  `is_approved = false` is what actually gates them, not the role value).
- `approve_user` already existed with signature `(uuid, user_role)` — it was
  **replaced** (same signature), not overloaded with a conflicting `(uuid,
  text)` version.
- Several **pre-existing cross-tenant leaks** were found during the audit and
  fixed as part of this change:
  - `profiles`: any approved user could see *every* profile in the system;
    `"Users can insert own profile"` let a client self-insert with an
    arbitrary role/`is_approved` (privilege escalation) — that policy is
    removed; profile creation is now RPC-only.
  - `entities` / `inventory`: view/update/delete had no org awareness.
  - `orders`: 4 OR'd SELECT policies, several with no org check — any one
    alone would have leaked cross-org orders.
  - `audit_log` / `order_edit_log` / `urgent_notes`: "manager/verifier sees
    all" policies were global, not scoped to the related order's org.
  - `order_items` insert/update checked role only, never which order (and
    therefore which org) the item was being attached to.
  - `order_templates` / `order_template_items` / `chat_message_reactions` had
    fully open (`USING (true)`) policies.
- The auto-stamp trigger **unconditionally overwrites** `organization_id` on
  insert (not just when null), closing a spoof vector where a client could
  otherwise pass a different org's UUID directly.
- A follow-up hardening pass (`20260623_harden_rpc_grants.sql`) revoked
  `anon` EXECUTE on every new SECURITY DEFINER RPC (Postgres grants EXECUTE to
  `PUBLIC`, which `anon` inherits, by default) and pinned `search_path` on two
  functions the security advisor flagged.

Post-apply `get_advisors` (security) run: **zero error-level findings**. The
only new warnings were the two missing-`search_path` functions (now fixed)
and the `anon`-executable RPCs (now revoked). `chat_audit_log` and
`inventory_audit_log` show up as "RLS enabled, no policy" — that's intentional
default-deny (written only by triggers), not a regression.

## Migration files (apply in this order if rebuilding elsewhere)

1. `20260623_organizations.sql` — tables, `organization_id` columns, helpers,
   auto-stamp trigger, backfill (existing data → one `URA` org), safety check.
2. `20260623_org_rls.sql` — surgical RLS patch (see above).
3. `20260623_onboarding_rpcs.sql` — onboarding RPCs + org-scoped `approve_user`.
4. `20260623_admin_rpcs.sql` — platform-admin RPCs.
5. `20260623_harden_rpc_grants.sql` — anon EXECUTE revocation + search_path pins.

## Make yourself the hidden platform admin

Run once in the SQL editor (or via MCP `execute_sql`), using your account's
email:

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
                        || '{"platform_admin": true}'::jsonb
where email = 'YOUR_EMAIL_HERE';
```

Then **sign out and back in** so the new claim is in your JWT. You'll be
routed to `/admin` and won't appear in any organization's member list.

## Auth settings

Keep **email confirmation disabled** (Auth → Providers → Email). The app calls
an onboarding RPC immediately after sign-up; with confirmation on, the user has
no session at that moment and onboarding fails.

## Update 2026-06-24: invite-token join method removed

The invite-token flow (`org_invites`, `create_org_invite`, `accept_invite`) was
dropped — it was functionally redundant with the join-code flow (both are
"type in a code to join"; join code is simpler, reusable, and manager-
rotatable). Joining an org is now two ways only: **directory** and **join
code**. See `20260624_drop_org_invites.sql`. The onboarding flow was also
restructured the same day: "Create organization" is now a pre-auth landing
action (name the org, then sign up, then a first-member details screen) —
see git history for `create_org_name_screen.dart` / `create_org_details_screen.dart`.

## Still needs a real end-to-end pass

SQL/MCP access runs as a privileged service role with no `auth.uid()`, so the
onboarding RPCs couldn't be exercised end-to-end from here. Please verify in
the running app:

1. Sign up → "Create organization" → land on manager home, approved.
2. Sign up (separate account) → "Join by code" using the first org's join
   code → pending → first manager approves → routed by assigned role.
3. Directory tab only shows orgs with `is_discoverable = true` (the backfilled
   `URA` org is intentionally **not** discoverable).
4. Two separate orgs: confirm org A cannot see org B's orders/inventory/chat.
5. Platform admin account → `/admin` console → sees all orgs/members.
