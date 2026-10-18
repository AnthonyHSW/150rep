# ARC App — Theme & UI Design Plan

## Product Direction

A native iOS workout app that helps UCI students decide when to train, log workouts, and contribute to shared gym activity estimates.

The interface should feel calm, athletic, and practical. Prioritize clear information, quick actions, and familiar Apple interactions. Use an AntAlmanac-inspired palette with native floating Liquid Glass navigation.

## Color Theme

Reference: [AntAlmanac](https://antalmanac.com). The palette below adapts its blue and neutral colors to this app; it does not imply affiliation.
- We should not adopt its style, however. Just the color theme. 

| Role | Light Mode | Dark Mode |
| --- | --- | --- |
| Brand blue | `#305DB7` | `#305DB7` |
| Interactive tint | `#305DB7` | `#90B3F9` |
| Page background | `#F5F6FC` | `#1E1E1E` |
| Content surface | `#FFFFFF` | `#2A2A2A` |
| Primary text | `#212529` | System primary label |
| Secondary text | `#606166` | System secondary label |
| Separators | System separator | System separator |

- Define semantic color assets with light and dark variants.
- Use blue for primary actions, links, and selected controls.
- Use pale blue-gray backgrounds and white surfaces in light mode.
- Use charcoal backgrounds and slightly lighter surfaces in dark mode.
- Use lighter blue for dark-mode icons, links, and selections.
- Prefer system text colors when needed for accessible contrast.
- Do not use gold as a general decorative accent.

### Crowding Colors

| State | Color family |
| --- | --- |
| Quiet | Blue |
| Moderate | Teal |
| Busy | Orange |
| Packed | Red |

Use a cool-to-hot gradient for the busyness meter. Reserve these colors for crowd severity and pair them with words or numeric values. Exact status shades should be tested in both appearances.

## Typography

- Use the native San Francisco system font and Dynamic Type text styles.
- Use large titles for main pages, semibold section headings, and regular body text.
- Use secondary text for captions, timestamps, and supporting details.
- Use monospaced digits for timers and changing numeric readings.
- Allow text and containers to expand at larger accessibility sizes.

## Layout and Surfaces

- Use approximately 16–20 points of horizontal page padding.
- Follow a spacing scale of 4, 8, 12, 16, 24, and 32 points.
- Use approximately 20-point corner radii for content cards where appropriate.
- Group information with spacing before adding borders.
- Each card should answer one question or support one task; avoid nested cards.
- Prefer subtle surface differences over heavy shadows.
- Keep charts, workout entries, and forms on stable, readable surfaces.

## Native Navigation and Liquid Glass

### Shared Page Structure

1. Native top navigation with the page title and an optional top-right control.
2. Scrollable page content, with the primary information or action first.
3. Floating bottom tab navigation.
4. An active-workout accessory above or alongside the bottom navigation when needed.

### Top Navigation

- Use a separate `NavigationStack` within each tab.
- Place page-specific controls in native toolbar items.
- Use a native `Menu` for multiple related options and a direct button for one destination.
- Omit the top-right control when there are no useful options.
- Use the system Liquid Glass treatment on supported versions.
- Let iOS manage navigation-bar appearance and scroll transitions; do not force the entire title/header into a custom glass capsule.
- Give icon-only controls accessible labels.

### Bottom Tabs

Use a native `TabView` with icons and visible labels:

| Tab | Purpose | Suggested SF Symbol |
| --- | --- | --- |
| Live | Current crowding, daily patterns, and reporting | `waveform.path.ecg` |
| Workouts | Start, resume, and manage workouts | `dumbbell` |
| Profile | Personal progress, workout history, and account | `person.crop.circle` |

- Use the system floating Liquid Glass tab-bar appearance where supported.
- Apply interactive blue to selected controls while keeping glass materials system-managed.
- Preserve navigation and content state when switching tabs.
- Keep tabs available on main pages.
- Workout history belongs inside Profile; there is no separate History tab.

### Per-Page Top-Right Controls

| Page | Control | Behavior |
| --- | --- | --- |
| Live | Optional view-options menu | Show only when additional supported views exist |
| Workouts | Workout-options menu | Create a routine or manage saved routines |
| Profile | Settings gear | Open account and app settings |

### Active Workout Accessory

- Show a compact Resume Workout control near the bottom navigation.
- Prefer the native tab accessory mechanism where supported.
- Include the workout name and elapsed time.
- Tapping resumes the active workout without losing logged data.

### Glass Usage

- Use Liquid Glass primarily for navigation and floating controls.
- Let the page background show through native glass materials.
- Avoid custom blur imitations and solid-blue navigation panels.
- Use native fallback appearances on older supported iOS versions.
- Respect Reduce Transparency, Reduce Motion, and system contrast settings.

## Page 1 — Live / ARC Busyness

Purpose: Help users decide whether to visit the ARC now or wait for a quieter time.

### 1. Live Busyness Meter

- Heading: “ARC right now.”
- Main visual: a semicircular gauge with a cool-to-hot gradient.
- Scale: 1–10, with a marker indicating current crowding.
- Endpoint labels: “1 · Quiet” and “10 · Packed.”
- Current score above the gauge, for example: “6/10 · Busy.”
- Center reading: a supported approximate equipment wait, such as “~3–5 min.”
- Caption: “Estimated equipment wait.”
- Supporting line: “Updated 2 min ago · 18 recent reports.”
- Example values are illustrative, not actual ARC readings.

#### Data States

- Only display wait times when supported by observations or a calibrated model.
- A crowd score alone does not establish average wait time.
- Otherwise, display the crowd category as the center reading.
- Show “Not enough recent data” when coverage is insufficient.
- Mark stale readings clearly; never present them as live.

### 2. Best Time Today

- Place a compact hourly bar chart beneath the meter.
- Use the same 1–10 crowding scale.
- Mark the current time with a labeled “Now” indicator.
- Place a useful takeaway above the chart, such as “Usually quieter after 8 PM.”
- Label historical averages “Typical traffic.”
- Use “Today’s forecast” only for predictions adjusted for current conditions.
- Distinguish observations and predictions with labels or mark styling.
- Show “Still learning the ARC’s patterns” when history is insufficient.

### 3. Quick Crowd Report

- Heading: “Here now? How busy is it?”
- Four large buttons: Quiet, Moderate, Busy, Packed.
- Prefer a single row; reflow when screen width or Dynamic Type requires it.
- One tap submits a report and highlights the selected response.
- Confirm: “Thanks—you’re helping other Anteaters plan.”
- Allow corrections by updating the current report rather than adding a duplicate.
- Show submission failures inline with a retry option.
- Four simple reporting categories can feed a whole-number 1–10 estimate; avoid false precision.

Keep these three sections as the home page’s core scope. Equipment breakdowns and workout-focus selectors are outside the agreed first-page layout.

## Page 2 — Workouts

Purpose: “What am I training today?”

- Prominent Start Workout or Resume Workout action.
- Saved routines below the primary action.
- Simple exercise search and selection.
- Equipment selection when an exercise has multiple equipment variants.
- Top-right menu for routine creation and management.

### Active Workout

Purpose: “Record this set with minimal effort.”

- Show workout title and elapsed time.
- Organize exercises into expandable sections.
- Provide set rows with weight, reps, and completion controls.
- Make previous set values available as reference.
- Provide Add Exercise and Finish Workout actions.
- Save locally so interruptions and poor connectivity do not lose progress.
- Use subtle haptics for set completion.
- Preserve the workout when navigating between tabs.

## Page 3 — Profile

Purpose: “See my training history and manage my account.”

### Content Order

1. Profile header with name and verified account email.
2. Compact personal summary, such as workouts completed this week.
3. Workout history grouped by date.

### Workout History

- Each entry shows workout name, date, duration, and exercise count.
- Tapping an entry opens its exercises and recorded sets.
- Show an encouraging empty state before the first completed workout.
- Add personal progress charts after the core logging flow works.

### Settings

Access settings through the top-right gear button:

- Account details.
- Weight units: pounds or kilograms.
- Appearance: system, light, or dark.
- Privacy and contribution preferences.
- Sign-out.

## Shared Controls and Feedback

- Use native buttons, menus, pickers, sheets, and confirmation dialogs.
- Give each section one visually dominant action.
- Use clear verbs: Start Workout, Add Exercise, Finish Workout.
- Use full-width buttons for major actions when appropriate.
- Highlight selections immediately and confirm successful submissions inline.
- Avoid alerts for routine successes.
- Keep error messages close to the affected control and offer recovery.
- Use SF Symbols consistently, with labels where meaning is not obvious.

## Charts and Data Presentation

- Prefer Swift Charts for traffic and personal progress.
- Use blue for ordinary trends; use crowding colors only when encoding severity.
- Keep axes consistent, gridlines subtle, and labels readable.
- Provide a short written takeaway and accessible chart summaries.
- Treat crowding as an estimate, not an exact headcount or availability guarantee.
- Show freshness and reporting coverage alongside live estimates.
- Use whole-number crowd scores and approximate wait ranges.
- Keep individual workout histories private; expose aggregate community activity.
- Historical uploads contribute to history, not current activity.
- Distinguish locally saved changes from successfully synced data.

## Accessibility

- Provide minimum 44 × 44-point effective touch targets.
- Support Dynamic Type and VoiceOver.
- Never communicate meaning through color alone.
- Respect Reduce Motion and Reduce Transparency.
- Keep essential actions available without hidden gestures.
- Avoid truncating important labels and data.
- Test light mode, dark mode, large text, and increased contrast.

## MVP Implementation Order

1. Semantic colors, typography, shared controls, and native navigation shell.
2. Live page with explicit demo/loading/empty/error states.
3. Login and account states.
4. Workout start and exercise selection.
5. Active workout logging and resume accessory.
6. Profile, workout history, and settings.
7. Data-backed traffic forecasts and additional progress insights.
