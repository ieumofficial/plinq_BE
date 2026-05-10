-- 디자인의 ProgressLabel(889:7487) 기준으로 status를 통일.
-- 5단계: planned / in_progress / review / blocked / done
--
-- task_status: 'todo'를 'planned'로 rename. (나머지는 이미 일치)
-- project_status: planning/active/on_hold/done → planned/in_progress/review/blocked/done
--                 기존 데이터는 의미 비슷한 것으로 매핑.

-- ─── 1) task_status: 단순 rename ─────────────────────────────────────────

ALTER TYPE task_status RENAME VALUE 'todo' TO 'planned';

-- ─── 2) project_status: 새 enum + 데이터 마이그레이션 ────────────────────

CREATE TYPE project_status_new AS ENUM ('planned', 'in_progress', 'review', 'blocked', 'done');

-- column을 일시적으로 text로 변환 (default 먼저 drop)
ALTER TABLE public.projects ALTER COLUMN status DROP DEFAULT;
ALTER TABLE public.projects ALTER COLUMN status TYPE text;

-- 기존 값 → 새 값 매핑
--   planning → planned
--   active   → in_progress
--   on_hold  → blocked
--   done     → done
UPDATE public.projects SET status = CASE
    WHEN status = 'planning' THEN 'planned'
    WHEN status = 'active'   THEN 'in_progress'
    WHEN status = 'on_hold'  THEN 'blocked'
    WHEN status = 'done'     THEN 'done'
    ELSE 'planned'
END;

-- 새 enum 타입으로 cast
ALTER TABLE public.projects
    ALTER COLUMN status TYPE project_status_new
    USING status::project_status_new;

-- 기본값 'planned'로 재설정
ALTER TABLE public.projects ALTER COLUMN status SET DEFAULT 'planned';

-- 기존 enum 폐기, 새 enum 이름 변경
DROP TYPE project_status;
ALTER TYPE project_status_new RENAME TO project_status;
