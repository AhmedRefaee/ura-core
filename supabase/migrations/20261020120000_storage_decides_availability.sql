-- Storage, not the verifier, decides what is in stock on an outbound order.
--
-- Before: the verifier saw stock while writing the order; create_order_with_items
-- froze `was_unavailable_at_creation` from it, and a 100%-purple order skipped
-- storage entirely (Flow 2).
--
-- Now: the verifier feeds in the order blind. Every outbound order goes to
-- storage, which marks each row ✓ (have it, ready to pick up) or ✗ (don't
-- have it, the rep buys it), lowering the quantity on a ✓ row when it only
-- has part of it -- the shortfall becomes a new ✗ row for the rep.
-- storage_confirm_pickup then either sends the order on (any ✓ row ->
-- picked_up, existing Flow 1 path) or leaves it 'assigned' with the review
-- stamped so the rep can start the trip directly (all ✗ -> old Flow 2 path).
--
-- `orders.storage_reviewed_at` is the single "storage has decided" fact.
-- Functions are replaced with their exact current signatures, so grants carry
-- over; anon is revoked on the ones that would otherwise let a NULL auth.uid()
-- slip through a `!=` comparison.

-- ── 1. Column + backfill ─────────────────────────────────────────────────────

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS storage_reviewed_at timestamptz;

COMMENT ON COLUMN public.orders.storage_reviewed_at IS
  'When storage finished marking every outbound item available (checked) or not (rejected). NULL = storage has not decided yet.';

-- Orders already past 'assigned' were decided under the old rules: what the
-- verifier saw as unavailable is exactly what the rep had to buy.
UPDATE public.order_items oi
SET check_status = CASE
      WHEN oi.is_custom OR oi.was_unavailable_at_creation THEN 'rejected'::item_check_status
      ELSE 'checked'::item_check_status
    END
FROM public.orders o
WHERE o.id = oi.order_id
  AND o.direction = 'outbound'
  AND o.status <> 'assigned'
  AND oi.check_status = 'pending';

UPDATE public.orders
SET storage_reviewed_at = COALESCE(picked_up_at, move_started_at, assigned_at, created_at)
WHERE direction = 'outbound'
  AND status <> 'assigned'
  AND storage_reviewed_at IS NULL;

-- ── 2. check_order_item: storage marks ✓ / ✗ / back to pending ───────────────

CREATE OR REPLACE FUNCTION "public"."check_order_item"("target_item_id" "uuid", "new_status" "public"."item_check_status") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_user_role user_role;
    v_item RECORD;
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
    END IF;

    SELECT role INTO v_user_role FROM profiles WHERE id = auth.uid();
    IF v_user_role IS NULL OR v_user_role NOT IN ('storage_actor', 'admin') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only storage actors can check items');
    END IF;

    SELECT oi.*, o.status AS order_status, o.direction AS order_direction,
           o.storage_reviewed_at AS order_reviewed_at
    INTO v_item
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE oi.id = target_item_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Item not found');
    END IF;

    IF v_item.order_direction = 'inbound_rep' THEN
        RETURN jsonb_build_object('success', false, 'error', 'هذا الإجراء غير متاح لهذا النوع من الطلبات');
    END IF;

    -- Can only check items on orders that are still in 'assigned' status,
    -- and (outbound) before storage has confirmed its review.
    IF v_item.order_status != 'assigned' OR v_item.order_reviewed_at IS NOT NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order has already been approved');
    END IF;

    UPDATE order_items
    SET check_status = new_status,
        checked_by = CASE WHEN new_status = 'pending' THEN NULL ELSE auth.uid() END,
        checked_at = CASE WHEN new_status = 'pending' THEN NULL ELSE NOW() END
    WHERE id = target_item_id;

    RETURN jsonb_build_object('success', true, 'message', 'Item marked as ' || new_status::text);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."check_order_item"("uuid", "public"."item_check_status") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."check_order_item"("uuid", "public"."item_check_status") TO "authenticated";

