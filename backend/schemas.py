from pydantic import BaseModel, Field, field_validator
from typing import Optional, List
from datetime import date as DateType


# ── Entry Schemas ─────────────────────────────────────────────────────────────

class EntryCreate(BaseModel):
    date:           str = Field(..., pattern=r"^\d{4}-\d{2}-\d{2}$")
    cal_breakfast:  float = Field(default=0.0, ge=0)
    cal_lunch:      float = Field(default=0.0, ge=0)
    cal_dinner:     float = Field(default=0.0, ge=0)
    cal_misc:       float = Field(default=0.0, ge=0)
    weight_kg:      Optional[float] = Field(default=None, ge=0, le=500)
    waist_cm:       Optional[float] = Field(default=None, ge=0, le=300)
    body_fat_pct:   Optional[float] = Field(default=None, ge=0, le=100)
    water_pct:      Optional[float] = Field(default=None, ge=0, le=100)
    muscle_pct:     Optional[float] = Field(default=None, ge=0, le=100)
    bone_kg:        Optional[float] = Field(default=None, ge=0, le=50)
    bmr_kcal:       Optional[float] = Field(default=None, ge=0, le=10000)
    impedance_ohm:  Optional[int]   = Field(default=None, ge=0, le=5000)
    protein_g:        Optional[float] = Field(default=None, ge=0, le=1000)
    calorie_target:   Optional[float] = Field(default=None, ge=0, le=10000)
    protein_target_g: Optional[float] = Field(default=None, ge=0, le=1000)
    meal_items:       Optional[str]   = None   # JSON string
    gym_attended:   bool = False
    sleep_hours:    Optional[float] = Field(default=None, ge=0, le=24)
    water_litres:   Optional[float] = Field(default=None, ge=0, le=20)
    mood_score:     Optional[int]   = Field(default=None, ge=1, le=5)
    notes:          Optional[str]   = None


class EntryResponse(EntryCreate):
    id:             int
    total_calories: float
    created_at:     str
    updated_at:     str

    class Config:
        from_attributes = True


# ── Watch Data Schemas ────────────────────────────────────────────────────────

class WatchDataCreate(BaseModel):
    date:             str = Field(..., pattern=r"^\d{4}-\d{2}-\d{2}$")
    steps:            Optional[int]   = Field(default=None, ge=0)
    distance_km:      Optional[float] = Field(default=None, ge=0)
    active_calories:  Optional[float] = Field(default=None, ge=0)
    total_calories:   Optional[float] = Field(default=None, ge=0)
    resting_hr:       Optional[int]   = Field(default=None, ge=0, le=300)
    avg_hr:           Optional[int]   = Field(default=None, ge=0, le=300)
    min_hr:           Optional[int]   = Field(default=None, ge=0, le=300)
    max_hr:           Optional[int]   = Field(default=None, ge=0, le=300)
    sleep_minutes:    Optional[int]   = Field(default=None, ge=0, le=1440)
    exercise_minutes: Optional[int]   = Field(default=None, ge=0, le=1440)
    exercise_count:   Optional[int]   = Field(default=None, ge=0)
    exercises:        Optional[str]   = None   # JSON string


class WatchDataResponse(WatchDataCreate):
    id:         int
    created_at: str
    updated_at: str

    class Config:
        from_attributes = True


# ── Analytics Schemas ─────────────────────────────────────────────────────────

class DataPoint(BaseModel):
    date:  str
    value: Optional[float]


class WeeklyAnalytics(BaseModel):
    week_start:             str
    week_end:               str
    days_logged:            int
    gym_days:               int
    gym_streak:             int
    avg_weight_kg:          Optional[float]
    weight_change_kg:       Optional[float]
    avg_waist_cm:           Optional[float]
    waist_change_cm:        Optional[float]
    total_calories:         float
    avg_daily_calories:     float
    avg_sleep_hours:        Optional[float]
    avg_water_litres:       Optional[float]
    avg_mood_score:         Optional[float]
    motivation_message:     str
    performance_score:      int
    entries:                List[EntryResponse]


class MonthlyAnalytics(BaseModel):
    month:                  str
    days_logged:            int
    gym_days:               int
    gym_attendance_pct:     float
    start_weight_kg:        Optional[float]
    end_weight_kg:          Optional[float]
    weight_change_kg:       Optional[float]
    weight_change_pct:      Optional[float]
    start_waist_cm:         Optional[float]
    end_waist_cm:           Optional[float]
    waist_change_cm:        Optional[float]
    avg_daily_calories:     float
    best_gym_streak:        int
    weight_series:          List[DataPoint]
    calorie_series:         List[DataPoint]
    waist_series:           List[DataPoint]
    mood_series:            List[DataPoint]
    highlights:             List[str]
    motivation_message:     str


class StreakInfo(BaseModel):
    current_streak:         int
    longest_streak:         int
    last_gym_date:          Optional[str]
    total_gym_days:         int
