-- Project
CREATE TABLE public.projects (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id     uuid REFERENCES public.teams(id) ON DELETE SET NULL,
    name        text NOT NULL,
    description text,
    lead_id     uuid REFERENCES public.users(id) ON DELETE SET NULL,
    status      project_status NOT NULL DEFAULT 'planning',
    budget      decimal,
    created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN public.projects.team_id IS 'nullable — team에 속하지 않는 독립 프로젝트 허용';

-- ProjectMember
CREATE TABLE public.project_members (
    project_id  uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role        project_role NOT NULL DEFAULT 'member',
    PRIMARY KEY (project_id, user_id)
);

-- KanbanColumn
CREATE TABLE public.kanban_columns (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id  uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    name        text NOT NULL,
    "order"     int NOT NULL DEFAULT 0
);

CREATE INDEX idx_kanban_columns_project ON public.kanban_columns(project_id, "order");
