-- 프로젝트 카테고리(EXEC, R&D 같은 free-text 라벨) 사용 안 함으로 결정.
-- 4번 마이그레이션에서 추가했던 컬럼 제거.

ALTER TABLE public.projects
    DROP COLUMN IF EXISTS category;
