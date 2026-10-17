# First Page — ARC Busyness

**Purpose:** Help users decide whether to visit the ARC now or wait for a quieter time. Fits on a single mobile screen with no scrolling.

---

## 1. Live Busyness (Compact Gauge)
**Space:** 40% of viewport height

- Semicircular gauge: cool-to-hot gradient (1–10 scale).
- Endpoint labels: “Quiet” (1) and “Packed” (10).
- Center: current score + wait estimate: `”6/10 · ~3–5 min”` (or crowd category if wait data unavailable).
- Below gauge: timestamp + report count: `”2 min ago · 18 reports”`.
- **Data states:**
  - Live: show wait estimate only when recent reports or model confidence ≥ threshold.
  - Degraded: show crowd category in center; omit wait time.
  - No data: `”Waiting for reports”`.

---

## 2. Daily Pattern (Micro Chart)
**Space:** 25% of viewport height

- Hourly bar chart (6 AM–10 PM, 16 hours) using same 1–10 scale; compress bars to fit.
- Current hour highlighted with a “Now” marker.
- Label: `”Typical traffic for today”` (left) + optional takeaway (right, e.g., `”Quieter after 8 PM”`).
- If insufficient history: omit chart, show `”Still learning patterns”`.

---

## 3. Quick Report (Button Row)
**Space:** 20% of viewport height

- Heading: `”Here now? How busy is it?”`
- Four buttons in a row (or 2×2 on small screens): Quiet · Moderate · Busy · Packed.
- One tap submits immediately; highlight selected state.
- Confirm toast: `”Thanks—helping Anteaters plan.”`
- Changing selection updates the current report (no duplicate).
- Retry prompt on failure.

---

## Layout & Constraints
- **No scrolling:** Meter (40%) + Chart (25%) + Buttons (20%) + padding/margins (15%).
- **Responsive:** Stack buttons as 2×2 on screens < 360px wide.
- **Color:** Pair scale colors (cool→hot) with text labels; use high contrast.
- **Typography:** Headings in system font, body in smaller weight; prioritize readability.

---

## Model Architecture

### State Structure
```
BusynessModel:
  current:
    timestamp: ISO8601
    crowd_score: 1–10 (int)
    confidence: 0.0–1.0 (float, from report count & recency)
    wait_estimate_min: int (null if confidence < threshold)
    wait_estimate_max: int (null if confidence < threshold)
    recent_reports: int (count of reports in last 30 min)
  
  daily_pattern:
    [Hour, AvgScore, ForecastScore] × 16 (6 AM–10 PM)
    has_sufficient_history: bool
    peak_hour: int or null
    quiet_hour: int or null
  
  metadata:
    last_updated: ISO8601
    data_source: “reports” | “model” | “degraded”
```

### Refresh Logic
- **On app launch:** load from Supabase, compute model state.
- **Background refresh:** every 5 minutes, fetch latest reports and recompute scores.
- **User submits report:** immediately POST to Supabase, recompute current score.
- **Stale threshold:** if last update > 15 min, mark as degraded (show score, omit wait estimate).

### Database Queries
- `fetch_recent_reports(minutes=30)` → list of (timestamp, crowd_category, user_id).
- `fetch_daily_history(date)` → hourly aggregates (avg score, count).
- `submit_report(user_id, crowd_category)` → insert and return updated current score.

### Stub Implementation (Python)
```python
class BusynessModel:
  def __init__(self):
    self.current = {...}
    self.daily_pattern = {...}
  
  def refresh(self):
    # Fetch from Supabase, compute scores
    pass
  
  def submit_report(self, category):
    # POST to Supabase, recompute
    pass
```

**Note:** Supabase client (Python) handles auth and real-time subscriptions. Refresh runs on a background timer.





