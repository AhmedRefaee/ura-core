-- Per-item خارج المخزون purchase checklist. Replaces the never-built
-- whole-order off_stock_purchased_at design (plans/off_stock_purchase_confirmation.md)
-- with per-order_item state: one checkbox per outside-inventory line, not
-- one flag for the whole order. Non-blocking -- never gates mark_picked_up,
-- start_move or mark_delivered. Toggle-able both ways (check/uncheck) any
-- time before the parent order is delivered.

ALTER TABLE public.order_items
  ADD COLUMN purchased_at timestamptz,
  ADD COLUMN purchased_by uuid REFERENCES public.profiles(id);

COMMENT ON COLUMN public.order_items.purchased_at IS
  'When a خارج المخزون (is_custom = true) item was confirmed bought by the rep. '
  'Null = not yet purchased. Toggle-able both ways any time before the parent '
  'order is delivered. Meaningless for is_custom = false rows.';
COMMENT ON COLUMN public.order_items.purchased_by IS
  'Who last set purchased_at -- the order''s rep, or an admin acting on their '
  'behalf. Cleared alongside purchased_at when un-checked.';

CREATE OR REPLACE FUNCTION public.toggle_off_stock_item_purchased(
  target_item_id uuid,
  p_purchased boolean,
  p_notes text DEFAULT NULL
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

  IF v_item.is_custom != true THEN
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
  INSERT INTO audit_log (order_id, action, performed_by, notes, details, server_timestamp)
  VALUES (
    v_item.order_id,
    'toggle_off_stock_item_purchased',
    auth.uid(),
    p_notes,
    jsonb_build_object('item_id', target_item_id, 'purchased', p_purchased)::text,
    NOW()
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

ALTER FUNCTION public.toggle_off_stock_item_purchased(uuid, boolean, text) OWNER TO postgres;

GRANT ALL ON FUNCTION public.toggle_off_stock_item_purchased(uuid, boolean, text) TO anon;
GRANT ALL ON FUNCTION public.toggle_off_stock_item_purchased(uuid, boolean, text) TO authenticated;
GRANT ALL ON FUNCTION public.toggle_off_stock_item_purchased(uuid, boolean, text) TO service_role;
