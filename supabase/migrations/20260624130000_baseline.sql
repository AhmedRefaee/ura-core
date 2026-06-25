


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE TYPE "public"."entity_category" AS ENUM (
    'incoming',
    'outgoing',
    'unassigned'
);


ALTER TYPE "public"."entity_category" OWNER TO "postgres";


CREATE TYPE "public"."entity_type" AS ENUM (
    'customer',
    'supplier'
);


ALTER TYPE "public"."entity_type" OWNER TO "postgres";


CREATE TYPE "public"."item_check_status" AS ENUM (
    'pending',
    'checked',
    'rejected'
);


ALTER TYPE "public"."item_check_status" OWNER TO "postgres";


CREATE TYPE "public"."order_direction" AS ENUM (
    'outbound',
    'inbound_rep',
    'inbound_external'
);


ALTER TYPE "public"."order_direction" OWNER TO "postgres";


CREATE TYPE "public"."order_status" AS ENUM (
    'assigned',
    'picked_up',
    'on_the_move',
    'delivered',
    'delivered_to_storage'
);


ALTER TYPE "public"."order_status" OWNER TO "postgres";


CREATE TYPE "public"."user_role" AS ENUM (
    'verifier',
    'rep',
    'storage_actor',
    'manager'
);


ALTER TYPE "public"."user_role" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."_gen_order_reference_code"() RETURNS "text"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
  v_digits TEXT;
  v_letters TEXT;
BEGIN
  v_digits := lpad((floor(random() * 10000))::int::text, 4, '0');
  v_letters := chr(65 + floor(random() * 26)::int) ||
               chr(65 + floor(random() * 26)::int);
  RETURN 'URA-' || v_digits || '-' || v_letters;
END;
$$;


ALTER FUNCTION "public"."_gen_order_reference_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."acknowledge_chat_message"("p_message_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE chat_messages
  SET
    is_acknowledged = TRUE,
    acknowledged_by = auth.uid(),
    acknowledged_at = NOW()
  WHERE id = p_message_id AND is_urgent = TRUE;
END;
$$;


