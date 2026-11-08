-- بنود العرض now work like the inventory: a template adds new lines and an
-- exported file updates existing ones by id.
--
-- replace_project_items deleted every line and re-inserted the file. That gave
-- each line a new id, which set delivery_receipt_items.project_item_id to NULL
-- on past سندات (ON DELETE SET NULL) and wiped the packaging conversion, since
-- Excel doesn't carry it. apply_project_items never deletes: a row with an id
-- updates that line in place, packaging and sort_order untouched; a row without
-- one is added after the project's last line.
--
-- replace_project_items stays because already-installed APKs still call it.

CREATE OR REPLACE FUNCTION "public"."apply_project_items"(
    "p_project_id" "uuid",
    "p_items" "jsonb"
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_org uuid;
  v_bad int;
  v_row text;
  v_next int;
  v_inserted int;
  v_updated int;
BEGIN
  IF auth.uid() IS NULL
     OR coalesce(is_current_user_approved(), false) IS NOT TRUE
     OR project_item_pricing_visible() IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح بتعديل بنود العرض');
  END IF;

  SELECT organization_id INTO v_org FROM projects WHERE id = p_project_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المشروع غير موجود');
  END IF;
  IF v_org IS DISTINCT FROM auth_org_id() AND coalesce(is_platform_admin(), false) IS NOT TRUE THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'لا توجد بنود في الملف');
  END IF;

  -- The jsonb_typeof checks come first in each CASE: casting a non-number to
  -- numeric raises, and OR doesn't guarantee evaluation order.
  SELECT count(*) INTO v_bad
  FROM jsonb_array_elements(p_items) e
  WHERE jsonb_typeof(e) IS DISTINCT FROM 'object'
     OR coalesce(trim(e->>'item_name'), '') = ''
     OR coalesce(trim(e->>'unit'), '') = ''
     OR CASE WHEN jsonb_typeof(e->'quantity') = 'number' THEN (e->>'quantity')::numeric < 0 ELSE true END
     OR CASE jsonb_typeof(e->'unit_price')
          WHEN 'number' THEN (e->>'unit_price')::numeric < 0
          WHEN 'null' THEN false
          ELSE e ? 'unit_price'
        END
     OR CASE jsonb_typeof(e->'total_price')
          WHEN 'number' THEN (e->>'total_price')::numeric < 0
          WHEN 'null' THEN false
          ELSE e ? 'total_price'
        END;
  IF v_bad > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'يوجد ' || v_bad || ' بند ناقص البيانات');
  END IF;

  -- Ids compare as text, so a mangled id in the file is "not found" here
  -- rather than a uuid cast error.
  SELECT coalesce(e->>'row_number', '؟') INTO v_row
  FROM jsonb_array_elements(p_items) e
  WHERE coalesce(trim(e->>'id'), '') <> ''
    AND NOT EXISTS (
      SELECT 1 FROM project_items pi
      WHERE pi.project_id = p_project_id
        AND pi.id::text = lower(trim(e->>'id'))
    )
  LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الصف ' || v_row || ': البند غير موجود في هذا المشروع');
  END IF;

  SELECT coalesce(max(e->>'row_number'), '؟') INTO v_row
  FROM jsonb_array_elements(p_items) e
  WHERE coalesce(trim(e->>'id'), '') <> ''
  GROUP BY lower(trim(e->>'id'))
  HAVING count(*) > 1
  LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الصف ' || v_row || ': البند مكرر في الملف');
  END IF;

  UPDATE project_items pi
  SET category = coalesce(trim(e->>'category'), ''),
      item_name = trim(e->>'item_name'),
      description = nullif(trim(e->>'description'), ''),
      quantity = (e->>'quantity')::numeric,
      unit = trim(e->>'unit'),
      unit_price = (e->>'unit_price')::numeric,
      total_price = (e->>'total_price')::numeric
  FROM jsonb_array_elements(p_items) e
  WHERE coalesce(trim(e->>'id'), '') <> ''
    AND pi.project_id = p_project_id
    AND pi.id::text = lower(trim(e->>'id'));
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  SELECT coalesce(max(sort_order), 0) INTO v_next
  FROM project_items WHERE project_id = p_project_id;

  INSERT INTO project_items (
    project_id, category, sort_order, item_name, description,
    quantity, unit, unit_price, total_price, created_by
  )
  SELECT
    p_project_id,
    coalesce(trim(e->>'category'), ''),
    v_next + (row_number() OVER (ORDER BY ord))::int,
    trim(e->>'item_name'),
    nullif(trim(e->>'description'), ''),
    (e->>'quantity')::numeric,
    trim(e->>'unit'),
    (e->>'unit_price')::numeric,
    (e->>'total_price')::numeric,
    auth.uid()
  FROM jsonb_array_elements(p_items) WITH ORDINALITY AS t(e, ord)
  WHERE coalesce(trim(e->>'id'), '') = '';
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  RETURN jsonb_build_object('success', true, 'inserted', v_inserted, 'updated', v_updated);
END;
$$;

REVOKE EXECUTE ON FUNCTION "public"."apply_project_items"("uuid", "jsonb") FROM "anon", PUBLIC;
GRANT EXECUTE ON FUNCTION "public"."apply_project_items"("uuid", "jsonb") TO "authenticated";
