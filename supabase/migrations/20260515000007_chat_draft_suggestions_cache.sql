-- Per-(session, user) cache for AI-drafted reply suggestions.
--
-- Same rationale as chat_catch_me_up: drafting is a ~10s Sonnet call. The
-- user asked for it to happen ONCE per incoming question and then be
-- *remembered* — reloading the page must NOT regenerate. We key the cache
-- by the message the draft is answering (`after_message_id`): while that's
-- still the newest incoming message the same drafts are served from here;
-- once the conversation moves on, the row goes stale and is overwritten.
--
-- Only the *auto* draft (no user-typed text) is cached. Refining a draft
-- the user is typing is inherently per-keystroke and never cached.

CREATE TABLE public.chat_draft_suggestions (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          uuid NOT NULL REFERENCES public.chat_sessions(id) ON DELETE CASCADE,
    user_id             uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,

    -- The incoming message these drafts are a reply to. Cache is valid only
    -- while this is still the newest message from someone other than the user.
    after_message_id    uuid REFERENCES public.chat_messages(id) ON DELETE CASCADE,

    suggestions         jsonb NOT NULL DEFAULT '[]'::jsonb,
    created_at          timestamptz NOT NULL DEFAULT now(),

    UNIQUE (session_id, user_id)
);

CREATE INDEX chat_draft_suggestions_lookup
    ON public.chat_draft_suggestions (user_id, session_id);

ALTER TABLE public.chat_draft_suggestions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cds_select_own" ON public.chat_draft_suggestions
    FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "cds_modify_own" ON public.chat_draft_suggestions
    FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