ALTER FUNCTION "public"."acknowledge_chat_message"("p_message_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."add_thread_participant"("p_thread_id" "uuid", "p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role::TEXT INTO v_role FROM profiles WHERE id = auth.uid();

  IF v_role NOT IN ('verifier', 'manager') THEN
    RAISE EXCEPTION 'RBAC: only verifiers and managers may add thread participants';
  END IF;

  INSERT INTO chat_thread_participants (thread_id, user_id, added_by)
  VALUES (p_thread_id, p_user_id, auth.uid())
  ON CONFLICT (thread_id, user_id) DO NOTHING;
END;
$$;


ALTER FUNCTION "public"."add_thread_participant"("p_thread_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_orgs"() RETURNS TABLE("id" "uuid", "name" "text", "join_code" "text", "is_discoverable" boolean, "member_count" bigint, "pending_count" bigint, "created_at" timestamp with time zone)
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select o.id, o.name, o.join_code, o.is_discoverable,
         count(p.id) as member_count,
         count(p.id) filter (where p.is_approved = false) as pending_count,
         o.created_at
  from organizations o
  left join profiles p on p.organization_id = o.id
  where is_platform_admin()
  group by o.id
  order by o.created_at desc
$$;


ALTER FUNCTION "public"."admin_list_orgs"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_rotate_join_code"("p_org_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_code text;
begin
  if not is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'forbidden');
  end if;
  loop
    v_code := gen_join_code();
    exit when not exists (select 1 from organizations where join_code = v_code);
  end loop;
  update organizations set join_code = v_code where id = p_org_id;
  return jsonb_build_object('success', true, 'join_code', v_code);
end
$$;


ALTER FUNCTION "public"."admin_rotate_join_code"("p_org_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_discoverable"("p_org_id" "uuid", "p_value" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not is_platform_admin() then
    return jsonb_build_object('success', false, 'error', 'forbidden');
  end if;
  update organizations set is_discoverable = p_value where id = p_org_id;
  return jsonb_build_object('success', true);
end
$$;


ALTER FUNCTION "public"."admin_set_discoverable"("p_org_id" "uuid", "p_value" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."approve_order"("target_order_id" "uuid") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order orders%ROWTYPE;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id;

  IF NOT FOUND THEN
    RETURN json_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  -- inbound_rep: storage approves AFTER rep delivers → delivered → delivered_to_storage
  -- outbound/inbound_external: storage approves BEFORE rep moves → assigned → picked_up
  IF v_order.direction = 'inbound_rep' AND v_order.status != 'delivered' THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن اعتماد الطلب في الحالة الحالية');
  ELSIF v_order.direction != 'inbound_rep' AND v_order.status != 'assigned' THEN
    RETURN json_build_object('success', false, 'error', 'لا يمكن اعتماد الطلب في الحالة الحالية');
  END IF;

  IF v_order.direction = 'inbound_rep' THEN
    UPDATE orders SET status = 'delivered_to_storage' WHERE id = target_order_id;
    -- PASTE YOUR EXISTING INVENTORY INCREMENT BLOCK HERE (same as for inbound_external)

  ELSE
    UPDATE orders SET status = 'picked_up' WHERE id = target_order_id;
    -- PASTE YOUR EXISTING INVENTORY/DECREMENT BLOCK HERE (unchanged from current function)
  END IF;

  RETURN json_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."approve_order"("target_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."approve_transaction"("target_order_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_order RECORD;
    v_item RECORD;
    v_user_role user_role;
    v_unchecked_count INTEGER;
BEGIN
    -- 1. Must be a storage actor
    SELECT role INTO v_user_role FROM profiles WHERE id = auth.uid();
    IF v_user_role != 'storage_actor' THEN
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


ALTER FUNCTION "public"."approve_transaction"("target_order_id" "uuid") OWNER TO "postgres";


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

  if v_caller_role != 'manager'::user_role and not is_platform_admin() then
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


ALTER FUNCTION "public"."approve_user"("target_user_id" "uuid", "assigned_role" "public"."user_role") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auth_org_id"() RETURNS "uuid"
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select organization_id from profiles where id = auth.uid()
$$;


ALTER FUNCTION "public"."auth_org_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."auto_post_order_status_message"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_entity_name TEXT;
  v_ar_status   TEXT;
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    SELECT name INTO v_entity_name FROM entities WHERE id = NEW.entity_id;

    v_ar_status := CASE NEW.status
      WHEN 'assigned'            THEN 'معيّن'
      WHEN 'picked_up'           THEN 'تم الاستلام'
      WHEN 'on_the_move'         THEN 'في الطريق'
      WHEN 'delivered'           THEN 'تم التسليم'
      WHEN 'delivered_to_storage' THEN 'تم الاستلام في المخزن'
      ELSE NEW.status::text
    END;

    INSERT INTO chat_messages (
      id, thread_id, sender_id, sender_name, content,
      order_mention_id, message_type, created_at
    )
    SELECT
      gen_random_uuid(),
      cm.thread_id,
      NULL,
      'النظام',
      'تغيّرت حالة طلب ' || COALESCE(v_entity_name, '') || ' إلى: ' || v_ar_status,
      NEW.id,
      'system',
      now()
    FROM (
      SELECT DISTINCT cm2.thread_id
      FROM   chat_messages cm2
      JOIN   chat_threads  ct ON ct.id = cm2.thread_id
      WHERE  cm2.order_mention_id = NEW.id
        AND  cm2.message_type     = 'user'
        AND  ct.system_messages_enabled = TRUE
    ) cm;
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."auto_post_order_status_message"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_order_item"("target_item_id" "uuid", "new_status" "public"."item_check_status") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
    v_user_role user_role;
    v_item RECORD;
BEGIN
    SELECT role INTO v_user_role FROM profiles WHERE id = auth.uid();
    IF v_user_role != 'storage_actor' THEN
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


ALTER FUNCTION "public"."check_order_item"("target_item_id" "uuid", "new_status" "public"."item_check_status") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."check_urgent_notes_block"("p_order_id" "uuid", "p_current_stage" "public"."order_status") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_blocking_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_blocking_count
  FROM urgent_notes
  WHERE order_id = p_order_id
    AND is_resolved = FALSE
    AND stage = p_current_stage;
  
  RETURN jsonb_build_object(
    'is_blocked', v_blocking_count > 0,
    'pending_count', v_blocking_count
  );
END;
$$;


ALTER FUNCTION "public"."check_urgent_notes_block"("p_order_id" "uuid", "p_current_stage" "public"."order_status") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_chat_thread"("p_title" "text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_thread_id UUID;
  v_role      TEXT;
BEGIN
  SELECT role::TEXT INTO v_role FROM profiles WHERE id = auth.uid();

  IF v_role NOT IN ('verifier', 'manager') THEN
    RAISE EXCEPTION 'RBAC: only verifiers and managers may create chat threads';
  END IF;

  INSERT INTO chat_threads (title, created_by)
  VALUES (p_title, auth.uid())
  RETURNING id INTO v_thread_id;

  INSERT INTO chat_thread_participants (thread_id, user_id, added_by)
  VALUES (v_thread_id, auth.uid(), auth.uid());

  RETURN v_thread_id;
END;
$$;


ALTER FUNCTION "public"."create_chat_thread"("p_title" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_order_with_items"("p_direction" "text", "p_entity_id" "uuid", "p_rep_id" "uuid" DEFAULT NULL::"uuid", "p_notes" "text" DEFAULT NULL::"text", "p_items" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order_id UUID;
  v_item JSONB;
  v_inv_id UUID;
  v_current_qty INT;
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
      (v_item->>'quantity')::INT,
      COALESCE((v_item->>'is_custom')::BOOLEAN, FALSE),
      v_item->>'custom_description',
      NULLIF(v_item->>'source_inventory_id', '')::UUID,
      v_was_unavailable
    );
  END LOOP;

  RETURN jsonb_build_object('success', true, 'order_id', v_order_id, 'reference_code', v_code);
END;
$$;


ALTER FUNCTION "public"."create_order_with_items"("p_direction" "text", "p_entity_id" "uuid", "p_rep_id" "uuid", "p_notes" "text", "p_items" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_organization_and_owner"("p_org_name" "text", "p_full_name" "text", "p_phone" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_code   text;
begin
  if auth.uid() is null then
    return jsonb_build_object('success', false, 'error', 'غير مصرح');
  end if;
  if exists (select 1 from profiles where id = auth.uid()) then
    return jsonb_build_object('success', false, 'error', 'لديك حساب بالفعل');
  end if;
  if coalesce(trim(p_org_name), '') = '' or coalesce(trim(p_full_name), '') = '' then
    return jsonb_build_object('success', false, 'error', 'الاسم مطلوب');
  end if;

  loop
    v_code := gen_join_code();
    exit when not exists (select 1 from organizations where join_code = v_code);
  end loop;

  insert into organizations (name, join_code, created_by)
  values (trim(p_org_name), v_code, auth.uid())
  returning id into v_org_id;

  insert into profiles (id, full_name, phone, role, is_approved, organization_id)
  values (auth.uid(), trim(p_full_name), nullif(p_phone, ''), 'manager'::user_role, true, v_org_id);

  return jsonb_build_object('success', true, 'organization_id', v_org_id, 'join_code', v_code);
end
$$;


ALTER FUNCTION "public"."create_organization_and_owner"("p_org_name" "text", "p_full_name" "text", "p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_urgent_note"("p_order_id" "uuid", "p_stage" "public"."order_status", "p_message" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_note_id UUID;
  v_order_status order_status;
BEGIN
  -- Validate that the order exists and belongs to the rep
  SELECT status INTO v_order_status
  FROM orders
  WHERE id = p_order_id AND rep_id = auth.uid();
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Order not found or not assigned to you'
    );
  END IF;
  
  -- Validate that the stage matches current order status
  IF v_order_status != p_stage THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Stage does not match current order status'
    );
  END IF;
  
  -- Insert the urgent note
  INSERT INTO urgent_notes (order_id, stage, message, created_by)
  VALUES (p_order_id, p_stage, p_message, auth.uid())
  RETURNING id INTO v_note_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'note_id', v_note_id
  );
END;
$$;


ALTER FUNCTION "public"."create_urgent_note"("p_order_id" "uuid", "p_stage" "public"."order_status", "p_message" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_chat_thread"("p_thread_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_creator UUID;
  v_role    TEXT;
BEGIN
  SELECT created_by INTO v_creator
  FROM chat_threads
  WHERE id = p_thread_id;

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'Thread not found';
  END IF;

  IF v_creator != auth.uid() THEN
    RAISE EXCEPTION 'Only the thread creator can delete this thread';
  END IF;

  SELECT role::TEXT INTO v_role FROM profiles WHERE id = auth.uid();
  IF v_role NOT IN ('verifier', 'manager') THEN
    RAISE EXCEPTION 'RBAC: only verifiers and managers may delete threads';
  END IF;

  -- ON DELETE CASCADE handles chat_messages and chat_thread_participants
  DELETE FROM chat_threads WHERE id = p_thread_id;
END;
$$;


ALTER FUNCTION "public"."delete_chat_thread"("p_thread_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."dispatch_push"("user_ids" "uuid"[], "title" "text", "body" "text", "data" "jsonb" DEFAULT '{}'::"jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  edge_url       constant text := 'https://musaqyislgvshurfrjwx.supabase.co';
  webhook_secret constant text := 'URA_SECRET_STRING_2026';
begin
  if array_length(user_ids, 1) is null then return; end if;

  perform net.http_post(
    url     := edge_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || webhook_secret
    ),
    body    := jsonb_build_object(
      'user_ids', to_jsonb(user_ids::text[]),
      'title',    title,
      'body',     body,
      'data',     data
    )::text
  );
exception when others then
  raise warning 'dispatch_push failed: %', sqlerrm;
end;
$$;


ALTER FUNCTION "public"."dispatch_push"("user_ids" "uuid"[], "title" "text", "body" "text", "data" "jsonb") OWNER TO "postgres";


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


ALTER FUNCTION "public"."edit_order_items"("p_order_id" "uuid", "p_reason" "text", "p_updates" "jsonb", "p_removals" "uuid"[], "p_additions" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gen_join_code"() RETURNS "text"
    LANGUAGE "sql"
    SET "search_path" TO 'public'
    AS $$
  select upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
$$;


ALTER FUNCTION "public"."gen_join_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_all_pending_urgent_notes"() RETURNS TABLE("id" "uuid", "order_id" "uuid", "stage" "public"."order_status", "message" "text", "created_at" timestamp with time zone, "created_by_name" "text", "created_by_id" "uuid", "entity_name" "text", "order_status" "public"."order_status")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    un.id,
    un.order_id,
    un.stage,
    un.message,
    un.created_at,
    p.full_name,
    un.created_by,
    e.name,
    o.status
  FROM urgent_notes un
  JOIN profiles p ON un.created_by = p.id
  JOIN orders o ON un.order_id = o.id
  JOIN entities e ON o.entity_id = e.id
  WHERE un.is_resolved = FALSE
  ORDER BY un.created_at DESC;
END;
$$;


ALTER FUNCTION "public"."get_all_pending_urgent_notes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_entity_frequency"("p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_limit" integer DEFAULT 10) RETURNS TABLE("entity_id" "uuid", "entity_name" "text", "entity_type" "text", "order_count" bigint, "outbound_count" bigint, "inbound_count" bigint)
    LANGUAGE "sql" STABLE
    AS $$
  SELECT
    e.id AS entity_id,
    e.name AS entity_name,
    e.category::text AS entity_type,
    COUNT(o.id) AS order_count,
    COUNT(o.id) FILTER (WHERE o.direction = 'outbound') AS outbound_count,
    COUNT(o.id) FILTER (WHERE o.direction != 'outbound') AS inbound_count
  FROM entities e
  JOIN orders o ON o.entity_id = e.id AND o.created_at BETWEEN p_start AND p_end
  GROUP BY e.id, e.name, e.category
  ORDER BY COUNT(o.id) DESC
  LIMIT p_limit;
$$;


ALTER FUNCTION "public"."get_entity_frequency"("p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_global_stats_overview"("p_start" timestamp with time zone DEFAULT ("now"() - '30 days'::interval), "p_end" timestamp with time zone DEFAULT "now"()) RETURNS json
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT JSON_BUILD_OBJECT(
    'total_orders',     COUNT(*),
    'delivered_orders', COUNT(*) FILTER (WHERE status = 'delivered'),
    'active_orders',    COUNT(*) FILTER (WHERE status != 'delivered'),
    'outbound_count',   COUNT(*) FILTER (WHERE direction = 'outbound'),
    'inbound_count',    COUNT(*) FILTER (WHERE direction != 'outbound'),
    'avg_total_hours',  ROUND(AVG(
      EXTRACT(EPOCH FROM (delivered_at - created_at)) / 3600
    ) FILTER (WHERE delivered_at IS NOT NULL), 1)
  )
  FROM orders
  WHERE created_at BETWEEN p_start AND p_end;
$$;


ALTER FUNCTION "public"."get_global_stats_overview"("p_start" timestamp with time zone, "p_end" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_or_create_direct_thread"("p_other_user_id" "uuid") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_me         uuid := auth.uid();
  v_pair_key   text;
  v_thread_id  uuid;
  v_caller_name text;
  v_other_name  text;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF p_other_user_id = v_me THEN
    RAISE EXCEPTION 'Cannot create a direct thread with yourself';
  END IF;

  -- Stable pair key: LEAST/GREATEST ensures the same key regardless of caller order
  v_pair_key := LEAST(v_me::text, p_other_user_id::text)
             || '_' ||
                GREATEST(v_me::text, p_other_user_id::text);

  -- Fast indexed lookup
  SELECT id INTO v_thread_id
  FROM   chat_threads
  WHERE  is_direct        = TRUE
  AND    direct_pair_key  = v_pair_key;

  IF v_thread_id IS NOT NULL THEN
    RETURN v_thread_id;
  END IF;

  -- Resolve display names for the thread title
  SELECT full_name INTO v_caller_name FROM profiles WHERE id = v_me;
  SELECT full_name INTO v_other_name  FROM profiles WHERE id = p_other_user_id;

  -- Insert with ON CONFLICT to be safe against concurrent callers
  INSERT INTO chat_threads (title, created_by, is_direct, direct_pair_key)
  VALUES (
    COALESCE(v_caller_name, 'مستخدم') || ' — ' || COALESCE(v_other_name, 'موظف'),
    v_me,
    TRUE,
    v_pair_key
  )
  ON CONFLICT (direct_pair_key) WHERE is_direct = TRUE DO NOTHING
  RETURNING id INTO v_thread_id;

  IF v_thread_id IS NULL THEN
    -- Race: another concurrent caller inserted first — re-read
    SELECT id INTO v_thread_id
    FROM   chat_threads
    WHERE  is_direct       = TRUE
    AND    direct_pair_key = v_pair_key;

    RETURN v_thread_id;
  END IF;

  -- Add both participants
  INSERT INTO chat_thread_participants (thread_id, user_id, added_by)
  VALUES
    (v_thread_id, v_me,              v_me),
    (v_thread_id, p_other_user_id,   v_me)
  ON CONFLICT DO NOTHING;

  RETURN v_thread_id;
END;
$$;


ALTER FUNCTION "public"."get_or_create_direct_thread"("p_other_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_orders_monthly_summary"("p_start" timestamp with time zone DEFAULT ("now"() - '1 year'::interval), "p_end" timestamp with time zone DEFAULT "now"()) RETURNS TABLE("month" "text", "total_orders" bigint, "delivered_orders" bigint, "outbound_orders" bigint, "inbound_orders" bigint)
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT
    TO_CHAR(DATE_TRUNC('month', created_at), 'YYYY-MM'),
    COUNT(*),
    COUNT(*) FILTER (WHERE status = 'delivered'),
    COUNT(*) FILTER (WHERE direction = 'outbound'),
    COUNT(*) FILTER (WHERE direction != 'outbound')
  FROM orders
  WHERE created_at BETWEEN p_start AND p_end
  GROUP BY DATE_TRUNC('month', created_at)
  ORDER BY DATE_TRUNC('month', created_at);
$$;


ALTER FUNCTION "public"."get_orders_monthly_summary"("p_start" timestamp with time zone, "p_end" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_pending_urgent_notes"("p_order_id" "uuid") RETURNS TABLE("id" "uuid", "stage" "public"."order_status", "message" "text", "created_at" timestamp with time zone, "created_by_name" "text", "created_by_id" "uuid")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN QUERY
  SELECT 
    un.id,
    un.stage,
    un.message,
    un.created_at,
    p.full_name,
    un.created_by
  FROM urgent_notes un
  JOIN profiles p ON un.created_by = p.id
  WHERE un.order_id = p_order_id
    AND un.is_resolved = FALSE
  ORDER BY un.created_at DESC;
END;
$$;


ALTER FUNCTION "public"."get_pending_urgent_notes"("p_order_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_pending_urgent_notes_count"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  RETURN (
    SELECT COUNT(*)
    FROM urgent_notes
    WHERE is_resolved = FALSE
  );
END;
$$;


ALTER FUNCTION "public"."get_pending_urgent_notes_count"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_rep_performance_stats"("p_start" timestamp with time zone DEFAULT ("now"() - '30 days'::interval), "p_end" timestamp with time zone DEFAULT "now"()) RETURNS TABLE("rep_id" "uuid", "rep_name" "text", "total_orders" bigint, "delivered_orders" bigint, "avg_hours_to_pickup" numeric, "avg_hours_in_transit" numeric, "avg_total_hours" numeric)
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  SELECT
    p.id,
    p.full_name,
    COUNT(o.id),
    COUNT(o.id) FILTER (WHERE o.status = 'delivered'),
    ROUND(AVG(
      EXTRACT(EPOCH FROM (o.picked_up_at - o.assigned_at)) / 3600
    ) FILTER (WHERE o.picked_up_at IS NOT NULL AND o.assigned_at IS NOT NULL), 1),
    ROUND(AVG(
      EXTRACT(EPOCH FROM (o.delivered_at - o.picked_up_at)) / 3600
    ) FILTER (WHERE o.delivered_at IS NOT NULL AND o.picked_up_at IS NOT NULL), 1),
    ROUND(AVG(
      EXTRACT(EPOCH FROM (o.delivered_at - o.created_at)) / 3600
    ) FILTER (WHERE o.delivered_at IS NOT NULL), 1)
  FROM profiles p
  LEFT JOIN orders o
    ON o.rep_id = p.id AND o.created_at BETWEEN p_start AND p_end
  WHERE p.role = 'rep' AND p.is_approved = true
  GROUP BY p.id, p.full_name
  ORDER BY COUNT(o.id) DESC;
$$;


ALTER FUNCTION "public"."get_rep_performance_stats"("p_start" timestamp with time zone, "p_end" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_thread_participants"("p_thread_id" "uuid") RETURNS TABLE("id" "uuid", "full_name" "text", "phone" "text", "role" "text", "is_approved" boolean, "created_at" timestamp with time zone)
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM chat_threads ct
    WHERE ct.id = p_thread_id
      AND (
        ct.created_by = auth.uid()
        OR EXISTS (
          SELECT 1 FROM chat_thread_participants
          WHERE chat_thread_participants.thread_id = ct.id
            AND chat_thread_participants.user_id = auth.uid()
        )
        OR is_platform_admin()
      )
  ) THEN
    RAISE EXCEPTION 'Not authorized to view this thread';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    p.phone,
    p.role,
    p.is_approved,
    p.created_at
  FROM chat_thread_participants ctp
  JOIN profiles p ON p.id = ctp.user_id
  WHERE ctp.thread_id = p_thread_id
  ORDER BY p.full_name;
END;
$$;


ALTER FUNCTION "public"."get_thread_participants"("p_thread_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_thread_reactions"("p_thread_id" "uuid") RETURNS TABLE("message_id" "uuid", "user_id" "uuid", "emoji" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM chat_threads ct
    WHERE ct.id = p_thread_id
      AND (
        ct.created_by = auth.uid()
        OR EXISTS (
          SELECT 1 FROM chat_thread_participants
          WHERE chat_thread_participants.thread_id = ct.id
            AND chat_thread_participants.user_id = auth.uid()
        )
        OR is_platform_admin()
      )
  ) THEN
    RAISE EXCEPTION 'Not authorized to view this thread';
  END IF;

  RETURN QUERY
  SELECT r.message_id, r.user_id, r.emoji
  FROM   chat_message_reactions r
  JOIN   chat_messages m ON m.id = r.message_id
  WHERE  m.thread_id = p_thread_id;
END;
$$;


ALTER FUNCTION "public"."get_thread_reactions"("p_thread_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_threads_with_preview"() RETURNS TABLE("id" "uuid", "title" "text", "created_by" "uuid", "created_at" timestamp with time zone, "is_direct" boolean, "system_messages_enabled" boolean, "last_message_content" "text", "last_message_sender_name" "text", "last_message_at" timestamp with time zone, "other_participant_id" "uuid", "other_participant_name" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT
    t.id,
    t.title,
    t.created_by,
    t.created_at,
    t.is_direct,
    t.system_messages_enabled,
    m.content        AS last_message_content,
    m.sender_name    AS last_message_sender_name,
    m.created_at     AS last_message_at,
    op.id            AS other_participant_id,
    op.full_name     AS other_participant_name
  FROM chat_threads t
  -- ① Only threads the current user belongs to
  JOIN chat_thread_participants me
    ON me.thread_id = t.id
   AND me.user_id   = auth.uid()
  -- ② Only threads that have at least one message (INNER, not LEFT)
  JOIN LATERAL (
    SELECT content, sender_name, created_at
    FROM   chat_messages
    WHERE  thread_id = t.id
    ORDER  BY created_at DESC
    LIMIT  1
  ) m ON true
  -- ③ Other participant name for direct threads only
  LEFT JOIN LATERAL (
    SELECT p.id, p.full_name
    FROM   chat_thread_participants ctp
    JOIN   profiles p ON p.id = ctp.user_id
    WHERE  ctp.thread_id = t.id
      AND  ctp.user_id  != auth.uid()
      AND  t.is_direct   = true
    LIMIT  1
  ) op ON true
  ORDER BY m.created_at DESC;
$$;


ALTER FUNCTION "public"."get_threads_with_preview"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_user_role"() RETURNS "public"."user_role"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT role FROM profiles WHERE id = auth.uid();
$$;


ALTER FUNCTION "public"."get_user_role"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_inventory_bulk"("p_deltas" "jsonb") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  UPDATE inventory
  SET quantity = GREATEST(0, quantity + (d->>'delta')::int)
  FROM jsonb_array_elements(p_deltas) AS d
  WHERE id = (d->>'inventory_id')::uuid;
$$;


ALTER FUNCTION "public"."increment_inventory_bulk"("p_deltas" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_template_usage"("p_id" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  update order_templates
  set usage_count = usage_count + 1,
      updated_at  = now()
  where id = p_id;
$$;


ALTER FUNCTION "public"."increment_template_usage"("p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."inventory_bulk_update_quantities"("p_updates" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_update       JSONB;
  v_item_id      UUID;
  v_new_quantity INT;
  v_old_quantity INT;
BEGIN
  FOR v_update IN SELECT * FROM jsonb_array_elements(p_updates)
  LOOP
    v_item_id      := (v_update->>'item_id')::UUID;
    v_new_quantity := (v_update->>'quantity')::INT;

    SELECT quantity INTO v_old_quantity FROM inventory WHERE id = v_item_id;

    UPDATE inventory SET quantity = v_new_quantity WHERE id = v_item_id;

    INSERT INTO inventory_audit_log (item_id, action, old_quantity, new_quantity, performed_by)
    VALUES (v_item_id, 'quantity_updated', v_old_quantity, v_new_quantity, auth.uid());
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."inventory_bulk_update_quantities"("p_updates" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."inventory_create_item"("p_name" "text", "p_unit" "text", "p_quantity" integer, "p_sku" "text" DEFAULT NULL::"text", "p_category" "text" DEFAULT NULL::"text", "p_min_quantity" integer DEFAULT 0, "p_description" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text") RETURNS "void"
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


ALTER FUNCTION "public"."inventory_create_item"("p_name" "text", "p_unit" "text", "p_quantity" integer, "p_sku" "text", "p_category" "text", "p_min_quantity" integer, "p_description" "text", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."inventory_delete_item"("p_item_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_already_archived TIMESTAMPTZ;
  v_old_quantity     INT;
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


ALTER FUNCTION "public"."inventory_delete_item"("p_item_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."inventory_update_item"("p_item_id" "uuid", "p_name" "text", "p_unit" "text", "p_quantity" integer, "p_sku" "text" DEFAULT NULL::"text", "p_category" "text" DEFAULT NULL::"text", "p_min_quantity" integer DEFAULT 0, "p_description" "text" DEFAULT NULL::"text", "p_notes" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_old_quantity INT;
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


ALTER FUNCTION "public"."inventory_update_item"("p_item_id" "uuid", "p_name" "text", "p_unit" "text", "p_quantity" integer, "p_sku" "text", "p_category" "text", "p_min_quantity" integer, "p_description" "text", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_current_user_approved"() RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  SELECT COALESCE(is_approved, false) FROM profiles WHERE id = auth.uid();
$$;


ALTER FUNCTION "public"."is_current_user_approved"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_platform_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE
    SET "search_path" TO 'public'
    AS $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'platform_admin')::boolean, false)
$$;


ALTER FUNCTION "public"."is_platform_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."join_organization_by_code"("p_code" "text", "p_full_name" "text", "p_phone" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_org_id uuid;
begin
  if auth.uid() is null then
    return jsonb_build_object('success', false, 'error', 'غير مصرح');
  end if;
  if exists (select 1 from profiles where id = auth.uid()) then
    return jsonb_build_object('success', false, 'error', 'لديك حساب بالفعل');
  end if;

  select id into v_org_id from organizations where join_code = upper(trim(p_code));
  if v_org_id is null then
    return jsonb_build_object('success', false, 'error', 'رمز الانضمام غير صالح');
  end if;

  insert into profiles (id, full_name, phone, role, is_approved, organization_id)
  values (auth.uid(), trim(p_full_name), nullif(p_phone, ''), 'rep'::user_role, false, v_org_id);

  return jsonb_build_object('success', true, 'organization_id', v_org_id);
end
$$;


ALTER FUNCTION "public"."join_organization_by_code"("p_code" "text", "p_full_name" "text", "p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."join_organization_by_id"("p_org_id" "uuid", "p_full_name" "text", "p_phone" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if auth.uid() is null then
    return jsonb_build_object('success', false, 'error', 'غير مصرح');
  end if;
  if exists (select 1 from profiles where id = auth.uid()) then
    return jsonb_build_object('success', false, 'error', 'لديك حساب بالفعل');
  end if;
  if not exists (select 1 from organizations where id = p_org_id and is_discoverable) then
    return jsonb_build_object('success', false, 'error', 'المؤسسة غير متاحة');
  end if;

  insert into profiles (id, full_name, phone, role, is_approved, organization_id)
  values (auth.uid(), trim(p_full_name), nullif(p_phone, ''), 'rep'::user_role, false, p_org_id);

  return jsonb_build_object('success', true, 'organization_id', p_org_id);
end
$$;


ALTER FUNCTION "public"."join_organization_by_id"("p_org_id" "uuid", "p_full_name" "text", "p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."list_discoverable_orgs"("p_search" "text" DEFAULT NULL::"text") RETURNS TABLE("id" "uuid", "name" "text", "slug" "text")
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select o.id, o.name, o.slug
  from organizations o
  where o.is_discoverable
    and (p_search is null or o.name ilike '%'||p_search||'%')
  order by o.name
  limit 50
$$;


ALTER FUNCTION "public"."list_discoverable_orgs"("p_search" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_chat_event"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO chat_audit_log (
    event_type, thread_id, message_id, actor_id, payload, created_at
  ) VALUES (
    CASE WHEN TG_OP = 'INSERT' THEN 'message_sent' ELSE 'message_updated' END,
    NEW.thread_id,
    NEW.id,
    NEW.sender_id,
    jsonb_build_object(
      'content_length', length(NEW.content),
      'is_urgent',      NEW.is_urgent,
      'message_type',   NEW.message_type
    ),
    now()
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."log_chat_event"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_order_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO audit_log (order_id, action, performed_by, notes, server_timestamp)
  VALUES (NEW.id, 'order_created', NEW.created_by, NEW.notes, NOW());
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."log_order_created"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."log_order_status_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO audit_log (order_id, action, old_status, new_status, performed_by)
        VALUES (
            NEW.id,
            'status_change',
            OLD.status,
            NEW.status,
            auth.uid()
        );
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."log_order_status_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_delivered"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order RECORD;
  v_item_count INT;
  v_block_check JSONB;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Order not found'); END IF;

  SELECT count(*) INTO v_item_count FROM order_items WHERE order_id = target_order_id;
  IF v_item_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب غير صالح لأنه لا يحتوي على عناصر');
  END IF;

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
$$;


ALTER FUNCTION "public"."mark_delivered"("target_order_id" "uuid", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."mark_picked_up"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order RECORD;
  v_involves_storage BOOLEAN;
  v_item_count INT;
  v_block_check JSONB;
BEGIN
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

  IF v_order.rep_id != auth.uid() THEN
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


ALTER FUNCTION "public"."mark_picked_up"("target_order_id" "uuid", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_chat_message"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  participants uuid[];
  extra_users  uuid[] := '{}';
  order_row    record;
  ar_title     text;
begin
  -- System messages never send push notifications
  IF NEW.message_type = 'system' THEN RETURN NEW; END IF;

  -- Everyone in the thread except the sender
  select array_agg(user_id) into participants
    from public.chat_thread_participants
   where thread_id = NEW.thread_id
     and user_id  <> NEW.sender_id;

  -- Mentioned user
  if NEW.user_mention_id is not null then
    extra_users := array_append(extra_users, NEW.user_mention_id);
  end if;

  -- Order mention: add rep + verifier of that order
  if NEW.order_mention_id is not null then
    select rep_id, created_by into order_row
      from public.orders where id = NEW.order_mention_id;
    if found then
      extra_users := array_cat(extra_users, array[order_row.rep_id, order_row.created_by]);
    end if;
  end if;

  -- Merge, deduplicate, exclude sender
  participants := array(
    select distinct unnest(array_cat(coalesce(participants, '{}'), extra_users))
    except select NEW.sender_id
  );

  ar_title := case when NEW.is_urgent then 'رسالة عاجلة' else 'رسالة جديدة' end;

  perform public.dispatch_push(
    participants,
    ar_title,
    coalesce(left(NEW.content, 80), '...'),
    jsonb_build_object('route', '/chat/' || NEW.thread_id, 'thread_id', NEW.thread_id::text)
  );
  return NEW;
end;
$$;


ALTER FUNCTION "public"."notify_chat_message"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_new_signup"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  admin_ids uuid[];
begin
  select array_agg(id) into admin_ids
    from public.profiles
   where role in ('verifier', 'manager') and is_approved = true;

  perform public.dispatch_push(
    admin_ids,
    'مستخدم جديد يطلب الموافقة',
    coalesce(NEW.full_name, 'مستخدم') || ' ينتظر الموافقة على حسابه',
    jsonb_build_object('route', '/users/pending')
  );
  return NEW;
end;
$$;


ALTER FUNCTION "public"."notify_new_signup"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_order_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  storage_ids uuid[];
  recipients  uuid[];
begin
  select array_agg(id) into storage_ids
    from public.profiles
   where role = 'storage_actor' and is_approved = true;

  if NEW.direction = 'inbound_external' then
    recipients := coalesce(storage_ids, '{}');
  else
    recipients := array_remove(
      array_cat(coalesce(storage_ids, '{}'), array[NEW.rep_id]),
      null
    );
  end if;

  perform public.dispatch_push(
    recipients,
    'طلب جديد',
    'تم تعيين طلب جديد لك',
    jsonb_build_object('route', '/orders/' || NEW.id, 'order_id', NEW.id::text)
  );
  return NEW;
end;
$$;


ALTER FUNCTION "public"."notify_order_created"() OWNER TO "postgres";


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

  elsif OLD.status = 'picked_up' and NEW.status = 'on_the_move' then
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


ALTER FUNCTION "public"."notify_order_status_change"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_user_approved"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  if OLD.is_approved = false and NEW.is_approved = true then
    perform public.dispatch_push(
      array[NEW.id],
      'تمت الموافقة على حسابك',
      'يمكنك الآن تسجيل الدخول والبدء باستخدام التطبيق',
      jsonb_build_object('route', '/login')
    );
  end if;
  return NEW;
end;
$$;


ALTER FUNCTION "public"."notify_user_approved"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."notify_users"("p_user_ids" "uuid"[], "p_title" "text", "p_body" "text", "p_action_route" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  insert into public.notifications (user_id, title, body, action_route)
  select unnest(p_user_ids), p_title, p_body, p_action_route;
end;
$$;


ALTER FUNCTION "public"."notify_users"("p_user_ids" "uuid"[], "p_title" "text", "p_body" "text", "p_action_route" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_thread_participant"("p_thread_id" "uuid", "p_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role::TEXT INTO v_role FROM profiles WHERE id = auth.uid();

  IF v_role NOT IN ('verifier', 'manager') THEN
    RAISE EXCEPTION 'RBAC: only verifiers and managers may remove participants';
  END IF;

  -- Protect the thread creator from being kicked
  IF EXISTS (
    SELECT 1 FROM chat_threads WHERE id = p_thread_id AND created_by = p_user_id
  ) THEN
    RAISE EXCEPTION 'Cannot remove the thread creator';
  END IF;

  DELETE FROM chat_thread_participants
  WHERE thread_id = p_thread_id AND user_id = p_user_id;
END;
$$;


ALTER FUNCTION "public"."remove_thread_participant"("p_thread_id" "uuid", "p_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."resolve_urgent_note"("p_note_id" "uuid", "p_reply" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_note RECORD;
BEGIN
  -- Check if note exists and is not already resolved
  SELECT * INTO v_note
  FROM urgent_notes
  WHERE id = p_note_id AND is_resolved = FALSE;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Urgent note not found or already resolved'
    );
  END IF;
  
  -- Update the note as resolved
  UPDATE urgent_notes
  SET is_resolved = TRUE,
      resolved_by = auth.uid(),
      resolved_at = NOW(),
      reply = p_reply
  WHERE id = p_note_id;
  
  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "public"."resolve_urgent_note"("p_note_id" "uuid", "p_reply" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rls_auto_enable"() RETURNS "event_trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


ALTER FUNCTION "public"."rls_auto_enable"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."rotate_join_code"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_org_id uuid;
  v_code   text;
begin
  if get_user_role() <> 'manager'::user_role or not is_current_user_approved() then
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


ALTER FUNCTION "public"."rotate_join_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."save_device_token"("p_user_id" "uuid", "p_token" "text", "p_platform" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Only the authenticated user can save their own token.
  IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'unauthorized';
  END IF;

  -- If this token was previously registered to a different user
  -- (same device, different account), remove the stale row first.
  DELETE FROM user_devices
  WHERE fcm_token = p_token
    AND user_id  != p_user_id;

  -- Upsert: insert or update the token for this user.
  INSERT INTO user_devices (user_id, fcm_token, platform, last_seen_at)
  VALUES (p_user_id, p_token, p_platform, now())
  ON CONFLICT (fcm_token) DO UPDATE SET
    user_id      = EXCLUDED.user_id,
    platform     = EXCLUDED.platform,
    last_seen_at = EXCLUDED.last_seen_at;
END;
$$;


ALTER FUNCTION "public"."save_device_token"("p_user_id" "uuid", "p_token" "text", "p_platform" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_chat_message"("p_thread_id" "uuid", "p_content" "text", "p_order_mention_id" "uuid" DEFAULT NULL::"uuid", "p_order_mention_text" "text" DEFAULT NULL::"text", "p_user_mention_id" "uuid" DEFAULT NULL::"uuid", "p_user_mention_text" "text" DEFAULT NULL::"text", "p_is_urgent" boolean DEFAULT false) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_message_id UUID;
  v_role       TEXT;
  v_has_access BOOLEAN;
BEGIN
  -- Verify caller has access to this thread (creator or participant)
  SELECT EXISTS (
    SELECT 1 FROM chat_threads ct
    WHERE ct.id = p_thread_id
      AND (
        ct.created_by = auth.uid()
        OR EXISTS (
          SELECT 1 FROM chat_thread_participants
          WHERE thread_id = ct.id AND user_id = auth.uid()
        )
      )
  ) INTO v_has_access;

  IF NOT v_has_access THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  SELECT role::TEXT INTO v_role FROM profiles WHERE id = auth.uid();

  INSERT INTO chat_messages (
    thread_id,
    sender_id,
    sender_name,
    content,
    order_mention_id,
    order_mention_text,
    user_mention_id,
    user_mention_text,
    is_urgent,
    is_acknowledged,
    acknowledged_by
  )
  SELECT
    p_thread_id,
    auth.uid(),
    p.full_name,
    p_content,
    p_order_mention_id,
    p_order_mention_text,
    p_user_mention_id,
    p_user_mention_text,
    p_is_urgent,
    -- Auto-acknowledge when a verifier/manager sends in their own thread
    (v_role IN ('verifier', 'manager')),
    CASE WHEN v_role IN ('verifier', 'manager') THEN auth.uid() ELSE NULL END
  FROM profiles p
  WHERE p.id = auth.uid()
  RETURNING id INTO v_message_id;

  RETURN v_message_id;
END;
$$;


ALTER FUNCTION "public"."send_chat_message"("p_thread_id" "uuid", "p_content" "text", "p_order_mention_id" "uuid", "p_order_mention_text" "text", "p_user_mention_id" "uuid", "p_user_mention_text" "text", "p_is_urgent" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."send_chat_message"("p_thread_id" "uuid", "p_content" "text", "p_order_mention_id" "uuid" DEFAULT NULL::"uuid", "p_order_mention_text" "text" DEFAULT NULL::"text", "p_user_mention_id" "uuid" DEFAULT NULL::"uuid", "p_user_mention_text" "text" DEFAULT NULL::"text", "p_is_urgent" boolean DEFAULT false, "p_reply_to_id" "uuid" DEFAULT NULL::"uuid", "p_reply_to_content" "text" DEFAULT NULL::"text", "p_reply_to_sender" "text" DEFAULT NULL::"text", "p_attachment_url" "text" DEFAULT NULL::"text", "p_attachment_type" "text" DEFAULT NULL::"text", "p_attachment_name" "text" DEFAULT NULL::"text", "p_attachment_size_bytes" bigint DEFAULT NULL::bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_sender_id   UUID := auth.uid();
  v_sender_name TEXT;
BEGIN
  SELECT full_name INTO v_sender_name FROM profiles WHERE id = v_sender_id;

  INSERT INTO chat_messages (
    id, thread_id, sender_id, sender_name, content,
    order_mention_id, order_mention_text,
    user_mention_id,  user_mention_text,
    is_urgent,
    reply_to_id, reply_to_content, reply_to_sender,
    attachment_url, attachment_type, attachment_name, attachment_size_bytes,
    message_type, created_at
  ) VALUES (
    gen_random_uuid(), p_thread_id, v_sender_id, v_sender_name, p_content,
    p_order_mention_id, p_order_mention_text,
    p_user_mention_id,  p_user_mention_text,
    p_is_urgent,
    p_reply_to_id, p_reply_to_content, p_reply_to_sender,
    p_attachment_url, p_attachment_type, p_attachment_name, p_attachment_size_bytes,
    'user', now()
  );
END;
$$;


ALTER FUNCTION "public"."send_chat_message"("p_thread_id" "uuid", "p_content" "text", "p_order_mention_id" "uuid", "p_order_mention_text" "text", "p_user_mention_id" "uuid", "p_user_mention_text" "text", "p_is_urgent" boolean, "p_reply_to_id" "uuid", "p_reply_to_content" "text", "p_reply_to_sender" "text", "p_attachment_url" "text", "p_attachment_type" "text", "p_attachment_name" "text", "p_attachment_size_bytes" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_organization_id"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  new.organization_id := auth_org_id();
  return new;
end
$$;


ALTER FUNCTION "public"."set_organization_id"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."start_move"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order RECORD;
  v_item_count INT;
  v_block_check JSONB;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = target_order_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'Order not found'); END IF;

  SELECT count(*) INTO v_item_count FROM order_items WHERE order_id = target_order_id;
  IF v_item_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب غير صالح لأنه لا يحتوي على عناصر');
  END IF;

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
$$;


ALTER FUNCTION "public"."start_move"("target_order_id" "uuid", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."storage_confirm_delivery"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_final_quantities" "jsonb" DEFAULT '[]'::"jsonb") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order orders%ROWTYPE;
  v_item  order_items%ROWTYPE;
  v_final_qty INT;
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
    SET final_quantity = (p_final_quantities->i->>'quantity')::INT
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


ALTER FUNCTION "public"."storage_confirm_delivery"("target_order_id" "uuid", "p_notes" "text", "p_final_quantities" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."storage_confirm_pickup"("target_order_id" "uuid", "p_notes" "text" DEFAULT NULL::"text", "p_final_quantities" "jsonb" DEFAULT '[]'::"jsonb") RETURNS json
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_order orders%ROWTYPE;
  v_item  order_items%ROWTYPE;
  v_final_qty INT;
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
    SET final_quantity = (p_final_quantities->i->>'quantity')::INT
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


ALTER FUNCTION "public"."storage_confirm_pickup"("target_order_id" "uuid", "p_notes" "text", "p_final_quantities" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_push_on_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  -- Only fire on fresh registrations (is_approved starts as false)
  IF NEW.is_approved = false THEN
    PERFORM net.http_post(
      'https://musaqyislgvshurfrjwx.supabase.co/functions/v1/push-on-new-user'::text,
      jsonb_build_object('type', TG_OP, 'record', row_to_json(NEW))
    );
  END IF;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trigger_push_on_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."trigger_push_on_order_status"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  PERFORM net.http_post(
    'https://musaqyislgvshurfrjwx.supabase.co/functions/v1/push-on-order-status'::text,
    jsonb_build_object(
      'type',       TG_OP,
      'record',     row_to_json(NEW),
      'old_record', CASE WHEN TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE NULL END
    )
  );
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."trigger_push_on_order_status"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_updated_at"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_updated_at"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "action" "text" NOT NULL,
    "old_status" "public"."order_status",
    "new_status" "public"."order_status",
    "performed_by" "uuid" NOT NULL,
    "details" "text",
    "server_timestamp" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notes" "text"
);


ALTER TABLE "public"."audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_type" "text" NOT NULL,
    "thread_id" "uuid",
    "message_id" "uuid",
    "actor_id" "uuid",
    "payload" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."chat_audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_message_reactions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "message_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "emoji" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."chat_message_reactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "thread_id" "uuid" NOT NULL,
    "sender_id" "uuid",
    "sender_name" "text" NOT NULL,
    "content" "text" NOT NULL,
    "order_mention_id" "uuid",
    "order_mention_text" "text",
    "is_urgent" boolean DEFAULT false,
    "is_acknowledged" boolean DEFAULT false,
    "acknowledged_by" "uuid",
    "acknowledged_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "user_mention_id" "uuid",
    "user_mention_text" "text",
    "message_type" "text" DEFAULT 'user'::"text" NOT NULL,
    "reply_to_id" "uuid",
    "reply_to_content" "text",
    "reply_to_sender" "text",
    "action_payload" "jsonb",
    "attachment_url" "text",
    "attachment_type" "text",
    "attachment_name" "text",
    "attachment_size_bytes" bigint
);


ALTER TABLE "public"."chat_messages" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_thread_participants" (
    "thread_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "added_by" "uuid" NOT NULL,
    "added_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."chat_thread_participants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chat_threads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "title" "text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "is_direct" boolean DEFAULT false NOT NULL,
    "system_messages_enabled" boolean DEFAULT true NOT NULL,
    "direct_pair_key" "text",
    "organization_id" "uuid"
);


ALTER TABLE "public"."chat_threads" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."entities" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "contact_name" "text",
    "contact_phone" "text",
    "address" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "category" "public"."entity_category" DEFAULT 'unassigned'::"public"."entity_category" NOT NULL,
    "organization_id" "uuid"
);


ALTER TABLE "public"."entities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "item_name" "text" NOT NULL,
    "sku" "text",
    "quantity" integer DEFAULT 0 NOT NULL,
    "min_threshold" integer DEFAULT 0,
    "unit" "text" DEFAULT 'piece'::"text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "category" "text",
    "min_quantity" integer DEFAULT 0 NOT NULL,
    "description" "text",
    "notes" "text",
    "archived_at" timestamp with time zone,
    "organization_id" "uuid",
    CONSTRAINT "inventory_quantity_check" CHECK (("quantity" >= 0))
);


ALTER TABLE "public"."inventory" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."inventory_audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "item_id" "uuid" NOT NULL,
    "action" "text" NOT NULL,
    "old_quantity" integer,
    "new_quantity" integer,
    "performed_by" "uuid",
    "notes" "text",
    "performed_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."inventory_audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "title" "text" NOT NULL,
    "body" "text" NOT NULL,
    "action_route" "text",
    "is_read" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_edit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "performed_by" "uuid" NOT NULL,
    "reason" "text" NOT NULL,
    "changes" "jsonb" NOT NULL,
    "server_timestamp" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."order_edit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "inventory_id" "uuid",
    "quantity" integer NOT NULL,
    "is_custom" boolean DEFAULT false,
    "custom_description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "check_status" "public"."item_check_status" DEFAULT 'pending'::"public"."item_check_status" NOT NULL,
    "checked_by" "uuid",
    "checked_at" timestamp with time zone,
    "final_quantity" integer,
    "source_inventory_id" "uuid",
    "was_unavailable_at_creation" boolean DEFAULT false NOT NULL,
    CONSTRAINT "custom_item_check" CHECK (((("is_custom" = true) AND ("custom_description" IS NOT NULL) AND ("inventory_id" IS NULL)) OR (("is_custom" = false) AND ("inventory_id" IS NOT NULL) AND ("custom_description" IS NULL)))),
    CONSTRAINT "order_items_quantity_check" CHECK (("quantity" > 0))
);


ALTER TABLE "public"."order_items" OWNER TO "postgres";


COMMENT ON COLUMN "public"."order_items"."was_unavailable_at_creation" IS 'True if inventory quantity was 0 when this order item was created. Frozen at creation time; never changes.';



CREATE TABLE IF NOT EXISTS "public"."order_template_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "template_id" "uuid" NOT NULL,
    "inventory_id" "uuid",
    "inventory_name" "text",
    "quantity" integer NOT NULL,
    "is_custom" boolean DEFAULT false NOT NULL,
    "custom_description" "text",
    "source_inventory_id" "uuid"
);


ALTER TABLE "public"."order_template_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."order_templates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "entity_id" "uuid" NOT NULL,
    "direction" "text" NOT NULL,
    "rep_id" "uuid",
    "notes" "text",
    "is_manual" boolean DEFAULT false NOT NULL,
    "usage_count" integer DEFAULT 1 NOT NULL,
    "fingerprint" "text" NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" "uuid",
    CONSTRAINT "order_templates_direction_check" CHECK (("direction" = ANY (ARRAY['outbound'::"text", 'inbound_rep'::"text", 'inbound_external'::"text"])))
);


ALTER TABLE "public"."order_templates" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orders" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "direction" "public"."order_direction" NOT NULL,
    "entity_id" "uuid" NOT NULL,
    "rep_id" "uuid",
    "status" "public"."order_status" DEFAULT 'assigned'::"public"."order_status" NOT NULL,
    "notes" "text",
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "assigned_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "picked_up_at" timestamp with time zone,
    "move_started_at" timestamp with time zone,
    "delivered_at" timestamp with time zone,
    "storage_actor_id" "uuid",
    "reference_code" "text",
    "organization_id" "uuid",
    CONSTRAINT "rep_required_check" CHECK (((("direction" = 'inbound_external'::"public"."order_direction") AND ("rep_id" IS NULL)) OR (("direction" <> 'inbound_external'::"public"."order_direction") AND ("rep_id" IS NOT NULL))))
);


ALTER TABLE "public"."orders" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."organizations" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "slug" "text",
    "join_code" "text" NOT NULL,
    "is_discoverable" boolean DEFAULT true NOT NULL,
    "created_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "description" "text",
    "address" "text",
    "contact_email" "text",
    "contact_phone" "text"
);


ALTER TABLE "public"."organizations" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "full_name" "text" NOT NULL,
    "phone" "text",
    "role" "public"."user_role" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "is_approved" boolean DEFAULT false NOT NULL,
    "organization_id" "uuid"
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."receipts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "image_url" "text" NOT NULL,
    "uploaded_by" "uuid" NOT NULL,
    "uploaded_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "order_item_id" "uuid"
);


ALTER TABLE "public"."receipts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."urgent_notes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "order_id" "uuid" NOT NULL,
    "stage" "public"."order_status" NOT NULL,
    "message" "text" NOT NULL,
    "created_by" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "is_resolved" boolean DEFAULT false,
    "resolved_by" "uuid",
    "resolved_at" timestamp with time zone,
    "reply" "text",
    CONSTRAINT "valid_stage" CHECK (("stage" = ANY (ARRAY['assigned'::"public"."order_status", 'picked_up'::"public"."order_status", 'on_the_move'::"public"."order_status"])))
);


ALTER TABLE "public"."urgent_notes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "fcm_token" "text" NOT NULL,
    "platform" "text" NOT NULL,
    "last_seen_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "user_devices_platform_check" CHECK (("platform" = ANY (ARRAY['android'::"text", 'ios'::"text", 'web'::"text"])))
);


ALTER TABLE "public"."user_devices" OWNER TO "postgres";


ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_audit_log"
    ADD CONSTRAINT "chat_audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_message_reactions"
    ADD CONSTRAINT "chat_message_reactions_message_id_user_id_emoji_key" UNIQUE ("message_id", "user_id", "emoji");



ALTER TABLE ONLY "public"."chat_message_reactions"
    ADD CONSTRAINT "chat_message_reactions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chat_thread_participants"
    ADD CONSTRAINT "chat_thread_participants_pkey" PRIMARY KEY ("thread_id", "user_id");



ALTER TABLE ONLY "public"."chat_threads"
    ADD CONSTRAINT "chat_threads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."entities"
    ADD CONSTRAINT "entities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory_audit_log"
    ADD CONSTRAINT "inventory_audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_sku_key" UNIQUE ("sku");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_action_unique" UNIQUE ("user_id", "action_route");



ALTER TABLE ONLY "public"."order_edit_log"
    ADD CONSTRAINT "order_edit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_template_items"
    ADD CONSTRAINT "order_template_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."order_templates"
    ADD CONSTRAINT "order_templates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_join_code_key" UNIQUE ("join_code");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_slug_key" UNIQUE ("slug");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."urgent_notes"
    ADD CONSTRAINT "urgent_notes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_fcm_token_key" UNIQUE ("fcm_token");



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "chat_threads_direct_pair_uq" ON "public"."chat_threads" USING "btree" ("direct_pair_key") WHERE ("is_direct" = true);



CREATE INDEX "chat_threads_org_idx" ON "public"."chat_threads" USING "btree" ("organization_id");



CREATE INDEX "entities_org_idx" ON "public"."entities" USING "btree" ("organization_id");



CREATE INDEX "idx_audit_log_order_id" ON "public"."audit_log" USING "btree" ("order_id");



CREATE INDEX "idx_chat_messages_mention" ON "public"."chat_messages" USING "btree" ("order_mention_id") WHERE ("order_mention_id" IS NOT NULL);



CREATE INDEX "idx_chat_messages_thread" ON "public"."chat_messages" USING "btree" ("thread_id", "created_at" DESC);



CREATE INDEX "idx_chat_messages_urgent" ON "public"."chat_messages" USING "btree" ("is_urgent", "is_acknowledged") WHERE ("is_urgent" = true);



CREATE INDEX "idx_ctp_thread_id" ON "public"."chat_thread_participants" USING "btree" ("thread_id");



CREATE INDEX "idx_ctp_user_id" ON "public"."chat_thread_participants" USING "btree" ("user_id");



CREATE INDEX "idx_inventory_sku" ON "public"."inventory" USING "btree" ("sku");



CREATE INDEX "idx_order_edit_log_order" ON "public"."order_edit_log" USING "btree" ("order_id", "server_timestamp" DESC);



CREATE INDEX "idx_order_items_order_id" ON "public"."order_items" USING "btree" ("order_id");



CREATE INDEX "idx_orders_created_by" ON "public"."orders" USING "btree" ("created_by");



CREATE INDEX "idx_orders_entity_id" ON "public"."orders" USING "btree" ("entity_id");



CREATE INDEX "idx_orders_rep_id" ON "public"."orders" USING "btree" ("rep_id");



CREATE INDEX "idx_orders_status" ON "public"."orders" USING "btree" ("status");



CREATE INDEX "idx_receipts_order_id" ON "public"."receipts" USING "btree" ("order_id");



CREATE INDEX "idx_urgent_notes_all_pending" ON "public"."urgent_notes" USING "btree" ("created_at" DESC) WHERE ("is_resolved" = false);



CREATE INDEX "idx_urgent_notes_order" ON "public"."urgent_notes" USING "btree" ("order_id", "created_at" DESC);



CREATE INDEX "idx_urgent_notes_pending" ON "public"."urgent_notes" USING "btree" ("order_id", "stage") WHERE ("is_resolved" = false);



CREATE INDEX "inventory_active_idx" ON "public"."inventory" USING "btree" ("item_name") WHERE ("archived_at" IS NULL);



CREATE INDEX "inventory_org_idx" ON "public"."inventory" USING "btree" ("organization_id");



CREATE INDEX "notifications_user_id_is_read_created_at_idx" ON "public"."notifications" USING "btree" ("user_id", "is_read", "created_at" DESC);



CREATE UNIQUE INDEX "order_templates_entity_fingerprint" ON "public"."order_templates" USING "btree" ("entity_id", "fingerprint");



CREATE INDEX "order_templates_org_idx" ON "public"."order_templates" USING "btree" ("organization_id");



CREATE INDEX "orders_org_idx" ON "public"."orders" USING "btree" ("organization_id");



CREATE UNIQUE INDEX "orders_reference_code_key" ON "public"."orders" USING "btree" ("reference_code") WHERE ("reference_code" IS NOT NULL);



CREATE INDEX "profiles_org_idx" ON "public"."profiles" USING "btree" ("organization_id");



CREATE INDEX "user_devices_user_id_idx" ON "public"."user_devices" USING "btree" ("user_id");



CREATE OR REPLACE TRIGGER "chat_messages_after_insert" AFTER INSERT ON "public"."chat_messages" FOR EACH ROW EXECUTE FUNCTION "public"."notify_chat_message"();



CREATE OR REPLACE TRIGGER "inventory_updated_at" BEFORE UPDATE ON "public"."inventory" FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at"();



CREATE OR REPLACE TRIGGER "on-chat-message" AFTER INSERT ON "public"."chat_messages" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://musaqyislgvshurfrjwx.supabase.co/functions/v1/push-on-chat-message', 'POST', '{"Authorization":"Bearer ura_webhook_2024"}', '{}', '5000');



CREATE OR REPLACE TRIGGER "on_new_user_registered" AFTER INSERT ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_push_on_new_user"();



CREATE OR REPLACE TRIGGER "on_order_status_change" AFTER INSERT OR UPDATE OF "status" ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."trigger_push_on_order_status"();



CREATE OR REPLACE TRIGGER "order_status_audit" AFTER UPDATE ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."log_order_status_change"();



CREATE OR REPLACE TRIGGER "orders_after_insert" AFTER INSERT ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."notify_order_created"();



CREATE OR REPLACE TRIGGER "orders_after_status_update" AFTER UPDATE OF "status" ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."notify_order_status_change"();



CREATE OR REPLACE TRIGGER "orders_log_creation" AFTER INSERT ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."log_order_created"();



CREATE OR REPLACE TRIGGER "profiles_after_approval_update" AFTER UPDATE OF "is_approved" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."notify_user_approved"();



CREATE OR REPLACE TRIGGER "profiles_after_insert" AFTER INSERT ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."notify_new_signup"();



CREATE OR REPLACE TRIGGER "set_org_id_chat_threads" BEFORE INSERT ON "public"."chat_threads" FOR EACH ROW EXECUTE FUNCTION "public"."set_organization_id"();



CREATE OR REPLACE TRIGGER "set_org_id_entities" BEFORE INSERT ON "public"."entities" FOR EACH ROW EXECUTE FUNCTION "public"."set_organization_id"();



CREATE OR REPLACE TRIGGER "set_org_id_inventory" BEFORE INSERT ON "public"."inventory" FOR EACH ROW EXECUTE FUNCTION "public"."set_organization_id"();



CREATE OR REPLACE TRIGGER "set_org_id_order_templates" BEFORE INSERT ON "public"."order_templates" FOR EACH ROW EXECUTE FUNCTION "public"."set_organization_id"();



CREATE OR REPLACE TRIGGER "set_org_id_orders" BEFORE INSERT ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."set_organization_id"();



CREATE OR REPLACE TRIGGER "trg_chat_audit" AFTER INSERT OR UPDATE ON "public"."chat_messages" FOR EACH ROW EXECUTE FUNCTION "public"."log_chat_event"();



CREATE OR REPLACE TRIGGER "trg_order_status_chat_message" AFTER UPDATE OF "status" ON "public"."orders" FOR EACH ROW EXECUTE FUNCTION "public"."auto_post_order_status_message"();



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."audit_log"
    ADD CONSTRAINT "audit_log_performed_by_fkey" FOREIGN KEY ("performed_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."chat_audit_log"
    ADD CONSTRAINT "chat_audit_log_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."chat_messages"("id");



ALTER TABLE ONLY "public"."chat_audit_log"
    ADD CONSTRAINT "chat_audit_log_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."chat_threads"("id");



ALTER TABLE ONLY "public"."chat_message_reactions"
    ADD CONSTRAINT "chat_message_reactions_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."chat_messages"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_message_reactions"
    ADD CONSTRAINT "chat_message_reactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_acknowledged_by_fkey" FOREIGN KEY ("acknowledged_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_order_mention_id_fkey" FOREIGN KEY ("order_mention_id") REFERENCES "public"."orders"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_reply_to_id_fkey" FOREIGN KEY ("reply_to_id") REFERENCES "public"."chat_messages"("id");



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."chat_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_messages"
    ADD CONSTRAINT "chat_messages_user_mention_id_fkey" FOREIGN KEY ("user_mention_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."chat_thread_participants"
    ADD CONSTRAINT "chat_thread_participants_added_by_fkey" FOREIGN KEY ("added_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."chat_thread_participants"
    ADD CONSTRAINT "chat_thread_participants_thread_id_fkey" FOREIGN KEY ("thread_id") REFERENCES "public"."chat_threads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_thread_participants"
    ADD CONSTRAINT "chat_thread_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chat_threads"
    ADD CONSTRAINT "chat_threads_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."chat_threads"
    ADD CONSTRAINT "chat_threads_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."entities"
    ADD CONSTRAINT "entities_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."inventory_audit_log"
    ADD CONSTRAINT "inventory_audit_log_item_id_fkey" FOREIGN KEY ("item_id") REFERENCES "public"."inventory"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."inventory_audit_log"
    ADD CONSTRAINT "inventory_audit_log_performed_by_fkey" FOREIGN KEY ("performed_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."inventory"
    ADD CONSTRAINT "inventory_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_edit_log"
    ADD CONSTRAINT "order_edit_log_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_edit_log"
    ADD CONSTRAINT "order_edit_log_performed_by_fkey" FOREIGN KEY ("performed_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_checked_by_fkey" FOREIGN KEY ("checked_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_inventory_id_fkey" FOREIGN KEY ("inventory_id") REFERENCES "public"."inventory"("id");



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_items"
    ADD CONSTRAINT "order_items_source_inventory_id_fkey" FOREIGN KEY ("source_inventory_id") REFERENCES "public"."inventory"("id");



ALTER TABLE ONLY "public"."order_template_items"
    ADD CONSTRAINT "order_template_items_inventory_id_fkey" FOREIGN KEY ("inventory_id") REFERENCES "public"."inventory"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."order_template_items"
    ADD CONSTRAINT "order_template_items_source_inventory_id_fkey" FOREIGN KEY ("source_inventory_id") REFERENCES "public"."inventory"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."order_template_items"
    ADD CONSTRAINT "order_template_items_template_id_fkey" FOREIGN KEY ("template_id") REFERENCES "public"."order_templates"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_templates"
    ADD CONSTRAINT "order_templates_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."order_templates"
    ADD CONSTRAINT "order_templates_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "public"."entities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."order_templates"
    ADD CONSTRAINT "order_templates_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."order_templates"
    ADD CONSTRAINT "order_templates_rep_id_fkey" FOREIGN KEY ("rep_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "public"."entities"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_rep_id_fkey" FOREIGN KEY ("rep_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."orders"
    ADD CONSTRAINT "orders_storage_actor_id_fkey" FOREIGN KEY ("storage_actor_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."organizations"
    ADD CONSTRAINT "organizations_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_order_item_id_fkey" FOREIGN KEY ("order_item_id") REFERENCES "public"."order_items"("id");



ALTER TABLE ONLY "public"."receipts"
    ADD CONSTRAINT "receipts_uploaded_by_fkey" FOREIGN KEY ("uploaded_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."urgent_notes"
    ADD CONSTRAINT "urgent_notes_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."urgent_notes"
    ADD CONSTRAINT "urgent_notes_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."urgent_notes"
    ADD CONSTRAINT "urgent_notes_resolved_by_fkey" FOREIGN KEY ("resolved_by") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."user_devices"
    ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Approved users can view entities" ON "public"."entities" FOR SELECT USING (((( SELECT "profiles"."is_approved"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())) = true) AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())));



CREATE POLICY "Approved users can view inventory" ON "public"."inventory" FOR SELECT USING (((( SELECT "profiles"."is_approved"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())) = true) AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())));



CREATE POLICY "Managers can update any profile" ON "public"."profiles" FOR UPDATE USING ((("public"."get_user_role"() = 'manager'::"public"."user_role") AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())));



CREATE POLICY "Managers can view all audit logs" ON "public"."audit_log" FOR SELECT USING ((("public"."get_user_role"() = 'manager'::"public"."user_role") AND (EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "audit_log"."order_id") AND (("orders"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()))))));



CREATE POLICY "Managers can view all orders" ON "public"."orders" FOR SELECT USING ((("public"."get_user_role"() = 'manager'::"public"."user_role") AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())));



CREATE POLICY "Managers can view all profiles" ON "public"."profiles" FOR SELECT USING ((("public"."get_user_role"() = 'manager'::"public"."user_role") AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())));



CREATE POLICY "Profile visibility based on approval" ON "public"."profiles" FOR SELECT USING (
CASE
    WHEN ("public"."is_current_user_approved"() = true) THEN (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
    ELSE ("id" = "auth"."uid"())
END);



CREATE POLICY "Reps can upload receipts" ON "public"."receipts" FOR INSERT WITH CHECK ((("public"."get_user_role"() = 'rep'::"public"."user_role") AND (EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "receipts"."order_id") AND ("orders"."rep_id" = "auth"."uid"()))))));



CREATE POLICY "Role-based audit log visibility" ON "public"."audit_log" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "audit_log"."order_id") AND (("orders"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())))));



CREATE POLICY "Role-based order updates" ON "public"."orders" FOR UPDATE USING (((("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()) AND
CASE "public"."get_user_role"()
    WHEN 'verifier'::"public"."user_role" THEN true
    WHEN 'rep'::"public"."user_role" THEN ("rep_id" = "auth"."uid"())
    WHEN 'storage_actor'::"public"."user_role" THEN ("status" = ANY (ARRAY['assigned'::"public"."order_status", 'picked_up'::"public"."order_status"]))
    ELSE false
END));



CREATE POLICY "Role-based order visibility" ON "public"."orders" FOR SELECT USING (((( SELECT "profiles"."is_approved"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())) = true) AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()) AND
CASE "public"."get_user_role"()
    WHEN 'verifier'::"public"."user_role" THEN true
    WHEN 'rep'::"public"."user_role" THEN ("rep_id" = "auth"."uid"())
    WHEN 'storage_actor'::"public"."user_role" THEN ("status" = ANY (ARRAY['assigned'::"public"."order_status", 'picked_up'::"public"."order_status"]))
    ELSE false
END));



CREATE POLICY "Storage actors can check order items" ON "public"."order_items" FOR UPDATE USING ((("public"."get_user_role"() = 'storage_actor'::"public"."user_role") AND (EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "order_items"."order_id") AND ("orders"."status" = 'assigned'::"public"."order_status"))))));



CREATE POLICY "System can insert audit logs" ON "public"."audit_log" FOR INSERT WITH CHECK (true);



CREATE POLICY "Users can manage own reactions" ON "public"."chat_message_reactions" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "Users can read reactions" ON "public"."chat_message_reactions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM ("public"."chat_messages" "m"
     JOIN "public"."chat_threads" "ct" ON (("ct"."id" = "m"."thread_id")))
  WHERE (("m"."id" = "chat_message_reactions"."message_id") AND (("ct"."created_by" = "auth"."uid"()) OR (EXISTS ( SELECT 1
           FROM "public"."chat_thread_participants"
          WHERE (("chat_thread_participants"."thread_id" = "ct"."id") AND ("chat_thread_participants"."user_id" = "auth"."uid"())))) OR "public"."is_platform_admin"())))));



CREATE POLICY "Users can update own profile" ON "public"."profiles" FOR UPDATE USING (("id" = "auth"."uid"()));



CREATE POLICY "Users can view items of visible orders" ON "public"."order_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE ("orders"."id" = "order_items"."order_id"))));



CREATE POLICY "Users can view receipts of visible orders" ON "public"."receipts" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE ("orders"."id" = "receipts"."order_id"))));



CREATE POLICY "Verifiers and managers can create entities" ON "public"."entities" FOR INSERT WITH CHECK (("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role"])));



CREATE POLICY "Verifiers and managers can delete entities" ON "public"."entities" FOR DELETE USING ((("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role"])) AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())));



CREATE POLICY "Verifiers and managers can update entities" ON "public"."entities" FOR UPDATE USING ((("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'manager'::"public"."user_role"])) AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())));



CREATE POLICY "Verifiers and storage can create inventory" ON "public"."inventory" FOR INSERT WITH CHECK (("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'storage_actor'::"public"."user_role"])));



CREATE POLICY "Verifiers and storage can update inventory" ON "public"."inventory" FOR UPDATE USING ((("public"."get_user_role"() = ANY (ARRAY['verifier'::"public"."user_role", 'storage_actor'::"public"."user_role"])) AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())));



CREATE POLICY "Verifiers can add order items" ON "public"."order_items" FOR INSERT WITH CHECK ((("public"."get_user_role"() = 'verifier'::"public"."user_role") AND (EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "order_items"."order_id") AND (("orders"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()))))));



CREATE POLICY "Verifiers can create orders" ON "public"."orders" FOR INSERT WITH CHECK (("public"."get_user_role"() = 'verifier'::"public"."user_role"));



CREATE POLICY "Verifiers can delete their own non-delivered orders" ON "public"."orders" FOR DELETE TO "authenticated" USING ((("created_by" = "auth"."uid"()) AND (( SELECT "profiles"."role"
   FROM "public"."profiles"
  WHERE ("profiles"."id" = "auth"."uid"())) = 'verifier'::"public"."user_role") AND ("status" <> 'delivered'::"public"."order_status")));



CREATE POLICY "Verifiers can update order items" ON "public"."order_items" FOR UPDATE USING ((("public"."get_user_role"() = 'verifier'::"public"."user_role") AND (EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "order_items"."order_id") AND (("orders"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()))))));



CREATE POLICY "approved_users_can_view_edit_log" ON "public"."order_edit_log" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."is_approved" = true)))) AND (EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "order_edit_log"."order_id") AND (("orders"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()))))));



