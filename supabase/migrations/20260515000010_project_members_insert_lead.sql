-- 프로젝트 생성 시 "lead가 다른 멤버를 추가"하는 INSERT가 RLS에 막히는 문제 수정.
--
-- 기존 정책(20260511000003): project_members_insert_self
--   FOR INSERT WITH CHECK (user_id = auth.uid())   -- 본인 행만
-- → createProject()가 다른 user들의 멤버 행을 bulk insert할 때
--   "new row violates row-level security policy for table project_members".
--   (주석에 "lead의 다른 멤버 추가는 추후 RPC로 분리"라고 미뤄둔 부분)
--
-- 해결: 본인 추가(트리거의 lead 자동 추가 포함) 또는 그 프로젝트의 lead면 허용.
-- projects 만 참조하므로 project_members 자기참조 재귀 없음
-- (20260515000004_org_select_owner.sql 와 동일한 안전 패턴).

DROP POLICY IF EXISTS "project_members_insert_self" ON public.project_members;
DROP POLICY IF EXISTS "project_members_insert" ON public.project_members;

CREATE POLICY "project_members_insert" ON public.project_members
    FOR INSERT WITH CHECK (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1
              FROM public.projects p
             WHERE p.id = project_members.project_id
               AND p.lead_id = auth.uid()
        )
    );
