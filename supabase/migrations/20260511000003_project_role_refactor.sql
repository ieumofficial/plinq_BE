-- project_role 재구성: lead/member/viewer → editor/admin/readonly
-- "lead"는 더 이상 role이 아니라 projects.lead_id 컬럼으로 관리.
-- 기존 lead 멤버는 admin role로 보존됨.

-- ─── 1) role 컬럼을 참조하는 정책 모두 임시 삭제 (enum 교체 위함) ──────

DROP POLICY IF EXISTS "projects_update_lead" ON public.projects;
DROP POLICY IF EXISTS "project_members_select" ON public.project_members;
DROP POLICY IF EXISTS "project_members_manage" ON public.project_members;
DROP POLICY IF EXISTS "project_members_insert" ON public.project_members;
DROP POLICY IF EXISTS "project_members_update" ON public.project_members;
DROP POLICY IF EXISTS "project_members_delete" ON public.project_members;
DROP POLICY IF EXISTS "project_members_insert_self" ON public.project_members;
DROP POLICY IF EXISTS "project_members_update_self" ON public.project_members;
DROP POLICY IF EXISTS "project_members_delete_self" ON public.project_members;

-- ─── 2) project_role enum 교체 ─────────────────────────────────────────

CREATE TYPE project_role_new AS ENUM ('editor', 'admin', 'readonly');

-- column 타입 일시 text 변환 (default 먼저 drop)
ALTER TABLE public.project_members ALTER COLUMN role DROP DEFAULT;
ALTER TABLE public.project_members ALTER COLUMN role TYPE text;

-- 데이터 매핑
UPDATE public.project_members SET role = CASE
    WHEN role = 'lead'   THEN 'admin'
    WHEN role = 'member' THEN 'editor'
    WHEN role = 'viewer' THEN 'readonly'
    ELSE 'editor'
END;

-- 새 enum 으로 cast
ALTER TABLE public.project_members
    ALTER COLUMN role TYPE project_role_new
    USING role::project_role_new;

-- default 'editor' 로 재설정
ALTER TABLE public.project_members ALTER COLUMN role SET DEFAULT 'editor';

-- 기존 enum 폐기, 이름 변경
DROP TYPE project_role;
ALTER TYPE project_role_new RENAME TO project_role;

-- ─── 2) handle_new_project trigger: lead 멤버를 admin role 로 ───────────

CREATE OR REPLACE FUNCTION public.handle_new_project()
RETURNS trigger AS $$
BEGIN
    IF NEW.lead_id IS NOT NULL THEN
        INSERT INTO public.project_members (project_id, user_id, role)
        VALUES (NEW.id, NEW.lead_id, 'admin')
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─── 3) get_my_lead_project_ids 헬퍼: 이제 admin role 기준 ────────────────

CREATE OR REPLACE FUNCTION public.get_my_lead_project_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT pm.project_id
    FROM public.project_members pm
    JOIN public.projects p ON p.id = pm.project_id
    WHERE pm.user_id = auth.uid()
      AND (pm.role = 'admin' OR p.lead_id = auth.uid());
$$;

-- ─── 4) 삭제했던 정책들 복원 (008번 단순 정책 + projects_update) ────────

CREATE POLICY "project_members_select" ON public.project_members
    FOR SELECT USING (auth.uid() IS NOT NULL);

CREATE POLICY "project_members_insert_self" ON public.project_members
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "project_members_update_self" ON public.project_members
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "project_members_delete_self" ON public.project_members
    FOR DELETE USING (user_id = auth.uid());

-- projects update: lead_id 본인이거나 admin role
CREATE POLICY "projects_update_lead" ON public.projects
    FOR UPDATE USING (
        lead_id = auth.uid()
        OR id IN (SELECT public.get_my_lead_project_ids())
    );
