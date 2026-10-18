-- Time-based exercises: a set measured by how long it was held rather than by weight
-- and reps. Run workout_sync.sql first so the tables exist.
-- This migration is safe to run again.

BEGIN;

-- Marks the whole exercise, not the individual set: a plank is time-based every time it is
-- logged, and the set rows under one log must not disagree about which columns mean anything.
ALTER TABLE public.exercise_logs
    ADD COLUMN IF NOT EXISTS is_cardio BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE public.exercise_sets
    ADD COLUMN IF NOT EXISTS duration_seconds INTEGER;

-- Weight and reps have to become nullable, and their defaults have to go. A time-based set
-- sends them as null, and "0 kg × 0 reps" is not the same claim as "this set was not measured
-- that way" — the first reads as a logged set the user left empty.
ALTER TABLE public.exercise_sets
    ALTER COLUMN weight DROP NOT NULL,
    ALTER COLUMN weight DROP DEFAULT,
    ALTER COLUMN reps DROP NOT NULL,
    ALTER COLUMN reps DROP DEFAULT;

-- Durations are counted, never negative, and a zero-second hold is an unmeasured set rather
-- than a performed one — so leave it as null instead.
ALTER TABLE public.exercise_sets
    DROP CONSTRAINT IF EXISTS exercise_sets_duration_positive;
ALTER TABLE public.exercise_sets
    ADD CONSTRAINT exercise_sets_duration_positive
    CHECK (duration_seconds IS NULL OR duration_seconds > 0);

COMMIT;
