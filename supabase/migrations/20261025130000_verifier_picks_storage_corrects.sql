-- The verifier can pick outbound lines from the catalog again; storage can
-- correct any line before it confirms pickup.
--
-- An outbound order now mixes two kinds of line:
--   * typed / pasted   -> arrives pending, storage decides (unchanged)
--   * picked by name   -> the verifier decided: arrives ✓ "from storage".
--     Storage still sees it and may flip it to ✗, change the quantity (less
--     OR more than asked), or swap it to another catalog row -- the app's
--     stock counts are not always what is on the shelf.
--
-- Storage may also correct a row's stock count from the order; that goes
-- through inventory_bulk_update_quantities, which gains the NULL-uid and
-- organization checks it never had.

-- ── 1. A picked line arrives ✓ ──────────────────────────────────────────────

-- A trigger rather than edits to create_order_with_items and edit_order_items:
-- every way a catalog line lands on an undecided outbound order (create, edit,
-- template) is the verifier choosing that row, and all of them get the same rule.
CREATE OR REPLACE FUNCTION public._preconfirm_picked_outbound_line()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.inventory_id IS NOT NULL
     AND NOT NEW.is_custom
     AND NEW.custom_description IS NULL
     AND NEW.source_inventory_id IS NULL
     AND NEW.check_status = 'pending'
     AND EXISTS (
       SELECT 1 FROM orders o
       WHERE o.id = NEW.order_id
         AND o.direction = 'outbound'
         AND o.status = 'assigned'
         AND o.storage_reviewed_at IS NULL
     )
  THEN
    NEW.check_status := 'checked';
    NEW.checked_by := auth.uid();
    NEW.checked_at := NOW();
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._preconfirm_picked_outbound_line() FROM anon, authenticated, PUBLIC;

DROP TRIGGER IF EXISTS preconfirm_picked_outbound_line ON public.order_items;
CREATE TRIGGER preconfirm_picked_outbound_line
  BEFORE INSERT ON public.order_items
  FOR EACH ROW EXECUTE FUNCTION public._preconfirm_picked_outbound_line();

-- ── 2. Storage may swap a picked line too ──────────────────────────────────

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
  -- A line the verifier typed (linked or not) or picked from the catalog.
  -- Not a split-off shortfall, which points at its source row.
  IF v_item.source_inventory_id IS NOT NULL
     OR (v_item.custom_description IS NULL AND v_item.inventory_id IS NULL) THEN
    RAISE EXCEPTION 'لا يمكن تعديل هذا الصنف';
  END IF;
  RETURN v_item;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._storage_review_item(uuid) FROM anon, authenticated, PUBLIC;

-- Unchanged but for one rule: a picked line has no typed text to go back to,
-- so it cannot be unlinked -- storage marks it ✗ instead.
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
    IF v_item.custom_description IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'استخدم غير متوفر بدلاً من ذلك');
    END IF;
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

-- ── 3. storage_confirm_pickup: storage may send more than was asked ────────

-- As in 20261025120000, without the "no more than requested" check. Stock
-- drops by what actually left the shelf.
CREATE OR REPLACE FUNCTION "public"."storage_confirm_pickup"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_final_quantities" "jsonb" DEFAULT '[]'::"jsonb") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order orders%ROWTYPE;
  v_item  order_items%ROWTYPE;
  v_inv   inventory%ROWTYPE;
  v_role  user_role;
  v_final_qty NUMERIC;
  v_override NUMERIC;
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

  -- Pass 1, reads only: every ✓ line's quantity, as it will be after this
  -- call's final quantities, must be valid before anything is written.
  FOR v_item IN
    SELECT * FROM order_items
    WHERE order_id = target_order_id AND check_status = 'checked'
  LOOP
    SELECT (e->>'quantity')::NUMERIC INTO v_override
    FROM jsonb_array_elements(p_final_quantities) e
    WHERE (e->>'item_id')::UUID = v_item.id
    LIMIT 1;
    v_final_qty := COALESCE(v_override, v_item.final_quantity, v_item.quantity);
    IF v_final_qty <= 0 THEN
      RETURN json_build_object('success', false, 'error', 'كمية صنف متوفر يجب أن تكون أكبر من صفر — استخدم غير متوفر بدلاً من ذلك');
    END IF;
  END LOOP;

  -- Pass 2, writes.
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

-- ── 4. inventory_bulk_update_quantities: org + NULL-uid checks ──────────────

-- Storage now corrects counts from inside an order as well as from the
-- inventory screen. Same behaviour, plus: fail closed with no user, only the
-- caller's organization's rows, no negative counts. RAISE (not RETURN) keeps
-- a bad row anywhere in the batch from committing the rows before it.
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
  IF auth.uid() IS NULL OR v_role IS NULL OR v_role NOT IN ('storage_actor', 'admin') THEN
    RAISE EXCEPTION 'الكمية يحددها أمين المخزن فقط';
  END IF;

  FOR v_update IN SELECT * FROM jsonb_array_elements(p_updates)
  LOOP
    v_item_id      := (v_update->>'item_id')::UUID;
    v_new_quantity := (v_update->>'quantity')::NUMERIC;

    IF v_new_quantity IS NULL OR v_new_quantity < 0 THEN
      RAISE EXCEPTION 'الكمية لا يمكن أن تكون سالبة';
    END IF;

    SELECT quantity INTO v_old_quantity FROM inventory
    WHERE id = v_item_id AND organization_id = auth_org_id();
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
