-- Storage links the verifier's typed lines to the catalog.
--
-- The verifier no longer matches anything: an outbound order arrives as the
-- lines they typed or pasted. When storage marks a typed line ✓ it can:
--   * link it to an existing inventory row  -> storage_link_order_item
--   * add it to the catalog as a new row and link it in one step
--                                           -> storage_create_and_link_item
--   * leave it as is ("just available")     -> check_order_item, as before
--
-- A linked line becomes an ordinary inventory line (inventory_id set,
-- is_custom = false) and keeps the verifier's text in custom_description.
-- On a non-custom row with no source_inventory_id that text is the "storage
-- linked a typed line" marker, and what the item list shows as "كتبها
-- المدقق". It deducts stock on confirm like any other row, and the typed name
-- is added to the row's aliases then, so the same words suggest the same row
-- next time (exact text only; the app never links on its own).
--
-- storage_confirm_pickup also splits a partly available "just available"
-- line: the shortfall becomes a ✗ line the rep buys. It now also checks the
-- order belongs to the caller's organization, which it never did.
--
-- Every function: SECURITY DEFINER, fails closed on a NULL auth.uid(), checks
-- the order and the inventory row belong to the caller's organization, anon
-- revoked.

-- ── 1. Alias helper ─────────────────────────────────────────────────────────

