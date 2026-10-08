-- سند استلام module, step 3 of 3: the delivery receipt itself.
--
-- Keys off entity_id + project_id, deliberately NOT a required order_id --
-- reps sometimes file these later in the day as a standalone logistics step,
-- disconnected from any specific order. order_id stays nullable for
-- traceability when a سند is triggered from an order's last step, but is
-- never required. Reps are the only creators for v1 (view-only for
-- verifier/storage_actor/manager/admin -- approve/flag is explicitly out of
-- scope, a later addition if ever needed).
--
-- No UPDATE policy for anyone, including the creating rep: the client
-- uploads the generated PDF to Storage and gets its public URL *before*
-- calling create_delivery_receipt, so pdf_url is set at INSERT time and the
-- row never needs to change afterwards. That keeps a filed سند a true
-- immutable record, not just "view-only for other roles".
--
-- item_name_snapshot/unit_snapshot freeze what project_items said at receipt
-- time, same reasoning as letterhead_image_url_snapshot on the parent row --
-- a later edit to the project's catalog or letterhead must not retroactively
-- change a historical سند.

CREATE TABLE IF NOT EXISTS "public"."delivery_receipts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "entity_id" "uuid" NOT NULL,
    "project_id" "uuid" NOT NULL,
    "order_id" "uuid",
    "rep_id" "uuid" NOT NULL,
    "delivered_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "pdf_url" "text",
    "letterhead_image_url_snapshot" "text",
    "notes" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "organization_id" "uuid",
    CONSTRAINT "delivery_receipts_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "public"."delivery_receipts" OWNER TO "postgres";

ALTER TABLE ONLY "public"."delivery_receipts"
    ADD CONSTRAINT "delivery_receipts_entity_id_fkey" FOREIGN KEY ("entity_id") REFERENCES "public"."entities"("id");

ALTER TABLE ONLY "public"."delivery_receipts"
    ADD CONSTRAINT "delivery_receipts_project_id_fkey" FOREIGN KEY ("project_id") REFERENCES "public"."projects"("id");

ALTER TABLE ONLY "public"."delivery_receipts"
    ADD CONSTRAINT "delivery_receipts_order_id_fkey" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "public"."delivery_receipts"
    ADD CONSTRAINT "delivery_receipts_rep_id_fkey" FOREIGN KEY ("rep_id") REFERENCES "public"."profiles"("id");

ALTER TABLE ONLY "public"."delivery_receipts"
    ADD CONSTRAINT "delivery_receipts_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "public"."organizations"("id");

CREATE OR REPLACE TRIGGER "set_org_id_delivery_receipts" BEFORE INSERT ON "public"."delivery_receipts" FOR EACH ROW EXECUTE FUNCTION "public"."set_organization_id"();

ALTER TABLE "public"."delivery_receipts" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Approved users can view delivery receipts" ON "public"."delivery_receipts" FOR SELECT USING (
  "public"."is_current_user_approved"()
  AND (("organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
);

GRANT ALL ON TABLE "public"."delivery_receipts" TO "anon";
GRANT ALL ON TABLE "public"."delivery_receipts" TO "authenticated";
GRANT ALL ON TABLE "public"."delivery_receipts" TO "service_role";

CREATE TABLE IF NOT EXISTS "public"."delivery_receipt_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "delivery_receipt_id" "uuid" NOT NULL,
    "project_item_id" "uuid",
    "item_name_snapshot" "text" NOT NULL,
    "unit_snapshot" "text" NOT NULL,
    "quantity_delivered" numeric NOT NULL,
    CONSTRAINT "delivery_receipt_items_pkey" PRIMARY KEY ("id")
);

ALTER TABLE "public"."delivery_receipt_items" OWNER TO "postgres";

ALTER TABLE ONLY "public"."delivery_receipt_items"
    ADD CONSTRAINT "delivery_receipt_items_delivery_receipt_id_fkey" FOREIGN KEY ("delivery_receipt_id") REFERENCES "public"."delivery_receipts"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."delivery_receipt_items"
    ADD CONSTRAINT "delivery_receipt_items_project_item_id_fkey" FOREIGN KEY ("project_item_id") REFERENCES "public"."project_items"("id") ON DELETE SET NULL;

ALTER TABLE "public"."delivery_receipt_items" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "org_isolation" ON "public"."delivery_receipt_items" TO "authenticated" USING (
  EXISTS (
    SELECT 1 FROM "public"."delivery_receipts" "dr"
    WHERE ("dr"."id" = "delivery_receipt_items"."delivery_receipt_id")
      AND "public"."is_current_user_approved"()
      AND (("dr"."organization_id" = "public"."auth_org_id"()) OR "public"."is_platform_admin"())
  )
);

GRANT ALL ON TABLE "public"."delivery_receipt_items" TO "anon";
GRANT ALL ON TABLE "public"."delivery_receipt_items" TO "authenticated";
GRANT ALL ON TABLE "public"."delivery_receipt_items" TO "service_role";

-- Single atomic entry point for creating a سند: validates entity/project/
-- order match server-side, writes the header + every item in one
-- transaction. SECURITY DEFINER lets a rep's call read project_items (whose
-- own RLS would otherwise hide the row from a rep) to snapshot item
-- name/unit -- note it never reads or returns unit_price/total_price, so
-- pricing never leaks through this path regardless of the caller's role.
CREATE OR REPLACE FUNCTION "public"."create_delivery_receipt"(
    "p_entity_id" "uuid",
    "p_project_id" "uuid",
    "p_items" "jsonb",
    "p_order_id" "uuid" DEFAULT NULL::"uuid",
    "p_pdf_url" "text" DEFAULT NULL::"text",
    "p_notes" "text" DEFAULT NULL::"text"
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
  v_caller_role user_role;
  v_project RECORD;
  v_receipt_id uuid;
  v_item jsonb;
  v_project_item RECORD;
BEGIN
  SELECT role INTO v_caller_role FROM profiles WHERE id = auth.uid();
  IF v_caller_role NOT IN ('rep', 'admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only reps can create delivery receipts');
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'At least one item is required');
  END IF;

  SELECT * INTO v_project FROM projects WHERE id = p_project_id AND entity_id = p_entity_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Project not found for this entity');
  END IF;

  IF NOT (v_project.organization_id = auth_org_id() OR is_platform_admin()) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authorized');
  END IF;

  IF p_order_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM orders WHERE id = p_order_id AND entity_id = p_entity_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order does not match this entity');
  END IF;

  INSERT INTO delivery_receipts (entity_id, project_id, order_id, rep_id, notes, pdf_url, letterhead_image_url_snapshot)
  VALUES (p_entity_id, p_project_id, p_order_id, auth.uid(), p_notes, p_pdf_url, v_project.letterhead_image_url)
  RETURNING id INTO v_receipt_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    SELECT * INTO v_project_item FROM project_items
      WHERE id = (v_item->>'project_item_id')::uuid AND project_id = p_project_id;
    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'Invalid item for this project');
    END IF;

    INSERT INTO delivery_receipt_items (delivery_receipt_id, project_item_id, item_name_snapshot, unit_snapshot, quantity_delivered)
    VALUES (v_receipt_id, v_project_item.id, v_project_item.item_name, v_project_item.unit, (v_item->>'quantity_delivered')::numeric);
  END LOOP;

  RETURN jsonb_build_object('success', true, 'delivery_receipt_id', v_receipt_id);
END;
$$;
