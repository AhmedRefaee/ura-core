-- Soft-delete support for inventory items.
--
-- Why: order_items.inventory_id has ON DELETE NO ACTION, so any item ever used
-- in an order cannot be hard-deleted without breaking historical order rows.
-- We mark items as archived instead; archived items are hidden from the active
-- inventory list, picker, SKU uniqueness check, and export, but remain
-- referenceable by past order_items rows.

ALTER TABLE inventory
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ NULL;

CREATE INDEX IF NOT EXISTS inventory_active_idx
  ON inventory (item_name)
  WHERE archived_at IS NULL;

CREATE OR REPLACE FUNCTION public.inventory_delete_item(p_item_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_already_archived TIMESTAMPTZ;
  v_old_quantity     INT;
BEGIN
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
$function$;
