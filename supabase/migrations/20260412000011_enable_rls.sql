-- Enable RLS on all public tables
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kanban_columns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_assignees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_attendees ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_agendas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_minutes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transcript_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.meeting_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.knowledge_chunks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_reflections ENABLE ROW LEVEL SECURITY;

------------------------------------------------------------
-- Helper: 현재 인증된 사용자의 uuid
------------------------------------------------------------
-- auth.uid() 사용 (Supabase built-in)

------------------------------------------------------------
-- Users: 본인 프로필만 읽기/수정
------------------------------------------------------------
CREATE POLICY "users_select_own" ON public.users
    FOR SELECT USING (id = auth.uid());

CREATE POLICY "users_update_own" ON public.users
    FOR UPDATE USING (id = auth.uid());

-- 같은 조직 멤버의 프로필 조회 허용
CREATE POLICY "users_select_same_org" ON public.users
    FOR SELECT USING (
        id IN (
            SELECT om.user_id FROM public.organization_members om
            WHERE om.org_id IN (
                SELECT org_id FROM public.organization_members WHERE user_id = auth.uid()
            )
        )
    );

------------------------------------------------------------
-- Organizations
------------------------------------------------------------
CREATE POLICY "org_select_member" ON public.organizations
    FOR SELECT USING (
        id IN (SELECT org_id FROM public.organization_members WHERE user_id = auth.uid())
    );

CREATE POLICY "org_insert" ON public.organizations
    FOR INSERT WITH CHECK (owner_id = auth.uid());

CREATE POLICY "org_update_owner" ON public.organizations
    FOR UPDATE USING (owner_id = auth.uid());

------------------------------------------------------------
-- OrganizationMembers
------------------------------------------------------------
CREATE POLICY "org_members_select" ON public.organization_members
    FOR SELECT USING (
        org_id IN (SELECT org_id FROM public.organization_members WHERE user_id = auth.uid())
    );

CREATE POLICY "org_members_insert_admin" ON public.organization_members
    FOR INSERT WITH CHECK (
        org_id IN (
            SELECT org_id FROM public.organization_members
            WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
        )
    );

CREATE POLICY "org_members_delete_admin" ON public.organization_members
    FOR DELETE USING (
        org_id IN (
            SELECT org_id FROM public.organization_members
            WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
        )
    );

------------------------------------------------------------
-- Teams: 같은 조직 소속이면 조회 가능
------------------------------------------------------------
CREATE POLICY "teams_select_org_member" ON public.teams
    FOR SELECT USING (
        org_id IN (SELECT org_id FROM public.organization_members WHERE user_id = auth.uid())
    );

CREATE POLICY "teams_insert_org_admin" ON public.teams
    FOR INSERT WITH CHECK (
        org_id IN (
            SELECT org_id FROM public.organization_members
            WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
        )
    );

CREATE POLICY "teams_update_org_admin" ON public.teams
    FOR UPDATE USING (
        org_id IN (
            SELECT org_id FROM public.organization_members
            WHERE user_id = auth.uid() AND role IN ('owner', 'admin')
        )
    );

------------------------------------------------------------
-- TeamMembers
------------------------------------------------------------
CREATE POLICY "team_members_select" ON public.team_members
    FOR SELECT USING (
        team_id IN (
            SELECT id FROM public.teams WHERE org_id IN (
                SELECT org_id FROM public.organization_members WHERE user_id = auth.uid()
            )
        )
    );

CREATE POLICY "team_members_manage" ON public.team_members
    FOR ALL USING (
        team_id IN (
            SELECT tm.team_id FROM public.team_members tm
            WHERE tm.user_id = auth.uid() AND tm.role = 'lead'
        )
    );

------------------------------------------------------------
-- Projects: 프로젝트 멤버만 접근
------------------------------------------------------------
CREATE POLICY "projects_select_member" ON public.projects
    FOR SELECT USING (
        id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
    );

CREATE POLICY "projects_insert" ON public.projects
    FOR INSERT WITH CHECK (lead_id = auth.uid());

CREATE POLICY "projects_update_lead" ON public.projects
    FOR UPDATE USING (
        lead_id = auth.uid()
        OR id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid() AND role = 'lead'
        )
    );

------------------------------------------------------------
-- ProjectMembers
------------------------------------------------------------
CREATE POLICY "project_members_select" ON public.project_members
    FOR SELECT USING (
        project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
    );

CREATE POLICY "project_members_manage" ON public.project_members
    FOR ALL USING (
        project_id IN (
            SELECT project_id FROM public.project_members
            WHERE user_id = auth.uid() AND role = 'lead'
        )
    );

