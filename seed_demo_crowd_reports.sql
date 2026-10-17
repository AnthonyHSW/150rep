-- Demo-only data for GET /v1/crowd-level.
-- Run only in a development/test project: these votes affect the global average.
BEGIN;

INSERT INTO public.users (name, email, password)
VALUES
    ('Demo crowd voter 1', 'demo-crowd-voter-1@example.invalid', NULL),
    ('Demo crowd voter 2', 'demo-crowd-voter-2@example.invalid', NULL)
ON CONFLICT (email) DO NOTHING;

INSERT INTO public.crowd_reports (user_id, level, updated_at)
SELECT users.id, demo.level, CURRENT_TIMESTAMP
FROM (
    VALUES
        ('demo-crowd-voter-1@example.invalid', 4),
        ('demo-crowd-voter-2@example.invalid', 6)
) AS demo(email, level)
JOIN public.users AS users
    ON users.email = demo.email
WHERE TRUE
ON CONFLICT (user_id)
DO UPDATE SET level = EXCLUDED.level,
              updated_at = CURRENT_TIMESTAMP;

COMMIT;
