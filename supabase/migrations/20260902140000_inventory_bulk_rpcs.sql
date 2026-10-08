-- Route the Excel bulk import/edit through guarded RPCs instead of raw table
-- writes.
--
-- InventoryManagementRepository.bulkImportItems/bulkUpdateItems wrote straight
-- to public.inventory (`.from('inventory').insert(...)` / `.update(...)`). The
-- only thing standing in front of that was the table's own RLS, whose UPDATE
-- and INSERT policies allow verifier, storage_actor and admin alike. So the
-- storage-only-quantity rule added in 20260901130000 -- which lives inside
-- inventory_create_item/inventory_update_item -- did not apply to the Excel
-- path at all: a verifier could export the catalogue, retype the quantity
-- column, re-import, and reset stock levels for every item at once. Exactly the
-- mistake that rule was written to prevent, through a second door.
--
-- Three more things came free with the raw writes being wrong:
--   * no audit trail -- the single-item RPCs log every change to
--     inventory_audit_log; the raw writes logged nothing, so a bulk edit of the
--     whole catalogue left no history;
--   * the unique index (20260901120000) still fired, but the Arabic message
--     naming which rule broke lives inside the RPCs, so the Excel path surfaced
--     only a bare 23505;
--   * bulkUpdateItems looped one HTTP round trip per row with no transaction,
--     so a failure halfway left the catalogue half-updated.
--
-- These two functions fix all four: one call, one transaction, the same role
-- check and verifier quantity clamp as the single-item RPCs, audit rows for
-- every change, and errors that name the offending spreadsheet row.
--
-- ON `notes`: p_notes on the single-item RPCs has always meant "note for the
-- change log", never inventory.notes -- the form field says so out loud
-- («ملاحظات (تُحفظ في سجل التغييرات)»). The raw Excel writes were the odd one
-- out, sending it to the inventory.notes column instead. These follow the
-- form's meaning. Nothing is lost: all 195 live rows have inventory.notes empty,
-- and nothing in the app reads that column.

-- ── Bulk create ──────────────────────────────────────────────────────────────
-- p_items: a JSON array of objects shaped like ImportedItemModel.toInsertMap(),
-- each carrying a `row_number` so a failure can point at the spreadsheet row.
CREATE OR REPLACE FUNCTION "public"."inventory_bulk_create_items"(
  "p_items" "jsonb"
) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_role     user_role := get_user_role();
  v_item     jsonb;
  v_item_id  uuid;
  v_quantity numeric;
  v_row      text := '?';
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('verifier', 'storage_actor', 'admin') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية لإضافة أصناف للمخزن';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_row := COALESCE(v_item->>'row_number', '?');

    -- Same rule as inventory_create_item: a verifier defines the product, the
    -- storage actor owns the count.
    v_quantity := CASE
      WHEN v_role = 'verifier' THEN 0
      ELSE COALESCE((v_item->>'quantity')::numeric, 0)
    END;

    INSERT INTO inventory (
      item_name, unit, quantity, sku, category, min_quantity, description,
      brand, variety, packaging_size, packaging_size_unit, aliases
    ) VALUES (
      v_item->>'item_name',
      v_item->>'unit',
      v_quantity,
      v_item->>'sku',
      v_item->>'category',
      COALESCE((v_item->>'min_quantity')::numeric, 3),
      v_item->>'description',
      v_item->>'brand',
      v_item->>'variety',
      (v_item->>'packaging_size')::numeric,
      v_item->>'packaging_size_unit',
      CASE
        WHEN jsonb_typeof(v_item->'aliases') = 'array'
          THEN ARRAY(SELECT jsonb_array_elements_text(v_item->'aliases'))
        ELSE NULL
      END
    )
    RETURNING id INTO v_item_id;

    INSERT INTO inventory_audit_log (
      item_id, action, old_quantity, new_quantity, performed_by, notes
    )
    VALUES (v_item_id, 'created', 0, v_quantity, auth.uid(), v_item->>'notes');
  END LOOP;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'الصف %: هذا الصنف موجود بالفعل في المخزن بنفس الاسم والعلامة التجارية والنوع والتعبئة', v_row
      USING ERRCODE = 'unique_violation';
END;
$$;

-- ── Bulk update ──────────────────────────────────────────────────────────────
-- p_items: a JSON array shaped like BulkEditItemModel.toUpdateMap(), each with
-- an `id` and a `row_number`.
CREATE OR REPLACE FUNCTION "public"."inventory_bulk_update_items"(
  "p_items" "jsonb"
) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_role         user_role := get_user_role();
  v_item         jsonb;
  v_item_id      uuid;
  v_old_quantity numeric;
  v_new_quantity numeric;
  v_action       text;
  v_row          text := '?';
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('verifier', 'storage_actor', 'admin') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية لتعديل أصناف المخزن';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_row     := COALESCE(v_item->>'row_number', '?');
    v_item_id := (v_item->>'id')::uuid;

    SELECT quantity INTO v_old_quantity FROM inventory WHERE id = v_item_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'الصف %: الصنف غير موجود', v_row;
    END IF;

    -- Same rule as inventory_update_item: a verifier's quantity is discarded
    -- silently, so they can still correct a name or fill in a brand without
    -- disturbing the stock count.
    v_new_quantity := CASE
      WHEN v_role = 'verifier' THEN v_old_quantity
      ELSE COALESCE((v_item->>'quantity')::numeric, v_old_quantity)
    END;

    UPDATE inventory
    SET item_name           = v_item->>'item_name',
        unit                = v_item->>'unit',
        quantity            = v_new_quantity,
        sku                 = v_item->>'sku',
        category            = v_item->>'category',
        min_quantity        = COALESCE((v_item->>'min_quantity')::numeric, 3),
        description         = v_item->>'description',
        brand               = v_item->>'brand',
        variety             = v_item->>'variety',
        packaging_size      = (v_item->>'packaging_size')::numeric,
        packaging_size_unit = v_item->>'packaging_size_unit',
        aliases             = CASE
          WHEN jsonb_typeof(v_item->'aliases') = 'array'
            THEN ARRAY(SELECT jsonb_array_elements_text(v_item->'aliases'))
          ELSE NULL
        END
    WHERE id = v_item_id;

    v_action := CASE
      WHEN v_old_quantity IS DISTINCT FROM v_new_quantity THEN 'quantity_updated'
      ELSE 'item_updated'
    END;

    INSERT INTO inventory_audit_log (
      item_id, action, old_quantity, new_quantity, performed_by, notes
    )
    VALUES (
      v_item_id, v_action, v_old_quantity, v_new_quantity, auth.uid(),
      v_item->>'notes'
    );
  END LOOP;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'الصف %: هذا الصنف موجود بالفعل في المخزن بنفس الاسم والعلامة التجارية والنوع والتعبئة', v_row
      USING ERRCODE = 'unique_violation';
END;
$$;

-- Only signed-in app users, never anon/PUBLIC. Matches the posture set for the
-- single-item RPCs in 20260902120000; the role check inside is the real guard,
-- this just removes the pointless surface.
REVOKE EXECUTE ON FUNCTION "public"."inventory_bulk_create_items"("jsonb")
  FROM PUBLIC, "anon";
REVOKE EXECUTE ON FUNCTION "public"."inventory_bulk_update_items"("jsonb")
  FROM PUBLIC, "anon";
GRANT EXECUTE ON FUNCTION "public"."inventory_bulk_create_items"("jsonb")
  TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."inventory_bulk_update_items"("jsonb")
  TO "authenticated";
