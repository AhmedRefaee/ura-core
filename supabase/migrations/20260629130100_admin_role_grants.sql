-- Grants for the new org-level 'admin' role: the union of manager +
-- verifier + rep + storage_actor permissions, scoped to the admin's own
-- organization, with no ownership/status restriction (admin is meant to
-- have full, unrestricted access within their org).
--
-- Two edit strategies, matching what each policy/function already does:
--   1. Direct edits to existing role-list/CASE checks where 'admin' belongs
--      alongside an existing role (entities, inventory, the orders CASE
--      policies, order creation).
--   2. New additive "org_admin_bypass" policies, modeled on the
--      platform_admin_bypass pattern from
--      20260629120000_platform_admin_full_access.sql, for policies that are
--      ownership-bound (rep_id = auth.uid()) or role-exclusive in a way that
--      doesn't make sense to directly edit (admin isn't literally "the rep"
--      or "the verifier" on a row, so it needs its own grant, not a
--      widened existing one). These are purely additive permissive
--      policies and cannot weaken any existing access.

-- ---------------------------------------------------------------------
-- 1. Direct edits
-- ---------------------------------------------------------------------

ALTER POLICY "Role-based order updates" ON "public"."orders" USING (
  (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()) AND
  CASE "public"."get_user_role"()
    WHEN 'verifier'::"public"."user_role" THEN true
    WHEN 'admin'::"public"."user_role" THEN true
    WHEN 'rep'::"public"."user_role" THEN ("rep_id" = "auth"."uid"())
    WHEN 'storage_actor'::"public"."user_role" THEN ("status" = ANY (ARRAY['assigned'::"public"."order_status", 'picked_up'::"public"."order_status"]))
    ELSE false
  END
);

ALTER POLICY "Role-based order visibility" ON "public"."orders" USING (
  ((SELECT "profiles"."is_approved" FROM "public"."profiles" WHERE ("profiles"."id" = "auth"."uid"())) = true)
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
  AND CASE "public"."get_user_role"()
    WHEN 'verifier'::"public"."user_role" THEN true
    WHEN 'admin'::"public"."user_role" THEN true
    WHEN 'rep'::"public"."user_role" THEN ("rep_id" = "auth"."uid"())
    WHEN 'storage_actor'::"public"."user_role" THEN ("status" = ANY (ARRAY['assigned'::"public"."order_status", 'picked_up'::"public"."order_status"]))
    ELSE false
  END
);

ALTER POLICY "Verifiers can create orders" ON "public"."orders" WITH CHECK (
  "public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'admin'::"public"."user_role"])
);

ALTER POLICY "Verifiers and managers can create entities" ON "public"."entities" WITH CHECK (
  "public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role", 'admin'::"public"."user_role"])
);

ALTER POLICY "Verifiers and managers can update entities" ON "public"."entities" USING (
  ("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role", 'admin'::"public"."user_role"]))
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);

ALTER POLICY "Verifiers and managers can delete entities" ON "public"."entities" USING (
  ("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role", 'admin'::"public"."user_role"]))
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);

ALTER POLICY "Verifiers and storage can create inventory" ON "public"."inventory" WITH CHECK (
  "public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'storage_actor'::"public"."user_role", 'admin'::"public"."user_role"])
);

