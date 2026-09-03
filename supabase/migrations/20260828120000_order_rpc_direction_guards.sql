-- Fix: mark_picked_up, start_move and mark_delivered had no (or an
-- incomplete) direction guard, so a rep could drive an inbound_external or
-- inbound_rep order through the rep-side transitions instead of the storage
-- side, landing it in 'delivered' without storage_confirm_delivery ever
-- running -- which is the only function that credits inventory for inbound
-- orders. Not reachable through the app UI today (it never shows these
-- buttons for those directions/statuses), but nothing at the database layer
-- stopped a direct .rpc() call from doing it.
--
-- Correct shape per direction:
--   outbound          -> mark_picked_up (Flow 2 only) / start_move / mark_delivered, all usable
--   inbound_rep       -> mark_picked_up ("تم الشراء") / start_move usable; delivered only via storage_confirm_delivery
--   inbound_external  -> none of the three rep RPCs are ever legitimate; assigned -> delivered only via storage_confirm_delivery
--
-- No signature change on any of the three, so grants/ownership carry over
-- from CREATE OR REPLACE.

CREATE OR REPLACE FUNCTION "public"."mark_picked_up"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order RECORD;
  v_involves_storage BOOLEAN;
  v_item_count INT;
  v_block_check JSONB;
  v_caller_role user_role;
BEGIN
  SELECT role INTO v_caller_role FROM profiles WHERE id = auth.uid();
  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
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

  IF v_order.rep_id != auth.uid() AND v_caller_role != 'admin' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;

  IF v_order.direction = 'inbound_external' THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الإجراء غير متاح لطلبات الشراء الخارجي');
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
$$;

CREATE OR REPLACE FUNCTION "public"."start_move"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order RECORD;
  v_item_count INT;
  v_block_check JSONB;
  v_caller_role user_role;
BEGIN
  SELECT role INTO v_caller_role FROM profiles WHERE id = auth.uid();
  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Order not found'); END IF;

  SELECT count(*) INTO v_item_count FROM order_items WHERE order_id = target_order_id;
  IF v_item_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب غير صالح لأنه لا يحتوي على عناصر');
  END IF;

  IF v_order.status != 'picked_up' THEN RETURN jsonb_build_object('success', false, 'error', 'Order must be in picked_up status'); END IF;
  IF v_order.rep_id != auth.uid() AND v_caller_role != 'admin' THEN RETURN jsonb_build_object('success', false, 'error', 'Not authorized'); END IF;

  IF v_order.direction = 'inbound_external' THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الإجراء غير متاح لطلبات الشراء الخارجي');
  END IF;

  SELECT check_urgent_notes_block(target_order_id, 'picked_up') INTO v_block_check;
  IF (v_block_check->>'is_blocked')::boolean = TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot proceed: There are pending urgent notes awaiting Verifier response', 'pending_count', (v_block_check->>'pending_count')::integer);
  END IF;

  UPDATE orders SET status = 'on_the_move', move_started_at = NOW() WHERE id = target_order_id;
  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes)
  VALUES (target_order_id, 'start_move', 'picked_up', 'on_the_move', auth.uid(), p_notes);
  RETURN jsonb_build_object('success', true);
END;
$$;

CREATE OR REPLACE FUNCTION "public"."mark_delivered"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order RECORD;
  v_item_count INT;
  v_block_check JSONB;
  v_caller_role user_role;
BEGIN
  SELECT role INTO v_caller_role FROM profiles WHERE id = auth.uid();
  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Order not found'); END IF;

  SELECT count(*) INTO v_item_count FROM order_items WHERE order_id = target_order_id;
  IF v_item_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب غير صالح لأنه لا يحتوي على عناصر');
  END IF;

  IF v_order.status != 'on_the_move' THEN RETURN jsonb_build_object('success', false, 'error', 'Order must be in on_the_move status'); END IF;
  IF v_order.rep_id != auth.uid() AND v_caller_role != 'admin' THEN RETURN jsonb_build_object('success', false, 'error', 'Not authorized'); END IF;

  IF v_order.direction != 'outbound' THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الإجراء مخصص للطلبات الصادرة فقط');
  END IF;

  SELECT check_urgent_notes_block(target_order_id, 'on_the_move') INTO v_block_check;
  IF (v_block_check->>'is_blocked')::boolean = TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot proceed: There are pending urgent notes awaiting Verifier response', 'pending_count', (v_block_check->>'pending_count')::integer);
  END IF;

  UPDATE orders SET status = 'delivered', delivered_at = NOW() WHERE id = target_order_id;
  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes)
  VALUES (target_order_id, 'mark_delivered', 'on_the_move', 'delivered', auth.uid(), p_notes);
  RETURN jsonb_build_object('success', true);
END;
$$;
