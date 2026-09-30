-- Inventory schema cleanup. item_name is deliberately NOT restructured or
-- re-parsed -- all existing rows keep their current full descriptive name
-- exactly as-is. New columns are additive metadata alongside it, chosen to
-- give a future matcher fix a structured place to look instead of guessing
-- from free text (found via today's "قهوة عربي 9 كيلو" investigation).

-- 1. Fix the one confirmed typo, by id (not by name match).
UPDATE inventory SET unit = 'بكت' WHERE id = '1f4f7ea9-7c53-449b-abb0-dc4f955f0c18';

-- 2. Drop the dead column -- confirmed unreferenced anywhere in lib/.
ALTER TABLE public.inventory DROP COLUMN min_threshold;

-- 3. min_quantity: nullable now, new default 3 for future inserts only.
-- Existing rows' actual values (currently all 0) are untouched.
ALTER TABLE public.inventory
  ALTER COLUMN min_quantity DROP NOT NULL,
  ALTER COLUMN min_quantity SET DEFAULT 3;

-- 4. unit's default never matched real data (always Arabic, never 'piece').
ALTER TABLE public.inventory ALTER COLUMN unit DROP DEFAULT;

-- 5. Four new, purely additive columns.
ALTER TABLE public.inventory
  ADD COLUMN brand text,
  ADD COLUMN variety text,
  ADD COLUMN packaging_size numeric,
  ADD COLUMN packaging_size_unit text,
  ADD COLUMN aliases text[];

COMMENT ON COLUMN public.inventory.brand IS 'Manufacturer/brand name, e.g. نوفا, باجة. Nullable -- not backfilled for existing rows.';
COMMENT ON COLUMN public.inventory.variety IS 'Finer classification within category (النوع) -- e.g. category=قهوة, variety=عربي/برازيلي. Nullable.';
COMMENT ON COLUMN public.inventory.packaging_size IS 'Fixed weight/volume per unit, e.g. 1 for a 1kg bag. Nullable. Pairs with packaging_size_unit.';
COMMENT ON COLUMN public.inventory.packaging_size_unit IS 'Unit for packaging_size, e.g. كجم, جم, مل, لتر. Distinct from the unit column, which is how it is counted (كرتون/كيس), not how much product is in each.';
COMMENT ON COLUMN public.inventory.aliases IS 'Alternate names/common misspellings/colloquial terms a sender might use for this item. Not yet consumed by the matcher -- structural groundwork only.';

-- 6. inventory_create_item / inventory_update_item: append new optional
-- params with defaults. Plain CREATE OR REPLACE is sufficient and preserves
-- existing grants/ownership -- unlike quantities_to_numeric.sql's
-- integer->numeric change (an existing param's TYPE changed, which forces a
-- DROP+recreate), this only adds new trailing defaulted params, which
-- Postgres explicitly allows CREATE OR REPLACE to handle as a true
-- replacement of the same function, not a new overload.

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
END;
$$;