ALTER POLICY "Verifiers and storage can update inventory" ON "public"."inventory" USING (
  ("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'storage_actor'::"public"."user_role", 'admin'::"public"."user_role"]))
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);

ALTER POLICY "Verifiers can add order items" ON "public"."order_items" WITH CHECK (
  ("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'admin'::"public"."user_role"]))
  AND (EXISTS (SELECT 1 FROM "public"."orders" WHERE (("orders"."id" = "order_items"."order_id") AND (("orders"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()))))
);

ALTER POLICY "Verifiers can update order items" ON "public"."order_items" USING (
  ("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'admin'::"public"."user_role"]))
  AND (EXISTS (SELECT 1 FROM "public"."orders" WHERE (("orders"."id" = "order_items"."order_id") AND (("orders"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()))))
);

ALTER POLICY "Storage actors can check order items" ON "public"."order_items" USING (
  ("public"."get_user_role"() = ANY (ARRAY['storage_actor'::"public"."user_role", 'admin'::"public"."user_role"]))
  AND (EXISTS (SELECT 1 FROM "public"."orders" WHERE (("orders"."id" = "order_items"."order_id") AND ("orders"."status" = 'assigned'::"public"."order_status"))))
);

-- ---------------------------------------------------------------------
-- 2. Additive org_admin_bypass policies (ownership-bound / role-exclusive
--    checks that don't fit a direct array/CASE edit)
-- ---------------------------------------------------------------------

CREATE POLICY "org_admin_bypass" ON public.profiles
  FOR ALL
  USING (public.get_user_role() = 'admin'::public.user_role AND organization_id = public.auth_org_id())
  WITH CHECK (public.get_user_role() = 'admin'::public.user_role AND organization_id = public.auth_org_id());

CREATE POLICY "org_admin_bypass" ON public.organizations
  FOR ALL
  USING (public.get_user_role() = 'admin'::public.user_role AND id = public.auth_org_id())
  WITH CHECK (public.get_user_role() = 'admin'::public.user_role AND id = public.auth_org_id());

CREATE POLICY "org_admin_bypass" ON public.orders
  FOR DELETE
  USING (public.get_user_role() = 'admin'::public.user_role AND organization_id = public.auth_org_id());

CREATE POLICY "org_admin_bypass" ON public.audit_log
  FOR SELECT
  USING (
    public.get_user_role() = 'admin'::public.user_role
    AND EXISTS (SELECT 1 FROM public.orders WHERE orders.id = audit_log.order_id AND orders.organization_id = public.auth_org_id())
  );

CREATE POLICY "org_admin_bypass" ON public.order_edit_log
  FOR ALL
  USING (
    public.get_user_role() = 'admin'::public.user_role
    AND EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_edit_log.order_id AND orders.organization_id = public.auth_org_id())
  )
  WITH CHECK (
    public.get_user_role() = 'admin'::public.user_role
    AND EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_edit_log.order_id AND orders.organization_id = public.auth_org_id())
  );

CREATE POLICY "org_admin_bypass" ON public.receipts
  FOR ALL
  USING (
    public.get_user_role() = 'admin'::public.user_role
    AND EXISTS (SELECT 1 FROM public.orders WHERE orders.id = receipts.order_id AND orders.organization_id = public.auth_org_id())
  )
  WITH CHECK (
    public.get_user_role() = 'admin'::public.user_role
    AND EXISTS (SELECT 1 FROM public.orders WHERE orders.id = receipts.order_id AND orders.organization_id = public.auth_org_id())
  );

CREATE POLICY "org_admin_bypass" ON public.urgent_notes
  FOR ALL
  USING (
    public.get_user_role() = 'admin'::public.user_role
    AND EXISTS (SELECT 1 FROM public.orders WHERE orders.id = urgent_notes.order_id AND orders.organization_id = public.auth_org_id())
  )
  WITH CHECK (
    public.get_user_role() = 'admin'::public.user_role
    AND EXISTS (SELECT 1 FROM public.orders WHERE orders.id = urgent_notes.order_id AND orders.organization_id = public.auth_org_id())
  );

-- ---------------------------------------------------------------------
-- 3. Function-internal role checks: admin bypasses entirely, no
--    ownership/status restriction.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "public"."approve_transaction"("target_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_order RECORD;
    v_item RECORD;
    v_user_role user_role;
    v_unchecked_count INTEGER;
BEGIN
    -- 1. Must be a storage actor (or org admin)
    SELECT role INTO v_user_role FROM profiles WHERE id = auth.uid();
    IF v_user_role NOT IN ('storage_actor', 'admin') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only storage actors can approve transactions');
    END IF;

    -- 2. Get and lock the order
    SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order not found');
    END IF;

    -- 3. Must be in 'assigned' status
    IF v_order.status != 'assigned' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order is not in assigned status');
    END IF;

    -- 4. Check that ALL non-custom items are marked 'checked' (not pending, not rejected)
    SELECT COUNT(*) INTO v_unchecked_count
    FROM order_items
    WHERE order_id = target_order_id
    AND is_custom = false
    AND check_status != 'checked';

    IF v_unchecked_count > 0 THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Cannot approve: ' || v_unchecked_count || ' inventory item(s) have not been checked yet'
        );
    END IF;

    -- 5. Process inventory for checked items
    FOR v_item IN
        SELECT oi.*, i.quantity AS current_stock, i.item_name
        FROM order_items oi
        JOIN inventory i ON i.id = oi.inventory_id
        WHERE oi.order_id = target_order_id
        AND oi.is_custom = false
        AND oi.check_status = 'checked'
    LOOP
        IF v_order.direction = 'outbound' THEN
            IF v_item.current_stock < v_item.quantity THEN
                RETURN jsonb_build_object(
                    'success', false,
                    'error', 'Insufficient stock for: ' || v_item.item_name
                        || '. Available: ' || v_item.current_stock
                        || ', Requested: ' || v_item.quantity
                );
            END IF;
            UPDATE inventory SET quantity = quantity - v_item.quantity WHERE id = v_item.inventory_id;

        ELSIF v_order.direction IN ('inbound_rep', 'inbound_external') THEN
            UPDATE inventory SET quantity = quantity + v_item.quantity WHERE id = v_item.inventory_id;
        END IF;
    END LOOP;

    -- 6. Update order status
    UPDATE orders SET status = 'picked_up', picked_up_at = NOW() WHERE id = target_order_id;

    -- 7. Audit log
    INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by, details)
    VALUES (target_order_id, 'storage_approval', 'assigned', 'picked_up', auth.uid(), 'All inventory items verified and approved');

    RETURN jsonb_build_object('success', true, 'message', 'Transaction approved');
END;
$$;

CREATE OR REPLACE FUNCTION "public"."check_order_item"("target_item_id" "uuid", "new_status" "public"."item_check_status") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_user_role user_role;
    v_item RECORD;
BEGIN
    SELECT role INTO v_user_role FROM profiles WHERE id = auth.uid();
    IF v_user_role NOT IN ('storage_actor', 'admin') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Only storage actors can check items');
    END IF;

    SELECT oi.*, o.status AS order_status
    INTO v_item
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE oi.id = target_item_id;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'Item not found');
    END IF;

    -- Can only check items on orders that are still in 'assigned' status
    IF v_item.order_status != 'assigned' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order has already been approved');
    END IF;

    UPDATE order_items
    SET check_status = new_status,
        checked_by = auth.uid(),
        checked_at = NOW()
    WHERE id = target_item_id;

    RETURN jsonb_build_object('success', true, 'message', 'Item marked as ' || new_status::text);
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
    AND role IN ('verifier', 'admin')
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
        SET quantity = (v_update->>'new_quantity')::INT
        WHERE id = v_item.id;

      v_changes := v_changes || jsonb_build_array(jsonb_build_object(
        'action', 'update_quantity',
        'item_id', v_item.id,
        'item_name', COALESCE(v_item_name, 'Unknown'),
        'old_quantity', v_item.quantity,
        'new_quantity', (v_update->>'new_quantity')::INT
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
      (v_addition->>'quantity')::INT,
      COALESCE((v_addition->>'is_custom')::BOOL, false),
      v_addition->>'custom_description',
      (v_addition->>'source_inventory_id')::UUID
    ) RETURNING id INTO v_new_item_id;

    v_changes := v_changes || jsonb_build_array(jsonb_build_object(
      'action', 'add_item',
      'item_id', v_new_item_id,
      'item_name', COALESCE(v_item_name, 'Unknown'),
      'quantity', (v_addition->>'quantity')::INT,
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

-- approve_user gates on caller role = 'manager'; admin is a superset of
-- manager so must be able to approve/assign roles too.
CREATE OR REPLACE FUNCTION "public"."approve_user"("target_user_id" "uuid", "assigned_role" "public"."user_role") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_caller_role user_role;
  v_caller_org  uuid;
  v_target_org  uuid;
begin
  select role, organization_id into v_caller_role, v_caller_org
  from profiles where id = auth.uid();

  if v_caller_role NOT IN ('manager', 'admin') and not is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'Only managers can approve users');
  end if;

  select organization_id into v_target_org from profiles where id = target_user_id;
  if v_target_org is null then
    return jsonb_build_object('success', false, 'error', 'User not found');
  end if;

  if not is_platform_admin() and v_caller_org is distinct from v_target_org then
    return jsonb_build_object('success', false, 'error', 'Only managers can approve users');
  end if;

  update profiles
  set role = assigned_role,
      is_approved = true
  where id = target_user_id;

  if not found then
    return jsonb_build_object('success', false, 'error', 'User not found');
  end if;

  return jsonb_build_object('success', true, 'message', 'User approved as ' || assigned_role::text);
end
$$;

-- start_move/mark_picked_up/mark_delivered gate on literal rep_id = auth.uid()
-- ownership (not just RLS), since they're rep-specific status transitions.
-- Admin bypasses that ownership check too, consistent with "no restrictions".

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

CREATE OR REPLACE FUNCTION "public"."rotate_join_code"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_code   text;
begin
  if get_user_role() NOT IN ('manager', 'admin') or not is_current_user_approved() then
    return jsonb_build_object('success', false, 'error', 'غير مصرح');
  end if;

  select organization_id into v_org_id from profiles where id = auth.uid();
  loop
    v_code := gen_join_code();
    exit when not exists (select 1 from organizations where join_code = v_code);
  end loop;
  update organizations set join_code = v_code where id = v_org_id;

  return jsonb_build_object('success', true, 'join_code', v_code);
end
$$;
