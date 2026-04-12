-- Meeting (forward declaration needed for Task.source_meeting_id FK)
-- Meeting is fully defined in the next migration; create a minimal shell here.
-- Actually, we defer the FK and add it after Meeting is created.

-- Task
CREATE TABLE public.tasks (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id        uuid REFERENCES public.projects(id) ON DELETE CASCADE,
    team_id           uuid REFERENCES public.teams(id) ON DELETE CASCADE,
    parent_task_id    uuid REFERENCES public.tasks(id) ON DELETE CASCADE,
    title             text NOT NULL,
    description       text,
    status            task_status NOT NULL DEFAULT 'todo',
    priority          task_priority NOT NULL DEFAULT 'medium',
    start_date        date,
    due_date          date,
    kanban_column_id  uuid REFERENCES public.kanban_columns(id) ON DELETE SET NULL,
    created_by        uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    source_meeting_id uuid, -- FK added after meetings table is created
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),

    -- Scope XOR: project_id와 team_id 둘 다 set 금지
    CONSTRAINT task_scope_xor CHECK (NOT (project_id IS NOT NULL AND team_id IS NOT NULL))
);

COMMENT ON COLUMN public.tasks.parent_task_id IS 'self-reference for subtask. NULL = top-level task';
COMMENT ON COLUMN public.tasks.source_meeting_id IS '회의에서 자동 생성된 task일 때만 채워짐';

-- TaskAssignee (다대다)
CREATE TABLE public.task_assignees (
    task_id     uuid NOT NULL REFERENCES public.tasks(id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role        task_assignee_role NOT NULL DEFAULT 'contributor',
    assigned_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    assigned_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (task_id, user_id)
);

-- Indexes
CREATE INDEX idx_tasks_project_parent ON public.tasks(project_id, parent_task_id);
CREATE INDEX idx_tasks_project_status ON public.tasks(project_id, status);
CREATE INDEX idx_tasks_team ON public.tasks(team_id) WHERE team_id IS NOT NULL;
CREATE INDEX idx_task_assignees_user ON public.task_assignees(user_id);

-- updated_at 자동 갱신 트리거
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tasks_updated_at
    BEFORE UPDATE ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
