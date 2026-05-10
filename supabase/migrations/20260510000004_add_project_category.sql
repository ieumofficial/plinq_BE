-- Add free-text category tag to projects (e.g., "EXEC", "R&D").
-- Displayed as a chip on Project cards in the dashboard / projects list.
ALTER TABLE public.projects
    ADD COLUMN category text;

COMMENT ON COLUMN public.projects.category IS 'Optional category label shown on project cards (e.g. "EXEC", "R&D"). Free-text for now.';
