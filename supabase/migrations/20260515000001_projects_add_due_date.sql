-- Add a due_date to projects so AI proposals can suggest a project deadline
-- alongside per-task due dates. Nullable — most existing rows have no
-- explicit deadline, and not every project needs one.

ALTER TABLE public.projects
    ADD COLUMN IF NOT EXISTS due_date date;
