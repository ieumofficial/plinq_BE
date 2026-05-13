-- Lifecycle for agent proposals.
--
-- 'open'       — created, not yet acted on. Carries the user-visible card.
-- 'applied'    — user clicked Apply (any subset). applied_item_ids /
--                applied_result hold the materialization record.
-- 'rejected'   — user explicitly dismissed (UI button or said "안 할래").
-- 'superseded' — model dismissed it because the user moved on to a new
--                topic without acting on the previous proposal.
--
-- Backfill: any pre-existing row that already has applied_item_ids was
-- successfully applied → status='applied'. Everything else is 'open'.
--
-- This file is idempotent: parts of the schema may already exist if the
-- ai server applied them ad-hoc during development.

DO $$ BEGIN
    CREATE TYPE agent_proposal_status AS ENUM (
        'open',
        'applied',
        'rejected',
        'superseded'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.agent_proposals
    ADD COLUMN IF NOT EXISTS status           agent_proposal_status NOT NULL DEFAULT 'open',
    ADD COLUMN IF NOT EXISTS dismissed_at     timestamptz,
    ADD COLUMN IF NOT EXISTS dismissed_reason text;

UPDATE public.agent_proposals
   SET status = 'applied'
 WHERE applied_item_ids IS NOT NULL
   AND status = 'open';

CREATE INDEX IF NOT EXISTS agent_proposals_open_per_convo
    ON public.agent_proposals (conversation_id, created_at DESC)
    WHERE status = 'open';
