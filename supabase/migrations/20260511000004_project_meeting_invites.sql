-- 이메일로 미가입 사용자를 초대하는 pending invite 저장.
-- 가입 트리거에서 매칭되는 invite를 찾아 자동으로 멤버/참석자 row 생성.

CREATE TABLE public.project_invites (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id   uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    email        text NOT NULL,
    role         project_role NOT NULL DEFAULT 'editor',
    invited_by   uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    invited_at   timestamptz NOT NULL DEFAULT now(),
    consumed_at  timestamptz,
    consumed_by  uuid REFERENCES public.users(id) ON DELETE SET NULL
);

CREATE INDEX idx_project_invites_email_pending
    ON public.project_invites(lower(email))
    WHERE consumed_at IS NULL;

CREATE UNIQUE INDEX uniq_project_invites_pending
    ON public.project_invites(project_id, lower(email))
    WHERE consumed_at IS NULL;

CREATE TABLE public.meeting_invites (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id   uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
    email        text NOT NULL,
    invited_by   uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    invited_at   timestamptz NOT NULL DEFAULT now(),
    consumed_at  timestamptz,
    consumed_by  uuid REFERENCES public.users(id) ON DELETE SET NULL
);

CREATE INDEX idx_meeting_invites_email_pending
    ON public.meeting_invites(lower(email))
    WHERE consumed_at IS NULL;

CREATE UNIQUE INDEX uniq_meeting_invites_pending
    ON public.meeting_invites(meeting_id, lower(email))
    WHERE consumed_at IS NULL;

-- ─── RLS: 단순 정책 (재귀 회피) ──────────────────────────────────────────

ALTER TABLE public.project_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_invites ENABLE ROW LEVEL SECURITY;

-- 인증된 사용자는 모든 invite 읽기 가능 (앱이 .eq()로 필터)
CREATE POLICY "project_invites_select" ON public.project_invites
    FOR SELECT USING (auth.uid() IS NOT NULL);
CREATE POLICY "meeting_invites_select" ON public.meeting_invites
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- INSERT/UPDATE/DELETE: 인증된 사용자 전체 허용 (앱 단에서 admin/owner 검증 권장)
CREATE POLICY "project_invites_modify" ON public.project_invites
    FOR ALL USING (auth.uid() IS NOT NULL) WITH CHECK (invited_by = auth.uid());
CREATE POLICY "meeting_invites_modify" ON public.meeting_invites
    FOR ALL USING (auth.uid() IS NOT NULL) WITH CHECK (invited_by = auth.uid());
