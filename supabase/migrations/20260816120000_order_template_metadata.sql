-- Optional metadata for order templates, editable from the template management page.
-- Both nullable: existing templates keep falling back to their items summary for a title.
ALTER TABLE "public"."order_templates"
  ADD COLUMN "name" "text",
  ADD COLUMN "description" "text";
