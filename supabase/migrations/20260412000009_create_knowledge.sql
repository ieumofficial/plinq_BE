-- KnowledgeDocument
CREATE TABLE public.knowledge_documents (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id  uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    name        text NOT NULL,
    file_url    text,
    file_type   text,
    source      knowledge_source NOT NULL DEFAULT 'uploaded',
    uploaded_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
    uploaded_at timestamptz NOT NULL DEFAULT now()
);

-- KnowledgeChunk (pgvector)
CREATE TABLE public.knowledge_chunks (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id  uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    source_type chunk_source_type NOT NULL,
    source_id   uuid NOT NULL,
    chunk_text  text NOT NULL,
    embedding   vector(1536), -- OpenAI text-embedding-3-small 차원. 모델에 따라 조정
    metadata    jsonb NOT NULL DEFAULT '{}',
    created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN public.knowledge_chunks.source_id IS 'source_type에 따라 다른 테이블의 id를 참조 (polymorphic FK)';
COMMENT ON COLUMN public.knowledge_chunks.embedding IS 'Embedding 벡터. 차원은 사용 모델에 따라 조정 필요.';

-- Indexes
CREATE INDEX idx_knowledge_chunks_project_source ON public.knowledge_chunks(project_id, source_type);

-- HNSW index for vector similarity search
CREATE INDEX idx_knowledge_chunks_embedding ON public.knowledge_chunks
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);
