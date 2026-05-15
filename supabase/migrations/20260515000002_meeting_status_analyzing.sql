-- Add 'analyzing' to meeting_status so the FE can show a progress card
-- between recording end and analyze completion. The pipeline transitions
-- the row 'recording'/'planned' → 'analyzing' (when STT/LLM start) → 'processed'.

ALTER TYPE meeting_status ADD VALUE IF NOT EXISTS 'analyzing';