-- ── 3. storage_confirm_pickup: the review is final ───────────────────────────

CREATE OR REPLACE FUNCTION "public"."storage_confirm_pickup"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_final_quantities" "jsonb" DEFAULT '[]'::"jsonb") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order orders%ROWTYPE;
  v_item  order_items%ROWTYPE;
  v_inv   inventory%ROWTYPE;
  v_role  user_role;
  v_final_qty NUMERIC;
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
    IF v_final_qty <= 0 THEN
      RETURN json_build_object('success', false, 'error', 'كمية صنف متوفر يجب أن تكون أكبر من صفر — استخدم غير متوفر بدلاً من ذلك');
    END IF;
    IF v_final_qty > v_item.quantity THEN
      RETURN json_build_object('success', false, 'error', 'لا يمكن أن تزيد الكمية عن المطلوبة');
    END IF;
    v_sent_count := v_sent_count + 1;

    -- Real inventory rows leave the shelf; a ✓ on a new (custom) item just
    -- means storage hands it over, so there is nothing to deduct.
    IF v_item.inventory_id IS NOT NULL AND v_item.is_custom = FALSE THEN
      UPDATE inventory SET quantity = GREATEST(0, quantity - v_final_qty) WHERE id = v_item.inventory_id;

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

-- ── 4. start_move: a reviewed order with nothing sent may start from 'assigned'

CREATE OR REPLACE FUNCTION "public"."start_move"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_location_lat" float8 DEFAULT NULL, "p_location_lng" float8 DEFAULT NULL) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order RECORD;
  v_item_count INT;
  v_block_check JSONB;
  v_caller_role user_role;
BEGIN
  IF auth.uid() IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'Not authorized'); END IF;
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

  -- Normally must be 'picked_up'. Exception: an outbound order storage has
  -- reviewed and found nothing to send (every row ✗) -- the rep buys it all,
  -- so it moves straight from 'assigned' to 'on_the_move'.
  IF v_order.status != 'picked_up' THEN
    IF v_order.status = 'assigned' AND v_order.direction = 'outbound' THEN
      IF v_order.storage_reviewed_at IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'بانتظار مراجعة المخزن');
      END IF;
      IF EXISTS (SELECT 1 FROM order_items WHERE order_id = target_order_id AND check_status = 'checked') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order must be in picked_up status');
      END IF;
    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'Order must be in picked_up status');
    END IF;
  END IF;

  IF v_order.rep_id != auth.uid() AND v_caller_role != 'admin' THEN RETURN jsonb_build_object('success', false, 'error', 'Not authorized'); END IF;

  -- v_order.status still holds the pre-update value (assigned or picked_up).
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

REVOKE EXECUTE ON FUNCTION "public"."start_move"("uuid", "text", float8, float8) FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."start_move"("uuid", "text", float8, float8) TO "authenticated";

-- ── 5. toggle_off_stock_item_purchased: ✗ rows are what the rep buys ─────────

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
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;
  SELECT role INTO v_caller_role FROM profiles WHERE id = auth.uid();

  SELECT oi.* INTO v_item FROM order_items oi WHERE oi.id = target_item_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'العنصر غير موجود');
  END IF;

  SELECT * INTO v_order FROM orders WHERE id = v_item.order_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  IF v_order.direction != 'outbound' THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الإجراء متاح فقط لطلبات التوريد');
  END IF;

  -- On an outbound order the rep buys whatever storage marked unavailable
  -- (✗) -- including new items and the shortfall rows storage split off.
  IF v_item.check_status != 'rejected' THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا العنصر ليس خارج المخزون');
  END IF;

  IF v_order.storage_reviewed_at IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'بانتظار مراجعة المخزن');
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

REVOKE EXECUTE ON FUNCTION public.toggle_off_stock_item_purchased(uuid, boolean, text, float8, float8) FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.toggle_off_stock_item_purchased(uuid, boolean, text, float8, float8) TO authenticated;

