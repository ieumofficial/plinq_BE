-- User table
-- Supabase Auth의 auth.users와 별도로 비즈니스 프로필을 저장하는 public.users 테이블.
-- auth.users.id와 동일한 uuid를 PK로 사용하여 1:1 매핑.
CREATE TABLE public.users (
    id          uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email       text NOT NULL UNIQUE,
    first_name  text NOT NULL,
    last_name   text NOT NULL,
    nickname    text,
    job_title   text,
    language    text NOT NULL DEFAULT 'ko',
    notification_settings jsonb NOT NULL DEFAULT '{}',
    created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.users IS '사용자 프로필. auth.users와 1:1 매핑.';
COMMENT ON COLUMN public.users.job_title IS '직책 (자유 텍스트). 권한 role과 다른 개념.';
COMMENT ON COLUMN public.users.notification_settings IS '알림 on/off 매트릭스';
