-- Fix: on an inboundExternal delivery, marking an item "rejected" (check_status)
-- had no server-side effect. storage_confirm_delivery credited the full
-- inventory quantity for every non-custom item regardless of check_status --
-- rejecting an item only stopped the credit if the storage actor also
-- remembered to manually zero that item's final_quantity. Now a rejected
-- item is excluded from the inventory credit outright.
--
-- No signature change, so grants/ownership carry over from CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION "public"."storage_confirm_delivery"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_final_quantities" "jsonb" DEFAULT '[]'::"jsonb") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order orders%ROWTYPE;
  v_item  order_items%ROWTYPE;
  v_final_qty NUMERIC;
  v_item_count INT;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN json_build_object('success', false, 'error', 'الطلب غير موجود'); END IF;

  SELECT count(*) INTO v_item_count FROM order_items WHERE order_id = target_order_id;
  IF v_item_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'هذا الطلب غير صالح لأنه لا يحتوي على عناصر');
  END IF;

  IF v_order.direction NOT IN ('inbound_rep', 'inbound_external') THEN
    RETURN json_build_object('success', false, 'error', 'هذا الإجراء للطلبات الواردة فقط');
  END IF;
  IF v_order.direction = 'inbound_rep' AND v_order.status != 'on_the_move' THEN
    RETURN json_build_object('success', false, 'error', 'انتظر حتى يبدأ المندوب التنقل');
  END IF;
  IF v_order.direction = 'inbound_external' AND v_order.status != 'assigned' THEN
    RETURN json_build_object('success', false, 'error', 'الطلب ليس في الحالة الصحيحة');
  END IF;

  FOR i IN 0..jsonb_array_length(p_final_quantities) - 1 LOOP
    UPDATE order_items
    SET final_quantity = (p_final_quantities->i->>'quantity')::NUMERIC
    WHERE id = (p_final_quantities->i->>'item_id')::UUID
      AND order_id = target_order_id;
  END LOOP;

  FOR v_item IN
    SELECT * FROM order_items
    WHERE order_id = target_order_id
      AND inventory_id IS NOT NULL
      AND is_custom = FALSE
      AND check_status != 'rejected'
  LOOP
    v_final_qty := COALESCE(v_item.final_quantity, v_item.quantity);
    UPDATE inventory SET quantity = quantity + v_final_qty WHERE id = v_item.inventory_id;
  END LOOP;

  UPDATE orders SET status = 'delivered', storage_actor_id = auth.uid(), delivered_at = NOW() WHERE id = target_order_id;

  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes, server_timestamp)
  VALUES (
    target_order_id, 'storage_delivery',
    CASE v_order.direction WHEN 'inbound_rep' THEN 'on_the_move'::order_status ELSE 'assigned'::order_status END,
    'delivered', auth.uid(), p_notes, NOW()
  );

  RETURN json_build_object('success', true);
END;
$$;
