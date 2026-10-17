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
        self.name = None
        self.password = None
        self.email = None

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
                name TEXT NOT NULL,
                email TEXT UNIQUE NOT NULL,
                password TEXT NOT NULL,
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

    def get_or_link_user_id(self, auth_user_id: str, email: str) -> Optional[int]:
        """Resolve a Supabase user to a local account with the same email."""
        self.cursor.execute(
            "SELECT id FROM users WHERE auth_user_id = %s",
            (auth_user_id,),
        )
        linked_user = self.cursor.fetchone()
        if linked_user:
            return linked_user[0]

        self.cursor.execute(
            "SELECT id, auth_user_id FROM users "
            "WHERE LOWER(email) = LOWER(%s) FOR UPDATE",
            (email,),
        )
        matching_users = self.cursor.fetchall()
        if len(matching_users) != 1:
            self.conn.rollback()
            return None

        user_id, linked_auth_user_id = matching_users[0]
        if linked_auth_user_id and str(linked_auth_user_id) != auth_user_id:
            self.conn.rollback()
            return None

        if linked_auth_user_id is None:
            self.cursor.execute(
                "UPDATE users SET auth_user_id = %s "
                "WHERE id = %s AND auth_user_id IS NULL",
                (auth_user_id, user_id),
            )
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
        """Return the average current crowd report and number of reporting users."""
        self.cursor.execute('''
            SELECT AVG(level)::FLOAT, COUNT(*)
            FROM crowd_reports
        ''')
        average, report_count = self.cursor.fetchone()
        return average, report_count

    def insert_user_login(self, name, email, password):
        """Insert a local account for a UCI email address."""
        if not email.endswith("@uci.edu"):
            return False

        try:
            self.cursor.execute('''
                INSERT INTO users (name, email, password)
                VALUES (%s, %s, %s)
            ''', (name, email, password))
            self.conn.commit()
            return True
        except psycopg2.IntegrityError:
            self.conn.rollback()
            return False
