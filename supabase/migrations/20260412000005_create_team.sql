-- Team
CREATE TABLE public.teams (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id      uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    name        text NOT NULL,
    description text
);

-- TeamMember
CREATE TABLE public.team_members (
    team_id     uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role        team_role NOT NULL DEFAULT 'member',
    PRIMARY KEY (team_id, user_id)
);
