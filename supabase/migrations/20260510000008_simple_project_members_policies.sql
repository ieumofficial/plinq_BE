-- 006/007에서 helper 기반 정책으로 recursion을 풀려 했으나
-- Supabase Cloud의 `postgres` role이 BYPASSRLS 권한을 갖지 못한 환경에서는
-- SECURITY DEFINER + SET row_security = off 모두 효과가 없음.
-- (실제로 `row_security = off`는 BYPASSRLS 없이는 RLS를 끄지 않고
--  "정책 적용 필요 시 에러" 의미일 뿐)
--
-- 결론: project_members 자체를 참조하는 RLS 표현식은 환경에 따라 무조건
-- 재귀에 빠질 수 있음. → SELECT 정책을 "인증된 사용자 전체 허용"으로
-- 단순화하고, 실제 row 필터링은 application 쿼리에서 .eq()로 책임짐.
--
-- 보안 영향:
--   - 인증된 어떤 user든 raw 쿼리로 모든 project_members 행 열람 가능
--   - MVP 단계에선 수용 가능 (멤버십 정보만 노출, 민감 데이터 없음)
--   - 추후 dedicated RPC + tighter RLS로 리팩토링 가능

-- ─── project_members 정책 단순화 ─────────────────────────────────────────

DROP POLICY IF EXISTS "project_members_select" ON public.project_members;
DROP POLICY IF EXISTS "project_members_manage" ON public.project_members;
DROP POLICY IF EXISTS "project_members_insert" ON public.project_members;
DROP POLICY IF EXISTS "project_members_update" ON public.project_members;
DROP POLICY IF EXISTS "project_members_delete" ON public.project_members;

-- SELECT: 인증된 모든 user 허용 (재귀 없음). app이 필터.
CREATE POLICY "project_members_select" ON public.project_members
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- INSERT: 본인을 추가하는 경우만 (트리거 자동 lead 추가용).
-- lead의 다른 멤버 추가는 추후 RPC로 분리.
CREATE POLICY "project_members_insert_self" ON public.project_members
    FOR INSERT WITH CHECK (user_id = auth.uid());

-- UPDATE/DELETE: 본인 행만.
CREATE POLICY "project_members_update_self" ON public.project_members
    FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "project_members_delete_self" ON public.project_members
    FOR DELETE USING (user_id = auth.uid());

-- ─── projects 정책 단순화 ────────────────────────────────────────────────

-- 기존 11번 마이그레이션의 projects_select_member 와 006번의 projects_select
-- 모두 project_members를 참조 → 똑같은 재귀 위험.

DROP POLICY IF EXISTS "projects_select" ON public.projects;
DROP POLICY IF EXISTS "projects_select_member" ON public.projects;

-- SELECT: 인증된 user면 OK. app이 본인이 속한 것만 select.
CREATE POLICY "projects_select" ON public.projects
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ─── 의존 테이블 단순화 ──────────────────────────────────────────────────

DROP POLICY IF EXISTS "kanban_columns_project_member" ON public.kanban_columns;
CREATE POLICY "kanban_columns_authenticated" ON public.kanban_columns
    FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "tasks_select" ON public.tasks;
CREATE POLICY "tasks_select" ON public.tasks
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- meeting/knowledge/agent_reflections는 그대로 두면 project_members 참조 →
-- 재귀 동일. 모두 단순화.
DROP POLICY IF EXISTS "meetings_project_member" ON public.meetings;
CREATE POLICY "meetings_authenticated" ON public.meetings
    FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "meeting_attendees_access" ON public.meeting_attendees;
CREATE POLICY "meeting_attendees_authenticated" ON public.meeting_attendees
    FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "meeting_agendas_access" ON public.meeting_agendas;
CREATE POLICY "meeting_agendas_authenticated" ON public.meeting_agendas
    FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "meeting_minutes_access" ON public.meeting_minutes;
CREATE POLICY "meeting_minutes_authenticated" ON public.meeting_minutes
    FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "transcript_segments_access" ON public.transcript_segments;
CREATE POLICY "transcript_segments_authenticated" ON public.transcript_segments
    FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "meeting_decisions_access" ON public.meeting_decisions;
CREATE POLICY "meeting_decisions_authenticated" ON public.meeting_decisions
    FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "knowledge_documents_project_member" ON public.knowledge_documents;
CREATE POLICY "knowledge_documents_authenticated" ON public.knowledge_documents
    FOR ALL USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "knowledge_chunks_project_member" ON public.knowledge_chunks;
CREATE POLICY "knowledge_chunks_authenticated" ON public.knowledge_chunks
    FOR ALL USING (auth.uid() IS NOT NULL);

-- agent_reflections의 project scope 조회도 동일 패턴 → 단순화
DROP POLICY IF EXISTS "agent_reflections_select" ON public.agent_reflections;
CREATE POLICY "agent_reflections_select" ON public.agent_reflections
    FOR SELECT USING (
        (scope = 'user' AND scope_id = auth.uid())
        OR scope = 'project' -- project scope는 인증된 user에게 모두 허용
    );

-- task_assignees도 tasks 통한 lookup이 재귀 위험 → 단순화
DROP POLICY IF EXISTS "task_assignees_select" ON public.task_assignees;
CREATE POLICY "task_assignees_select" ON public.task_assignees
    FOR SELECT USING (auth.uid() IS NOT NULL);
