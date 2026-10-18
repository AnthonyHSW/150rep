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


def create_machine(
    database: db.Database, name: str, location: Optional[str] = None
) -> Tuple[int, str, Optional[str], datetime]:
    """Add a machine to the shared inventory."""
    return database.create_machine(name, location)


def get_machines(
    database: db.Database,
) -> List[Tuple[int, str, Optional[str], Optional[bool], Optional[datetime]]]:
    """List the machine inventory and latest status reports."""
    return database.get_machines()


def set_machine_in_use(
    database: db.Database, machine_id: int, user_id: int, is_in_use: bool
) -> Optional[Tuple[int, bool, datetime]]:
    """Set or replace the machine's latest in-use report."""
    return database.set_machine_in_use(machine_id, user_id, is_in_use)
