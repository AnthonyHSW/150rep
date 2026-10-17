# 150rep
ZotHacks Workout App with busy-ness meter for UCI students
Made by Anthony & Janice & Oliver

Using SWIFT for the front end of the app, using SQL and Supabase for the database.

## Workout attendance calendar

The current API stores each visit as a `presence = TRUE` row in `user_data`,
using a time-zone-aware `timestamp`. It can return daily counts in the user's
IANA time zone; multiple visits on one day are counted separately. The
standalone [`workout_attendance.sql`](./workout_attendance.sql) file describes an
alternative table and is not used by this API.

## HTTP API for the Swift app

The Swift client calls this API over HTTPS; it must not connect directly to
PostgreSQL or contain database credentials. The API verifies Supabase access
tokens with Supabase Auth. The user must have a confirmed Supabase email matching
an existing row in `users`; the API links that row to the Supabase user ID on
first request. It never accepts a client-supplied `user_id`.

### Configure and run

1. Ensure the existing `users` table is created, then run
   [`api_migration.sql`](./api_migration.sql) in the Supabase SQL editor. It
   creates `user_data` and adds the Supabase-user link.
   The timestamp conversion assumes existing `user_data.timestamp` values were
   stored in UTC.
2. Copy [`.env.example`](./.env.example) to `.env` and set `SUPABASE_URL`,
   `SUPABASE_PUBLISHABLE_KEY`, and `DATABASE_URL` from your Supabase project.
   Keep `.env` private; only the publishable key is intended for client use.
3. Install dependencies and start the API:

   ```sh
   python -m pip install -r requirements.txt
   uvicorn api:app --host 0.0.0.0 --port 8000
   ```

Use the Supabase database connection string with SSL for `DATABASE_URL`. For a
deployed app, put the API behind HTTPS and configure these values as server-side
environment variables. Interactive API documentation is available at `/docs`.

### Endpoints

All `/v1` endpoints require:

```http
Authorization: Bearer <Supabase access token>
```

Record a visit (the server uses the current time):

```http
POST /v1/attendance
Content-Type: application/json
```

To provide a visit time instead, send an ISO-8601 timestamp with an offset:

```json
{"attended_at": "2026-10-17T10:30:00-07:00"}
```

The response is `201 Created`:

```json
{"id": 123, "attended_at": "2026-10-17T17:30:00+00:00"}
```

Read daily counts for an inclusive range:

```http
GET /v1/attendance/calendar?start=2026-10-12&end=2026-10-18&timezone=America/Los_Angeles
```

The response includes every date in the range, including days with no visits:

```json
{
  "timezone": "America/Los_Angeles",
  "days": [
    {"date": "2026-10-12", "visits": 1},
    {"date": "2026-10-13", "visits": 0}
  ]
}
```

The date range is limited to 366 days. `GET /health` is a public process-health
check and does not verify database connectivity.

### Crowd level

Run the updated [`api_migration.sql`](./api_migration.sql) in Supabase SQL Editor
to create the private `crowd_reports` table. Row-level security is enabled, so
the Swift app should call the API rather than querying this table through
PostgREST.

Submit or update the signed-in user's current crowd rating:

```http
POST /v1/crowd-reports
Authorization: Bearer <Supabase access token>
Content-Type: application/json
```

```json
{"level": 4}
```

Levels must be integers from 1 through 10. Each user has one current report;
submitting again updates that user's level instead of adding another vote.

Get the average of the 10 most recently updated reports from the last 30
minutes:

```http
GET /v1/crowd-level
Authorization: Bearer <Supabase access token>
```

```json
{"level": 4.0, "report_count": 3}
```

