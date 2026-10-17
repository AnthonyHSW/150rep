# First Page — ARC Busyness

## Purpose
Help users decide whether to visit the ARC now or wait for a quieter time.

## 1. Live Busyness Meter
- Heading: “ARC right now.”
- Semicircular gauge with a cool-to-hot gradient.
- Scale from 1–10, with a marker indicating current crowding.
- Endpoint labels: “1 · Quiet” and “10 · Packed.”
- Current score above the gauge: “6/10 · Busy.”
- Center reading: estimated equipment wait, such as “~3–5 min.”
- Caption: “Estimated equipment wait.”
- Below the gauge: “Updated 2 min ago · 18 recent reports.”

### Data States
- Display a wait estimate only when supported by wait data or a calibrated model.
- Otherwise, show the crowd category in the center.
- If data is insufficient, show “Not enough recent data.”
- Do not present stale readings as live.

## 2. Best Time Today
- Compact hourly bar chart using the same 1–10 crowding scale.
- Clearly highlight the current time with a “Now” marker.
- Show a takeaway above the chart: “Usually quieter after 8 PM.”
- Label historical averages “Typical traffic.”
- Label predictions adjusted for current conditions “Today’s forecast.”
- If history is insufficient, show “Still learning the ARC’s patterns.”

## 3. Quick Crowd Report
- Heading: “Here now? How busy is it?”
- Four large, labeled buttons:
  - Quiet
  - Moderate
  - Busy
  - Packed
- One tap submits a report.
- Highlight the selected response.
- Confirm: “Thanks—you’re helping other Anteaters plan.”
- Changing the selection updates the current report instead of adding a duplicate.
- Show a retry option if submission fails.

## Layout
1. Live busyness meter — primary visual.
2. Daily traffic chart — planning information.
3. Crowd report buttons — quick contribution.

## Design Principles
- Keep the page readable and easy to use with one hand.
- Pair colors with text labels.
- Distinguish live observations from historical patterns and predictions.
- Use whole-number crowd scores and approximate wait ranges.
- Keep freshness and reporting coverage visible.
- This should be a one-pager without any scrolling. As a result, the information should be as concise as possible
- The information should come from a model. 

## The Model
- The model should have the state of all of the user's workouts and first page metrics
- Essentially, the model is the source of truth, and we query the database to update it.
- There should be a refresh function in the model. Every ~5 minutes, it also force updates the model from the database for updates
    - Just use stubs for now. The database is being implemented using supabase in python.



