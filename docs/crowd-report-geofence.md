# Crowd-report geofence — backend changes

The app now proves a reporter is at the ARC before it submits. The device-side check is
only the fast half: it runs first so someone across campus gets an explanation instead of
a round trip. **The backend is what actually decides**, because the client check is worth
nothing against anyone calling the API with a bearer token and `curl`.

Nothing here changes `GET /v1/crowd-level`, the `crowd_reports` table, or the averaging.

## 1. Config

Four env vars, with the values the app already assumes as defaults:

```
ARC_LATITUDE=33.6487
ARC_LONGITUDE=-117.8276
ARC_GEOFENCE_RADIUS_M=300
ARC_MAX_ACCURACY_M=150
```

These are duplicated in `rep150/Services/ArcGeofence.swift`. If one changes, both change —
otherwise the app lets a report through that the backend then refuses (or vice versa).

Radius is 300 m: the whole rec complex, building and fields and the walkways between, so
standing at the front door still counts. The accuracy ceiling is half the radius, so a fix
that passes is at worst at the edge of the complex rather than across campus.

## 2. Request body

`POST /v1/crowd-reports` gains three fields, all required:

```json
{ "level": 7, "latitude": 33.6489, "longitude": -117.8271, "accuracy_m": 12.4 }
```

`accuracy_m` is CoreLocation's `horizontalAccuracy` — the fix's own horizontal error
estimate in metres. The app never sends a negative one (that means an invalid fix) and
never sends one above `ARC_MAX_ACCURACY_M`.

```python
class CrowdLevelCreate(BaseModel):
    level: int = Field(strict=True, ge=1, le=10)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_m: float = Field(ge=0, le=100_000)
```

## 3. The check

No PostGIS needed — one haversine in Python, no dependencies:

```python
from math import asin, cos, radians, sin, sqrt

EARTH_RADIUS_M = 6_371_008.8


def meters_between(
    lat_a: float, lon_a: float, lat_b: float, lon_b: float
) -> float:
    """Great-circle distance in metres."""
    phi_a, phi_b = radians(lat_a), radians(lat_b)
    delta_phi = phi_b - phi_a
    delta_lambda = radians(lon_b - lon_a)
    haversine = (
        sin(delta_phi / 2) ** 2
        + cos(phi_a) * cos(phi_b) * sin(delta_lambda / 2) ** 2
    )
    return 2 * EARTH_RADIUS_M * asin(sqrt(haversine))
```

Then, in `submit_crowd_level`, before `query.submit_crowd_level(...)`:

```python
if payload.accuracy_m > ARC_MAX_ACCURACY_M:
    raise HTTPException(
        status_code=422,
        detail={
            "code": "outside_geofence",
            "message": "Location fix is too inaccurate to verify.",
        },
    )

distance_m = meters_between(
    payload.latitude, payload.longitude, ARC_LATITUDE, ARC_LONGITUDE
)
if distance_m > ARC_GEOFENCE_RADIUS_M:
    raise HTTPException(
        status_code=422,
        detail={
            "code": "outside_geofence",
            "message": "Crowd reports have to be submitted at the ARC.",
        },
    )
```

## 4. Why 422 and not 403

**This part matters.** `BusynessService.validate` hands every 401 and 403 to
`AuthService.handleRejection`, which signs the user out — that is how the backend's UCI
domain rule reaches the app. Standing in the wrong place is not a bad session, so a
geofence refusal must not come back as 403 or it logs people out of the app for being at
home.

So: **422, with the string `outside_geofence` somewhere in the body.** The client matches
on that substring (`BackendError.isOutsideGeofence`) and turns it into "You have to be at
the ARC to report how busy it is." Any other 4xx/5xx becomes a generic "couldn't send
your report", which is why the too-inaccurate case above reuses the same code — it's
only reachable from a hand-crafted request, and the geofence wording is close enough.

## 5. Don't store the coordinates

The app's doc comment promises the backend uses the coordinates once and keeps only the
verdict, so don't add lat/lon columns to `crowd_reports`. If you want something for
debugging, log the distance (`"crowd report accepted at %.0f m"`), not the position.

## 6. Rollout order

Required fields mean a build of the app that predates this change gets a 422 on every
report. Deploy the backend and ship the app build together, or land the backend with the
fields optional-but-checked-when-present first and flip them to required once the old
build is gone.

## 7. Known limit

This proves the *device* reports a location at the ARC. A simulated location on a
jailbroken phone still gets through — GPS is self-reported, and nothing short of
server-side cross-checks fixes that. If it ever matters, the cheap next step is
correlating a report against the reporter's own `user_data` presence row or an active
workout rather than trying to harden the coordinates themselves.
