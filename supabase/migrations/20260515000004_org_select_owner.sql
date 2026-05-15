-- org_select_member 정책에 owner_id = auth.uid() 분기 추가.
--
-- 배경: PostgREST가 .insert(...).select() (= INSERT ... RETURNING) 를 보내면
-- PostgreSQL은 INSERT WITH CHECK 외에 SELECT USING 정책도 새 row에 대해
-- 평가한다. 기존 정책은
--     id IN (SELECT org_id FROM organization_members WHERE user_id = auth.uid())
-- 인데, AFTER INSERT 트리거가 막 넣은 owner 멤버십이 SELECT 정책의 subquery
-- snapshot 안에서 보이지 않는 경우 row가 visible하지 않게 되어 42501이 발생.
-- → owner는 자기 org를 멤버십 테이블 상태와 상관 없이 항상 볼 수 있어야 의미상도 자연스러움.
DROP POLICY IF EXISTS "org_select_member" ON public.organizations;
CREATE POLICY "org_select_member" ON public.organizations
    FOR SELECT USING (
        owner_id = auth.uid()
        OR id IN (SELECT public.get_my_org_ids())
    );
