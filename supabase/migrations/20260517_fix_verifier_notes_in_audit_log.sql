-- Log order creation so verifier notes appear in the timeline "Created" step.
-- Also stop overwriting orders.notes with rep step notes (step notes live in audit_log).

CREATE OR REPLACE FUNCTION public.log_order_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO audit_log (order_id, action, performed_by, notes, server_timestamp)
  VALUES (NEW.id, 'order_created', NEW.created_by, NEW.notes, NOW());
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS orders_log_creation ON public.orders;
CREATE TRIGGER orders_log_creation
AFTER INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION log_order_created();

CREATE OR REPLACE FUNCTION public.start_move(target_order_id uuid, p_notes text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_order RECORD; v_block_check JSONB;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Order not found'); END IF;
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

CREATE OR REPLACE FUNCTION public.mark_delivered(target_order_id uuid, p_notes text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
DECLARE v_order RECORD; v_block_check JSONB;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Order not found'); END IF;
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

CREATE OR REPLACE FUNCTION public.mark_picked_up(target_order_id uuid, p_notes text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $function$
BEGIN
  UPDATE orders SET status = 'picked_up', picked_up_at = now() WHERE id = target_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Order not found'); END IF;
  IF p_notes IS NOT NULL AND p_notes != '' THEN
    UPDATE audit_log SET notes = p_notes
    WHERE order_id = target_order_id AND action = 'status_change' AND new_status = 'picked_up' AND notes IS NULL;
  END IF;
  RETURN jsonb_build_object('success', true);
END;
$function$;
