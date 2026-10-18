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

load_dotenv(override=True)

app = FastAPI(title="150rep Workout API", version="1.0.0")
bearer_scheme = HTTPBearer(auto_error=False)


class AttendanceCreate(BaseModel):
    attended_at: Optional[datetime] = None


class AuthCredentials(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=1, max_length=128)


class AuthRefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class AuthUser(BaseModel):
    id: str
    email: Optional[str] = None


class LoginResponse(BaseModel):
    access_token: str
    token_type: str
    expires_in: int
    refresh_token: str
    user: AuthUser


class SignupResponse(BaseModel):
    confirmation_required: bool
    access_token: Optional[str] = None
    token_type: Optional[str] = None
    expires_in: Optional[int] = None
    refresh_token: Optional[str] = None
    user: Optional[AuthUser] = None


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


class CrowdScheduleResponse(BaseModel):
    e: int
    values: List[float]


class MachineCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    location: Optional[str] = Field(default=None, max_length=120)


class MachineStatusUpdate(BaseModel):
    is_in_use: bool = Field(strict=True)


class MachineResponse(BaseModel):
    id: int
    name: str
    location: Optional[str] = None
    is_in_use: bool
    # Null until somebody first reports on this machine, which is not the same as having
    # been reported free.
    status_updated_at: Optional[datetime] = None


class SupabaseIdentity(BaseModel):
    id: str
    email: Optional[str] = None


def require_uci_email(email: str) -> str:
    normalized_email = email.strip().lower()
    if not is_uci_email(normalized_email):
        raise HTTPException(
            status_code=422,
            detail="Email must be an address ending in @uci.edu",
        )
    return normalized_email


def is_uci_email(email: str) -> bool:
    local_part, separator, domain = email.strip().rpartition("@")
    return bool(local_part and separator and domain.casefold() == "uci.edu")


def supabase_auth_config() -> tuple[str, str]:
    supabase_url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    publishable_key = os.environ.get("SUPABASE_PUBLISHABLE_KEY")
    if not supabase_url or not publishable_key:
        raise HTTPException(
            status_code=503,
            detail="SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be configured",
        )
    return supabase_url, publishable_key


async def request_supabase_auth(
    endpoint: str,
    payload: dict[str, str],
    *,
    invalid_credentials_detail: Optional[str] = None,
) -> dict:
    supabase_url, publishable_key = supabase_auth_config()
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(
                f"{supabase_url}/auth/v1/{endpoint}",
                headers={"apikey": publishable_key},
                json=payload,
            )
    except httpx.RequestError as error:
        raise HTTPException(
            status_code=503, detail="Could not reach Supabase Auth"
        ) from error

    if (
        invalid_credentials_detail is not None
        and response.status_code in (400, 401, 422)
    ):
        raise HTTPException(status_code=401, detail=invalid_credentials_detail)
    if response.status_code == 429:
        raise HTTPException(status_code=429, detail="Too many authentication attempts")
    if response.status_code >= 500:
        raise HTTPException(status_code=503, detail="Supabase Auth is unavailable")
    if response.status_code not in (200, 201):
        raise HTTPException(
            status_code=400 if endpoint == "signup" else 502,
            detail="Supabase Auth rejected the request",
        )

    try:
        auth_result = response.json()
    except ValueError as error:
        raise HTTPException(
            status_code=502, detail="Supabase Auth returned an invalid response"
        ) from error
    if not isinstance(auth_result, dict):
        raise HTTPException(
            status_code=502, detail="Supabase Auth returned an invalid response"
        )
    return auth_result


def auth_user_from_response(auth_result: dict) -> Optional[AuthUser]:
    user_data = auth_result.get("user")
    if not isinstance(user_data, dict):
        return None
    user_id = user_data.get("id")
    email = user_data.get("email")
    if not isinstance(user_id, str):
        return None
    return AuthUser(id=user_id, email=email if isinstance(email, str) else None)


def login_response_from_auth_result(auth_result: dict) -> LoginResponse:
    user = auth_user_from_response(auth_result)
    access_token = auth_result.get("access_token")
    token_type = auth_result.get("token_type")
    expires_in = auth_result.get("expires_in")
    refresh_token = auth_result.get("refresh_token")
    if (
        not isinstance(access_token, str)
        or not isinstance(token_type, str)
        or not isinstance(expires_in, int)
        or isinstance(expires_in, bool)
        or not isinstance(refresh_token, str)
        or user is None
    ):
        raise HTTPException(
            status_code=502, detail="Supabase Auth returned an incomplete login response"
        )
    if user.email is None or not is_uci_email(user.email):
        raise HTTPException(
            status_code=403,
            detail="A valid @uci.edu Supabase account is required",
        )
    return LoginResponse(
        access_token=access_token,
        token_type=token_type,
        expires_in=expires_in,
        refresh_token=refresh_token,
        user=user,
    )


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

    if response.status_code in (401, 403):
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
    if not isinstance(auth_user_id, str):
        raise HTTPException(
            status_code=502, detail="Supabase Auth returned an invalid user response"
        )
    email = auth_user.get("email")

    return SupabaseIdentity(id=auth_user_id, email=email if isinstance(email, str) else None)


