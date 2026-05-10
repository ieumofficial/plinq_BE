-- 1. handle_new_user 트리거 수정: first_name이 없으면 public.users 생성 건너뜀
-- OTP 인증만 한 상태에서는 metadata가 비어있으므로 public.users가 만들어지지 않음
-- signUp 또는 Admin API로 생성할 때는 metadata에 first_name이 있으므로 정상 생성됨
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
    IF COALESCE(NEW.raw_user_meta_data->>'first_name', '') != '' THEN
        INSERT INTO public.users (id, email, first_name, last_name, nickname, job_title)
        VALUES (
            NEW.id,
            NEW.email,
            NEW.raw_user_meta_data->>'first_name',
            COALESCE(NEW.raw_user_meta_data->>'last_name', ''),
            NEW.raw_user_meta_data->>'nickname',
            NEW.raw_user_meta_data->>'job_title'
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. 회원가입 완료 시 호출하는 함수
-- auth.uid()로 본인만 가능, SECURITY DEFINER로 RLS 우회
CREATE OR REPLACE FUNCTION public.complete_registration(
    p_first_name text,
    p_last_name text,
    p_nickname text DEFAULT NULL,
    p_job_title text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.users (id, email, first_name, last_name, nickname, job_title)
    VALUES (
        auth.uid(),
        (SELECT email FROM auth.users WHERE id = auth.uid()),
        p_first_name,
        p_last_name,
        p_nickname,
        p_job_title
    )
    ON CONFLICT (id) DO UPDATE SET
        first_name = EXCLUDED.first_name,
        last_name = EXCLUDED.last_name,
        nickname = EXCLUDED.nickname,
        job_title = EXCLUDED.job_title;
END;
$$;
