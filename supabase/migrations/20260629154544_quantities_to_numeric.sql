-- Support decimal quantities app-wide: convert integer quantity columns to numeric
-- and update RPC functions so JSON casts and local vars no longer truncate decimals.
-- usage_count stays integer (it is a count, not a measurable quantity).

-- ── 1. Column type changes ───────────────────────────────────────────────────
-- numeric keeps the existing >= 0 / > 0 CHECK constraints valid.
ALTER TABLE "public"."inventory"
  ALTER COLUMN "quantity"     TYPE numeric,
  ALTER COLUMN "min_quantity" TYPE numeric;

ALTER TABLE "public"."inventory_audit_log"
  ALTER COLUMN "old_quantity" TYPE numeric,
  ALTER COLUMN "new_quantity" TYPE numeric;

ALTER TABLE "public"."order_items"
  ALTER COLUMN "quantity"       TYPE numeric,
  ALTER COLUMN "final_quantity" TYPE numeric;

ALTER TABLE "public"."order_template_items"
  ALTER COLUMN "quantity" TYPE numeric;

-- ── 2. Functions with no signature change (CREATE OR REPLACE) ─────────────────

CREATE OR REPLACE FUNCTION "public"."increment_inventory_bulk"("p_deltas" "jsonb") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  UPDATE inventory
  SET quantity = GREATEST(0, quantity + (d->>'delta')::numeric)
  FROM jsonb_array_elements(p_deltas) AS d
  WHERE id = (d->>'inventory_id')::uuid;
$$;