CREATE POLICY "approved_users_read_all_order_items" ON "public"."order_items" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."is_approved" = true)))));



CREATE POLICY "approved_users_read_all_orders" ON "public"."orders" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."is_approved" = true)))) AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())));



ALTER TABLE "public"."audit_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "auth_can_acknowledge" ON "public"."chat_messages" FOR UPDATE USING ((EXISTS ( SELECT 1
   FROM "public"."chat_threads" "ct"
  WHERE (("ct"."id" = "chat_messages"."thread_id") AND (("ct"."created_by" = "auth"."uid"()) OR (EXISTS ( SELECT 1
           FROM "public"."chat_thread_participants"
          WHERE (("chat_thread_participants"."thread_id" = "ct"."id") AND ("chat_thread_participants"."user_id" = "auth"."uid"()))))))))) WITH CHECK ((("is_acknowledged" = true) AND ("acknowledged_by" = "auth"."uid"())));



ALTER TABLE "public"."chat_audit_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_message_reactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_thread_participants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chat_threads" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "deny_direct_insert_participants" ON "public"."chat_thread_participants" FOR INSERT WITH CHECK (false);



CREATE POLICY "deny_direct_message_insert" ON "public"."chat_messages" FOR INSERT WITH CHECK (false);



CREATE POLICY "deny_direct_thread_insert" ON "public"."chat_threads" FOR INSERT WITH CHECK (false);



