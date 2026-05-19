-- Add notes column to inventory table for storing item-level notes
ALTER TABLE inventory ADD COLUMN IF NOT EXISTS notes text;
