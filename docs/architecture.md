# GymTracker — System Architecture

## Tech Stack Justification

| Layer | Choice | Why |
|-------|--------|-----|
| Mobile | **Flutter** | Native performance, gorgeous charts via `fl_chart`, single codebase (Android + iOS later), Dart is easy to learn, rich offline support with `sqflite` |
| Backend | **Python FastAPI** | Auto-generates OpenAPI docs, async by default, excellent Pydantic validation, fastest Python framework, easy to containerise |
| Database | **SQLite** | Zero-config, perfect for single-user, runs inside the container, no separate DB service needed — upgrade to PostgreSQL later if needed |
| Container | **Docker on Proxmox LXC** | Lightweight, easy to update, standard deployment pattern |
| State Mgmt | **Provider** (Flutter) | Official recommendation, simple, performant for this scale |
| Caching | **sqflite** (Flutter) | Local SQLite on device for offline-first behaviour |

---

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        YOUR HOME NETWORK                        │
│                                                                 │
│  ┌──────────────────────┐         ┌────────────────────────┐   │
│  │    ANDROID PHONE      │         │   PROXMOX HOST         │   │
│  │                       │  HTTP   │                        │   │
│  │  ┌────────────────┐  │◄───────►│  ┌──────────────────┐ │   │
│  │  │  Flutter App   │  │  :8000  │  │  Docker / LXC    │ │   │
│  │  │                │  │         │  │                  │ │   │
│  │  │  ┌──────────┐  │  │         │  │  ┌────────────┐  │ │   │
│  │  │  │ Screens  │  │  │         │  │  │ FastAPI    │  │ │   │
│  │  │  │ Dashboard│  │  │         │  │  │ app        │  │ │   │
│  │  │  │ Daily Log│  │  │         │  │  │            │  │ │   │
│  │  │  │ Weekly   │  │  │         │  │  │ /entries   │  │ │   │
│  │  │  │ Monthly  │  │  │         │  │  │ /analytics │  │ │   │
│  │  │  │ Insights │  │  │         │  │  │ /summary   │  │ │   │
│  │  │  └──────────┘  │  │         │  │  └─────┬──────┘  │ │   │
│  │  │                │  │         │  │        │          │ │   │
│  │  │  ┌──────────┐  │  │         │  │  ┌─────▼──────┐  │ │   │
│  │  │  │ Provider │  │  │         │  │  │  SQLite DB  │  │ │   │
│  │  │  │  State   │  │  │         │  │  │             │  │ │   │
│  │  │  └──────────┘  │  │         │  │  │ entries     │  │ │   │
│  │  │                │  │         │  │  │ table       │  │ │   │
│  │  │  ┌──────────┐  │  │         │  │  └─────────────┘  │ │   │
│  │  │  │ sqflite  │  │  │         │  └──────────────────┘ │   │
│  │  │  │ (local   │  │  │         └────────────────────────┘   │
│  │  │  │  cache)  │  │  │                                      │
│  │  │  └──────────┘  │  │                                      │
│  │  └────────────────┘  │                                      │
│  └──────────────────────┘                                      │
└─────────────────────────────────────────────────────────────────┘

Offline mode: App reads/writes sqflite cache. On reconnect, syncs to API.
```

---

## Database Schema

```sql
-- Daily log entries (core table)
CREATE TABLE entries (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    date        TEXT NOT NULL UNIQUE,   -- ISO format: "2025-01-15"
    
    -- Calories
    cal_breakfast   REAL DEFAULT 0,
    cal_lunch       REAL DEFAULT 0,
    cal_dinner      REAL DEFAULT 0,
    cal_misc        REAL DEFAULT 0,
    
    -- Body metrics
    weight_kg       REAL,
    waist_cm        REAL,
    
    -- Gym
    gym_attended    INTEGER DEFAULT 0,  -- 0 = No, 1 = Yes
    
    -- Optional extras
    sleep_hours     REAL,
    water_litres    REAL,
    mood_score      INTEGER,            -- 1–5 scale
    notes           TEXT,
    
    -- Timestamps
    created_at  TEXT DEFAULT (datetime('now')),
    updated_at  TEXT DEFAULT (datetime('now'))
);

-- Index for date-range queries
CREATE INDEX idx_entries_date ON entries(date);
```

**Computed columns** (calculated at query time, not stored):
- `total_calories = cal_breakfast + cal_lunch + cal_dinner + cal_misc`
- Weekly summaries (avg weight, total gym days, avg calories)
- Monthly summaries (trend lines, % improvements)

---

## API Endpoint Reference

### Base URL: `http://<proxmox-ip>:8000`

---

#### `POST /entries`
Create or update today's entry (upsert by date).

**Request:**
```json
{
  "date": "2025-01-15",
  "cal_breakfast": 450,
  "cal_lunch": 650,
  "cal_dinner": 700,
  "cal_misc": 200,
  "weight_kg": 78.5,
  "waist_cm": 85.0,
  "gym_attended": true,
  "sleep_hours": 7.5,
  "water_litres": 2.5,
  "mood_score": 4,
  "notes": "Good session today!"
}
```
**Response:** `201 Created` — the saved entry object.

---

#### `GET /entries/{date}`
Fetch a single day's entry.