ALTER TABLE "public"."entities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "inbound_external_restricted" ON "public"."orders" FOR SELECT USING (((("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()) AND (("direction" <> 'inbound_external'::"public"."order_direction") OR (("auth"."jwt"() ->> 'role'::"text") = ANY (ARRAY['verifier'::"text", 'storage_actor'::"text", 'manager'::"text"])))));



ALTER TABLE "public"."inventory" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."inventory_audit_log" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "managers can update own org info" ON "public"."organizations" FOR UPDATE TO "authenticated" USING ((("id" = "public"."auth_org_id"()) AND ("public"."get_user_role"() = 'manager'::"public"."user_role") AND "public"."is_current_user_approved"())) WITH CHECK ((("id" = "public"."auth_org_id"()) AND ("public"."get_user_role"() = 'manager'::"public"."user_role") AND "public"."is_current_user_approved"()));



ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."order_edit_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."order_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."order_template_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."order_templates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."orders" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "org_isolation" ON "public"."order_template_items" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."order_templates" "t"
  WHERE (("t"."id" = "order_template_items"."template_id") AND (("t"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."order_templates" "t"
  WHERE (("t"."id" = "order_template_items"."template_id") AND (("t"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())))));



CREATE POLICY "org_isolation" ON "public"."order_templates" TO "authenticated" USING ((("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())) WITH CHECK ((("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()));



CREATE POLICY "org_read_own" ON "public"."organizations" FOR SELECT TO "authenticated" USING ((("id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()));



ALTER TABLE "public"."organizations" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "own notifications" ON "public"."notifications" USING (("auth"."uid"() = "user_id"));



CREATE POLICY "participant_can_read_own_rows" ON "public"."chat_thread_participants" FOR SELECT USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "read_accessible_thread_messages" ON "public"."chat_messages" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."chat_threads" "ct"
  WHERE (("ct"."id" = "chat_messages"."thread_id") AND (("ct"."created_by" = "auth"."uid"()) OR (EXISTS ( SELECT 1
           FROM "public"."chat_thread_participants"
          WHERE (("chat_thread_participants"."thread_id" = "ct"."id") AND ("chat_thread_participants"."user_id" = "auth"."uid"())))))))));



CREATE POLICY "read_own_or_participant_threads" ON "public"."chat_threads" FOR SELECT USING ((("created_by" = "auth"."uid"()) OR (EXISTS ( SELECT 1
   FROM "public"."chat_thread_participants"
  WHERE (("chat_thread_participants"."thread_id" = "chat_threads"."id") AND ("chat_thread_participants"."user_id" = "auth"."uid"()))))));



ALTER TABLE "public"."receipts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reps_can_create_urgent_notes" ON "public"."urgent_notes" FOR INSERT WITH CHECK (((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."role" = 'rep'::"public"."user_role") AND ("profiles"."is_approved" = true)))) AND (EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "urgent_notes"."order_id") AND ("orders"."rep_id" = "auth"."uid"()))))));



