-- Fix: project_members 정책의 자기참조 recursion 해결.
-- 같은 패턴이 organization_members에서 14번 마이그레이션으로 해결됐지만
-- project_members는 누락. SELECT 정책뿐 아니라 manage 정책도 자기참조라
-- 둘 다 SECURITY DEFINER 헬퍼로 우회.
--
-- 증상: project 생성 시 trigger가 project_members INSERT → 그 후 SELECT
-- 에서 RLS 평가 시 동일 테이블의 정책을 재귀 호출 →
-- "infinite recursion detected in policy for relation 'project_members'".

-- ─── Helpers (SECURITY DEFINER로 RLS 우회) ─────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_my_project_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT project_id FROM public.project_members WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_my_lead_project_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT project_id FROM public.project_members
    WHERE user_id = auth.uid() AND role = 'lead';
$$;

-- ─── project_members 정책 전체 교체 ────────────────────────────────────────

DROP POLICY IF EXISTS "project_members_select" ON public.project_members;
DROP POLICY IF EXISTS "project_members_manage" ON public.project_members;
DROP POLICY IF EXISTS "project_members_insert" ON public.project_members;
DROP POLICY IF EXISTS "project_members_update" ON public.project_members;
DROP POLICY IF EXISTS "project_members_delete" ON public.project_members;

-- SELECT: 본인 멤버십 + 자신이 속한 프로젝트의 다른 멤버
CREATE POLICY "project_members_select" ON public.project_members
    FOR SELECT USING (
        user_id = auth.uid()
        OR project_id IN (SELECT public.get_my_project_ids())
    );

-- INSERT: 본인을 추가하거나 (트리거에서 lead 자동 추가용),
--         프로젝트 lead가 다른 멤버 추가
CREATE POLICY "project_members_insert" ON public.project_members
    FOR INSERT WITH CHECK (
        user_id = auth.uid()
        OR project_id IN (SELECT public.get_my_lead_project_ids())
    );

-- UPDATE / DELETE: lead만
CREATE POLICY "project_members_update" ON public.project_members
    FOR UPDATE USING (project_id IN (SELECT public.get_my_lead_project_ids()));

CREATE POLICY "project_members_delete" ON public.project_members
    FOR DELETE USING (project_id IN (SELECT public.get_my_lead_project_ids()));

-- ─── projects SELECT 정책도 helper로 정리 (recursion 위험 동일) ──────────

DROP POLICY IF EXISTS "projects_select" ON public.projects;
CREATE POLICY "projects_select" ON public.projects
    FOR SELECT USING (id IN (SELECT public.get_my_project_ids()));

-- ─── 의존 테이블도 helper로 ──────────────────────────────────────────────

DROP POLICY IF EXISTS "kanban_columns_project_member" ON public.kanban_columns;
CREATE POLICY "kanban_columns_project_member" ON public.kanban_columns
    FOR ALL USING (project_id IN (SELECT public.get_my_project_ids()));

DROP POLICY IF EXISTS "tasks_select" ON public.tasks;
CREATE POLICY "tasks_select" ON public.tasks
    FOR SELECT USING (
        project_id IN (SELECT public.get_my_project_ids())
        OR team_id IN (SELECT team_id FROM public.team_members WHERE user_id = auth.uid())
        OR id IN (SELECT task_id FROM public.task_assignees WHERE user_id = auth.uid())
        -- 개인 task (project + team 모두 NULL)
        OR (project_id IS NULL AND team_id IS NULL AND created_by = auth.uid())
    );
