-- storage_confirm_pickup validated each ✓ line inside the loop that writes.
-- A RETURN of {success:false} still commits whatever ran before it, so with
-- line 1 partly available and line 2 over the requested quantity, line 1's
-- stock was deducted and its shortfall ✗ line inserted, the call "failed",
-- and the retry deducted and split line 1 a second time.
--
-- Now every line is checked (and the final quantities written) before
-- anything else is: one pass that only reads, then the pass that writes.
-- Behaviour on success is unchanged.

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
    IF v_final_qty > v_item.quantity THEN
      RETURN json_build_object('success', false, 'error', 'لا يمكن أن تزيد الكمية عن المطلوبة');
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
