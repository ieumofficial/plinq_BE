-- check_email_exists를 public.users 기준으로 변경
-- auth.users는 OTP 인증만 해도 생기지만,
-- public.users는 회원가입 완료(complete_registration) 시에만 생성됨
CREATE OR REPLACE FUNCTION public.check_email_exists(check_email text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS(SELECT 1 FROM public.users WHERE email = check_email);
$$;
