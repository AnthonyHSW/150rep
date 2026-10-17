-- Import the illustrative 150rep Page grid from chart.xlsx.
-- This is a weekly reference schedule, not live crowd measurements or user votes.
BEGIN;

CREATE TABLE IF NOT EXISTS public.crowd_schedule (
    day_of_week SMALLINT NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    hour_of_day SMALLINT NOT NULL CHECK (hour_of_day BETWEEN 0 AND 23),
    level SMALLINT NOT NULL CHECK (level BETWEEN 0 AND 100),
    is_illustrative BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (day_of_week, hour_of_day)
);

ALTER TABLE public.crowd_schedule ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'crowd_schedule'
          AND policyname = 'crowd_schedule_read'
    ) THEN
        CREATE POLICY crowd_schedule_read
            ON public.crowd_schedule
            FOR SELECT
            TO anon, authenticated
            USING (TRUE);
    END IF;
END;
$$;

GRANT SELECT ON TABLE public.crowd_schedule TO anon, authenticated;

INSERT INTO public.crowd_schedule
    (day_of_week, hour_of_day, level, is_illustrative)
VALUES
    (1,  6,  22, TRUE), (2,  6,  32, TRUE), (3,  6,  28, TRUE), (4,  6,  31, TRUE), (5,  6,  26, TRUE), (6,  6,   8, TRUE), (7,  6,   6, TRUE),
    (1,  7,  32, TRUE), (2,  7,  40, TRUE), (3,  7,  36, TRUE), (4,  7,  39, TRUE), (5,  7,  34, TRUE), (6,  7,  12, TRUE), (7,  7,  10, TRUE),
    (1,  8,  34, TRUE), (2,  8,  34, TRUE), (3,  8,  30, TRUE), (4,  8,  33, TRUE), (5,  8,  30, TRUE), (6,  8,  22, TRUE), (7,  8,  18, TRUE),
    (1,  9,  32, TRUE), (2,  9,  32, TRUE), (3,  9,  28, TRUE), (4,  9,  31, TRUE), (5,  9,  32, TRUE), (6,  9,  38, TRUE), (7,  9,  30, TRUE),
    (1, 10,  34, TRUE), (2, 10,  42, TRUE), (3, 10,  38, TRUE), (4, 10,  41, TRUE), (5, 10,  40, TRUE), (6, 10,  50, TRUE), (7, 10,  42, TRUE),
    (1, 11,  38, TRUE), (2, 11,  55, TRUE), (3, 11,  50, TRUE), (4, 11,  54, TRUE), (5, 11,  48, TRUE), (6, 11,  55, TRUE), (7, 11,  50, TRUE),
    (1, 12,  42, TRUE), (2, 12,  52, TRUE), (3, 12,  48, TRUE), (4, 12,  51, TRUE), (5, 12,  46, TRUE), (6, 12,  52, TRUE), (7, 12,  54, TRUE),
    (1, 13,  38, TRUE), (2, 13,  40, TRUE), (3, 13,  36, TRUE), (4, 13,  39, TRUE), (5, 13,  36, TRUE), (6, 13,  45, TRUE), (7, 13,  48, TRUE),
    (1, 14,  38, TRUE), (2, 14,  36, TRUE), (3, 14,  32, TRUE), (4, 14,  35, TRUE), (5, 14,  30, TRUE), (6, 14,  40, TRUE), (7, 14,  42, TRUE),
    (1, 15,  46, TRUE), (2, 15,  50, TRUE), (3, 15,  46, TRUE), (4, 15,  49, TRUE), (5, 15,  40, TRUE), (6, 15,  35, TRUE), (7, 15,  38, TRUE),
    (1, 16,  64, TRUE), (2, 16,  70, TRUE), (3, 16,  66, TRUE), (4, 16,  69, TRUE), (5, 16,  54, TRUE), (6, 16,  30, TRUE), (7, 16,  36, TRUE),
    (1, 17,  88, TRUE), (2, 17,  88, TRUE), (3, 17,  82, TRUE), (4, 17,  86, TRUE), (5, 17,  66, TRUE), (6, 17,  24, TRUE), (7, 17,  34, TRUE),
    (1, 18,  99, TRUE), (2, 18,  92, TRUE), (3, 18,  88, TRUE), (4, 18,  91, TRUE), (5, 18,  70, TRUE), (6, 18,  18, TRUE), (7, 18,  30, TRUE),
    (1, 19, 100, TRUE), (2, 19,  80, TRUE), (3, 19,  76, TRUE), (4, 19,  79, TRUE), (5, 19,  58, TRUE), (6, 19,  12, TRUE), (7, 19,  26, TRUE),
    (1, 20,  86, TRUE), (2, 20,  62, TRUE), (3, 20,  58, TRUE), (4, 20,  61, TRUE), (5, 20,  42, TRUE), (6, 20,   8, TRUE), (7, 20,  20, TRUE),
    (1, 21,  60, TRUE), (2, 21,  44, TRUE), (3, 21,  40, TRUE), (4, 21,  43, TRUE), (5, 21,  28, TRUE), (6, 21,   5, TRUE), (7, 21,  12, TRUE),
    (1, 22,  34, TRUE), (2, 22,  26, TRUE), (3, 22,  24, TRUE), (4, 22,  25, TRUE), (5, 22,  16, TRUE), (6, 22,   3, TRUE), (7, 22,   6, TRUE),
    (1, 23,  17, TRUE), (2, 23,  12, TRUE), (3, 23,  10, TRUE), (4, 23,  11, TRUE), (5, 23,   8, TRUE), (6, 23,   2, TRUE), (7, 23,   3, TRUE)
ON CONFLICT (day_of_week, hour_of_day)
DO UPDATE SET level = EXCLUDED.level,
              is_illustrative = EXCLUDED.is_illustrative;

COMMIT;
