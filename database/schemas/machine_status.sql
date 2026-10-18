-- Machine inventory and the latest shared in-use report for each machine.
-- Run this once in the Supabase SQL editor after api_migration.sql.

CREATE TABLE IF NOT EXISTS public.machines (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    location TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS public.machine_status (
    machine_id INTEGER PRIMARY KEY
        REFERENCES public.machines (id) ON DELETE CASCADE,
    is_in_use BOOLEAN NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by INTEGER REFERENCES public.users (id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS machine_status_updated_at_idx
    ON public.machine_status (updated_at DESC);
