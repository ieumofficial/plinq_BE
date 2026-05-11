-- 가입 완료 시 (handle_new_user 트리거 또는 complete_registration) 본인 이메일과
-- 매칭되는 pending invite를 모두 소비해서 project_members / meeting_attendees row 자동 생성.

CREATE OR REPLACE FUNCTION public.process_pending_invites_for_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_email text;
BEGIN
    SELECT email INTO v_email FROM public.users WHERE id = p_user_id;
    IF v_email IS NULL THEN
        RETURN;
    END IF;

    -- 프로젝트 초대 처리
    INSERT INTO public.project_members (project_id, user_id, role)
    SELECT pi.project_id, p_user_id, pi.role
    FROM public.project_invites pi
    WHERE pi.consumed_at IS NULL
      AND lower(pi.email) = lower(v_email)
    ON CONFLICT (project_id, user_id) DO NOTHING;

    UPDATE public.project_invites
    SET consumed_at = now(), consumed_by = p_user_id
    WHERE consumed_at IS NULL
      AND lower(email) = lower(v_email);

    -- 회의 초대 처리
    INSERT INTO public.meeting_attendees (meeting_id, user_id, attendance)
    SELECT mi.meeting_id, p_user_id, 'invited'
    FROM public.meeting_invites mi
    WHERE mi.consumed_at IS NULL
      AND lower(mi.email) = lower(v_email)
    ON CONFLICT (meeting_id, user_id) DO NOTHING;

    UPDATE public.meeting_invites
    SET consumed_at = now(), consumed_by = p_user_id
    WHERE consumed_at IS NULL
      AND lower(email) = lower(v_email);
END;
$$;

-- handle_new_user 확장: public.users 생성 후 invites 처리
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
        )
        ON CONFLICT (id) DO NOTHING;

        PERFORM public.process_pending_invites_for_user(NEW.id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- complete_registration 확장: 동일 처리
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
DECLARE
    v_uid uuid := auth.uid();
BEGIN
    INSERT INTO public.users (id, email, first_name, last_name, nickname, job_title)
    VALUES (
        v_uid,
        (SELECT email FROM auth.users WHERE id = v_uid),
        p_first_name,
        p_last_name,
        p_nickname,
        p_job_title
    )
    ON CONFLICT (id) DO UPDATE SET
        first_name = EXCLUDED.first_name,
        last_name  = EXCLUDED.last_name,
        nickname   = EXCLUDED.nickname,
        job_title  = EXCLUDED.job_title;

    PERFORM public.process_pending_invites_for_user(v_uid);
END;
$$;
