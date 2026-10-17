"""HTTP API for authenticated workout attendance."""

import os
from datetime import date, datetime, timedelta
from typing import Generator, List, Optional
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx
from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from dotenv import load_dotenv
from pydantic import BaseModel, Field

import database as db
import query

load_dotenv()

app = FastAPI(title="150rep Workout API", version="1.0.0")
bearer_scheme = HTTPBearer(auto_error=False)


class AttendanceCreate(BaseModel):
    attended_at: Optional[datetime] = None


class AttendanceResponse(BaseModel):
    id: int
    attended_at: datetime


class AttendanceDay(BaseModel):
    date: date
    visits: int


class AttendanceCalendarResponse(BaseModel):
    timezone: str
    days: List[AttendanceDay]


class CrowdLevelCreate(BaseModel):
    level: int = Field(strict=True, ge=1, le=10)


class CrowdLevelResponse(BaseModel):
    level: Optional[float]
    report_count: int


class CrowdLevelSubmissionResponse(BaseModel):
    level: int
    updated_at: datetime


class SupabaseIdentity(BaseModel):
    id: str
    email: str


def get_database() -> Generator[db.Database, None, None]:
    try:
        database = db.Database.from_environment()
    except RuntimeError as error:
        raise HTTPException(status_code=503, detail=str(error)) from error

    try:
        yield database
    finally:
        database.close()


async def verify_supabase_access_token(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(bearer_scheme),
) -> SupabaseIdentity:
    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    publishable_key = os.environ.get("SUPABASE_PUBLISHABLE_KEY")
    if not supabase_url or not publishable_key:
        raise HTTPException(
            status_code=503,
            detail="SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be configured",
        )
    if credentials is None:
        raise HTTPException(
            status_code=401,
            detail="A Supabase access token is required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(
                f"{supabase_url}/auth/v1/user",
                headers={
                    "apikey": publishable_key,
                    "Authorization": f"Bearer {credentials.credentials}",
                },
            )
    except httpx.RequestError as error:
        raise HTTPException(
            status_code=503, detail="Could not verify the Supabase access token"
        ) from error

    if r)sponse.status_code in (401, 403):
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired Supabase access token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if response.status_code != 200:
    
        raise HTTPException(status_code=503, detail="Supabase Auth is unavailable")

    try:
        auth_user = response.json()
    except ValueError as error:
        raise HTTPException(
            status_code=502, detail="Supabase Auth returned an invalid user response"
        ) from error

    if not isinstance(auth_user, dict):
        raise HTTPException(
            status_code=502, detail="Supabase Auth returned an invalid user response"
        )
    auth_user_id = auth_user.get("id")
    email = auth_user.get("email")
    if not isinstance(auth_user_id, str) or not isinstance(email, str):
        raise HTTPException(
            status_code=502, detail="Supabase Auth returned an invalid user response"
        )
    if not email:
        raise HTTPException(
            status_code=403, detail="A Supabase email is required"
        )

    return SupabaseIdentity(id=auth_user_id, email=email)


def get_authenticated_user_id(
    identity: SupabaseIdentity = Depends(verify_supabase_access_token),
    database: db.Database = Depends(get_database),
) -> int:
    user_id = database.get_or_link_user_id(identity.id, identity.email)
    if user_id is None:
        raise HTTPException(
            status_code=403,
            detail="No unlinked local account matches the confirmed Supabase email",
        )
    return user_id


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post(
    "/v1/attendance",
    response_model=AttendanceResponse,
    status_code=201,
)
def create_attendance(
    payload: Optional[AttendanceCreate] = None,
    user_id: int = Depends(get_authenticated_user_id),
    database: db.Database = Depends(get_database),
) -> AttendanceResponse:
    attended_at = payload.attended_at if payload is not None else None
    if attended_at is not None and (
        attended_at.tzinfo is None or attended_at.utcoffset() is None
    ):
        raise HTTPException(
            status_code=422,
            detail="attended_at must include a timezone offset",
        )

    attendance_id, recorded_at = query.record_attendance(
        database, user_id, attended_at
    )
    return AttendanceResponse(id=attendance_id, attended_at=recorded_at)


@app.get(
    "/v1/attendance/calendar",
    response_model=AttendanceCalendarResponse,
)
def read_attendance_calendar(
    start: date,
    end: date,
    timezone: str = Query(default="UTC", min_length=1, max_length=64),
    user_id: int = Depends(get_authenticated_user_id),
    database: db.Database = Depends(get_database),
) -> AttendanceCalendarResponse:
    if start > end:
        raise HTTPException(status_code=422, detail="start must be on or before end")
    if end - start > timedelta(days=365):
        raise HTTPException(
            status_code=422, detail="Calendar date range cannot exceed 366 days"
        )
    try:
        ZoneInfo(timezone)
    except (ValueError, ZoneInfoNotFoundError) as error:
        raise HTTPException(status_code=422, detail="Invalid IANA timezone") from error

    rows = query.get_attendance_calendar(
        database, user_id, start, end, timezone
    )
    return AttendanceCalendarResponse(
        timezone=timezone,
        days=[AttendanceDay(date=day, visits=visits) for day, visits in rows],
    )


@app.post(
    "/v1/crowd-reports",
    response_model=CrowdLevelSubmissionResponse,
)
def submit_crowd_level(
    payload: CrowdLevelCreate,
    user_id: int = Depends(get_authenticated_user_id),
    database: db.Database = Depends(get_database),
) -> CrowdLevelSubmissionResponse:
    updated_at = query.submit_crowd_level(database, user_id, payload.level)
    return CrowdLevelSubmissionResponse(
        level=payload.level,
        updated_at=updated_at,
    )


@app.get(
    "/v1/crowd-level",
    response_model=CrowdLevelResponse,
    dependencies=[Depends(get_authenticated_user_id)],
)
def read_crowd_level(
    database: db.Database = Depends(get_database),
) -> CrowdLevelResponse:
    level, report_count = query.get_crowd_level(database)
    return CrowdLevelResponse(level=level, report_count=report_count)
