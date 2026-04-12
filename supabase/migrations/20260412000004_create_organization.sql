-- Organization
CREATE TABLE public.organizations (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name        text NOT NULL,
    owner_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- OrganizationMember
CREATE TABLE public.organization_members (
    org_id      uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    role        org_role NOT NULL DEFAULT 'member',
    permissions jsonb NOT NULL DEFAULT '{}',
    joined_at   timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (org_id, user_id)
);

COMMENT ON COLUMN public.organization_members.permissions IS 'Empowerment 매트릭스 (예: can_create_project, can_invite_member)';
