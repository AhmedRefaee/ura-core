-- Restore proper workflow validation that was lost in earlier migrations.
--
-- Two fixes:
-- 1. mark_picked_up now validates status, rep authorization, and storage involvement.
--    Previously (after 20260517) it blindly updated status regardless of direction,
--    which allowed reps to bypass the storage actor on outbound orders.
--
-- 2. storage_confirm_pickup reverted to its original behavior (without the
--    final_quantity snapshot added in 20260518). The snapshot was only needed
--    for the old live-inventory warning logic. The new warning uses the frozen
--    boolean was_unavailable_at_creation, so the snapshot is unnecessary.

-- ── Fix 1: Restore mark_picked_up validation ────────────────────────────────

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
  v_block_check JSONB;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  IF v_order.status != 'assigned' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order must be in assigned status');
  END IF;

  IF v_order.rep_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;

  -- Outbound orders with inventory items must go through storage_confirm_pickup.
  -- Rep can only mark_picked_up directly for: inbound_rep, or outbound-custom-only.
  IF v_order.direction = 'outbound' THEN
    SELECT EXISTS (
      SELECT 1 FROM order_items
      WHERE order_id = target_order_id
        AND inventory_id IS NOT NULL
    ) INTO v_involves_storage;

    IF v_involves_storage THEN
      RETURN jsonb_build_object('success', false, 'error', 'يجب على أمين المخزن تأكيد الإصدار أولاً');
    END IF;
  END IF;

  -- Urgent notes block check (same pattern as start_move / mark_delivered)
  SELECT check_urgent_notes_block(target_order_id, 'assigned') INTO v_block_check;
  IF (v_block_check->>'is_blocked')::boolean = TRUE THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Cannot proceed: There are pending urgent notes awaiting Verifier response',
      'pending_count', (v_block_check->>'pending_count')::integer
    );
  END IF;

  UPDATE orders
  SET status = 'picked_up',
      picked_up_at = NOW()
  WHERE id = target_order_id;

  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes, server_timestamp)
  VALUES (target_order_id, 'mark_picked_up', 'assigned', 'picked_up', auth.uid(), p_notes, NOW());

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- ── Fix 2: Revert storage_confirm_pickup to pre-snapshot behavior ───────────

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
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN json_build_object('success', false, 'error', 'الطلب غير موجود'); END IF;
  IF v_order.status != 'assigned' THEN RETURN json_build_object('success', false, 'error', 'الطلب ليس في حالة معين'); END IF;
  IF v_order.direction != 'outbound' THEN RETURN json_build_object('success', false, 'error', 'هذا الإجراء مخصص للطلبات الصادرة فقط'); END IF;

  -- Apply explicit quantity reductions from storage actor.
  FOR i IN 0..jsonb_array_length(p_final_quantities) - 1 LOOP
    UPDATE order_items
    SET final_quantity = (p_final_quantities->i->>'quantity')::INT
    WHERE id = (p_final_quantities->i->>'item_id')::UUID
      AND order_id = target_order_id;
  END LOOP;

  -- Deduct inventory using final_quantity if set, otherwise quantity.
  -- (No snapshot — items not explicitly reduced keep final_quantity = NULL.)
  FOR v_item IN
    SELECT * FROM order_items
    WHERE order_id = target_order_id AND inventory_id IS NOT NULL AND is_custom = FALSE
  LOOP
    v_final_qty := COALESCE(v_item.final_quantity, v_item.quantity);
    UPDATE inventory SET quantity = GREATEST(0, quantity - v_final_qty) WHERE id = v_item.inventory_id;
  END LOOP;

  UPDATE orders
  SET status = 'picked_up', storage_actor_id = auth.uid(), picked_up_at = NOW()
  WHERE id = target_order_id;

  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes, server_timestamp)
  VALUES (target_order_id, 'storage_pickup', 'assigned', 'picked_up', auth.uid(), p_notes, NOW());

  RETURN json_build_object('success', true);
END;
$function$;
