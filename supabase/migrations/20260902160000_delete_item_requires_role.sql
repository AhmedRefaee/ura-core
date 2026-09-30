-- inventory_delete_item: the last inventory RPC with no role check.
--
-- Same family as the three already fixed this week: SECURITY DEFINER (so RLS on
-- inventory does not apply) and EXECUTE granted to anon, with nothing in the
-- body checking who is calling. It archives a catalogue item -- soft delete via
-- archived_at, but the confirmation dialog tells the user «لا يمكن التراجع عن
-- هذا الإجراء», and an archived row also stops blocking the uniqueness index
-- from 20260901120000, so this is not a harmless flag flip. An unauthenticated
-- caller could archive the entire catalogue one id at a time.
--
-- Allowed roles deliberately match inventory_create_item/inventory_update_item
-- (verifier, storage_actor, admin) rather than the narrower storage-only set
-- used for quantity RPCs. Archiving is a catalogue operation, not a stock-count
-- one, and verifiers already reach it through the UI -- so this closes the
-- unauthenticated hole without taking a capability away from anyone who has it
-- today. Whether a verifier *should* be able to archive an item straight from
-- the order-drafting screen is a separate product question, deliberately not
-- decided here.

CREATE OR REPLACE FUNCTION "public"."inventory_delete_item"(
  "p_item_id" "uuid"
) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_already_archived TIMESTAMPTZ;
  v_old_quantity     NUMERIC;
  v_role             user_role := get_user_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('verifier', 'storage_actor', 'admin') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية لحذف أصناف المخزن';
  END IF;

  SELECT archived_at, quantity
    INTO v_already_archived, v_old_quantity
  FROM inventory
  WHERE id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لم يتم العثور على العنصر' USING ERRCODE = 'P0002';
  END IF;

  IF v_already_archived IS NOT NULL THEN
    RETURN;
  END IF;

  UPDATE inventory
     SET archived_at = now()
   WHERE id = p_item_id;

  INSERT INTO inventory_audit_log
    (item_id, action, old_quantity, new_quantity, performed_by)
  VALUES
    (p_item_id, 'archived', v_old_quantity, v_old_quantity, auth.uid());
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."inventory_delete_item"("uuid")
  FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."inventory_delete_item"("uuid")
  TO "authenticated";
