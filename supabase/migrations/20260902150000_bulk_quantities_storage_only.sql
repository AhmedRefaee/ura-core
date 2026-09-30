-- Close the last unguarded inventory write: inventory_bulk_update_quantities.
--
-- Found while verifying the new bulk RPCs -- its ACL still listed anon and
-- PUBLIC. Reading it confirmed the worst version of the pattern already fixed
-- twice this week (approve_order in 20260831130000, the stale
-- inventory_create_item/update_item overloads in 20260902120000): SECURITY
-- DEFINER, so RLS on inventory does not apply; EXECUTE granted to anon, so no
-- session is needed; and NO role check of any kind in the body. It takes a JSON
-- array of {item_id, quantity} and writes each one straight to
-- public.inventory.
--
-- In other words, the single most sensitive number in the system -- the stock
-- count the whole storage-only-quantity rule exists to protect -- could be set
-- to anything, on any item, by an unauthenticated caller.
--
-- Restricted to storage_actor and admin, deliberately NOT verifier. Every other
-- inventory RPC admits verifiers because they legitimately fix names, brands
-- and packaging; this one does nothing but set quantities, so a verifier has no
-- business calling it at all. That matches the UI exactly: its only caller is
-- InventoryBulkCubit, reached from InventoryBulkEditScreen, inside
-- InventoryManagementScreen -- which is mounted only by the storage and
-- org-admin home screens. Verifiers see InventoryAvailabilityScreen instead,
-- which is read-only. So no existing user loses a capability they had.
--
-- The signature is unchanged, so this is a true CREATE OR REPLACE with no
-- overload left behind -- see the note in 20260902120000 for why that
-- distinction matters here.

CREATE OR REPLACE FUNCTION "public"."inventory_bulk_update_quantities"(
  "p_updates" "jsonb"
) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_update       JSONB;
  v_item_id      UUID;
  v_new_quantity NUMERIC;
  v_old_quantity NUMERIC;
  v_role         user_role := get_user_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('storage_actor', 'admin') THEN
    RAISE EXCEPTION 'الكمية يحددها أمين المخزن فقط';
  END IF;

  FOR v_update IN SELECT * FROM jsonb_array_elements(p_updates)
  LOOP
    v_item_id      := (v_update->>'item_id')::UUID;
    v_new_quantity := (v_update->>'quantity')::NUMERIC;

    SELECT quantity INTO v_old_quantity FROM inventory WHERE id = v_item_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'الصنف غير موجود';
    END IF;

    UPDATE inventory SET quantity = v_new_quantity WHERE id = v_item_id;

    INSERT INTO inventory_audit_log (
      item_id, action, old_quantity, new_quantity, performed_by
    )
    VALUES (
      v_item_id, 'quantity_updated', v_old_quantity, v_new_quantity, auth.uid()
    );
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."inventory_bulk_update_quantities"("jsonb")
  FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."inventory_bulk_update_quantities"("jsonb")
  TO "authenticated";