-- ── 6. notify_order_status_change: the all-✗ trip starts from 'assigned' ─────

CREATE OR REPLACE FUNCTION "public"."notify_order_status_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  storage_ids uuid[];
  recipients  uuid[];
  ar_title    text;
  ar_body     text;
begin
  if OLD.status = NEW.status then return NEW; end if;

  select array_agg(id) into storage_ids
    from public.profiles
   where role = 'storage_actor' and is_approved = true;

  if OLD.status = 'assigned' and NEW.status = 'picked_up' then
    -- Storage actor approved → notify verifier + rep
    recipients := array_remove(array[NEW.created_by, NEW.rep_id], null);
    ar_title   := 'تم استلام البضاعة من المخزن';
    ar_body    := 'وافق مسؤول المخزن على الاستلام';

  elsif OLD.status in ('assigned', 'picked_up') and NEW.status = 'on_the_move' then
    -- Rep started move → notify verifier + storage actors
    recipients := array_remove(
      array_cat(coalesce(storage_ids, '{}'), array[NEW.created_by]),
      null
    );
    ar_title := 'الطلب في الطريق';
    ar_body  := 'بدأ المندوب رحلة التوصيل';

  elsif OLD.status = 'on_the_move' and NEW.status = 'delivered' then
    -- Rep delivered → notify verifier + storage actors
    recipients := array_remove(
      array_cat(coalesce(storage_ids, '{}'), array[NEW.created_by]),
      null
    );
    ar_title := 'تم تسليم الطلب';
    ar_body  := 'تم توصيل الطلب بنجاح';

  else
    return NEW;
  end if;

  perform public.dispatch_push(
    recipients,
    ar_title,
    ar_body,
    jsonb_build_object('route', '/orders/' || NEW.id, 'order_id', NEW.id::text)
  );
  return NEW;
end;
$$;

-- ── 7. create_order_with_items: the verifier no longer knows about stock ─────

CREATE OR REPLACE FUNCTION "public"."create_order_with_items"("p_direction" "text", "p_entity_id" "uuid", "p_rep_id" "uuid" DEFAULT NULL::"uuid", "p_notes" "text" DEFAULT NULL::"text", "p_items" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order_id UUID;
  v_item JSONB;
  v_code TEXT;
  v_attempt INT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_approved = TRUE) THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'يجب إضافة عنصر واحد على الأقل للطلب');
  END IF;

  IF p_direction NOT IN ('outbound', 'inbound_rep', 'inbound_external') THEN
    RETURN jsonb_build_object('success', false, 'error', 'اتجاه الطلب غير صالح');
  END IF;

  v_attempt := 0;
  LOOP
    v_attempt := v_attempt + 1;
    v_code := public._gen_order_reference_code();
    BEGIN
      INSERT INTO orders (direction, entity_id, rep_id, status, notes, created_by, assigned_at, reference_code)
      VALUES (
        p_direction::order_direction,
        p_entity_id,
        p_rep_id,
        'assigned'::order_status,
        NULLIF(p_notes, ''),
        auth.uid(),
        NOW(),
        v_code
      )
      RETURNING id INTO v_order_id;
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF v_attempt >= 10 THEN
        RETURN jsonb_build_object('success', false, 'error', 'فشل توليد الرمز المرجعي');
      END IF;
    END;
  END LOOP;

  -- was_unavailable_at_creation is left at its default (false): whether an
  -- item is available is storage's call now, recorded in check_status.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    INSERT INTO order_items (
      order_id,
      inventory_id,
      quantity,
      is_custom,
      custom_description,
      source_inventory_id
    ) VALUES (
      v_order_id,
      NULLIF(v_item->>'inventory_id', '')::UUID,
      (v_item->>'quantity')::NUMERIC,
      COALESCE((v_item->>'is_custom')::BOOLEAN, FALSE),
      v_item->>'custom_description',
      NULLIF(v_item->>'source_inventory_id', '')::UUID
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'reference_code', v_code);
END;
$$;
