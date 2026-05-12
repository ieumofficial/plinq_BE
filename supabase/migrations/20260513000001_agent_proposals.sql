-- Agent proposals: temporary store for tool-use suggestions the assistant
-- offers to the user (e.g. "create these 5 tasks", "schedule this meeting").
-- Items live as JSON until the user clicks Apply on a subset, at which point
-- the AI server materializes them into real rows in the relevant tables.
--
-- Rows older than `expires_at` (default +24h) can be GC'd by a nightly cron.

CREATE TYPE agent_proposal_kind AS ENUM (
    'tasks',          -- breakdown / suggested tasks for a project
    'project_outline',-- new project + initial tasks
    'meeting_agenda', -- agenda items for an upcoming meeting
    'assignee',       -- assignee suggestions for a task
    'meeting'         -- a follow-up meeting suggestion
);

CREATE TABLE public.agent_proposals (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid REFERENCES public.agent_conversations(id) ON DELETE CASCADE,
    user_id         uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    /** When the proposal is project-scoped (most are). NULL for personal-agent
        outputs that aren't tied to one project. */
    project_id      uuid REFERENCES public.projects(id) ON DELETE CASCADE,
    kind            agent_proposal_kind NOT NULL,
    /** Each item is `{id, ...kind-specific fields}`. The agent assigns the
        item ids so the FE can echo them back as `selected_item_ids` when
        the user clicks Apply. */
    items           jsonb NOT NULL,
    /** Once the user applies (possibly partially), record which item ids
        actually became real rows. Null on a fresh proposal. */
    applied_item_ids jsonb,
    /** "tasks/created":[uuid,...] etc. — kind-specific record of what was
        created when applied. Optional. */
    applied_result  jsonb,
    created_at      timestamptz NOT NULL DEFAULT now(),
    expires_at      timestamptz NOT NULL DEFAULT (now() + INTERVAL '24 hours')
);

CREATE INDEX agent_proposals_conversation
    ON public.agent_proposals (conversation_id)
    WHERE conversation_id IS NOT NULL;

CREATE INDEX agent_proposals_user
    ON public.agent_proposals (user_id, created_at DESC);

CREATE INDEX agent_proposals_expiry
    ON public.agent_proposals (expires_at)
    WHERE applied_item_ids IS NULL;

-- RLS: same simplified pattern as the rest of the project — application
-- enforces that conversation_id belongs to the user. The AI server uses
-- the service_role key and bypasses RLS.

ALTER TABLE public.agent_proposals ENABLE ROW LEVEL SECURITY;

CREATE POLICY agent_proposals_all ON public.agent_proposals
    FOR ALL TO authenticated
    USING (auth.uid() IS NOT NULL)
    WITH CHECK (auth.uid() IS NOT NULL);
