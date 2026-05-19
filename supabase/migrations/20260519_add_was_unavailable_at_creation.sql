-- Add frozen boolean flag: was the item unavailable (qty=0) when the order was created?
-- This replaces dynamic warning logic that recalculated from live inventory.

ALTER TABLE order_items
  ADD COLUMN IF NOT EXISTS was_unavailable_at_creation BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN order_items.was_unavailable_at_creation IS
  'True if inventory quantity was 0 when this order item was created. Frozen at creation time; never changes.';

-- Reload PostgREST schema cache so the new column is visible immediately
-- via the REST API (without this, client inserts fail with PGRST204).
NOTIFY pgrst, 'reload schema';
