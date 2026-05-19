-- ============================================================================
-- ATOMIC ORDER CREATION + 0-ITEM GUARDS
--
-- Problem 1: createOrder client code did INSERT order, then INSERT items as two
-- separate calls. If item insert failed (e.g., schema cache miss), the order
-- row was orphaned with 0 items — unrecoverable broken state.
--
-- Problem 2: Status-change RPCs (mark_picked_up, start_move, mark_delivered,
-- storage_confirm_pickup, storage_confirm_delivery) did not check that the
-- order had any items. A broken 0-item order could still be "processed".
--
-- Fix:
--   1. New RPC create_order_with_items: validates items not empty, inserts
--      order + items + sets was_unavailable_at_creation in a single
--      transaction. Either everything commits or nothing does.
--   2. Add 0-item rejection at the top of every status-change RPC.
-- ============================================================================

-- ── ATOMIC ORDER CREATION ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.create_order_with_items(
  p_direction TEXT,
  p_entity_id UUID,
  p_rep_id UUID DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_items JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order_id UUID;
  v_item JSONB;
  v_inv_id UUID;
  v_current_qty INT;
  v_was_unavailable BOOLEAN;
BEGIN
  -- Authentication check: must be an approved user.
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_approved = TRUE) THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  -- Reject empty orders. No exceptions.
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'يجب إضافة عنصر واحد على الأقل للطلب');
  END IF;

  -- Validate direction.
  IF p_direction NOT IN ('outbound', 'inbound_rep', 'inbound_external') THEN
    RETURN jsonb_build_object('success', false, 'error', 'اتجاه الطلب غير صالح');
  END IF;

  -- Insert order.
  INSERT INTO orders (direction, entity_id, rep_id, status, notes, created_by, assigned_at)
  VALUES (
    p_direction::order_direction,
    p_entity_id,
    p_rep_id,
    'assigned'::order_status,
    NULLIF(p_notes, ''),
    auth.uid(),
    NOW()
  )
  RETURNING id INTO v_order_id;

  -- Insert each item with was_unavailable_at_creation flag set from current inventory.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_inv_id := NULLIF(v_item->>'inventory_id', '')::UUID;
    v_was_unavailable := FALSE;

    IF v_inv_id IS NOT NULL THEN
      SELECT quantity INTO v_current_qty FROM inventory WHERE id = v_inv_id;
      v_was_unavailable := COALESCE(v_current_qty, 0) = 0;
    END IF;

    INSERT INTO order_items (
      order_id,
      inventory_id,
      quantity,
      is_custom,
      custom_description,
      source_inventory_id,
      was_unavailable_at_creation
    ) VALUES (
      v_order_id,
      v_inv_id,
      (v_item->>'quantity')::INT,
      COALESCE((v_item->>'is_custom')::BOOLEAN, FALSE),
      v_item->>'custom_description',
      NULLIF(v_item->>'source_inventory_id', '')::UUID,
      v_was_unavailable
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'order_id', v_order_id);
END;
$function$;

-- ── 0-ITEM GUARDS ON STATUS-CHANGE RPCS ─────────────────────────────────────

-- mark_picked_up: reject if order has no items
CREATE OR REPLACE FUNCTION public.mark_picked_up(
  target_order_id uuid,
  p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order RECORD;
  v_involves_storage BOOLEAN;
  v_item_count INT;
  v_block_check JSONB;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  SELECT count(*) INTO v_item_count FROM order_items WHERE order_id = target_order_id;
  IF v_item_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب غير صالح لأنه لا يحتوي على عناصر');
  END IF;

  IF v_order.status != 'assigned' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order must be in assigned status');
  END IF;

  IF v_order.rep_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;

  IF v_order.direction = 'outbound' THEN
    SELECT EXISTS (
      SELECT 1 FROM order_items WHERE order_id = target_order_id AND inventory_id IS NOT NULL
    ) INTO v_involves_storage;
    IF v_involves_storage THEN
      RETURN jsonb_build_object('success', false, 'error', 'يجب على أمين المخزن تأكيد الإصدار أولاً');
    END IF;
  END IF;

  SELECT check_urgent_notes_block(target_order_id, 'assigned') INTO v_block_check;
  IF (v_block_check->>'is_blocked')::boolean = TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Cannot proceed: There are pending urgent notes awaiting Verifier response',
      'pending_count', (v_block_check->>'pending_count')::integer
    );
  END IF;

  UPDATE orders SET status = 'picked_up', picked_up_at = NOW() WHERE id = target_order_id;

  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes, server_timestamp)
  VALUES (target_order_id, 'mark_picked_up', 'assigned', 'picked_up', auth.uid(), p_notes, NOW());

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- start_move: reject if order has no items
CREATE OR REPLACE FUNCTION public.start_move(
  target_order_id uuid,
  p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order RECORD;
  v_item_count INT;
  v_block_check JSONB;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Order not found'); END IF;

  SELECT count(*) INTO v_item_count FROM order_items WHERE order_id = target_order_id;
  IF v_item_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب غير صالح لأنه لا يحتوي على عناصر');
  END IF;

  IF v_order.status != 'picked_up' THEN RETURN jsonb_build_object('success', false, 'error', 'Order must be in picked_up status'); END IF;
  IF v_order.rep_id != auth.uid() THEN RETURN jsonb_build_object('success', false, 'error', 'Not authorized'); END IF;

  SELECT check_urgent_notes_block(target_order_id, 'picked_up') INTO v_block_check;
  IF (v_block_check->>'is_blocked')::boolean = TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot proceed: There are pending urgent notes awaiting Verifier response', 'pending_count', (v_block_check->>'pending_count')::integer);
  END IF;

  UPDATE orders SET status = 'on_the_move', move_started_at = NOW() WHERE id = target_order_id;
  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes)
  VALUES (target_order_id, 'start_move', 'picked_up', 'on_the_move', auth.uid(), p_notes);
  RETURN jsonb_build_object('success', true);
