"""Application query functions backed by the Database class."""

from datetime import date, datetime
from typing import List, Optional, Tuple

import database as db


def record_attendance(
    database: db.Database,
    user_id: int,
    attended_at: Optional[datetime] = None,
) -> Tuple[int, datetime]:
    """Record a workout visit using the supplied database connection."""
    return database.record_attendance(user_id, attended_at)


def get_attendance_calendar(
    database: db.Database,
    user_id: int,
    start_date: date,
    end_date: date,
    timezone: str = "UTC",
) -> List[Tuple[date, int]]:
    """Get daily workout counts for the inclusive date range."""
    return database.get_attendance_calendar(user_id, start_date, end_date, timezone)


def submit_crowd_level(
    database: db.Database, user_id: int, level: int
) -> datetime:
    """Create or update the user's current crowd-level report."""
    return database.submit_crowd_level(user_id, level)


def get_crowd_level(database: db.Database) -> Tuple[Optional[float], int]:
    """Return the crowd average and number of contributing users."""
    return database.get_crowd_level()


def get_crowd_schedule_values(database: db.Database, day_of_week: int) -> List[float]:
    """Get ordered schedule values scaled to the 0-10 range."""
    return database.get_crowd_schedule_values(day_of_week)


def insert_user_login(
    database: db.Database, name: str, email: str, password: str
) -> bool:
    """Create a user through the supplied database connection."""
    return database.insert_user_login(name, email, password)