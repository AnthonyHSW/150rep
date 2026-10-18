-- Add cardio exercise classification and time-based set measurements.
-- Run after workout_sync.sql. Safe to run more than once.

BEGIN;

ALTER TABLE public.exercise_logs
    ADD COLUMN IF NOT EXISTS is_cardio BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.exercise_sets
    ADD COLUMN IF NOT EXISTS duration_seconds INTEGER;

ALTER TABLE public.exercise_sets
    ALTER COLUMN weight DROP NOT NULL,
    ALTER COLUMN weight DROP DEFAULT,
    ALTER COLUMN reps DROP NOT NULL,
    ALTER COLUMN reps DROP DEFAULT;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'exercise_sets_duration_seconds_nonnegative'
          AND conrelid = 'public.exercise_sets'::regclass
    ) THEN
        ALTER TABLE public.exercise_sets
            ADD CONSTRAINT exercise_sets_duration_seconds_nonnegative
            CHECK (duration_seconds IS NULL OR duration_seconds >= 0);
    END IF;
END
$$;

NOTIFY pgrst, 'reload schema';

COMMIT;
