-- Per-user presence:
--   status              — current effective value shown to other members
--   status_is_manual    — true = the user set it by hand and we must not
--                         auto-flip it (e.g. LiveKit join shouldn't override
--                         "Unavailable")
-- Phase 2 will auto-set 'in_meeting' / 'available' from LiveKit webhooks
-- whenever status_is_manual = false.

CREATE TYPE user_status AS ENUM ('available', 'in_meeting', 'unavailable');

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS status            user_status NOT NULL DEFAULT 'available',
    ADD COLUMN IF NOT EXISTS status_is_manual  boolean     NOT NULL DEFAULT false;

-- Anyone signed in can see another user's status (member list dots etc.).
-- The existing users SELECT policy already allows this — no change needed.

-- Only the user themselves can update their own status row. Service role
-- (LiveKit webhook handler runs server-side) bypasses RLS.
DROP POLICY IF EXISTS "users_update_own_status" ON public.users;
CREATE POLICY "users_update_own_status"
    ON public.users
    FOR UPDATE
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());
