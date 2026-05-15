-- Notifications inbox.
--
-- Phase 1: 채팅 메시지 알림만 트리거. 다른 type(task/meeting/mention/agent)은
-- 컬럼 + ENUM에 미리 자리만 잡아둠 — 실제 트리거는 추후 phase에서 추가.
--
-- 설계 원칙:
--   - User 입장에서 row 1개 = inbox 1줄. 멤버가 N명인 채널에 메시지 1개 →
--     그 멤버 N-1명에게 row N-1개. (sender 본인은 제외.)
--   - preview_title / preview_body는 source row(예: chat_messages)가 나중에
--     수정/삭제되어도 그대로 렌더 가능하도록 *시점 스냅샷*.
--   - dismiss는 soft (dismissed_at 채움). 영구 삭제는 nightly job 또는
--     30일+ 된 row에 대한 cleanup으로 미래에.

-- ENUM — 미래 type 미리 자리만.
CREATE TYPE notification_type AS ENUM (
    'chat_message',
    'task_assigned',
    'task_due_soon',
    'meeting_starting',
    'mention',
    'agent_proposal'
);

CREATE TABLE public.notifications (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    type                notification_type NOT NULL,

    -- Polymorphic source pointer. For chat_message: source_id = chat_messages.id,
    -- source_session_id = chat_sessions.id.
    source_id           uuid NOT NULL,
    source_session_id   uuid REFERENCES public.chat_sessions(id) ON DELETE CASCADE,

    -- Snapshot fields rendered as-is by the UI.
    preview_title       text,           -- e.g. sender name (DM) or "#channel-name"
    preview_body        text,           -- e.g. message body (truncated)
    preview_meta        jsonb,          -- type-specific extras (kind/scope/project_id/author_id)

    read_at             timestamptz,    -- viewed in the inbox (not opened)
    dismissed_at        timestamptz,    -- explicit X click
    created_at          timestamptz NOT NULL DEFAULT now()
);

-- Most-frequent query: "my undismissed notifications, newest first".
CREATE INDEX notifications_user_inbox
    ON public.notifications (user_id, dismissed_at NULLS FIRST, created_at DESC);

-- Used by the AFTER-DELETE trigger on chat_messages so deleted messages don't
-- leave dangling notifications.
CREATE INDEX notifications_source ON public.notifications (source_id);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- A user can only ever see / mutate their own row.
CREATE POLICY "notif_select_own" ON public.notifications
    FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "notif_update_own" ON public.notifications
    FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "notif_delete_own" ON public.notifications
    FOR DELETE USING (user_id = auth.uid());
-- INSERT is performed exclusively by SECURITY DEFINER triggers (see below);
-- no direct INSERT policy is exposed to clients.

------------------------------------------------------------
-- Trigger: chat_message → notifications fanout
------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS trigger AS $$
DECLARE
    member_row   RECORD;
    s_kind       chat_session_kind;
    s_scope      chat_session_scope;
    s_name       text;
    s_project_id uuid;
    author_label text;
    body_snippet text;
BEGIN
    SELECT s.kind, s.scope, s.name, s.project_id
      INTO s_kind, s_scope, s_name, s_project_id
      FROM public.chat_sessions s
     WHERE s.id = NEW.session_id;

    SELECT COALESCE(
             u.nickname,
             NULLIF(TRIM(u.first_name || ' ' || u.last_name), ''),
             u.email,
             'User'
           )
      INTO author_label
      FROM public.users u WHERE u.id = NEW.author_id;

    -- Trim long messages so preview fits the dropdown (~200 chars).
    body_snippet := substring(NEW.body for 200);

    FOR member_row IN
        SELECT user_id
          FROM public.chat_session_members
         WHERE session_id = NEW.session_id
           AND user_id <> NEW.author_id
    LOOP
        INSERT INTO public.notifications (
            user_id, type, source_id, source_session_id,
            preview_title, preview_body, preview_meta
        )
        VALUES (
            member_row.user_id,
            'chat_message',
            NEW.id,
            NEW.session_id,
            CASE
                WHEN s_kind = 'dm'
                    THEN author_label
                ELSE
                    '#' || COALESCE(s_name, 'channel')
            END,
            CASE
                WHEN s_kind = 'dm'
                    THEN body_snippet
                ELSE
                    author_label || ': ' || body_snippet
            END,
            jsonb_build_object(
                'kind', s_kind,
                'scope', s_scope,
                'project_id', s_project_id,
                'author_id', NEW.author_id,
                'author_name', author_label
            )
        );
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_chat_message_notify
    AFTER INSERT ON public.chat_messages
    FOR EACH ROW EXECUTE FUNCTION public.notify_chat_message();

------------------------------------------------------------
-- Cleanup: deleting a chat message wipes its notifications too,
-- so the inbox doesn't show a row pointing at a vanished source.
------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cleanup_chat_message_notifications()
RETURNS trigger AS $$
BEGIN
    DELETE FROM public.notifications
     WHERE source_id = OLD.id
       AND type = 'chat_message';
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_chat_message_delete_notif_cleanup
    BEFORE DELETE ON public.chat_messages
    FOR EACH ROW EXECUTE FUNCTION public.cleanup_chat_message_notifications();