`level` is the arithmetic mean and can be a decimal. Each user's latest report
replaces their previous vote. Only reports updated within the rolling last 30
minutes count, and at most the 10 newest are used. The API recalculates on each
GET request; no scheduled job is required. As reports age past 30 minutes, they
stop contributing. `report_count` is the number of users contributing to this
calculation (maximum 10), because each user has only one current report. With
no recent reports, the API falls back to the illustrative schedule for the
current hour in `America/Los_Angeles`. The stored 0–100 schedule value is
divided by 10 to match the live 1–10 scale, and `report_count` remains `0` to
show that the result came from historical rather than recent user reports.
Because the schedule only contains 6 AM–11 PM entries, `level` is `null`
outside those hours when there are no recent reports.

### Import the illustrative weekly chart

The workbook's “Page grid” is a separate illustrative 0–100 weekly schedule,
not live measurements and not 1–10 crowd votes. To load its 126 Monday–Sunday,
6 AM–11 PM values into Supabase, paste and run
[`seed_crowd_schedule.sql`](./seed_crowd_schedule.sql) in the Supabase SQL
Editor. It creates `public.crowd_schedule`, enables read-only access for
`anon` and `authenticated` roles, and safely updates matching schedule slots
when run again. `day_of_week` uses ISO numbering (Monday = 1, Sunday = 7);
`hour_of_day` uses 24-hour time. `is_illustrative` is always true for these
workbook values.

The Swift app can read the schedule from Supabase PostgREST using the project
URL and publishable key:

```http
GET https://<project-ref>.supabase.co/rest/v1/crowd_schedule?select=day_of_week,hour_of_day,level,is_illustrative&order=day_of_week,hour_of_day
apikey: <Supabase publishable key>
Authorization: Bearer <Supabase access token>
```

This returns rows like:

```json
[
  {"day_of_week": 1, "hour_of_day": 6, "level": 22, "is_illustrative": true},
  {"day_of_week": 1, "hour_of_day": 7, "level": 32, "is_illustrative": true}
]
```

The schedule is separate from `GET /v1/crowd-level`, which returns a rolling
average of recent user-submitted 1–10 votes.

Alternatively, fetch one day's 18 hourly values through the Python API:

```http
GET <API_BASE_URL>/v1/crowd-schedule?e=0
```

This schedule endpoint is public and does not require an access token. The `e`
parameter maps `0` to Sunday, `1` to Monday, continuing through `6` for
Saturday. It returns values divided by 10, ordered from 6 AM through 11 PM:

```json
{"e": 0, "values": [0.6, 1.0, 1.8, 3.0, 4.2, 5.0, 5.4, 4.8, 4.2, 3.8, 3.6, 3.4, 3.0, 2.6, 2.0, 1.2, 0.6, 0.3]}
```

For example, request `/v1/crowd-schedule?e=1` to get Monday's values. Run
[`seed_crowd_schedule.sql`](./seed_crowd_schedule.sql) in Supabase before using
this endpoint.

For UI testing, run [`seed_demo_crowd_reports.sql`](./seed_demo_crowd_reports.sql)
in a development/test Supabase project after running `api_migration.sql`. It
creates two synthetic users and repeatably sets their reports to 4 and 6, so the
response becomes `{"level": 5.0, "report_count": 2}` for 30 minutes after it is
run, if there are no other recent votes. Run it again to refresh the sample
timestamps. Do not run this in production: these sample reports are included
in the global average. To remove the sample rows, run:

```sql
DELETE FROM public.crowd_reports
WHERE user_id IN (
    SELECT id
    FROM public.users
    WHERE email IN (
        'demo-crowd-voter-1@example.invalid',
        'demo-crowd-voter-2@example.invalid'
    )
);

DELETE FROM public.users
WHERE email IN (
    'demo-crowd-voter-1@example.invalid',
    'demo-crowd-voter-2@example.invalid'
);
```

### Optional demo attendance data

To populate the current Los Angeles calendar week with four visits for visual
testing, run [`seed_demo_attendance.sql`](./seed_demo_attendance.sql) in the
Supabase SQL editor after replacing `REPLACE_WITH_TARGET_EMAIL` with the email
for an existing `users` row. The script adds only the visits needed to reach
four; it does not delete or label them as demo data. Prefer a dedicated test
account, and do not run it for a real user's account unless you intend to add
these records to their attendance history.
