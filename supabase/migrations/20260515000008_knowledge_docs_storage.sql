-- Knowledge base file uploads.
--
-- A private Storage bucket holding the original files attached to
-- knowledge_documents. The DB row stores the *object path* in
-- knowledge_documents.file_url (not a public URL); the client mints a
-- short-lived signed URL on demand to view/download it.
--
-- RLS mirrors the project's permissive convention (see
-- 20260510000008_simple_project_members_policies.sql): any authenticated
-- user can read/write. Per-project isolation is enforced at the app layer
-- via knowledge_documents.project_id, same as the rest of the schema.

INSERT INTO storage.buckets (id, name, public)
VALUES ('knowledge-docs', 'knowledge-docs', false)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "knowledge_docs_read" ON storage.objects;
CREATE POLICY "knowledge_docs_read" ON storage.objects
    FOR SELECT USING (
        bucket_id = 'knowledge-docs' AND auth.uid() IS NOT NULL
    );

DROP POLICY IF EXISTS "knowledge_docs_insert" ON storage.objects;
CREATE POLICY "knowledge_docs_insert" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'knowledge-docs' AND auth.uid() IS NOT NULL
    );

DROP POLICY IF EXISTS "knowledge_docs_update" ON storage.objects;
CREATE POLICY "knowledge_docs_update" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'knowledge-docs' AND auth.uid() IS NOT NULL
    );

DROP POLICY IF EXISTS "knowledge_docs_delete" ON storage.objects;
CREATE POLICY "knowledge_docs_delete" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'knowledge-docs' AND auth.uid() IS NOT NULL
    );