CREATE OR REPLACE FUNCTION "public"."inventory_bulk_update_quantities"("p_updates" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_update       JSONB;
  v_item_id      UUID;
  v_new_quantity NUMERIC;
  v_old_quantity NUMERIC;
BEGIN
  FOR v_update IN SELECT * FROM jsonb_array_elements(p_updates)
  LOOP
    v_item_id      := (v_update->>'item_id')::UUID;
    v_new_quantity := (v_update->>'quantity')::NUMERIC;

    SELECT quantity INTO v_old_quantity FROM inventory WHERE id = v_item_id;

    UPDATE inventory SET quantity = v_new_quantity WHERE id = v_item_id;

    INSERT INTO inventory_audit_log (item_id, action, old_quantity, new_quantity, performed_by)
    VALUES (v_item_id, 'quantity_updated', v_old_quantity, v_new_quantity, auth.uid());
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION "public"."inventory_delete_item"("p_item_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_already_archived TIMESTAMPTZ;
  v_old_quantity     NUMERIC;
BEGIN
  SELECT archived_at, quantity
    INTO v_already_archived, v_old_quantity
  FROM inventory
  WHERE id = p_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'لم يتم العثور على العنصر' USING ERRCODE = 'P0002';
  END IF;

  IF v_already_archived IS NOT NULL THEN
    RETURN;
  END IF;

  UPDATE inventory
     SET archived_at = now()
   WHERE id = p_item_id;

  INSERT INTO inventory_audit_log
    (item_id, action, old_quantity, new_quantity, performed_by)
  VALUES
    (p_item_id, 'archived', v_old_quantity, v_old_quantity, auth.uid());
END;
$$;

CREATE OR REPLACE FUNCTION "public"."create_order_with_items"("p_direction" "text", "p_entity_id" "uuid", "p_rep_id" "uuid" DEFAULT NULL::"uuid", "p_notes" "text" DEFAULT NULL::"text", "p_items" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order_id UUID;
  v_item JSONB;
  v_inv_id UUID;
  v_current_qty NUMERIC;
  v_was_unavailable BOOLEAN;
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
      (v_item->>'quantity')::NUMERIC,
      COALESCE((v_item->>'is_custom')::BOOLEAN, FALSE),
      v_item->>'custom_description',
      NULLIF(v_item->>'source_inventory_id', '')::UUID,
      v_was_unavailable
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'reference_code', v_code);
END;
$$;

CREATE OR REPLACE FUNCTION "public"."edit_order_items"("p_order_id" "uuid", "p_reason" "text", "p_updates" "jsonb" DEFAULT '[]'::"jsonb", "p_removals" "uuid"[] DEFAULT ARRAY[]::"uuid"[], "p_additions" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order RECORD;
  v_changes JSONB := '[]'::JSONB;
  v_update JSONB;
  v_addition JSONB;
  v_item RECORD;
  v_removal_id UUID;
  v_new_item_id UUID;
  v_item_name TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid()
    AND role = 'verifier'
    AND is_approved = TRUE
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only verifiers can edit orders');
  END IF;

  SELECT * INTO v_order FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order not found');
  END IF;

  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Edit reason is required');
  END IF;

  FOR v_update IN SELECT * FROM jsonb_array_elements(p_updates)
  LOOP
    SELECT * INTO v_item FROM order_items
      WHERE id = (v_update->>'item_id')::UUID AND order_id = p_order_id;

    IF FOUND THEN
      IF v_item.inventory_id IS NOT NULL THEN
        SELECT item_name INTO v_item_name FROM inventory WHERE id = v_item.inventory_id;
      ELSE
        v_item_name := v_item.custom_description;
      END IF;

      UPDATE order_items
        SET quantity = (v_update->>'new_quantity')::NUMERIC
        WHERE id = v_item.id;

      v_changes := v_changes || jsonb_build_array(jsonb_build_object(
        'action', 'update_quantity',
        'item_id', v_item.id,
        'item_name', COALESCE(v_item_name, 'Unknown'),
        'old_quantity', v_item.quantity,
        'new_quantity', (v_update->>'new_quantity')::NUMERIC
      ));
    END IF;
  END LOOP;

  IF p_removals IS NOT NULL THEN
    FOREACH v_removal_id IN ARRAY p_removals
    LOOP
      SELECT * INTO v_item FROM order_items
        WHERE id = v_removal_id AND order_id = p_order_id;

      IF FOUND THEN
        IF v_item.inventory_id IS NOT NULL THEN
          SELECT item_name INTO v_item_name FROM inventory WHERE id = v_item.inventory_id;
        ELSE
          v_item_name := v_item.custom_description;
        END IF;

        DELETE FROM order_items WHERE id = v_removal_id;

        v_changes := v_changes || jsonb_build_array(jsonb_build_object(
          'action', 'remove_item',
          'item_id', v_item.id,
          'item_name', COALESCE(v_item_name, 'Unknown'),
          'quantity', v_item.quantity
        ));
      END IF;
    END LOOP;
  END IF;

  FOR v_addition IN SELECT * FROM jsonb_array_elements(p_additions)
  LOOP
    IF (v_addition->>'inventory_id') IS NOT NULL THEN
      SELECT item_name INTO v_item_name FROM inventory
        WHERE id = (v_addition->>'inventory_id')::UUID;
    ELSE
      v_item_name := v_addition->>'custom_description';
    END IF;

    INSERT INTO order_items (
      order_id,
      inventory_id,
      quantity,
      is_custom,
      custom_description,
      source_inventory_id
    ) VALUES (
      p_order_id,
      (v_addition->>'inventory_id')::UUID,
      (v_addition->>'quantity')::NUMERIC,
      COALESCE((v_addition->>'is_custom')::BOOL, false),
      v_addition->>'custom_description',
      (v_addition->>'source_inventory_id')::UUID
    ) RETURNING id INTO v_new_item_id;

    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'action', 'add_item',
      'item_id', v_new_item_id,
      'item_name', COALESCE(v_item_name, 'Unknown'),
      'quantity', (v_addition->>'quantity')::NUMERIC,
      'is_custom', COALESCE((v_addition->>'is_custom')::BOOL, false)
    ));
  END LOOP;

  INSERT INTO order_edit_log (order_id, performed_by, reason, changes)
  VALUES (p_order_id, auth.uid(), p_reason, v_changes);

  INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, details, notes)
  VALUES (
    p_order_id,
    'order_edited',
    v_order.status,
    v_order.status,
    auth.uid(),
    v_changes::TEXT,
    p_reason
  );

  RETURN jsonb_build_object(
    'success', true,
    'changes_count', jsonb_array_length(v_changes)
  );
END;
$$;

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
$$;

CREATE OR REPLACE FUNCTION "public"."storage_confirm_pickup"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_final_quantities" "jsonb" DEFAULT '[]'::"jsonb") RETURNS json
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

  IF v_order.status != 'assigned' THEN RETURN json_build_object('success', false, 'error', 'الطلب ليس في حالة معين'); END IF;
  IF v_order.direction != 'outbound' THEN RETURN json_build_object('success', false, 'error', 'هذا الإجراء مخصص للطلبات الصادرة فقط'); END IF;

  FOR i IN 0..jsonb_array_length(p_final_quantities) - 1 LOOP
    UPDATE order_items
    SET final_quantity = (p_final_quantities->i->>'quantity')::NUMERIC
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
$$;

