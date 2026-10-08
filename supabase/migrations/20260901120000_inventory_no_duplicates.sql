-- No two live inventory items may share the same identity within one
-- organization. Identity is the full set the catalogue is actually keyed on --
-- name + brand + variety + packaging -- not the name alone, so "قهوة عربي" from
-- two different brands, or the same product in 1 كجم and 500 جم, remain
-- legitimately distinct rows. Two rows with the same name and no brand/variety/
-- packaging filled in DO collide, which is the case this exists to catch.
--
-- Three details, each of which would silently defeat this if omitted:
--
-- 1. NULLS NOT DISTINCT (Postgres 15+, this project is on 17). By default
--    Postgres treats NULLs as distinct in a unique index, so two rows with a
--    NULL brand would NOT collide -- exactly the case we most need blocked,
--    since brand/variety/packaging are nullable and mostly unpopulated today.
-- 2. Scoped to organization_id. This table is multi-tenant (see the
--    set_org_id_inventory trigger); a global index would let one organization's
--    catalogue block another's.
-- 3. Partial on archived_at IS NULL. Archiving is this table's soft delete, so
--    an archived row must not prevent re-adding the same product later.
--
-- lower(btrim(...)) means casing and stray whitespace cannot smuggle a
-- duplicate past the index. Arabic spelling variants (أ/ا/إ, ة/ه) deliberately
-- are NOT normalized here -- verified 2026-09-01 that the live 194 rows contain
-- no such near-duplicates, and folding them risks refusing names the user
-- considers genuinely distinct.
CREATE UNIQUE INDEX IF NOT EXISTS "inventory_unique_identity"
  ON "public"."inventory" (
    "organization_id",
    lower(btrim("item_name")),
    lower(btrim("brand")),
    lower(btrim("variety")),
    "packaging_size",
    lower(btrim("packaging_size_unit"))
  )
  NULLS NOT DISTINCT
  WHERE "archived_at" IS NULL;

COMMENT ON INDEX "public"."inventory_unique_identity" IS
  'One live row per (org, name, brand, variety, packaging size + unit). NULLS NOT DISTINCT so unpopulated brand/variety/packaging still collide on name.';

-- Turn the raw constraint violation into a message a verifier can act on.
-- Both RPCs otherwise keep the exact signature and body from
-- 20260831120000_inventory_schema_cleanup.sql.
CREATE OR REPLACE FUNCTION "public"."inventory_create_item"(
  "p_name" "text",
  "p_unit" "text",
  "p_quantity" numeric,
  "p_sku" "text" DEFAULT NULL::"text",
  "p_category" "text" DEFAULT NULL::"text",
  "p_min_quantity" numeric DEFAULT 3,
  "p_description" "text" DEFAULT NULL::"text",
  "p_notes" "text" DEFAULT NULL::"text",
  "p_brand" "text" DEFAULT NULL::"text",
  "p_variety" "text" DEFAULT NULL::"text",
  "p_packaging_size" numeric DEFAULT NULL::numeric,
  "p_packaging_size_unit" "text" DEFAULT NULL::"text",
  "p_aliases" "text"[] DEFAULT NULL::"text"[]
) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE v_item_id UUID;
BEGIN
  INSERT INTO inventory (
    item_name, unit, quantity, sku, category, min_quantity, description,
    brand, variety, packaging_size, packaging_size_unit, aliases
  )
  VALUES (
    p_name, p_unit, p_quantity, p_sku, p_category, p_min_quantity, p_description,
    p_brand, p_variety, p_packaging_size, p_packaging_size_unit, p_aliases
  )
  RETURNING id INTO v_item_id;

  INSERT INTO inventory_audit_log (item_id, action, old_quantity, new_quantity, performed_by, notes)
  VALUES (v_item_id, 'created', 0, p_quantity, auth.uid(), p_notes);
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'هذا الصنف موجود بالفعل في المخزن بنفس الاسم والعلامة التجارية والنوع والتعبئة'
      USING ERRCODE = 'unique_violation';
END;
$$;

CREATE OR REPLACE FUNCTION "public"."inventory_update_item"(
  "p_item_id" "uuid",
  "p_name" "text",
  "p_unit" "text",
  "p_quantity" numeric,
  "p_sku" "text" DEFAULT NULL::"text",
  "p_category" "text" DEFAULT NULL::"text",
  "p_min_quantity" numeric DEFAULT 3,
  "p_description" "text" DEFAULT NULL::"text",
  "p_notes" "text" DEFAULT NULL::"text",
  "p_brand" "text" DEFAULT NULL::"text",
  "p_variety" "text" DEFAULT NULL::"text",
  "p_packaging_size" numeric DEFAULT NULL::numeric,
  "p_packaging_size_unit" "text" DEFAULT NULL::"text",
  "p_aliases" "text"[] DEFAULT NULL::"text"[]
) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
DECLARE
  v_old_quantity NUMERIC;
  v_action       TEXT;
BEGIN
  SELECT quantity INTO v_old_quantity FROM inventory WHERE id = p_item_id;

  UPDATE inventory
  SET item_name           = p_name,
      unit                = p_unit,
      quantity            = p_quantity,
      sku                 = p_sku,
      category            = p_category,
      min_quantity        = p_min_quantity,
      description         = p_description,
      brand               = p_brand,
      variety             = p_variety,
      packaging_size      = p_packaging_size,
      packaging_size_unit = p_packaging_size_unit,
      aliases             = p_aliases
  WHERE id = p_item_id;

  v_action := CASE WHEN v_old_quantity != p_quantity THEN 'quantity_updated' ELSE 'item_updated' END;

  INSERT INTO inventory_audit_log (item_id, action, old_quantity, new_quantity, performed_by, notes)
  VALUES (p_item_id, v_action, v_old_quantity, p_quantity, auth.uid(), p_notes);
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'هذا الصنف موجود بالفعل في المخزن بنفس الاسم والعلامة التجارية والنوع والتعبئة'
      USING ERRCODE = 'unique_violation';
END;
$$;
