-- Only the storage actor owns the stock count.
--
-- A verifier may add a product to the catalogue (that is the whole point of
-- promoting an off-stock order item) and may correct its details -- name,
-- brand, variety, packaging, aliases -- because they are the one reading
-- customer messages and noticing when a name is wrong. What they may NOT do is
-- state how much of it is on the shelf. Only someone standing in the warehouse
-- can know that.
--
-- This has to live in the functions, not in RLS. Both are SECURITY DEFINER, so
-- they run as the owner and RLS on inventory never applies to this path at all
-- -- and neither body carried ANY role check before this migration, meaning any
-- authenticated user, a rep included, could call them directly and set any
-- quantity on any item. The table's RLS policies ("Verifiers and storage can
-- update inventory") only ever governed direct table access, which the app
-- does not use for these writes.
--
-- Enforcement rather than UI hiding: a disabled field is a courtesy, not a
-- control.

CREATE OR REPLACE FUNCTION "public"."inventory_create_item"(
  "p_name" "text",
  "p_unit" "text",
  "p_quantity" numeric,
  "p_sku" "text" DEFAULT NULL::"text",
  "p_category" "text" DEFAULT NULL::"text",
  "p_min_quantity" numeric DEFAULT 3,
  "p_description" "text" DEFAULT NULL::"text",
  "p_notes" "text" DEFAULT NULL::"text",
  "p_brand" "text" DEFAULT NULL::"text",
  "p_variety" "text" DEFAULT NULL::"text",
  "p_packaging_size" numeric DEFAULT NULL::numeric,
  "p_packaging_size_unit" "text" DEFAULT NULL::"text",
  "p_aliases" "text"[] DEFAULT NULL::"text"[]
) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_item_id  UUID;
  v_role     user_role := get_user_role();
  v_quantity NUMERIC;
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('verifier', 'storage_actor', 'admin') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية لإضافة أصناف للمخزن';
  END IF;

  -- A verifier creates the product, not its stock level. Forced to zero rather
  -- than rejected, so promoting an off-stock item still works in one step and
  -- the storage actor sets the real count afterwards.
  v_quantity := CASE WHEN v_role = 'verifier' THEN 0 ELSE COALESCE(p_quantity, 0) END;

  INSERT INTO inventory (
    item_name, unit, quantity, sku, category, min_quantity, description,
    brand, variety, packaging_size, packaging_size_unit, aliases
  )
  VALUES (
    p_name, p_unit, v_quantity, p_sku, p_category, p_min_quantity, p_description,
    p_brand, p_variety, p_packaging_size, p_packaging_size_unit, p_aliases
  )
  RETURNING id INTO v_item_id;

  INSERT INTO inventory_audit_log (item_id, action, old_quantity, new_quantity, performed_by, notes)
  VALUES (v_item_id, 'created', 0, v_quantity, auth.uid(), p_notes);
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'هذا الصنف موجود بالفعل في المخزن بنفس الاسم والعلامة التجارية والنوع والتعبئة'
      USING ERRCODE = 'unique_violation';
END;
$$;

CREATE OR REPLACE FUNCTION "public"."inventory_update_item"(
  "p_item_id" "uuid",
  "p_name" "text",
  "p_unit" "text",
  "p_quantity" numeric,
  "p_sku" "text" DEFAULT NULL::"text",
  "p_category" "text" DEFAULT NULL::"text",
  "p_min_quantity" numeric DEFAULT 3,
  "p_description" "text" DEFAULT NULL::"text",
  "p_notes" "text" DEFAULT NULL::"text",
  "p_brand" "text" DEFAULT NULL::"text",
  "p_variety" "text" DEFAULT NULL::"text",
  "p_packaging_size" numeric DEFAULT NULL::numeric,
  "p_packaging_size_unit" "text" DEFAULT NULL::"text",
  "p_aliases" "text"[] DEFAULT NULL::"text"[]
) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_old_quantity NUMERIC;
  v_new_quantity NUMERIC;
  v_action       TEXT;
  v_role         user_role := get_user_role();
BEGIN
  IF v_role IS NULL OR v_role NOT IN ('verifier', 'storage_actor', 'admin') THEN
    RAISE EXCEPTION 'ليس لديك صلاحية لتعديل أصناف المخزن';
  END IF;

  SELECT quantity INTO v_old_quantity FROM inventory WHERE id = p_item_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الصنف غير موجود';
  END IF;

  -- Whatever quantity a verifier sends is discarded, silently by design: they
  -- reach this function to fix a name or add a brand, and the stock count must
  -- survive that edit untouched.
  v_new_quantity := CASE
    WHEN v_role = 'verifier' THEN v_old_quantity
    ELSE COALESCE(p_quantity, v_old_quantity)
  END;

  UPDATE inventory
  SET item_name           = p_name,
      unit                = p_unit,
      quantity            = v_new_quantity,
      sku                 = p_sku,
      category            = p_category,
      min_quantity        = p_min_quantity,
      description         = p_description,
      brand               = p_brand,
      variety             = p_variety,
      packaging_size      = p_packaging_size,
      packaging_size_unit = p_packaging_size_unit,
      aliases             = p_aliases
  WHERE id = p_item_id;

  v_action := CASE WHEN v_old_quantity != v_new_quantity THEN 'quantity_updated' ELSE 'item_updated' END;

  INSERT INTO inventory_audit_log (item_id, action, old_quantity, new_quantity, performed_by, notes)
  VALUES (p_item_id, v_action, v_old_quantity, v_new_quantity, auth.uid(), p_notes);
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'هذا الصنف موجود بالفعل في المخزن بنفس الاسم والعلامة التجارية والنوع والتعبئة'
      USING ERRCODE = 'unique_violation';
END;
$$;
