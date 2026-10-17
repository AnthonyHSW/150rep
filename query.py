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
) -> List[Tuple[date, int]]:
    """Get daily workout counts for the inclusive date range."""
    return database.get_attendance_calendar(user_id, start_date, end_date)


def insert_user_login(
    database: db.Database, name: str, email: str, password: str
) -> bool:
    """Create a user through the supplied database connection."""
    return database.insert_user_login(name, email, password)