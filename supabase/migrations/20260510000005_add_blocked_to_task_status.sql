-- Add 'blocked' to task_status enum.
-- Matches the StatusLabelBig UI component which already supports blocked state.
ALTER TYPE task_status ADD VALUE 'blocked';