-- Adds the typed name inside p_description (the custom-item JSON, or plain
-- text) to the row's aliases unless it already is its name or an alias.
CREATE OR REPLACE FUNCTION public._remember_inventory_alias(p_inventory_id uuid, p_description text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_name text;
BEGIN
  BEGIN
    v_name := btrim(p_description::jsonb->>'name');
  EXCEPTION WHEN others THEN
    v_name := btrim(p_description);
  END;
  IF v_name IS NULL OR v_name = '' THEN RETURN; END IF;

  UPDATE inventory i
  SET aliases = array_append(COALESCE(i.aliases, '{}'), v_name)
  WHERE i.id = p_inventory_id
    AND lower(btrim(i.item_name)) <> lower(v_name)
    AND NOT EXISTS (
      SELECT 1 FROM unnest(COALESCE(i.aliases, '{}')) a WHERE lower(btrim(a)) = lower(v_name)
    );
END;
$$;

-- Internal: only the SECURITY DEFINER functions below call it.
REVOKE EXECUTE ON FUNCTION public._remember_inventory_alias(uuid, text) FROM anon, authenticated, PUBLIC;

-- ── 2. Shared guard: storage may still change this outbound line ────────────

CREATE OR REPLACE FUNCTION public._storage_review_item(p_item_id uuid)
RETURNS order_items
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_role user_role;
  v_item order_items%ROWTYPE;
  v_order orders%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'غير مصرح'; END IF;
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role IS NULL OR v_role NOT IN ('storage_actor', 'admin') THEN
    RAISE EXCEPTION 'غير مصرح';
  END IF;

  SELECT * INTO v_item FROM order_items WHERE id = p_item_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'الصنف غير موجود'; END IF;
  SELECT * INTO v_order FROM orders WHERE id = v_item.order_id;
  IF v_order.organization_id IS DISTINCT FROM auth_org_id() THEN RAISE EXCEPTION 'غير مصرح'; END IF;
  IF v_order.direction <> 'outbound' OR v_order.status <> 'assigned' OR v_order.storage_reviewed_at IS NOT NULL THEN
    RAISE EXCEPTION 'لم يعد بالإمكان تعديل هذا الطلب';
  END IF;
  -- Only a line the verifier typed (linked or not). A catalog line from a
  -- template has no typed text; a split-off shortfall points at its source.
  IF v_item.custom_description IS NULL OR v_item.source_inventory_id IS NOT NULL THEN
    RAISE EXCEPTION 'هذا الصنف مرتبط بالمخزن أصلاً';
  END IF;
  RETURN v_item;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._storage_review_item(uuid) FROM anon, authenticated, PUBLIC;

-- ── 3. storage_link_order_item: link / unlink a typed line ──────────────────

-- p_inventory_id NULL unlinks: the line goes back to exactly what the
-- verifier typed, awaiting a decision. p_quantity restates the line in the
-- catalog row's unit ("2 كرتون" -> 48 حبة); NULL keeps it.
CREATE OR REPLACE FUNCTION public.storage_link_order_item(
  p_item_id uuid,
  p_inventory_id uuid,
  p_quantity numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_item order_items%ROWTYPE;
  v_typed_qty numeric;
BEGIN
  BEGIN
    v_item := public._storage_review_item(p_item_id);
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;

  IF p_inventory_id IS NULL THEN
    BEGIN
      v_typed_qty := (v_item.custom_description::jsonb->>'qty')::numeric;
    EXCEPTION WHEN others THEN
      v_typed_qty := NULL;
    END;
    UPDATE order_items
    SET inventory_id = NULL, is_custom = TRUE, final_quantity = NULL,
        quantity = COALESCE(NULLIF(v_typed_qty, 0), quantity),
        check_status = 'pending', checked_by = NULL, checked_at = NULL
    WHERE id = p_item_id;
    RETURN jsonb_build_object('success', true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM inventory
    WHERE id = p_inventory_id AND organization_id = auth_org_id() AND archived_at IS NULL
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'الصنف غير موجود في المخزن');
  END IF;
  IF p_quantity IS NOT NULL AND p_quantity <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'الكمية يجب أن تكون أكبر من صفر');
  END IF;

  UPDATE order_items
  SET inventory_id = p_inventory_id, is_custom = FALSE, final_quantity = NULL,
      quantity = COALESCE(p_quantity, quantity),
      check_status = 'checked', checked_by = auth.uid(), checked_at = NOW()
  WHERE id = p_item_id;
  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.storage_link_order_item(uuid, uuid, numeric) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.storage_link_order_item(uuid, uuid, numeric) TO authenticated;

-- ── 4. storage_create_and_link_item: new catalog row + link, one step ───────

-- The same insert as inventory_create_item (storage keeps its real count),
-- then the link. One transaction: a failed link leaves no orphan row.
CREATE OR REPLACE FUNCTION public.storage_create_and_link_item(
  p_item_id uuid,
  p_name text,
  p_unit text,
  p_quantity numeric,
  p_line_quantity numeric DEFAULT NULL,
  p_sku text DEFAULT NULL,
  p_category text DEFAULT NULL,
  p_min_quantity numeric DEFAULT 3,
  p_description text DEFAULT NULL,
  p_brand text DEFAULT NULL,
  p_variety text DEFAULT NULL,
  p_packaging_size numeric DEFAULT NULL,
  p_packaging_size_unit text DEFAULT NULL,
  p_aliases text[] DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_item order_items%ROWTYPE;
  v_inv_id uuid;
  v_qty numeric := GREATEST(COALESCE(p_quantity, 0), 0);
  v_link jsonb;
BEGIN
  BEGIN
    v_item := public._storage_review_item(p_item_id);
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
  END;
  IF NOT v_item.is_custom THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الصنف مرتبط بالمخزن أصلاً');
  END IF;
  IF p_name IS NULL OR btrim(p_name) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'اسم الصنف مطلوب');
  END IF;

  BEGIN
    INSERT INTO inventory (
      item_name, unit, quantity, sku, category, min_quantity, description,
      brand, variety, packaging_size, packaging_size_unit, aliases
    ) VALUES (
      btrim(p_name), p_unit, v_qty, p_sku, p_category, p_min_quantity, p_description,
      p_brand, p_variety, p_packaging_size, p_packaging_size_unit, p_aliases
    )
    RETURNING id INTO v_inv_id;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('success', false, 'error',
      'هذا الصنف موجود بالفعل في المخزن — استخدم "ربط بصنف في المخزن" بدلاً من ذلك');
  END;

  INSERT INTO inventory_audit_log (item_id, action, old_quantity, new_quantity, performed_by, notes)
  VALUES (v_inv_id, 'created', 0, v_qty, auth.uid(), 'أُضيف أثناء مراجعة طلب');

  v_link := public.storage_link_order_item(p_item_id, v_inv_id, p_line_quantity);
  IF NOT (v_link->>'success')::boolean THEN
    -- Undo the insert with the rest of the transaction.
    RAISE EXCEPTION '%', v_link->>'error';
  END IF;
  RETURN jsonb_build_object('success', true, 'inventory_id', v_inv_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.storage_create_and_link_item(uuid, text, text, numeric, numeric, text, text, numeric, text, text, text, numeric, text, text[]) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.storage_create_and_link_item(uuid, text, text, numeric, numeric, text, text, numeric, text, text, text, numeric, text, text[]) TO authenticated;

-- ── 5. storage_confirm_pickup: aliases + partial "just available" lines ────

CREATE OR REPLACE FUNCTION "public"."storage_confirm_pickup"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_final_quantities" "jsonb" DEFAULT '[]'::"jsonb") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order orders%ROWTYPE;
  v_item  order_items%ROWTYPE;
  v_inv   inventory%ROWTYPE;
  v_role  user_role;
  v_final_qty NUMERIC;
  v_item_count INT;
  v_sent_count INT;
  v_new_status order_status;
BEGIN
  IF auth.uid() IS NULL THEN RETURN json_build_object('success', false, 'error', 'غير مصرح'); END IF;
  SELECT role INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role IS NULL OR v_role NOT IN ('storage_actor', 'admin') THEN
    RETURN json_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN json_build_object('success', false, 'error', 'الطلب غير موجود'); END IF;
  IF v_order.organization_id IS DISTINCT FROM auth_org_id() THEN
    RETURN json_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT count(*) INTO v_item_count FROM order_items WHERE order_id = target_order_id;
  IF v_item_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'هذا الطلب غير صالح لأنه لا يحتوي على عناصر');
  END IF;

  IF v_order.status != 'assigned' OR v_order.storage_reviewed_at IS NOT NULL THEN
    RETURN json_build_object('success', false, 'error', 'الطلب ليس في حالة معين');
  END IF;
  IF v_order.direction != 'outbound' THEN RETURN json_build_object('success', false, 'error', 'هذا الإجراء مخصص للطلبات الصادرة فقط'); END IF;

  -- Every row needs a decision before the order can move on.
  IF EXISTS (SELECT 1 FROM order_items WHERE order_id = target_order_id AND check_status = 'pending') THEN
    RETURN json_build_object('success', false, 'error', 'يجب مراجعة جميع الأصناف (متوفر أو غير متوفر) قبل التأكيد');
  END IF;

  FOR i IN 0..jsonb_array_length(p_final_quantities) - 1 LOOP
    UPDATE order_items
    SET final_quantity = (p_final_quantities->i->>'quantity')::NUMERIC
    WHERE id = (p_final_quantities->i->>'item_id')::UUID
      AND order_id = target_order_id
      AND check_status = 'checked';
  END LOOP;

  v_sent_count := 0;
  FOR v_item IN
    SELECT * FROM order_items
    WHERE order_id = target_order_id AND check_status = 'checked'
  LOOP
    v_final_qty := COALESCE(v_item.final_quantity, v_item.quantity);
    IF v_final_qty <= 0 THEN
      RETURN json_build_object('success', false, 'error', 'كمية صنف متوفر يجب أن تكون أكبر من صفر — استخدم غير متوفر بدلاً من ذلك');
    END IF;
    IF v_final_qty > v_item.quantity THEN
      RETURN json_build_object('success', false, 'error', 'لا يمكن أن تزيد الكمية عن المطلوبة');
    END IF;
    v_sent_count := v_sent_count + 1;

    -- Real inventory rows leave the shelf; a ✓ on a typed line storage did
    -- not link ("just available") hands it over with nothing to deduct.
    IF v_item.inventory_id IS NOT NULL AND v_item.is_custom = FALSE THEN
      UPDATE inventory SET quantity = GREATEST(0, quantity - v_final_qty) WHERE id = v_item.inventory_id;

      -- A typed line storage linked to this row: remember what the verifier
      -- called it, so the same words suggest this row next time. Written now,
      -- not at link time, so a link storage undid before confirming leaves
      -- nothing behind.
      IF v_item.custom_description IS NOT NULL THEN
        PERFORM public._remember_inventory_alias(v_item.inventory_id, v_item.custom_description);
      END IF;

      -- Storage only had part of it: the rest becomes a ✗ row the rep buys.
      IF v_final_qty < v_item.quantity THEN
        SELECT * INTO v_inv FROM inventory WHERE id = v_item.inventory_id;
        INSERT INTO order_items (
          order_id, inventory_id, quantity, is_custom, custom_description,
          source_inventory_id, check_status, checked_by, checked_at
        ) VALUES (
          target_order_id, NULL, v_item.quantity - v_final_qty, TRUE,
          jsonb_build_object(
            'name', v_inv.item_name,
            'qty', v_item.quantity - v_final_qty,
            'unit', COALESCE(v_inv.unit, 'قطعة'),
            'minQty', 0
          )::text,
          v_item.inventory_id, 'rejected', auth.uid(), NOW()
        );
      END IF;
    ELSIF v_final_qty < v_item.quantity THEN
      -- "Just available", but only part of it: the rest is the rep's to buy,
      -- described exactly as the verifier wrote it.
      INSERT INTO order_items (
        order_id, inventory_id, quantity, is_custom, custom_description,
        source_inventory_id, check_status, checked_by, checked_at
      ) VALUES (
        target_order_id, NULL, v_item.quantity - v_final_qty, TRUE,
        v_item.custom_description, NULL, 'rejected', auth.uid(), NOW()
      );
    END IF;
  END LOOP;

  IF v_sent_count > 0 THEN
    v_new_status := 'picked_up';
    UPDATE orders
    SET status = 'picked_up', storage_actor_id = auth.uid(), picked_up_at = NOW(), storage_reviewed_at = NOW()
    WHERE id = target_order_id;

    INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes, server_timestamp)
    VALUES (target_order_id, 'storage_pickup', 'assigned', 'picked_up', auth.uid(), p_notes, NOW());
  ELSE
    -- Nothing to send: the rep buys everything. Status stays 'assigned' and
    -- the rep starts the trip directly (start_move allows it once reviewed).
    v_new_status := 'assigned';
    UPDATE orders
    SET storage_actor_id = auth.uid(), storage_reviewed_at = NOW()
    WHERE id = target_order_id;

    INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes, server_timestamp)
    VALUES (target_order_id, 'storage_review_all_unavailable', 'assigned', 'assigned', auth.uid(), p_notes, NOW());

    PERFORM public.dispatch_push(
      array_remove(array[v_order.rep_id, v_order.created_by], NULL),
      'راجع المخزن الطلب',
      'كل الأصناف غير متوفرة في المخزن — تُشترى من الخارج',
      jsonb_build_object('route', '/orders/' || target_order_id, 'order_id', target_order_id::text)
    );
  END IF;

  RETURN json_build_object('success', true, 'status', v_new_status::text);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."storage_confirm_pickup"("uuid", "text", "jsonb") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."storage_confirm_pickup"("uuid", "text", "jsonb") TO "authenticated";

