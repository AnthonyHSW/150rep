"""PostgreSQL database operations for the workout application."""

import os
from datetime import date, datetime
from typing import List, Optional, Tuple

import psycopg2


class Database:
    """Manage a PostgreSQL connection and workout data."""

    def __init__(self):
        database_url = os.environ.get("DATABASE_URL")
        if not database_url:
            raise RuntimeError("DATABASE_URL must be configured")

        self.conn = psycopg2.connect(database_url)
        self.cursor = self.conn.cursor()

    @classmethod
    def from_environment(cls) -> "Database":
        """Create a database connection from DATABASE_URL."""
        return cls()

    def close(self):
        """Close this database connection."""
        self.cursor.close()
        self.conn.close()

    def create_table_account(self):
        """Create the local user table if it does not already exist."""
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                name TEXT,
                email TEXT UNIQUE,
                auth_user_id UUID UNIQUE
            )
        ''')
        self.conn.commit()

    def create_table_data(self):
        """Create the workout attendance table and its lookup index."""
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS user_data (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                presence BOOLEAN NOT NULL,
                timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        self.cursor.execute('''
            CREATE INDEX IF NOT EXISTS user_data_user_timestamp_idx
            ON user_data (user_id, timestamp)
            WHERE presence = TRUE
        ''')
        self.conn.commit()

    def create_table_machines(self):
        """Create the machines table and its lookup index."""
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS machines (
                id SERIAL PRIMARY KEY,
                name TEXT NOT NULL UNIQUE,
                location TEXT,
                is_in_use BOOLEAN NOT NULL DEFAULT FALSE,
                status_updated_at TIMESTAMPTZ,
                status_updated_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        self.cursor.execute('''
            CREATE INDEX IF NOT EXISTS machines_location_name_idx
            ON machines (location, name)
        ''')
        self.conn.commit()

    def list_machines(self) -> List[Tuple]:
        """Return every machine with its latest status, grouped by location."""
        self.cursor.execute('''
            SELECT id, name, location, is_in_use, status_updated_at
            FROM machines
            ORDER BY location NULLS LAST, name
        ''')
        return self.cursor.fetchall()

    def add_machine(self, name: str, location: Optional[str]) -> Optional[Tuple]:
        """Add a machine, or return None if one by that name already exists.

        Names are unique so repeated submissions can't quietly fill the list with
        duplicate 'Leg Press 1' rows that nobody can tell apart.
        """
        self.cursor.execute('''
            INSERT INTO machines (name, location)
            VALUES (%s, %s)
            ON CONFLICT (name) DO NOTHING
            RETURNING id, name, location, is_in_use, status_updated_at
        ''', (name, location))
        machine = self.cursor.fetchone()
        self.conn.commit()
        return machine

    def set_machine_status(
        self, machine_id: int, is_in_use: bool, user_id: int
    ) -> Optional[Tuple]:
        """Update one machine's status, or return None if no such machine exists."""
        self.cursor.execute('''
            UPDATE machines
            SET is_in_use = %s,
                status_updated_at = CURRENT_TIMESTAMP,
                status_updated_by = %s
            WHERE id = %s
            RETURNING id, name, location, is_in_use, status_updated_at
        ''', (is_in_use, user_id, machine_id))
        machine = self.cursor.fetchone()
        self.conn.commit()
        return machine

    def get_or_create_user_id(self, auth_user_id: str, email: Optional[str] = None) -> int:
        """Resolve a Supabase user (anonymous or not) to a local account,
        creating one on first sight. No email or prior signup is required."""
        self.cursor.execute(
            "SELECT id FROM users WHERE auth_user_id = %s",
            (auth_user_id,),
        )
        existing_user = self.cursor.fetchone()
        if existing_user:
            return existing_user[0]

        self.cursor.execute(
            "INSERT INTO users (auth_user_id, email) VALUES (%s, %s) RETURNING id",
            (auth_user_id, email),
        )
        user_id = self.cursor.fetchone()[0]
        self.conn.commit()
        return user_id

    def record_attendance(
        self, user_id: int, attended_at: Optional[datetime] = None
    ) -> Tuple[int, datetime]:
        """Record one workout visit and return its id and timestamp."""
        if attended_at is None:
            self.cursor.execute('''
                INSERT INTO user_data (user_id, presence)
                VALUES (%s, TRUE)
                RETURNING id, timestamp
            ''', (user_id,))
        else:
            self.cursor.execute('''
                INSERT INTO user_data (user_id, presence, timestamp)
                VALUES (%s, TRUE, %s)
                RETURNING id, timestamp
            ''', (user_id, attended_at))

        attendance = self.cursor.fetchone()
        self.conn.commit()
        return attendance

    def get_attendance_calendar(
        self, user_id: int, start_date: date, end_date: date, timezone: str = "UTC"
    ) -> List[Tuple[date, int]]:
        """Return local date visit counts, including zero-visit days."""
        if start_date > end_date:
            raise ValueError("start_date must be on or before end_date")

        self.cursor.execute('''
            WITH calendar_days AS (
                SELECT generate_series(
                    %s::date, %s::date, INTERVAL '1 day'
                )::date AS calendar_date
            )
            SELECT calendar_days.calendar_date, COUNT(user_data.id)
            FROM calendar_days
            LEFT JOIN user_data
                ON user_data.user_id = %s
                AND user_data.presence = TRUE
                AND user_data.timestamp >= (
                    calendar_days.calendar_date::timestamp AT TIME ZONE %s
                )
                AND user_data.timestamp < (
                    (calendar_days.calendar_date + INTERVAL '1 day')::timestamp
                    AT TIME ZONE %s
                )
            GROUP BY calendar_days.calendar_date
            ORDER BY calendar_days.calendar_date
        ''', (start_date, end_date, user_id, timezone, timezone))
        return self.cursor.fetchall()

    def submit_crowd_level(self, user_id: int, level: int) -> datetime:
        """Create or update this user's current crowd-level report."""
        self.cursor.execute('''
            INSERT INTO crowd_reports (user_id, level, updated_at)
            VALUES (%s, %s, CURRENT_TIMESTAMP)
            ON CONFLICT (user_id)
            DO UPDATE SET level = EXCLUDED.level,
                          updated_at = CURRENT_TIMESTAMP
            RETURNING updated_at
        ''', (user_id, level))
        updated_at = self.cursor.fetchone()[0]
        self.conn.commit()
        return updated_at

    def get_crowd_level(self) -> Tuple[Optional[float], int]:
        """Return recent votes or this hour's historical Los Angeles schedule level."""
        self.cursor.execute('''
            WITH recent_reports AS (
                SELECT level
                FROM crowd_reports
                WHERE updated_at >= CURRENT_TIMESTAMP - INTERVAL '30 minutes'
                ORDER BY updated_at DESC, user_id
                LIMIT 10
            ),
            live_level AS (
                SELECT AVG(level)::FLOAT AS average, COUNT(*) AS report_count
                FROM recent_reports
            ),
            local_time AS (
                SELECT CURRENT_TIMESTAMP AT TIME ZONE 'America/Los_Angeles' AS value
            )
            SELECT COALESCE(
                       live_level.average,
                       (
                           SELECT crowd_schedule.level / 10.0
                           FROM public.crowd_schedule
                           WHERE crowd_schedule.day_of_week =
                               CASE EXTRACT(DOW FROM local_time.value)::INTEGER
                                   WHEN 0 THEN 7
                                   ELSE EXTRACT(DOW FROM local_time.value)::INTEGER
                               END
                             AND crowd_schedule.hour_of_day =
                                 EXTRACT(HOUR FROM local_time.value)::INTEGER
                       )
                   ),
                   live_level.report_count
            FROM live_level
            CROSS JOIN local_time
        ''')
        average, report_count = self.cursor.fetchone()
        return average, report_count

    def create_machine(
        self, name: str, location: Optional[str] = None
    ) -> Tuple[int, str, Optional[str], datetime]:
        """Add a physical machine to the shared inventory."""
        self.cursor.execute(
            '''
            INSERT INTO machines (name, location)
            VALUES (%s, %s)
            RETURNING id, name, location, created_at
            ''',
            (name, location),
        )
        machine = self.cursor.fetchone()
        self.conn.commit()
        return machine

    def get_machines(
        self,
    ) -> List[Tuple[int, str, Optional[str], Optional[bool], Optional[datetime]]]:
        """List machines with their latest in-use state, if one has been reported."""
        self.cursor.execute(
            '''
            SELECT machines.id, machines.name, machines.location,
                   machine_status.is_in_use, machine_status.updated_at
            FROM machines
            LEFT JOIN machine_status ON machine_status.machine_id = machines.id
            ORDER BY machines.name, machines.location NULLS FIRST, machines.id
            '''
        )
        return self.cursor.fetchall()

    def set_machine_in_use(
        self, machine_id: int, user_id: int, is_in_use: bool
    ) -> Optional[Tuple[int, bool, datetime]]:
        """Create or replace the current status report for a machine."""
        self.cursor.execute(
            '''
            INSERT INTO machine_status (machine_id, is_in_use, updated_by)
            SELECT id, %s, %s
            FROM machines
            WHERE id = %s
            ON CONFLICT (machine_id)
            DO UPDATE SET is_in_use = EXCLUDED.is_in_use,
                          updated_at = CURRENT_TIMESTAMP,
                          updated_by = EXCLUDED.updated_by
            RETURNING machine_id, is_in_use, updated_at
            ''',
            (is_in_use, user_id, machine_id),
        )
        status = self.cursor.fetchone()
        self.conn.commit()
        return status
