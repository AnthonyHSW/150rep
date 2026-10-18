-- All-time karma earned by submitting crowd reports.
-- Run after api_migration.sql. Safe to run more than once.

BEGIN;

ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS avatar_url TEXT,
    ADD COLUMN IF NOT EXISTS karma_points INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_crowd_karma_at TIMESTAMPTZ;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'users_karma_points_nonnegative'
          AND conrelid = 'public.users'::regclass
    ) THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_karma_points_nonnegative
            CHECK (karma_points >= 0);
    END IF;
END
$$;

CREATE INDEX IF NOT EXISTS users_karma_leaderboard_idx
    ON public.users (karma_points DESC, id ASC)
    WHERE auth_user_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';

COMMIT;
