ALTER TABLE users
    ADD COLUMN IF NOT EXISTS auth_user_id UUID;

-- MVP has no signup flow: local accounts are created on first anonymous
-- Supabase sign-in, so email/name/password can no longer be required.
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN name DROP NOT NULL;
ALTER TABLE users ALTER COLUMN password DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS users_auth_user_id_idx
    ON users (auth_user_id)
    WHERE auth_user_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS user_data (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    presence BOOLEAN NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS user_data_user_timestamp_idx
    ON user_data (user_id, timestamp)
    WHERE presence = TRUE;

CREATE TABLE IF NOT EXISTS public.crowd_reports (
    user_id INTEGER PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
    level SMALLINT NOT NULL CHECK (level BETWEEN 1 AND 10),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE public.crowd_reports ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS crowd_reports_updated_at_idx
    ON public.crowd_reports (updated_at DESC)
    INCLUDE (level);

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = current_schema()
          AND table_name = 'user_data'
          AND column_name = 'timestamp'
          AND data_type = 'timestamp without time zone'
    ) THEN
        ALTER TABLE user_data
            ALTER COLUMN timestamp TYPE TIMESTAMPTZ
            USING timestamp AT TIME ZONE 'UTC';
    END IF;
END
$$;
