-- Enable required extensions
-- gen_random_uuid()는 PostgreSQL 내장 함수이므로 uuid-ossp 불필요
CREATE EXTENSION IF NOT EXISTS "vector";