END;
$function$;

-- mark_delivered: reject if order has no items
CREATE OR REPLACE FUNCTION public.mark_delivered(
  target_order_id uuid,
  p_notes text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order RECORD;
  v_item_count INT;
  v_block_check JSONB;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Order not found'); END IF;

  SELECT count(*) INTO v_item_count FROM order_items WHERE order_id = target_order_id;
  IF v_item_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب غير صالح لأنه لا يحتوي على عناصر');
  END IF;

  IF v_order.status != 'on_the_move' THEN RETURN jsonb_build_object('success', false, 'error', 'Order must be in on_the_move status'); END IF;
  IF v_order.rep_id != auth.uid() THEN RETURN jsonb_build_object('success', false, 'error', 'Not authorized'); END IF;

  SELECT check_urgent_notes_block(target_order_id, 'on_the_move') INTO v_block_check;
  IF (v_block_check->>'is_blocked')::boolean = TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot proceed: There are pending urgent notes awaiting Verifier response', 'pending_count', (v_block_check->>'pending_count')::integer);
  END IF;

  UPDATE orders SET status = 'delivered', delivered_at = NOW() WHERE id = target_order_id;
  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes)
  VALUES (target_order_id, 'mark_delivered', 'on_the_move', 'delivered', auth.uid(), p_notes);
  RETURN jsonb_build_object('success', true);
END;
$function$;

-- storage_confirm_pickup: reject if order has no items
CREATE OR REPLACE FUNCTION public.storage_confirm_pickup(
  target_order_id UUID,
  p_notes TEXT DEFAULT NULL,
  p_final_quantities JSONB DEFAULT '[]'::jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order orders%ROWTYPE;
  v_item  order_items%ROWTYPE;
  v_final_qty INT;
  v_item_count INT;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN json_build_object('success', false, 'error', 'الطلب غير موجود'); END IF;

  SELECT count(*) INTO v_item_count FROM order_items WHERE order_id = target_order_id;
  IF v_item_count = 0 THEN
    RETURN json_build_object('success', false, 'error', 'هذا الطلب غير صالح لأنه لا يحتوي على عناصر');
  END IF;

  IF v_order.status != 'assigned' THEN RETURN json_build_object('success', false, 'error', 'الطلب ليس في حالة معين'); END IF;
  IF v_order.direction != 'outbound' THEN RETURN json_build_object('success', false, 'error', 'هذا الإجراء مخصص للطلبات الصادرة فقط'); END IF;

  FOR i IN 0..jsonb_array_length(p_final_quantities) - 1 LOOP
    UPDATE order_items
    SET final_quantity = (p_final_quantities->i->>'quantity')::INT
    WHERE id = (p_final_quantities->i->>'item_id')::UUID
      AND order_id = target_order_id;
  END LOOP;

  FOR v_item IN
    SELECT * FROM order_items
    WHERE order_id = target_order_id AND inventory_id IS NOT NULL AND is_custom = FALSE
  LOOP
    v_final_qty := COALESCE(v_item.final_quantity, v_item.quantity);
    UPDATE inventory SET quantity = GREATEST(0, quantity - v_final_qty) WHERE id = v_item.inventory_id;
  END LOOP;

  UPDATE orders SET status = 'picked_up', storage_actor_id = auth.uid(), picked_up_at = NOW() WHERE id = target_order_id;

  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes, server_timestamp)
  VALUES (target_order_id, 'storage_pickup', 'assigned', 'picked_up', auth.uid(), p_notes, NOW());

  RETURN json_build_object('success', true);
END;
$function$;

-- storage_confirm_delivery: reject if order has no items
CREATE OR REPLACE FUNCTION public.storage_confirm_delivery(
  target_order_id uuid,
  p_notes text DEFAULT NULL::text,
  p_final_quantities jsonb DEFAULT '[]'::jsonb
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_order orders%ROWTYPE;
  v_item  order_items%ROWTYPE;
  v_final_qty INT;
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
    SET final_quantity = (p_final_quantities->i->>'quantity')::INT
    WHERE id = (p_final_quantities->i->>'item_id')::UUID
      AND order_id = target_order_id;
  END LOOP;

  FOR v_item IN
    SELECT * FROM order_items
    WHERE order_id = target_order_id AND inventory_id IS NOT NULL AND is_custom = FALSE
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
$function$;

NOTIFY pgrst, 'reload schema';
