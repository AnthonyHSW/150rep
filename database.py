### database.py


### database.py
### Authors: Janice & Anthony
### Creates tables using sqlite3 and inserts data into them. Interacts with Supabase to retrieve 
### data from the database and display it in the GUI.

import psycopg2
from datetime import date, datetime
from typing import List, Optional, Tuple

SUPABASE_URL = "https://drjnsdrtqxyyjfgmrqzw.supabase.co"
SUPABASE_KEY = "sb_publishable_bFQ5tP7jTYYaz7K9UG9hEw_6lj2jM1_"

class Database:
    """Class to handele database operations"""
    def __init__(self):
        self.conn = psycopg2.connect(
            host="drjnsdrtqxyyjfgmrqzw.supabase.co",
            database="postgres",
            user="postgres",
            password="Zothacks2026"
        )
        self.cursor = self.conn.cursor()
        self.name = None
        self.password = None
        self.email = None

    def create_table_account(self):
        """Creates a table in the database"""
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                name TEXT NOT NULL,
                email TEXT UNIQUE NOT NULL,
                password TEXT NOT NULL
            )
        ''')
        self.conn.commit()

    def create_table_data(self):
        """Creates the table used to store workout attendance events."""
        self.cursor.execute('''
            CREATE TABLE IF NOT EXISTS user_data (
                id SERIAL PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                presence BOOLEAN NOT NULL,
                timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        self.cursor.execute('''
            CREATE INDEX IF NOT EXISTS user_data_user_timestamp_idx
            ON user_data (user_id, timestamp)
            WHERE presence = TRUE
        ''')
        self.conn.commit()

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
        self, user_id: int, start_date: date, end_date: date
    ) -> List[Tuple[date, int]]:
        """Return each calendar date and its visit count, including zero-visit days."""
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
                AND user_data.timestamp >= calendar_days.calendar_date
                AND user_data.timestamp < calendar_days.calendar_date + INTERVAL '1 day'
            GROUP BY calendar_days.calendar_date
            ORDER BY calendar_days.calendar_date
        ''', (start_date, end_date, user_id))
        return self.cursor.fetchall()

    def insert_user_login(self, name, email, password):
        """Inserts data into the table"""
        if email.endswith("@uci.edu"):
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
        else:
            return False

        
    