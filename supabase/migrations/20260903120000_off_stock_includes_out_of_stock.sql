-- Purple means one thing: the rep has to source this himself.
--
-- Until now the app painted only is_custom items purple -- things the business
-- does not carry at all. An item that IS in the catalogue but had a zero
-- balance when the order was written is the same errand for the rep, and was
-- shown instead as a passive orange "غير متوفر" warning with no checkbox
-- behind it. So the colour the rep had been taught to read as "go and buy
-- this" covered only half the things he had to buy.
--
-- The UI now treats both as خارج المخزون, told apart by a small badge
-- (جديد / غير متوفر) rather than by colour. This migration is the server half:
-- the purchase checklist has to accept the second kind too, or the rep would
-- see a checkbox he is not allowed to tick.
--
-- No signature change, so grants and ownership carry over from
-- CREATE OR REPLACE. Nothing else moves: the skip-pickup rule keys on
-- inventory_id IS NOT NULL, not on is_custom, so an out-of-stock row is still
-- an inventory row that routes through storage exactly as before. And
-- storage_confirm_pickup already deducts GREATEST(0, 0 - n) = 0 for it, so
-- ticking it as purchased cannot double-count anything.

COMMENT ON COLUMN public.order_items.purchased_at IS
  'When a خارج المخزون item was confirmed bought by the rep -- either an '
  'is_custom item, or an inventory item that had a zero balance when the '
  'order was created (was_unavailable_at_creation). Null = not yet purchased. '
  'Toggle-able both ways any time before the parent order is delivered. '
  'Meaningless for an in-stock inventory row, which the storage actor hands '
  'over instead.';

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