@app.post("/v1/auth/signup", response_model=SignupResponse, status_code=201)
async def signup(payload: AuthCredentials) -> SignupResponse:
    email = require_uci_email(payload.email)
    auth_result = await request_supabase_auth(
        "signup",
        {"email": email, "password": payload.password},
    )
    access_token = auth_result.get("access_token")
    token_type = auth_result.get("token_type")
    expires_in = auth_result.get("expires_in")
    refresh_token = auth_result.get("refresh_token")
    if access_token is not None and not isinstance(access_token, str):
        raise HTTPException(
            status_code=502, detail="Supabase Auth returned an invalid signup session"
        )
    if isinstance(access_token, str) and (
        not isinstance(token_type, str)
        or not isinstance(expires_in, int)
        or isinstance(expires_in, bool)
        or not isinstance(refresh_token, str)
    ):
        raise HTTPException(
            status_code=502, detail="Supabase Auth returned an incomplete signup session"
        )
    return SignupResponse(
        confirmation_required=not isinstance(access_token, str),
        access_token=access_token,
        token_type=token_type,
        expires_in=expires_in,
        refresh_token=refresh_token,
        user=auth_user_from_response(auth_result),
    )


@app.post("/v1/auth/login", response_model=LoginResponse)
async def login(payload: AuthCredentials) -> LoginResponse:
    email = require_uci_email(payload.email)
    auth_result = await request_supabase_auth(
        "token?grant_type=password",
        {"email": email, "password": payload.password},
        invalid_credentials_detail="Invalid email or password",
    )
    return login_response_from_auth_result(auth_result)


@app.post("/v1/auth/refresh", response_model=LoginResponse)
async def refresh_login(payload: AuthRefreshRequest) -> LoginResponse:
    auth_result = await request_supabase_auth(
        "token?grant_type=refresh_token",
        {"refresh_token": payload.refresh_token},
        invalid_credentials_detail="Invalid refresh token",
    )
    return login_response_from_auth_result(auth_result)


def get_authenticated_user_id(
    identity: SupabaseIdentity = Depends(verify_supabase_access_token),
    database: db.Database = Depends(get_database),
) -> int:
    if identity.email is None or not is_uci_email(identity.email):
        raise HTTPException(
            status_code=403, detail="A valid @uci.edu Supabase account is required"
        )
    return database.get_or_create_user_id(identity.id, identity.email)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/v1/crowd-schedule", response_model=CrowdScheduleResponse)
def read_crowd_schedule(
    e: int = Query(ge=0, le=6),
    database: db.Database = Depends(get_database),
) -> CrowdScheduleResponse:
    # Frontend numbering is Sunday=0, Monday=1, ..., Saturday=6.
    day_of_week = 7 if e == 0 else e
    values = query.get_crowd_schedule_values(database, day_of_week)
    if len(values) != 18:
        raise HTTPException(
            status_code=503,
            detail="Crowd schedule is not seeded with all 18 hourly values for this day",
        )
    return CrowdScheduleResponse(e=e, values=values)


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


def machine_response(row: tuple) -> MachineResponse:
    """Build a response from a `(id, name, location, is_in_use, status_updated_at)` row."""
    machine_id, name, location, is_in_use, status_updated_at = row
    return MachineResponse(
        id=machine_id,
        name=name,
        location=location,
        is_in_use=is_in_use,
        status_updated_at=status_updated_at,
    )


@app.get(
    "/v1/machines",
    response_model=List[MachineResponse],
    dependencies=[Depends(get_authenticated_user_id)],
)
def read_machines(
    database: db.Database = Depends(get_database),
) -> List[MachineResponse]:
    return [machine_response(row) for row in query.list_machines(database)]


@app.post(
    "/v1/machines",
    response_model=MachineResponse,
    status_code=201,
    dependencies=[Depends(get_authenticated_user_id)],
)
def create_machine(
    payload: MachineCreate,
    database: db.Database = Depends(get_database),
) -> MachineResponse:
    name = payload.name.strip()
    if not name:
        raise HTTPException(status_code=422, detail="name cannot be blank")
    location = payload.location.strip() if payload.location is not None else None

    machine = query.add_machine(database, name, location or None)
    # Names are unique, so a miss here means one already exists. 409 rather than returning
    # the existing row: the caller asked to create something and didn't.
    if machine is None:
        raise HTTPException(
            status_code=409, detail="A machine with that name already exists"
        )
    return machine_response(machine)


@app.put("/v1/machines/{machine_id}/status", response_model=MachineResponse)
def update_machine_status(
    machine_id: int,
    payload: MachineStatusUpdate,
    user_id: int = Depends(get_authenticated_user_id),
    database: db.Database = Depends(get_database),
) -> MachineResponse:
    machine = query.set_machine_status(
        database, machine_id, payload.is_in_use, user_id
    )
    if machine is None:
        raise HTTPException(status_code=404, detail="No machine with that id")
    return machine_response(machine)
