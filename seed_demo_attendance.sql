-- Adds enough sample visits to bring one user's current Los Angeles calendar
-- week to four. Replace the email below before running this in Supabase.
-- This changes real attendance data and does not label inserted rows as demo data.
BEGIN;

LOCK TABLE user_data IN SHARE ROW EXCLUSIVE MODE;

DO $$
DECLARE
    target_email TEXT := 'wongah3@uci.edu';
    local_timezone TEXT := 'America/Los_Angeles';
    target_user_id INTEGER;
    matching_users INTEGER;
    week_start DATE;
    existing_visits INTEGER;
    visit_slot RECORD;
BEGIN
    SELECT COUNT(*), MIN(id)
    INTO matching_users, target_user_id
    FROM users
    WHERE LOWER(email) = LOWER(target_email);

    IF matching_users <> 1 THEN
        RAISE EXCEPTION
            'Expected exactly one users row for %, found %',
            target_email,
            matching_users;
    END IF;

    week_start :=
        DATE_TRUNC('week', CURRENT_TIMESTAMP AT TIME ZONE local_timezone)::DATE;

    SELECT COUNT(*)
    INTO existing_visits
    FROM user_data
    WHERE user_id = target_user_id
      AND presence = TRUE
      AND timestamp >= (week_start::TIMESTAMP AT TIME ZONE local_timezone)
      AND timestamp < (
          ((week_start + 7)::TIMESTAMP AT TIME ZONE local_timezone)
      );

    FOR visit_slot IN
        SELECT sample.visit_number, sample.day_offset
        FROM (VALUES (1, 0), (2, 1), (3, 3), (4, 5))
            AS sample(visit_number, day_offset)
        WHERE sample.visit_number > existing_visits
        ORDER BY sample.visit_number
    LOOP
        INSERT INTO user_data (user_id, presence, timestamp)
        VALUES (
            target_user_id,
            TRUE,
            (
                (week_start + visit_slot.day_offset)::DATE + TIME '10:00'
            ) AT TIME ZONE local_timezone
        );
    END LOOP;

    RAISE NOTICE
        'Added % demo visit(s); user % now has at least four visits for the week starting % (%).',
        GREATEST(4 - existing_visits, 0),
        target_user_id,
        week_start,
        local_timezone;
END;
$$;

COMMIT;
