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

Get the average of current reports:

```http
GET /v1/crowd-level
Authorization: Bearer <Supabase access token>
```

```json
{"level": 4.0, "report_count": 3}
```

`level` is the arithmetic mean of reporting users' current levels and can be a
decimal. With no reports, the response is `{"level": null, "report_count": 0}`.

### Optional demo attendance data

To populate the current Los Angeles calendar week with four visits for visual
testing, run [`seed_demo_attendance.sql`](./seed_demo_attendance.sql) in the
Supabase SQL editor after replacing `REPLACE_WITH_TARGET_EMAIL` with the email
for an existing `users` row. The script adds only the visits needed to reach
four; it does not delete or label them as demo data. Prefer a dedicated test
account, and do not run it for a real user's account unless you intend to add
these records to their attendance history.
