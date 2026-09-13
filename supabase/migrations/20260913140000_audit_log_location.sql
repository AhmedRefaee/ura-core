-- Rep location capture on order actions: store rep's GPS coordinates
-- when mark_picked_up, start_move, mark_delivered, or toggle_off_stock_item_purchased
-- are performed, so verifier can later see where the rep was for each action.
-- Non-blocking: if location can't be obtained (permission denied, GPS off, timeout),
-- the action still succeeds with null coordinates.

-- Add location columns to audit_log. Nullable — other action types
-- (order_created, chat/urgent notes) never populate these.
ALTER TABLE public.audit_log
  ADD COLUMN location_lat float8,
  ADD COLUMN location_lng float8;

-- CRITICAL: Adding parameters to an RPC creates a new function overload in
-- Postgres if you don't DROP the old signature first. Postgres keys functions
-- by name + argument type list, so CREATE OR REPLACE without DROP leaves the
-- old version live, and both overloads coexist. This repo learned this the hard
-- way twice (inventory RPCs in Sept, then this feature). Do not skip these drops.

-- mark_picked_up: add optional p_location_lat, p_location_lng params
DROP FUNCTION IF EXISTS public.mark_picked_up(uuid, text);
CREATE OR REPLACE FUNCTION "public"."mark_picked_up"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_location_lat" float8 DEFAULT NULL, "p_location_lng" float8 DEFAULT NULL) RETURNS "jsonb"
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

  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes, location_lat, location_lng, server_timestamp)
  VALUES (target_order_id, 'mark_picked_up', 'assigned', 'picked_up', auth.uid(), p_notes, p_location_lat, p_location_lng, NOW());

  RETURN jsonb_build_object('success', true);
END;
$$;

-- start_move: add optional p_location_lat, p_location_lng params
DROP FUNCTION IF EXISTS public.start_move(uuid, text);
CREATE OR REPLACE FUNCTION "public"."start_move"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_location_lat" float8 DEFAULT NULL, "p_location_lng" float8 DEFAULT NULL) RETURNS "jsonb"
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
  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes, location_lat, location_lng)
  VALUES (target_order_id, 'start_move', v_order.status, 'on_the_move', auth.uid(), p_notes, p_location_lat, p_location_lng);
  RETURN jsonb_build_object('success', true);
END;
$$;

-- mark_delivered: add optional p_location_lat, p_location_lng params
DROP FUNCTION IF EXISTS public.mark_delivered(uuid, text);
CREATE OR REPLACE FUNCTION "public"."mark_delivered"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_location_lat" float8 DEFAULT NULL, "p_location_lng" float8 DEFAULT NULL) RETURNS "jsonb"
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
  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, notes, location_lat, location_lng)
  VALUES (target_order_id, 'mark_delivered', 'on_the_move', 'delivered', auth.uid(), p_notes, p_location_lat, p_location_lng);
  RETURN jsonb_build_object('success', true);
END;
$$;

-- toggle_off_stock_item_purchased: add optional p_location_lat, p_location_lng params
DROP FUNCTION IF EXISTS public.toggle_off_stock_item_purchased(uuid, boolean, text);
CREATE OR REPLACE FUNCTION public.toggle_off_stock_item_purchased(
  target_item_id uuid,
  p_purchased boolean,
  p_notes text DEFAULT NULL,
  p_location_lat float8 DEFAULT NULL,
  p_location_lng float8 DEFAULT NULL
) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
DECLARE
  v_item RECORD;
  v_order RECORD;
  v_caller_role user_role;
BEGIN
  SELECT role INTO v_caller_role FROM profiles WHERE id = auth.uid();

  SELECT oi.* INTO v_item FROM order_items oi WHERE oi.id = target_item_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'العنصر غير موجود');
  END IF;

  -- The two kinds of "the rep buys this". The outbound half of the rule is
  -- enforced by the direction check below, which is why it is not repeated
  -- here: was_unavailable_at_creation only carries this meaning outbound.
  IF v_item.is_custom != true
     AND v_item.was_unavailable_at_creation != true THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا العنصر ليس خارج المخزون');
  END IF;

  SELECT * INTO v_order FROM orders WHERE id = v_item.order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  IF v_order.direction != 'outbound' THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الإجراء متاح فقط لطلبات التوريد');
  END IF;

  IF v_order.rep_id != auth.uid() AND v_caller_role != 'admin' THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF v_order.status = 'delivered' THEN
    RETURN jsonb_build_object('success', false, 'error', 'تم تسليم الطلب بالفعل');
  END IF;

  UPDATE order_items
  SET purchased_at = CASE WHEN p_purchased THEN NOW() ELSE NULL END,
      purchased_by = CASE WHEN p_purchased THEN auth.uid() ELSE NULL END
  WHERE id = target_item_id;

  -- Deliberately no old_status/new_status: this event does not change order.status.
  INSERT INTO audit_log (order_id, action, performed_by, notes, details, location_lat, location_lng, server_timestamp)
  VALUES (
    v_item.order_id,
    'toggle_off_stock_item_purchased',
    auth.uid(),
    p_notes,
    jsonb_build_object('item_id', target_item_id, 'purchased', p_purchased)::text,
    p_location_lat,
    p_location_lng,
    NOW()
  );

  RETURN jsonb_build_object('success', true);
END;
$$;
