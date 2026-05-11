-- Recurring meetings.
-- 사용자가 모달에서 Repeat = once 가 아닌 값을 선택하면, recurrence_until 까지
-- 동일한 attendees/agenda를 가진 미래 인스턴스를 자동 생성한다.
-- 모든 생성 인스턴스는 동일한 recurrence_group_id 로 묶여서 한 번에 수정/삭제 가능.

CREATE TYPE meeting_recurrence AS ENUM ('once', 'every_day', 'every_week', 'every_year');

ALTER TABLE public.meetings
    ADD COLUMN IF NOT EXISTS recurrence meeting_recurrence NOT NULL DEFAULT 'once',
    ADD COLUMN IF NOT EXISTS recurrence_until date,
    ADD COLUMN IF NOT EXISTS recurrence_group_id uuid;

CREATE INDEX IF NOT EXISTS idx_meetings_recurrence_group
    ON public.meetings(recurrence_group_id)
    WHERE recurrence_group_id IS NOT NULL;

COMMENT ON COLUMN public.meetings.recurrence IS
    '회의 반복 주기. once 면 단일, 그 외는 recurrence_until 까지 매 주기 row 생성됨.';
COMMENT ON COLUMN public.meetings.recurrence_until IS
    '반복 종료일 (포함). recurrence != ''once'' 일 때만 의미 있음.';
COMMENT ON COLUMN public.meetings.recurrence_group_id IS
    '같은 시리즈에 속한 모든 인스턴스가 공유. 단일 회의는 NULL.';
