-- Fix: 006번 마이그레이션의 helper 함수가 SECURITY DEFINER만으로
-- RLS bypass가 안 되는 환경(특정 Supabase Cloud 설정)에서 여전히
-- "infinite recursion detected in policy for relation 'project_members'"
-- 가 발생.
--
-- 해결: 함수 정의에 SET row_security = off 를 명시적으로 박아서
-- BYPASSRLS 권한 유무와 무관하게 함수 호출 동안 RLS를 끔.
--
-- CREATE OR REPLACE이므로 정책은 그대로 두고 함수 본문만 교체.

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

-- organization 쪽 helper도 같은 방어막 적용 (14번에서 만들어진 것들)
CREATE OR REPLACE FUNCTION public.get_my_org_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT org_id FROM public.organization_members WHERE user_id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.get_my_org_member_ids()
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
SET row_security = off
AS $$
    SELECT DISTINCT om.user_id
    FROM public.organization_members om
    WHERE om.org_id IN (
        SELECT org_id FROM public.organization_members WHERE user_id = auth.uid()
    );
$$;
