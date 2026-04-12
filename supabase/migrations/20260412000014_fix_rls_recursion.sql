-- Fix: users_select_same_org 정책의 순환 참조 해결
-- organization_members RLS가 organization_members를 참조하고,
-- users RLS가 organization_members를 참조하면서 로그인 시
-- "Database error querying schema" 발생.
--
-- 해결: SECURITY DEFINER 함수로 RLS를 우회하여 조회.

-- 1. 현재 사용자의 조직 ID 목록을 반환하는 헬퍼 함수
CREATE OR REPLACE FUNCTION public.get_my_org_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT org_id FROM public.organization_members WHERE user_id = auth.uid();
$$;

-- 2. 현재 사용자와 같은 조직에 속한 유저 ID 목록
CREATE OR REPLACE FUNCTION public.get_my_org_member_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT DISTINCT om.user_id
    FROM public.organization_members om
    WHERE om.org_id IN (
        SELECT org_id FROM public.organization_members WHERE user_id = auth.uid()
    );
$$;

-- 3. 기존 순환 참조 정책 교체

-- users: 같은 조직 멤버 조회
DROP POLICY IF EXISTS "users_select_same_org" ON public.users;
CREATE POLICY "users_select_same_org" ON public.users
    FOR SELECT USING (id IN (SELECT public.get_my_org_member_ids()));

-- organization_members: 같은 조직 멤버 조회
DROP POLICY IF EXISTS "org_members_select" ON public.organization_members;
CREATE POLICY "org_members_select" ON public.organization_members
    FOR SELECT USING (org_id IN (SELECT public.get_my_org_ids()));

-- organization_members: admin/owner만 추가 가능
DROP POLICY IF EXISTS "org_members_insert_admin" ON public.organization_members;
CREATE POLICY "org_members_insert_admin" ON public.organization_members
    FOR INSERT WITH CHECK (
        org_id IN (
            SELECT om.org_id FROM public.organization_members om
            WHERE om.user_id = auth.uid() AND om.role IN ('owner', 'admin')
        )
    );

-- organization_members: admin/owner만 삭제 가능
DROP POLICY IF EXISTS "org_members_delete_admin" ON public.organization_members;
CREATE POLICY "org_members_delete_admin" ON public.organization_members
    FOR DELETE USING (
        org_id IN (
            SELECT om.org_id FROM public.organization_members om
            WHERE om.user_id = auth.uid() AND om.role IN ('owner', 'admin')
        )
    );
