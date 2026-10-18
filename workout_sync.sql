-- Workout session schema for direct Supabase PostgREST access.
-- Run workout_photos.sql first so public.workout_photos and its Storage bucket exist.
-- This migration is safe to run again.

BEGIN;

CREATE TABLE IF NOT EXISTS public.workout_sessions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL DEFAULT auth.uid()
        REFERENCES auth.users (id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    status TEXT NOT NULL
        CHECK (status IN ('active', 'completed', 'discarded')),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.exercise_logs (
    id UUID PRIMARY KEY,
    session_id UUID NOT NULL
        REFERENCES public.workout_sessions (id) ON DELETE CASCADE,
    user_id UUID NOT NULL DEFAULT auth.uid()
        REFERENCES auth.users (id) ON DELETE CASCADE,
    exercise_id TEXT NOT NULL,
    name TEXT NOT NULL,
    primary_muscle TEXT NOT NULL,
    image_name TEXT NOT NULL DEFAULT '',
    order_index INTEGER NOT NULL,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS public.exercise_sets (
    id UUID PRIMARY KEY,
    exercise_log_id UUID NOT NULL
        REFERENCES public.exercise_logs (id) ON DELETE CASCADE,
    user_id UUID NOT NULL DEFAULT auth.uid()
        REFERENCES auth.users (id) ON DELETE CASCADE,
    set_number INTEGER NOT NULL,
    set_type TEXT NOT NULL CHECK (set_type IN ('W', 'N', 'D', 'F')),
    weight DOUBLE PRECISION NOT NULL DEFAULT 0,
    reps INTEGER NOT NULL DEFAULT 0,
    is_completed BOOLEAN NOT NULL DEFAULT false,
    completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS workout_sessions_user_start_idx
    ON public.workout_sessions (user_id, start_time DESC);
CREATE INDEX IF NOT EXISTS exercise_logs_session_order_idx
    ON public.exercise_logs (session_id, order_index);
CREATE INDEX IF NOT EXISTS exercise_sets_log_number_idx
    ON public.exercise_sets (exercise_log_id, set_number);

ALTER TABLE public.workout_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercise_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.exercise_sets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own workout sessions"
    ON public.workout_sessions;
CREATE POLICY "Users manage own workout sessions"
    ON public.workout_sessions
    FOR ALL TO authenticated
    USING (
        user_id = auth.uid()
        AND coalesce(auth.jwt() ->> 'email', '') ~* '^[^@]+@uci[.]edu$'
    )
    WITH CHECK (
        user_id = auth.uid()
        AND coalesce(auth.jwt() ->> 'email', '') ~* '^[^@]+@uci[.]edu$'
    );

DROP POLICY IF EXISTS "Users manage own exercise logs"
    ON public.exercise_logs;
CREATE POLICY "Users manage own exercise logs"
    ON public.exercise_logs
    FOR ALL TO authenticated
    USING (
        user_id = auth.uid()
        AND coalesce(auth.jwt() ->> 'email', '') ~* '^[^@]+@uci[.]edu$'
    )
    WITH CHECK (
        user_id = auth.uid()
        AND coalesce(auth.jwt() ->> 'email', '') ~* '^[^@]+@uci[.]edu$'
    );

DROP POLICY IF EXISTS "Users manage own exercise sets"
    ON public.exercise_sets;
CREATE POLICY "Users manage own exercise sets"
    ON public.exercise_sets
    FOR ALL TO authenticated
    USING (
        user_id = auth.uid()
        AND coalesce(auth.jwt() ->> 'email', '') ~* '^[^@]+@uci[.]edu$'
    )
    WITH CHECK (
        user_id = auth.uid()
        AND coalesce(auth.jwt() ->> 'email', '') ~* '^[^@]+@uci[.]edu$'
    );

GRANT SELECT, INSERT, UPDATE, DELETE
    ON public.workout_sessions, public.exercise_logs, public.exercise_sets
    TO authenticated;

CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS workout_sessions_touch_updated_at
    ON public.workout_sessions;
CREATE TRIGGER workout_sessions_touch_updated_at
    BEFORE UPDATE ON public.workout_sessions
    FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

DO $$
BEGIN
    IF to_regclass('public.workout_photos') IS NULL THEN
        RAISE EXCEPTION
            'public.workout_photos is missing; run workout_photos.sql before workout_sync.sql';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'workout_photos_session_id_fkey'
          AND conrelid = 'public.workout_photos'::regclass
    ) THEN
        ALTER TABLE public.workout_photos
            ADD CONSTRAINT workout_photos_session_id_fkey
            FOREIGN KEY (session_id)
            REFERENCES public.workout_sessions (id)
            ON DELETE CASCADE
            NOT VALID;
    END IF;
END
$$;

DROP POLICY IF EXISTS "Users manage own workout photos"
    ON public.workout_photos;
CREATE POLICY "Users manage own workout photos"
    ON public.workout_photos
    FOR ALL TO authenticated
    USING (
        user_id = auth.uid()
        AND coalesce(auth.jwt() ->> 'email', '') ~* '^[^@]+@uci[.]edu$'
    )
    WITH CHECK (
        user_id = auth.uid()
        AND coalesce(auth.jwt() ->> 'email', '') ~* '^[^@]+@uci[.]edu$'
    );

GRANT SELECT, INSERT, UPDATE, DELETE
    ON public.workout_photos TO authenticated;

DROP POLICY IF EXISTS "Users manage own workout photo files"
    ON storage.objects;
CREATE POLICY "Users manage own workout photo files"
    ON storage.objects
    FOR ALL TO authenticated
    USING (
        bucket_id = 'workout-photos'
        AND (storage.foldername(name))[1] = auth.uid()::text
        AND coalesce(auth.jwt() ->> 'email', '') ~* '^[^@]+@uci[.]edu$'
    )
    WITH CHECK (
        bucket_id = 'workout-photos'
        AND (storage.foldername(name))[1] = auth.uid()::text
        AND coalesce(auth.jwt() ->> 'email', '') ~* '^[^@]+@uci[.]edu$'
    );

COMMIT;
