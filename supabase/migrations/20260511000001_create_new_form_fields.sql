-- "Create New" 폼들이 요구하는 추가 필드:
--   1) projects.color — 디자인의 6색 picker (Project Label 색)
--   2) meetings.meeting_type — Planning / Check-in / Review / Retrospective 탭

-- ─── projects.color ──────────────────────────────────────────────────────

ALTER TABLE public.projects
    ADD COLUMN IF NOT EXISTS color text NOT NULL DEFAULT 'blue';

COMMENT ON COLUMN public.projects.color IS
    'UI 색상 키 ("blue", "green", "amber", "red", "purple", "turquoise" 등). Project Label / avatar 색에 사용.';

-- ─── meetings.meeting_type ───────────────────────────────────────────────

CREATE TYPE meeting_type AS ENUM ('planning', 'check_in', 'review', 'retrospective');

ALTER TABLE public.meetings
    ADD COLUMN IF NOT EXISTS meeting_type meeting_type NOT NULL DEFAULT 'planning';

COMMENT ON COLUMN public.meetings.meeting_type IS
    '회의 유형. UI의 Meeting Type 탭(Planning/Check-in/Review/Retrospective)과 매핑.';