**Response:**
```json
{
  "id": 42,
  "date": "2025-01-15",
  "cal_breakfast": 450,
  "cal_lunch": 650,
  "cal_dinner": 700,
  "cal_misc": 200,
  "total_calories": 2000,
  "weight_kg": 78.5,
  "waist_cm": 85.0,
  "gym_attended": true,
  "sleep_hours": 7.5,
  "water_litres": 2.5,
  "mood_score": 4,
  "notes": "Good session today!"
}
```

---

#### `GET /entries?start=YYYY-MM-DD&end=YYYY-MM-DD`
Fetch all entries in a date range.

---

#### `GET /analytics/weekly?date=YYYY-MM-DD`
Returns the week containing the given date.

**Response:**
```json
{
  "week_start": "2025-01-13",
  "week_end": "2025-01-19",
  "days_logged": 5,
  "gym_days": 4,
  "gym_streak": 3,
  "avg_weight_kg": 78.3,
  "weight_change_kg": -0.4,
  "avg_waist_cm": 84.8,
  "waist_change_cm": -0.2,
  "total_calories": 13500,
  "avg_daily_calories": 1928,
  "avg_sleep_hours": 7.2,
  "avg_water_litres": 2.3,
  "motivation_message": "You hit the gym 4 out of 5 days — incredible dedication! Your waist dropped 0.2cm this week. Keep pushing! 💪",
  "entries": [...]
}
```

---

#### `GET /analytics/monthly?month=YYYY-MM`
Returns monthly aggregates and trend data.

**Response:**
```json
{
  "month": "2025-01",
  "days_logged": 22,
  "gym_days": 18,
  "gym_attendance_pct": 81.8,
  "start_weight_kg": 79.2,
  "end_weight_kg": 77.8,
  "weight_change_kg": -1.4,
  "weight_change_pct": -1.77,
  "start_waist_cm": 86.0,
  "end_waist_cm": 84.2,
  "waist_change_cm": -1.8,
  "avg_daily_calories": 1950,
  "best_gym_streak": 7,
  "weight_series": [{"date": "2025-01-01", "value": 79.2}, ...],
  "calorie_series": [...],
  "waist_series": [...],
  "highlights": [
    "Lost 1.4kg this month 🎉",
    "Best gym streak: 7 days in a row 🔥",
    "Gym attendance: 82% — personal best!"
  ]
}
```

---

#### `GET /analytics/streak`
Current gym streak and longest ever streak.

---

#### `GET /health`
Health check — returns `{"status": "ok"}`.

---

## Folder Structure

```
GYM APP/
│
├── architecture.md           ← This file
│
├── backend/
│   ├── main.py               ← FastAPI app entry point
│   ├── database.py           ← SQLite connection + init
│   ├── models.py             ← SQLAlchemy ORM models
│   ├── schemas.py            ← Pydantic request/response schemas
│   ├── routers/
│   │   ├── __init__.py
│   │   ├── entries.py        ← CRUD for daily log entries
│   │   └── analytics.py      ← Weekly/monthly analytics + motivation
│   ├── analytics_engine.py   ← Motivational message generator
│   ├── requirements.txt
│   └── Dockerfile
│
├── flutter_app/
│   ├── pubspec.yaml
│   ├── android/              ← Android build config
│   └── lib/
│       ├── main.dart         ← App entry, theme, routing
│       ├── config/
│       │   └── api_config.dart    ← Backend URL config
│       ├── models/
│       │   ├── entry.dart         ← DailyEntry data model
│       │   └── analytics.dart     ← Weekly/Monthly analytics models
│       ├── services/
│       │   ├── api_service.dart   ← HTTP calls to FastAPI
│       │   └── local_storage.dart ← sqflite offline cache
│       ├── providers/
│       │   └── gym_provider.dart  ← App state (Provider)
│       ├── screens/
│       │   ├── home_screen.dart       ← Dashboard
│       │   ├── log_screen.dart        ← Daily input form
│       │   ├── weekly_screen.dart     ← Weekly report + charts
│       │   ├── monthly_screen.dart    ← Monthly report + graphs
│       │   └── insights_screen.dart  ← Motivational analytics
│       └── widgets/
│           ├── stat_card.dart         ← Reusable stat display card
│           ├── calorie_ring.dart      ← Animated calorie donut
│           ├── gym_streak_badge.dart  ← Streak fire badge
│           └── trend_chart.dart       ← Reusable line chart
│
└── deploy/
    ├── proxmox_setup.md      ← Proxmox LXC deployment guide
    └── apk_build.md          ← APK build instructions
```

---

## Motivational Analytics Logic

The engine scores each week across 4 dimensions and generates personalised messages:

```
Score = (gym_pct × 40) + (calorie_score × 25) + (weight_trend × 20) + (streak_bonus × 15)

gym_pct       = gym_days / days_logged  (0–1)
calorie_score = 1 if avg < target, else penalise proportionally
weight_trend  = 1 if losing weight, 0.5 if maintaining, 0 if gaining
streak_bonus  = min(current_streak / 7, 1)  (caps at 7-day streak)
```

Message templates pick from 3 tiers:
- **Elite (80–100):** "You're in beast mode this week 🔥"
- **Good (50–79):** "Solid week — you're building great habits 💪"
- **Encouragement (0–49):** "Every rep counts. Let's make this week your comeback 🌟"

Specific callouts are appended for streak milestones (3, 7, 14, 30 days), weight loss PBs, and perfect gym weeks.