CREATE POLICY "reps_can_view_own_urgent_notes" ON "public"."urgent_notes" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "urgent_notes"."order_id") AND ("orders"."rep_id" = "auth"."uid"())))));



ALTER TABLE "public"."urgent_notes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user deletes own device" ON "public"."user_devices" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "user inserts own device" ON "public"."user_devices" FOR INSERT WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "user reads own devices" ON "public"."user_devices" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "user updates own device" ON "public"."user_devices" FOR UPDATE USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."user_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "verifiers_can_insert_edit_log" ON "public"."order_edit_log" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."role" = 'verifier'::"public"."user_role") AND ("profiles"."is_approved" = true)))));



CREATE POLICY "verifiers_can_resolve_urgent_notes" ON "public"."urgent_notes" FOR UPDATE USING (((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."role" = 'verifier'::"public"."user_role") AND ("profiles"."is_approved" = true)))) AND (EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "urgent_notes"."order_id") AND (("orders"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())))))) WITH CHECK ((("is_resolved" = true) AND ("resolved_by" = "auth"."uid"()) AND ("resolved_at" = "now"())));



CREATE POLICY "verifiers_can_view_all_urgent_notes" ON "public"."urgent_notes" FOR SELECT USING (((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."role" = 'verifier'::"public"."user_role") AND ("profiles"."is_approved" = true)))) AND (EXISTS ( SELECT 1
   FROM "public"."orders"
  WHERE (("orders"."id" = "urgent_notes"."order_id") AND (("orders"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"()))))));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."_gen_order_reference_code"() TO "anon";
GRANT ALL ON FUNCTION "public"."_gen_order_reference_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."_gen_order_reference_code"() TO "service_role";



GRANT ALL ON FUNCTION "public"."acknowledge_chat_message"("p_message_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."acknowledge_chat_message"("p_message_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."acknowledge_chat_message"("p_message_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."add_thread_participant"("p_thread_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."add_thread_participant"("p_thread_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."add_thread_participant"("p_thread_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_list_orgs"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_orgs"() TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_rotate_join_code"("p_org_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_rotate_join_code"("p_org_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_set_discoverable"("p_org_id" "uuid", "p_value" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_set_discoverable"("p_org_id" "uuid", "p_value" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."approve_order"("target_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."approve_order"("target_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_order"("target_order_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."approve_transaction"("target_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."approve_transaction"("target_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_transaction"("target_order_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."approve_user"("target_user_id" "uuid", "assigned_role" "public"."user_role") TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_user"("target_user_id" "uuid", "assigned_role" "public"."user_role") TO "service_role";



GRANT ALL ON FUNCTION "public"."auth_org_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auth_org_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_post_order_status_message"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_post_order_status_message"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_post_order_status_message"() TO "service_role";



GRANT ALL ON FUNCTION "public"."check_order_item"("target_item_id" "uuid", "new_status" "public"."item_check_status") TO "anon";
GRANT ALL ON FUNCTION "public"."check_order_item"("target_item_id" "uuid", "new_status" "public"."item_check_status") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_order_item"("target_item_id" "uuid", "new_status" "public"."item_check_status") TO "service_role";



GRANT ALL ON FUNCTION "public"."check_urgent_notes_block"("p_order_id" "uuid", "p_current_stage" "public"."order_status") TO "anon";
GRANT ALL ON FUNCTION "public"."check_urgent_notes_block"("p_order_id" "uuid", "p_current_stage" "public"."order_status") TO "authenticated";
GRANT ALL ON FUNCTION "public"."check_urgent_notes_block"("p_order_id" "uuid", "p_current_stage" "public"."order_status") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_chat_thread"("p_title" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_chat_thread"("p_title" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_chat_thread"("p_title" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_order_with_items"("p_direction" "text", "p_entity_id" "uuid", "p_rep_id" "uuid", "p_notes" "text", "p_items" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."create_order_with_items"("p_direction" "text", "p_entity_id" "uuid", "p_rep_id" "uuid", "p_notes" "text", "p_items" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_order_with_items"("p_direction" "text", "p_entity_id" "uuid", "p_rep_id" "uuid", "p_notes" "text", "p_items" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_organization_and_owner"("p_org_name" "text", "p_full_name" "text", "p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_organization_and_owner"("p_org_name" "text", "p_full_name" "text", "p_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."create_urgent_note"("p_order_id" "uuid", "p_stage" "public"."order_status", "p_message" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."create_urgent_note"("p_order_id" "uuid", "p_stage" "public"."order_status", "p_message" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_urgent_note"("p_order_id" "uuid", "p_stage" "public"."order_status", "p_message" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_chat_thread"("p_thread_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."delete_chat_thread"("p_thread_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_chat_thread"("p_thread_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."dispatch_push"("user_ids" "uuid"[], "title" "text", "body" "text", "data" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."dispatch_push"("user_ids" "uuid"[], "title" "text", "body" "text", "data" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."dispatch_push"("user_ids" "uuid"[], "title" "text", "body" "text", "data" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."edit_order_items"("p_order_id" "uuid", "p_reason" "text", "p_updates" "jsonb", "p_removals" "uuid"[], "p_additions" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."edit_order_items"("p_order_id" "uuid", "p_reason" "text", "p_updates" "jsonb", "p_removals" "uuid"[], "p_additions" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."edit_order_items"("p_order_id" "uuid", "p_reason" "text", "p_updates" "jsonb", "p_removals" "uuid"[], "p_additions" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."gen_join_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."gen_join_code"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_all_pending_urgent_notes"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_all_pending_urgent_notes"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_all_pending_urgent_notes"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_entity_frequency"("p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_limit" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."get_entity_frequency"("p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_entity_frequency"("p_start" timestamp with time zone, "p_end" timestamp with time zone, "p_limit" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_global_stats_overview"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_global_stats_overview"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_global_stats_overview"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_or_create_direct_thread"("p_other_user_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_or_create_direct_thread"("p_other_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_or_create_direct_thread"("p_other_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_or_create_direct_thread"("p_other_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_orders_monthly_summary"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_orders_monthly_summary"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_orders_monthly_summary"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_pending_urgent_notes"("p_order_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_pending_urgent_notes"("p_order_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_pending_urgent_notes"("p_order_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_pending_urgent_notes_count"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_pending_urgent_notes_count"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_pending_urgent_notes_count"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_rep_performance_stats"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."get_rep_performance_stats"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_rep_performance_stats"("p_start" timestamp with time zone, "p_end" timestamp with time zone) TO "service_role";



GRANT ALL ON FUNCTION "public"."get_thread_participants"("p_thread_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_thread_participants"("p_thread_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_thread_participants"("p_thread_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."get_thread_reactions"("p_thread_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."get_thread_reactions"("p_thread_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_thread_reactions"("p_thread_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_threads_with_preview"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_threads_with_preview"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_threads_with_preview"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_threads_with_preview"() TO "service_role";



GRANT ALL ON FUNCTION "public"."get_user_role"() TO "anon";
GRANT ALL ON FUNCTION "public"."get_user_role"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_user_role"() TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_inventory_bulk"("p_deltas" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."increment_inventory_bulk"("p_deltas" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_inventory_bulk"("p_deltas" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_template_usage"("p_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."increment_template_usage"("p_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_template_usage"("p_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."inventory_bulk_update_quantities"("p_updates" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."inventory_bulk_update_quantities"("p_updates" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inventory_bulk_update_quantities"("p_updates" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."inventory_create_item"("p_name" "text", "p_unit" "text", "p_quantity" integer, "p_sku" "text", "p_category" "text", "p_min_quantity" integer, "p_description" "text", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."inventory_create_item"("p_name" "text", "p_unit" "text", "p_quantity" integer, "p_sku" "text", "p_category" "text", "p_min_quantity" integer, "p_description" "text", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inventory_create_item"("p_name" "text", "p_unit" "text", "p_quantity" integer, "p_sku" "text", "p_category" "text", "p_min_quantity" integer, "p_description" "text", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."inventory_delete_item"("p_item_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."inventory_delete_item"("p_item_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inventory_delete_item"("p_item_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."inventory_update_item"("p_item_id" "uuid", "p_name" "text", "p_unit" "text", "p_quantity" integer, "p_sku" "text", "p_category" "text", "p_min_quantity" integer, "p_description" "text", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."inventory_update_item"("p_item_id" "uuid", "p_name" "text", "p_unit" "text", "p_quantity" integer, "p_sku" "text", "p_category" "text", "p_min_quantity" integer, "p_description" "text", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inventory_update_item"("p_item_id" "uuid", "p_name" "text", "p_unit" "text", "p_quantity" integer, "p_sku" "text", "p_category" "text", "p_min_quantity" integer, "p_description" "text", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_current_user_approved"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_current_user_approved"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_current_user_approved"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_platform_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_platform_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_platform_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."join_organization_by_code"("p_code" "text", "p_full_name" "text", "p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."join_organization_by_code"("p_code" "text", "p_full_name" "text", "p_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."join_organization_by_id"("p_org_id" "uuid", "p_full_name" "text", "p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."join_organization_by_id"("p_org_id" "uuid", "p_full_name" "text", "p_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."list_discoverable_orgs"("p_search" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."list_discoverable_orgs"("p_search" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."list_discoverable_orgs"("p_search" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."log_chat_event"() TO "anon";
GRANT ALL ON FUNCTION "public"."log_chat_event"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_chat_event"() TO "service_role";



GRANT ALL ON FUNCTION "public"."log_order_created"() TO "anon";
GRANT ALL ON FUNCTION "public"."log_order_created"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_order_created"() TO "service_role";



GRANT ALL ON FUNCTION "public"."log_order_status_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."log_order_status_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."log_order_status_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_delivered"("target_order_id" "uuid", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_delivered"("target_order_id" "uuid", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_delivered"("target_order_id" "uuid", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."mark_picked_up"("target_order_id" "uuid", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."mark_picked_up"("target_order_id" "uuid", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."mark_picked_up"("target_order_id" "uuid", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_chat_message"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_chat_message"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_chat_message"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_new_signup"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_new_signup"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_new_signup"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_order_created"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_order_created"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_order_created"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_order_status_change"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_order_status_change"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_order_status_change"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_user_approved"() TO "anon";
GRANT ALL ON FUNCTION "public"."notify_user_approved"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_user_approved"() TO "service_role";



GRANT ALL ON FUNCTION "public"."notify_users"("p_user_ids" "uuid"[], "p_title" "text", "p_body" "text", "p_action_route" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."notify_users"("p_user_ids" "uuid"[], "p_title" "text", "p_body" "text", "p_action_route" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."notify_users"("p_user_ids" "uuid"[], "p_title" "text", "p_body" "text", "p_action_route" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."remove_thread_participant"("p_thread_id" "uuid", "p_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."remove_thread_participant"("p_thread_id" "uuid", "p_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."remove_thread_participant"("p_thread_id" "uuid", "p_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."resolve_urgent_note"("p_note_id" "uuid", "p_reply" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."resolve_urgent_note"("p_note_id" "uuid", "p_reply" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."resolve_urgent_note"("p_note_id" "uuid", "p_reply" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "anon";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rls_auto_enable"() TO "service_role";



GRANT ALL ON FUNCTION "public"."rotate_join_code"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."rotate_join_code"() TO "service_role";



GRANT ALL ON FUNCTION "public"."save_device_token"("p_user_id" "uuid", "p_token" "text", "p_platform" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."save_device_token"("p_user_id" "uuid", "p_token" "text", "p_platform" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."save_device_token"("p_user_id" "uuid", "p_token" "text", "p_platform" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."send_chat_message"("p_thread_id" "uuid", "p_content" "text", "p_order_mention_id" "uuid", "p_order_mention_text" "text", "p_user_mention_id" "uuid", "p_user_mention_text" "text", "p_is_urgent" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."send_chat_message"("p_thread_id" "uuid", "p_content" "text", "p_order_mention_id" "uuid", "p_order_mention_text" "text", "p_user_mention_id" "uuid", "p_user_mention_text" "text", "p_is_urgent" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_chat_message"("p_thread_id" "uuid", "p_content" "text", "p_order_mention_id" "uuid", "p_order_mention_text" "text", "p_user_mention_id" "uuid", "p_user_mention_text" "text", "p_is_urgent" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."send_chat_message"("p_thread_id" "uuid", "p_content" "text", "p_order_mention_id" "uuid", "p_order_mention_text" "text", "p_user_mention_id" "uuid", "p_user_mention_text" "text", "p_is_urgent" boolean, "p_reply_to_id" "uuid", "p_reply_to_content" "text", "p_reply_to_sender" "text", "p_attachment_url" "text", "p_attachment_type" "text", "p_attachment_name" "text", "p_attachment_size_bytes" bigint) TO "anon";
GRANT ALL ON FUNCTION "public"."send_chat_message"("p_thread_id" "uuid", "p_content" "text", "p_order_mention_id" "uuid", "p_order_mention_text" "text", "p_user_mention_id" "uuid", "p_user_mention_text" "text", "p_is_urgent" boolean, "p_reply_to_id" "uuid", "p_reply_to_content" "text", "p_reply_to_sender" "text", "p_attachment_url" "text", "p_attachment_type" "text", "p_attachment_name" "text", "p_attachment_size_bytes" bigint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."send_chat_message"("p_thread_id" "uuid", "p_content" "text", "p_order_mention_id" "uuid", "p_order_mention_text" "text", "p_user_mention_id" "uuid", "p_user_mention_text" "text", "p_is_urgent" boolean, "p_reply_to_id" "uuid", "p_reply_to_content" "text", "p_reply_to_sender" "text", "p_attachment_url" "text", "p_attachment_type" "text", "p_attachment_name" "text", "p_attachment_size_bytes" bigint) TO "service_role";



GRANT ALL ON FUNCTION "public"."set_organization_id"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_organization_id"() TO "service_role";



GRANT ALL ON FUNCTION "public"."start_move"("target_order_id" "uuid", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."start_move"("target_order_id" "uuid", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."start_move"("target_order_id" "uuid", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."storage_confirm_delivery"("target_order_id" "uuid", "p_notes" "text", "p_final_quantities" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."storage_confirm_delivery"("target_order_id" "uuid", "p_notes" "text", "p_final_quantities" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."storage_confirm_delivery"("target_order_id" "uuid", "p_notes" "text", "p_final_quantities" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."storage_confirm_pickup"("target_order_id" "uuid", "p_notes" "text", "p_final_quantities" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."storage_confirm_pickup"("target_order_id" "uuid", "p_notes" "text", "p_final_quantities" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."storage_confirm_pickup"("target_order_id" "uuid", "p_notes" "text", "p_final_quantities" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_push_on_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_push_on_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_push_on_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."trigger_push_on_order_status"() TO "anon";
GRANT ALL ON FUNCTION "public"."trigger_push_on_order_status"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."trigger_push_on_order_status"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_updated_at"() TO "service_role";



GRANT ALL ON TABLE "public"."audit_log" TO "anon";
GRANT ALL ON TABLE "public"."audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."chat_audit_log" TO "anon";
GRANT ALL ON TABLE "public"."chat_audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."chat_message_reactions" TO "anon";
GRANT ALL ON TABLE "public"."chat_message_reactions" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_message_reactions" TO "service_role";



GRANT ALL ON TABLE "public"."chat_messages" TO "anon";
GRANT ALL ON TABLE "public"."chat_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_messages" TO "service_role";



GRANT ALL ON TABLE "public"."chat_thread_participants" TO "anon";
GRANT ALL ON TABLE "public"."chat_thread_participants" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_thread_participants" TO "service_role";



GRANT ALL ON TABLE "public"."chat_threads" TO "anon";
GRANT ALL ON TABLE "public"."chat_threads" TO "authenticated";
GRANT ALL ON TABLE "public"."chat_threads" TO "service_role";



GRANT ALL ON TABLE "public"."entities" TO "anon";
GRANT ALL ON TABLE "public"."entities" TO "authenticated";
GRANT ALL ON TABLE "public"."entities" TO "service_role";



GRANT ALL ON TABLE "public"."inventory" TO "anon";
GRANT ALL ON TABLE "public"."inventory" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory" TO "service_role";



GRANT ALL ON TABLE "public"."inventory_audit_log" TO "anon";
GRANT ALL ON TABLE "public"."inventory_audit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."inventory_audit_log" TO "service_role";



GRANT ALL ON TABLE "public"."notifications" TO "anon";
GRANT ALL ON TABLE "public"."notifications" TO "authenticated";
GRANT ALL ON TABLE "public"."notifications" TO "service_role";



GRANT ALL ON TABLE "public"."order_edit_log" TO "anon";
GRANT ALL ON TABLE "public"."order_edit_log" TO "authenticated";
GRANT ALL ON TABLE "public"."order_edit_log" TO "service_role";



GRANT ALL ON TABLE "public"."order_items" TO "anon";
GRANT ALL ON TABLE "public"."order_items" TO "authenticated";
GRANT ALL ON TABLE "public"."order_items" TO "service_role";



GRANT ALL ON TABLE "public"."order_template_items" TO "anon";
GRANT ALL ON TABLE "public"."order_template_items" TO "authenticated";
GRANT ALL ON TABLE "public"."order_template_items" TO "service_role";



GRANT ALL ON TABLE "public"."order_templates" TO "anon";
GRANT ALL ON TABLE "public"."order_templates" TO "authenticated";
GRANT ALL ON TABLE "public"."order_templates" TO "service_role";



GRANT ALL ON TABLE "public"."orders" TO "anon";
GRANT ALL ON TABLE "public"."orders" TO "authenticated";
GRANT ALL ON TABLE "public"."orders" TO "service_role";



GRANT ALL ON TABLE "public"."organizations" TO "anon";
GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."organizations" TO "authenticated";
GRANT ALL ON TABLE "public"."organizations" TO "service_role";



GRANT UPDATE("description") ON TABLE "public"."organizations" TO "authenticated";



GRANT UPDATE("address") ON TABLE "public"."organizations" TO "authenticated";



GRANT UPDATE("contact_email") ON TABLE "public"."organizations" TO "authenticated";



GRANT UPDATE("contact_phone") ON TABLE "public"."organizations" TO "authenticated";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT SELECT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT UPDATE("full_name") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("phone") ON TABLE "public"."profiles" TO "authenticated";



GRANT ALL ON TABLE "public"."receipts" TO "service_role";



GRANT ALL ON TABLE "public"."urgent_notes" TO "anon";
GRANT ALL ON TABLE "public"."urgent_notes" TO "authenticated";
GRANT ALL ON TABLE "public"."urgent_notes" TO "service_role";



GRANT ALL ON TABLE "public"."user_devices" TO "anon";
GRANT ALL ON TABLE "public"."user_devices" TO "authenticated";
GRANT ALL ON TABLE "public"."user_devices" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";







