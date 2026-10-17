# 150rep
ZotHacks Workout App with busy-ness meter for UCI students
Made by Anthony & Janice & Oliver

Using SWIFT for the front end of the app, using SQL and Supabase for the database.

## Workout attendance calendar

Run [`workout_attendance.sql`](./workout_attendance.sql) in the Supabase SQL editor
to create the attendance event table. Each row represents one visit; `attended_at`
stores a time-zone-aware instant, and `user_id` associates it with a user.
Calendar days and weeks can be calculated in the user's local time zone. Multiple
visits on the same day are allowed.

Count a user's visits per week with:

```sql
SELECT date_trunc(
           'week',
           attended_at AT TIME ZONE 'America/Los_Angeles'
       ) AS week_start,
       COUNT(*) AS visits
FROM workout_attendance
WHERE user_id = $1
GROUP BY week_start
ORDER BY week_start;
```

Replace `$1` with the user's id and use their IANA time zone in place of
`America/Los_Angeles` so visits are grouped by their local calendar week.
