-- Task priority를 디자인의 PRIORITY picker 기준으로 통일.
-- 5단계: lowest / low / medium / high / highest
--
-- 기존 task_priority: low / medium / high / urgent (4단계)
--   urgent → highest 로 매핑, 나머지는 동일.
--   lowest 는 신규 값 (기존 데이터에는 없음).
--
-- 패턴은 20260510000010_unify_status_enums.sql 와 동일:
-- 새 enum 생성 → 컬럼 text로 → CASE 매핑 → 새 enum cast → default 복원.

CREATE TYPE task_priority_new AS ENUM ('lowest', 'low', 'medium', 'high', 'highest');

-- 컬럼을 일시적으로 text로 (default 먼저 drop)
ALTER TABLE public.tasks ALTER COLUMN priority DROP DEFAULT;
ALTER TABLE public.tasks ALTER COLUMN priority TYPE text;

-- 기존 값 → 새 값 매핑
--   urgent → highest
--   high   → high
--   medium → medium
--   low    → low
UPDATE public.tasks SET priority = CASE
    WHEN priority = 'urgent' THEN 'highest'
    WHEN priority = 'high'   THEN 'high'
    WHEN priority = 'medium' THEN 'medium'
    WHEN priority = 'low'    THEN 'low'
    ELSE 'medium'
END;

-- 새 enum 타입으로 cast
ALTER TABLE public.tasks
    ALTER COLUMN priority TYPE task_priority_new
    USING priority::task_priority_new;

-- 기본값 'medium'로 재설정
ALTER TABLE public.tasks ALTER COLUMN priority SET DEFAULT 'medium';

-- 기존 enum 폐기, 새 enum 이름 변경
DROP TYPE task_priority;
ALTER TYPE task_priority_new RENAME TO task_priority;
