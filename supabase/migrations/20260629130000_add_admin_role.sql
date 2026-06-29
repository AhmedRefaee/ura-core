-- New org-level role: one admin per organization, assigned by that org's
-- manager, who gets the union of manager + verifier + rep + storage_actor
-- permissions within their own org. Postgres forbids using a newly added
-- enum value in the same transaction/migration it was added in, so this is
-- a standalone migration; the policy/function grants that reference 'admin'
-- live in the next migration file.

ALTER TYPE public.user_role ADD VALUE 'admin';