-- ── 3. Functions whose parameter types change (DROP + recreate + re-grant) ────
-- p_quantity / p_min_quantity go from integer to numeric, so the signature
-- changes and CREATE OR REPLACE would create an overload instead of replacing.

DROP FUNCTION IF EXISTS "public"."inventory_create_item"("text", "text", integer, "text", "text", integer, "text", "text");

CREATE FUNCTION "public"."inventory_create_item"("p_name" "text", "p_unit" "text", "p_quantity" numeric, "p_sku" "text" DEFAULT NULL::"text", "p_category" "text" DEFAULT NULL::"text", "p_min_quantity" numeric DEFAULT 0, "p_description" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_item_id UUID;
BEGIN
  INSERT INTO inventory (item_name, unit, quantity, sku, category, min_quantity, description)
  VALUES (p_name, p_unit, p_quantity, p_sku, p_category, p_min_quantity, p_description)
  RETURNING id INTO v_item_id;

  INSERT INTO inventory_audit_log (item_id, action, old_quantity, new_quantity, performed_by, notes)
  VALUES (v_item_id, 'created', 0, p_quantity, auth.uid(), p_notes);
END;
$$;

ALTER FUNCTION "public"."inventory_create_item"("p_name" "text", "p_unit" "text", "p_quantity" numeric, "p_sku" "text", "p_category" "text", "p_min_quantity" numeric, "p_description" "text", "p_notes" "text") OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."inventory_create_item"("p_name" "text", "p_unit" "text", "p_quantity" numeric, "p_sku" "text", "p_category" "text", "p_min_quantity" numeric, "p_description" "text", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."inventory_create_item"("p_name" "text", "p_unit" "text", "p_quantity" numeric, "p_sku" "text", "p_category" "text", "p_min_quantity" numeric, "p_description" "text", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inventory_create_item"("p_name" "text", "p_unit" "text", "p_quantity" numeric, "p_sku" "text", "p_category" "text", "p_min_quantity" numeric, "p_description" "text", "p_notes" "text") TO "service_role";

DROP FUNCTION IF EXISTS "public"."inventory_update_item"("uuid", "text", "text", integer, "text", "text", integer, "text", "text");

CREATE FUNCTION "public"."inventory_update_item"("p_item_id" "uuid", "p_name" "text", "p_unit" "text", "p_quantity" numeric, "p_sku" "text" DEFAULT NULL::"text", "p_category" "text" DEFAULT NULL::"text", "p_min_quantity" numeric DEFAULT 0, "p_description" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_old_quantity NUMERIC;
  v_action       TEXT;
BEGIN
  SELECT quantity INTO v_old_quantity FROM inventory WHERE id = p_item_id;

  UPDATE inventory
  SET item_name    = p_name,
      unit         = p_unit,
      quantity     = p_quantity,
      sku          = p_sku,
      category     = p_category,
      min_quantity = p_min_quantity,
      description  = p_description
  WHERE id = p_item_id;

  v_action := CASE WHEN v_old_quantity != p_quantity THEN 'quantity_updated' ELSE 'item_updated' END;

  INSERT INTO inventory_audit_log (item_id, action, old_quantity, new_quantity, performed_by, notes)
  VALUES (p_item_id, v_action, v_old_quantity, p_quantity, auth.uid(), p_notes);
END;
$$;

ALTER FUNCTION "public"."inventory_update_item"("p_item_id" "uuid", "p_name" "text", "p_unit" "text", "p_quantity" numeric, "p_sku" "text", "p_category" "text", "p_min_quantity" numeric, "p_description" "text", "p_notes" "text") OWNER TO "postgres";
GRANT ALL ON FUNCTION "public"."inventory_update_item"("p_item_id" "uuid", "p_name" "text", "p_unit" "text", "p_quantity" numeric, "p_sku" "text", "p_category" "text", "p_min_quantity" numeric, "p_description" "text", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."inventory_update_item"("p_item_id" "uuid", "p_name" "text", "p_unit" "text", "p_quantity" numeric, "p_sku" "text", "p_category" "text", "p_min_quantity" numeric, "p_description" "text", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inventory_update_item"("p_item_id" "uuid", "p_name" "text", "p_unit" "text", "p_quantity" numeric, "p_sku" "text", "p_category" "text", "p_min_quantity" numeric, "p_description" "text", "p_notes" "text") TO "service_role";
