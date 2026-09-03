-- Real flow simplification, not just a UI relabel: a pure خارج المخزون
-- outbound order (no real inventory items at all) has nothing to pick up
-- from storage, so "assigned -> picked_up" was a meaningless step the rep
-- had to tap through for no reason. Per explicit user decision:
--   - mark_picked_up is no longer valid for ANY outbound order (Flow 1
--     already required storage_confirm_pickup instead; Flow 2 now skips
--     the step entirely rather than using mark_picked_up either).
--   - start_move now accepts 'assigned' as a valid starting status too,
--     but ONLY for outbound orders with zero real inventory items --
--     Flow 1 (has real inventory) and inbound_rep still require 'picked_up'
--     exactly as before.
-- No signature change on either, so grants/ownership carry over from
-- CREATE OR REPLACE.

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
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب لا يحتاج إلى هذه الخطوة — استخدم بدء التنقل مباشرة');
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
  v_involves_storage BOOLEAN;
BEGIN
  SELECT role INTO v_caller_role FROM profiles WHERE id = auth.uid();
  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Order not found'); END IF;

  SELECT count(*) INTO v_item_count FROM order_items WHERE order_id = target_order_id;
  IF v_item_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب غير صالح لأنه لا يحتوي على عناصر');
  END IF;

  IF v_order.direction = 'inbound_external' THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الإجراء غير متاح لطلبات الشراء الخارجي');
  END IF;

  -- Normally must be 'picked_up'. Exception: a pure خارج المخزون outbound
  -- order (no real inventory items) has nothing to pick up from storage,
  -- so it moves straight from 'assigned' to 'on_the_move'.
  IF v_order.status != 'picked_up' THEN
    IF v_order.status = 'assigned' AND v_order.direction = 'outbound' THEN
      SELECT EXISTS (
        SELECT 1 FROM order_items WHERE order_id = target_order_id AND inventory_id IS NOT NULL
      ) INTO v_involves_storage;
      IF v_involves_storage THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order must be in picked_up status');
      END IF;
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'Order must be in picked_up status');
    END IF;
  END IF;

  IF v_order.rep_id != auth.uid() AND v_caller_role != 'admin' THEN RETURN jsonb_build_object('success', false, 'error', 'Not authorized'); END IF;

  -- v_order.status still holds the pre-update value (assigned or picked_up)
  -- since the row is only UPDATEd below -- pass it straight through so the
  -- urgent-notes check and audit trail reflect whichever stage this order
  -- actually left, instead of assuming 'picked_up'.
  SELECT check_urgent_notes_block(target_order_id, v_order.status) INTO v_block_check;
  IF (v_block_check->>'is_blocked')::boolean = TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'Cannot proceed: There are pending urgent notes awaiting Verifier response', 'pending_count', (v_block_check->>'pending_count')::integer);
  END IF;

  UPDATE orders SET status = 'on_the_move', move_started_at = NOW() WHERE id = target_order_id;
  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes)
  VALUES (target_order_id, 'start_move', v_order.status, 'on_the_move', auth.uid(), p_notes);
  RETURN jsonb_build_object('success', true);
END;
$$;
