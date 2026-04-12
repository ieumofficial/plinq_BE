-- handle_new_user 트리거 수정: job_title(회원가입 폼의 Role 필드) 포함
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
    INSERT INTO public.users (id, email, first_name, last_name, nickname, job_title)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'first_name', ''),
        COALESCE(NEW.raw_user_meta_data->>'last_name', ''),
        NEW.raw_user_meta_data->>'nickname',
        NEW.raw_user_meta_data->>'job_title'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