------------------------------------------------------------
-- KanbanColumns: 프로젝트 멤버만
------------------------------------------------------------
CREATE POLICY "kanban_columns_project_member" ON public.kanban_columns
    FOR ALL USING (
        project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
    );

------------------------------------------------------------
-- Tasks: 프로젝트 멤버 또는 assignee
------------------------------------------------------------
CREATE POLICY "tasks_select" ON public.tasks
    FOR SELECT USING (
        project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
        OR team_id IN (SELECT team_id FROM public.team_members WHERE user_id = auth.uid())
        OR id IN (SELECT task_id FROM public.task_assignees WHERE user_id = auth.uid())
        -- 개인 task
        OR (project_id IS NULL AND team_id IS NULL AND created_by = auth.uid())
    );

CREATE POLICY "tasks_insert" ON public.tasks
    FOR INSERT WITH CHECK (created_by = auth.uid());

CREATE POLICY "tasks_update" ON public.tasks
    FOR UPDATE USING (
        created_by = auth.uid()
        OR id IN (SELECT task_id FROM public.task_assignees WHERE user_id = auth.uid())
    );

CREATE POLICY "tasks_delete" ON public.tasks
    FOR DELETE USING (created_by = auth.uid());

------------------------------------------------------------
-- TaskAssignees
------------------------------------------------------------
CREATE POLICY "task_assignees_select" ON public.task_assignees
    FOR SELECT USING (
        task_id IN (
            SELECT id FROM public.tasks WHERE
                project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
                OR team_id IN (SELECT team_id FROM public.team_members WHERE user_id = auth.uid())
                OR id IN (SELECT task_id FROM public.task_assignees WHERE user_id = auth.uid())
        )
    );

CREATE POLICY "task_assignees_manage" ON public.task_assignees
    FOR ALL USING (assigned_by = auth.uid() OR user_id = auth.uid());

------------------------------------------------------------
-- Meetings: 프로젝트 멤버
------------------------------------------------------------
CREATE POLICY "meetings_project_member" ON public.meetings
    FOR ALL USING (
        project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
    );

------------------------------------------------------------
-- Meeting sub-tables: 회의 접근 가능하면 하위 데이터도 접근
------------------------------------------------------------
CREATE POLICY "meeting_attendees_access" ON public.meeting_attendees
    FOR ALL USING (
        meeting_id IN (
            SELECT id FROM public.meetings
            WHERE project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
        )
    );

CREATE POLICY "meeting_agendas_access" ON public.meeting_agendas
    FOR ALL USING (
        meeting_id IN (
            SELECT id FROM public.meetings
            WHERE project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
        )
    );

CREATE POLICY "meeting_minutes_access" ON public.meeting_minutes
    FOR ALL USING (
        meeting_id IN (
            SELECT id FROM public.meetings
            WHERE project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
        )
    );

CREATE POLICY "transcript_segments_access" ON public.transcript_segments
    FOR ALL USING (
        meeting_id IN (
            SELECT id FROM public.meetings
            WHERE project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
        )
    );

CREATE POLICY "meeting_decisions_access" ON public.meeting_decisions
    FOR ALL USING (
        meeting_id IN (
            SELECT id FROM public.meetings
            WHERE project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
        )
    );

------------------------------------------------------------
-- Knowledge: 프로젝트 멤버
------------------------------------------------------------
CREATE POLICY "knowledge_documents_project_member" ON public.knowledge_documents
    FOR ALL USING (
        project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
    );

CREATE POLICY "knowledge_chunks_project_member" ON public.knowledge_chunks
    FOR ALL USING (
        project_id IN (SELECT project_id FROM public.project_members WHERE user_id = auth.uid())
    );

------------------------------------------------------------
-- Agent: 본인 대화만
------------------------------------------------------------
CREATE POLICY "agent_conversations_own" ON public.agent_conversations
    FOR ALL USING (user_id = auth.uid());

CREATE POLICY "agent_messages_own" ON public.agent_messages
    FOR ALL USING (
        conversation_id IN (
            SELECT id FROM public.agent_conversations WHERE user_id = auth.uid()
        )
    );

-- AgentReflection: scope에 따라 접근 제어
CREATE POLICY "agent_reflections_select" ON public.agent_reflections
    FOR SELECT USING (
        (scope = 'user' AND scope_id = auth.uid())
        OR (scope = 'project' AND scope_id IN (
            SELECT project_id FROM public.project_members WHERE user_id = auth.uid()
        ))
    );
