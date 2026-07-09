# TimezoneBar — macOS Menubar Timezone App

## Spec v0.1 · 2026-07-08

## Problem

Checking times across cities means visiting conversion websites repeatedly. Scheduling a meeting across zones means mentally cross-referencing tables. Both should be one click from the menubar.

## Goals

1. Glance: current time in N cities, one click from the menubar.
2. Align: scrub a slider to shift all cities together and see day offsets (−1 day / +1 day).
3. Schedule: an alignment grid showing each city's working hours side by side, colored by meeting suitability.

## Non-goals (v1)

Calendar integration, meeting invites, iOS companion, team sharing, notifications.

---

## UX

### Menubar item

- Icon only by default; optional setting to show one "pinned" city's time next to the icon (e.g. `SF 14:30`).
- Left-click opens the popover. No dock icon (LSUIElement).

### Popover — List view (default)

```
┌──────────────────────────────┐
│ 03:57  🇬🇧 London             │
│ 08:27  🇮🇳 Kolkata            │
│ 12:57  🇦🇺 Sydney             │
│ 22:57  🇺🇸 San Francisco (-1) │
│                              │
│  ──────────●──────────  Now  │   ← time slider
│                        ⋯     │   ← settings menu
└──────────────────────────────┘
```

- Each row: time (HH:mm, respects 12/24h setting), flag emoji, city label, day-offset badge (`-1`/`+1`) when the date differs from the local date.
- Rows sorted by UTC offset (west→east) or manual drag order (setting).
- Row context menu: rename label, set as pinned, remove.

### Time slider

- Range: −24h to +24h from now, 15-min steps. Snaps to :00/:30 with light haptic-style resistance.
- Dragging updates every row live; day-offset badges update.
- While scrubbed, the header shows the reference local time (e.g. "Your time: Thu 9:30 PM") and a **Now** button resets to live time.
- Live clock resumes 10s after the popover closes or on **Now**.

### Alignment grid view (tab or ⌘2)

Horizontal 24-hour bar per city, all aligned to the user's local timeline:

```
          0   3   6   9   12  15  18  21  24  (your local hours)
London    ░░░░░░▒▒██████████▒▒░░░░░░
Sydney    ██▒▒░░░░░░░░░░▒▒██████████
SF        ▒▒██████████▒▒░░░░░░░░▒▒▒▒
              ▲ vertical cursor follows slider
```

- Cell colors: **green** = working hours (default 9–17, per-city editable), **yellow** = shoulder (7–9, 17–22), **red/gray** = night (22–7).
- A vertical cursor line spans all rows, driven by the same slider; a column where every row is green/yellow = viable meeting time.
- Clicking a column moves the cursor there (slider syncs).
- Selected column shows the exact time per city in a tooltip/footer line, e.g. `Wed 10:00 London · Wed 19:00 Sydney · Tue 02:00 SF`.

### Adding cities

- `+` button → search field querying the IANA tz database (city name, country, common aliases; fuzzy match "SF" → San Francisco).
- Max ~10 cities (UI degrades beyond that); reorderable.

### Settings

12/24h format · show seconds · pinned city in menubar · launch at login · sort mode · per-city working hours · global keyboard shortcut to open popover.

---

## Architecture

- **Stack:** Swift 5.10+, SwiftUI, macOS 14+. `MenuBarExtra` (`.window` style) for the popover. No third-party dependencies.
- **Time math:** Foundation `TimeZone`/`Calendar` with IANA identifiers — DST and day-offset handling comes free. Never store raw UTC offsets; store identifiers (`Australia/Sydney`).
- **State:** single `ObservableObject` store — `cities: [City]`, `scrubOffset: TimeInterval?`, `settings`. `City = { id, tzIdentifier, label, flag, workStart, workEnd, pinned }`.
- **Clock:** 1s timer while popover is open (or menubar shows time); paused otherwise. Timer recalculates from `Date.now`, never accumulates.
- **Persistence:** `UserDefaults` (JSON-encoded city list + settings). No accounts, no network.
- **City search:** bundled static JSON (city → tz identifier, country, flag, aliases) derived from IANA/CLDR data; searched in-memory.
- **Grid rendering:** SwiftUI `Canvas` — one draw pass per row, 48 half-hour cells; cursor as overlay. Cheap enough to redraw on every slider tick.

### Edge cases

- DST transitions: a city's bar can be 23/25 "local" hours against the user's timeline — derive cell colors from actual local time at each column, not fixed offset.
- Half-hour zones (India +5:30) and 45-min zones (Nepal, Eucla): grid columns are user-local; city local time is computed per column, so these work without special cases.
- Day-offset badge must compare calendar dates, not just ±12h offsets.
- User's own timezone changes (travel): observe `NSSystemTimeZoneDidChange` and recompute.

---

## Milestones

1. **M1 — Glance:** MenuBarExtra, city list with live clocks, add/remove/search cities, persistence. *(usable daily)*
2. **M2 — Scrub:** time slider, day-offset badges, Now reset.
3. **M3 — Align:** grid view, working-hours coloring, cursor/slider sync, per-city hours.
4. **M4 — Polish:** pinned menubar time, launch at login, global shortcut, sort options, 12/24h, dark mode audit.

## Success criteria

- Popover opens in <100 ms; idle CPU ~0% with popover closed.
- Finding a 3-city meeting time takes one slider drag, no mental math.
- Times verified correct across DST boundaries (test: Sydney/London/SF around early April & early October transitions).

## Open questions

- Show a second "home" reference row at top?
- Copy-to-clipboard of the selected slot ("Wed 10:00 GMT / 19:00 AEST / 02:00 PT") — deferred, cheap to add in M3.
- Distribution: direct download vs Mac App Store (sandbox is fine; no entitlements needed beyond login item).
