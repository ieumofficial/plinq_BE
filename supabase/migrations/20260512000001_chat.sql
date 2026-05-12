-- Chat: sessions (channels + DMs), members, messages, reactions, reads.
--
-- Sessions are scoped to the org (one row per channel/DM). For each session
-- chat_session_members lists who can see it. RLS in this migration uses the
-- same simplified `auth.uid() IS NOT NULL` policies as the other tables in
-- this project — application-level filtering enforces session membership.

-- Enums --------------------------------------------------------------------

CREATE TYPE chat_session_kind AS ENUM ('channel', 'dm');

-- A channel is one of:
--   org_wide      → visible to the entire organization (one #general per org)
--   project       → tied to a single project; members are project members
--   member_group  → arbitrary grouping of members (sometimes optionally tagged
--                   with a project label, but the source of truth is the
--                   members list, not the project)
-- DMs use 'dm'; the dm_user_a/dm_user_b columns identify the two participants.
CREATE TYPE chat_session_scope AS ENUM ('org_wide', 'project', 'member_group', 'dm');

CREATE TYPE chat_session_privacy AS ENUM ('public', 'private');

-- Sessions ------------------------------------------------------------------

CREATE TABLE public.chat_sessions (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id       uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    kind         chat_session_kind NOT NULL,
    scope        chat_session_scope NOT NULL,
    privacy      chat_session_privacy NOT NULL DEFAULT 'public',

    -- Channel-only fields ('dm' rows leave these NULL).
    name         text,
    description  text,
    project_id   uuid REFERENCES public.projects(id) ON DELETE SET NULL,

    -- DM-only fields ('channel' rows leave these NULL). dm_user_a is always
    -- the lower-uuid of the pair so a (a,b) pair is unique.
    dm_user_a    uuid REFERENCES public.users(id) ON DELETE CASCADE,
    dm_user_b    uuid REFERENCES public.users(id) ON DELETE CASCADE,

    created_by   uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),

    -- Channel rows must have a name; DM rows must have ordered participants.
    CONSTRAINT chat_session_shape CHECK (
        (kind = 'channel' AND name IS NOT NULL AND dm_user_a IS NULL AND dm_user_b IS NULL)
     OR (kind = 'dm'      AND dm_user_a IS NOT NULL AND dm_user_b IS NOT NULL AND dm_user_a < dm_user_b)
    )
);

-- One DM per pair per org.
CREATE UNIQUE INDEX chat_sessions_dm_pair_uniq
    ON public.chat_sessions (org_id, dm_user_a, dm_user_b)
    WHERE kind = 'dm';

CREATE INDEX chat_sessions_org ON public.chat_sessions (org_id);
CREATE INDEX chat_sessions_project ON public.chat_sessions (project_id) WHERE project_id IS NOT NULL;

-- Members --------------------------------------------------------------------

CREATE TABLE public.chat_session_members (
    session_id uuid NOT NULL REFERENCES public.chat_sessions(id) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    /** When the user last opened/read the session (used for unread counts). */
    last_read_at timestamptz,
    joined_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (session_id, user_id)
);

CREATE INDEX chat_session_members_user ON public.chat_session_members (user_id);

-- Messages -------------------------------------------------------------------

CREATE TABLE public.chat_messages (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id  uuid NOT NULL REFERENCES public.chat_sessions(id) ON DELETE CASCADE,
    author_id   uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    body        text NOT NULL,
    /** Optional: parent message for thread replies. NULL = top-level message. */
    reply_to_id uuid REFERENCES public.chat_messages(id) ON DELETE SET NULL,
    /** A message can be pinned to the session header. */
    pinned_at   timestamptz,
    pinned_by   uuid REFERENCES public.users(id) ON DELETE SET NULL,
    edited_at   timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX chat_messages_session ON public.chat_messages (session_id, created_at DESC);
CREATE INDEX chat_messages_thread ON public.chat_messages (reply_to_id) WHERE reply_to_id IS NOT NULL;
CREATE INDEX chat_messages_pinned ON public.chat_messages (session_id) WHERE pinned_at IS NOT NULL;

-- Reactions -----------------------------------------------------------------

CREATE TABLE public.chat_message_reactions (
    message_id uuid NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    /** Emoji glyph (e.g. "🎯") — one row per (message, user, emoji). */
    emoji      text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (message_id, user_id, emoji)
);

CREATE INDEX chat_message_reactions_message ON public.chat_message_reactions (message_id);

-- RLS ------------------------------------------------------------------------

ALTER TABLE public.chat_sessions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_session_members   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY chat_sessions_all ON public.chat_sessions
    FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY chat_session_members_all ON public.chat_session_members
    FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY chat_messages_all ON public.chat_messages
    FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY chat_message_reactions_all ON public.chat_message_reactions
    FOR ALL TO authenticated USING (auth.uid() IS NOT NULL) WITH CHECK (auth.uid() IS NOT NULL);
