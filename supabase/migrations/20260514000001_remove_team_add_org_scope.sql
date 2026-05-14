-- Remove the Team layer entirely. Projects now belong directly to an
-- Organization, and AgentConversations carry an org_id so the agent
-- always knows which org context it's operating in.
--
-- Migration policy (per design): wipe domain data — tasks, meetings,
-- projects (+children), agent conversations/proposals — and start fresh
-- under the new org-scoped model. Users / organizations / org_members
-- are preserved.
--
-- Fully idempotent: every step tolerates either a brand-new DB (no team
-- ever existed) or a DB where some of these tables/columns are already
-- gone from prior runs.

BEGIN;

-- 1. Drop team tables. CASCADE clears any FK from projects.team_id /
--    tasks.team_id that referenced them.
DROP TABLE IF EXISTS public.team_members CASCADE;
DROP TABLE IF EXISTS public.teams        CASCADE;

-- 2. Wipe domain data. Each TRUNCATE is wrapped so the migration
--    survives a DB where any of these tables haven't been created yet.
DO $$ DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'public.agent_proposals',
        'public.agent_messages',
        'public.agent_conversations',
        'public.tasks',
        'public.meetings',
        'public.project_members',
        'public.project_invites',
        'public.kanban_columns',
        'public.projects'
    ]
    LOOP
        BEGIN
            EXECUTE 'TRUNCATE ' || t || ' CASCADE';
        EXCEPTION
            WHEN undefined_table THEN NULL;
        END;
    END LOOP;
END $$;

-- 3. tasks: drop team_id + scope_xor CHECK (no longer applicable).
ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS task_scope_xor;
ALTER TABLE public.tasks DROP COLUMN     IF EXISTS team_id;

-- 4. projects: drop team_id, add org_id NOT NULL.
ALTER TABLE public.projects DROP COLUMN IF EXISTS team_id;
ALTER TABLE public.projects ADD COLUMN  IF NOT EXISTS org_id uuid;

DO $$ BEGIN
    ALTER TABLE public.projects
        ADD CONSTRAINT projects_org_id_fkey
        FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.projects ALTER COLUMN org_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS projects_org_id_idx ON public.projects(org_id);

-- 5. agent_conversations: add org_id NOT NULL.
ALTER TABLE public.agent_conversations ADD COLUMN IF NOT EXISTS org_id uuid;

DO $$ BEGIN
    ALTER TABLE public.agent_conversations
        ADD CONSTRAINT agent_conversations_org_id_fkey
        FOREIGN KEY (org_id) REFERENCES public.organizations(id) ON DELETE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.agent_conversations ALTER COLUMN org_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS agent_conversations_org_user_idx
    ON public.agent_conversations (org_id, user_id, created_at DESC);

COMMIT;
