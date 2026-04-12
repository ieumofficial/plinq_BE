-- AgentConversation
CREATE TABLE public.agent_conversations (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    project_id  uuid REFERENCES public.projects(id) ON DELETE CASCADE,
    title       text,
    created_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN public.agent_conversations.project_id IS 'NULL = Personal Agent, 값 있음 = Project Agent';

CREATE INDEX idx_agent_conversations_user ON public.agent_conversations(user_id);
CREATE INDEX idx_agent_conversations_project ON public.agent_conversations(project_id) WHERE project_id IS NOT NULL;

-- AgentMessage
CREATE TABLE public.agent_messages (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id uuid NOT NULL REFERENCES public.agent_conversations(id) ON DELETE CASCADE,
    role            agent_message_role NOT NULL,
    content         text NOT NULL,
    tokens_used     int,
    created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_agent_messages_conversation ON public.agent_messages(conversation_id, created_at);

-- AgentReflection
CREATE TABLE public.agent_reflections (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    scope           agent_scope NOT NULL,
    scope_id        uuid NOT NULL,
    reflection_type reflection_type NOT NULL,
    content         text NOT NULL,
    embedding       vector(1536),
    importance      real NOT NULL DEFAULT 0.5,
    valid_from      timestamptz NOT NULL DEFAULT now(),
    created_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN public.agent_reflections.scope_id IS 'scope=user일 때 user_id, scope=project일 때 project_id';

CREATE INDEX idx_agent_reflections_scope ON public.agent_reflections(scope, scope_id, reflection_type);
CREATE INDEX idx_agent_reflections_importance ON public.agent_reflections(scope, scope_id, importance DESC);
