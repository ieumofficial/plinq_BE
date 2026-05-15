-- Per-(session, user) cache for the AI "Catch me up" summary.
--
-- Why a cache table:
--   - Generating the summary is a ~10s Sonnet call. We only want to pay it
--     once per "batch of unread messages", not on every panel open / render.
--   - The summary must *persist* until the user has caught up: even if they
--     close and reopen the session, the same summary stays until either
--     (a) they read the messages it covers, or (b) newer unread messages
--     arrive (which makes the cache stale → regenerate).
--
-- Staleness rule (enforced in the API, not here): the cache is valid while
-- `covered_through_at >= the newest message's created_at`. A newer message
-- ⇒ regenerate and overwrite this row.

CREATE TABLE public.chat_catch_me_up (
    id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id                  uuid NOT NULL REFERENCES public.chat_sessions(id) ON DELETE CASCADE,
    user_id                     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

    summary                     text,
    action_items                jsonb NOT NULL DEFAULT '[]'::jsonb,

    -- Newest message this summary accounts for. Lets the API cheaply decide
    -- whether the cache still covers the current unread tail.
    covered_through_message_id  uuid REFERENCES public.chat_messages(id) ON DELETE SET NULL,
    covered_through_at          timestamptz,

    created_at                  timestamptz NOT NULL DEFAULT now(),

    -- Exactly one cached summary per person per session.
    UNIQUE (session_id, user_id)
);

CREATE INDEX chat_catch_me_up_lookup
    ON public.chat_catch_me_up (user_id, session_id);

ALTER TABLE public.chat_catch_me_up ENABLE ROW LEVEL SECURITY;

-- A user only ever touches their own cached summaries. plinq_ai connects as
-- the postgres role (BYPASSRLS) so the server can upsert freely; these
-- policies just keep the supabase-js client honest if it ever reads directly.
CREATE POLICY "ccmu_select_own" ON public.chat_catch_me_up
    FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "ccmu_modify_own" ON public.chat_catch_me_up
    FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
