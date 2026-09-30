-- Drop the pre-schema-cleanup inventory RPC overloads, which are still live,
-- still granted to anon/PUBLIC, and carry NONE of the protections added on
-- 2026-09-01.
--
-- Why they exist at all: 20260831120000_inventory_schema_cleanup.sql added five
-- trailing defaulted params to inventory_create_item/inventory_update_item with
-- a plain CREATE OR REPLACE, on the assumption that this replaces the function.
-- It does not. Postgres identifies a function by name + argument TYPE LIST, so
-- adding params -- defaulted or not -- creates a NEW overload and leaves the
-- old one untouched. The 2026-09-01 migrations (no-duplicates message, role
-- check, verifier quantity clamp) then only ever touched the new 13/14-arg
-- overloads, leaving the originals as an unguarded back door:
--
--   * no role check at all, and SECURITY DEFINER, so RLS on inventory is
--     bypassed -- the same hole class as the dropped approve_order RPC
--     (20260831130000);
--   * EXECUTE granted to anon and PUBLIC, so the create path was reachable
--     WITHOUT authenticating;
--   * no verifier quantity clamp, so the exact mistake that started this work
--     (an item promoted to inventory with a bogus quantity) was still possible;
--   * writes only the pre-cleanup column set, so brand/variety/packaging/aliases
--     silently stay NULL.
--
-- Nothing calls them: InventoryManagementRepository.createItem/updateItem always
-- send the full named-param set, so PostgREST resolves to the protected
-- overloads, and no other database function references either name.
--
-- Signatures are spelled out in full because the name alone is ambiguous now --
-- DROP FUNCTION without an argument list would error rather than pick one.

DROP FUNCTION IF EXISTS "public"."inventory_create_item"(
  "p_name" "text",
  "p_unit" "text",
  "p_quantity" numeric,
  "p_sku" "text",
  "p_category" "text",
  "p_min_quantity" numeric,
  "p_description" "text",
  "p_notes" "text"
);

DROP FUNCTION IF EXISTS "public"."inventory_update_item"(
  "p_item_id" "uuid",
  "p_name" "text",
  "p_unit" "text",
  "p_quantity" numeric,
  "p_sku" "text",
  "p_category" "text",
  "p_min_quantity" numeric,
  "p_description" "text",
  "p_notes" "text"
);

-- Belt and braces on the survivors. Their role check already rejects anon
-- (get_user_role() returns NULL with no JWT), but there is no reason for an
-- unauthenticated caller to reach an inventory write at all.
REVOKE EXECUTE ON FUNCTION "public"."inventory_create_item"(
  "text", "text", numeric, "text", "text", numeric, "text", "text",
  "text", "text", numeric, "text", "text"[]
) FROM PUBLIC, "anon";

REVOKE EXECUTE ON FUNCTION "public"."inventory_update_item"(
  "uuid", "text", "text", numeric, "text", "text", numeric, "text", "text",
  "text", "text", numeric, "text", "text"[]
) FROM PUBLIC, "anon";
