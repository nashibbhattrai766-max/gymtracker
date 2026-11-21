from sqlalchemy import Column, Integer, Float, String, Boolean, Text
from sqlalchemy.sql import func
from database import Base


class Entry(Base):
    __tablename__ = "entries"

    id              = Column(Integer, primary_key=True, index=True)
    date            = Column(String(10), unique=True, nullable=False, index=True)  # YYYY-MM-DD

    # Calories
    cal_breakfast   = Column(Float, default=0.0)
    cal_lunch       = Column(Float, default=0.0)
    cal_dinner      = Column(Float, default=0.0)
    cal_misc        = Column(Float, default=0.0)

    # Body metrics
    weight_kg       = Column(Float, nullable=True)
    waist_cm        = Column(Float, nullable=True)

    # Body composition from the Vitafit scale (weight + impedance → formulas in the app)
    body_fat_pct    = Column(Float, nullable=True)
    water_pct       = Column(Float, nullable=True)
    muscle_pct      = Column(Float, nullable=True)
    bone_kg         = Column(Float, nullable=True)
    bmr_kcal        = Column(Float, nullable=True)
    impedance_ohm   = Column(Integer, nullable=True)

    # Nutrition: protein eaten, the targets in force that day, and photo-estimated
    # food items (JSON list of {meal, name, portion, kcal, protein_g})
    protein_g        = Column(Float, nullable=True)
    calorie_target   = Column(Float, nullable=True)
    protein_target_g = Column(Float, nullable=True)
    meal_items       = Column(Text, nullable=True)

    # Gym
    gym_attended    = Column(Boolean, default=False)

    # Optional extras
    sleep_hours     = Column(Float, nullable=True)
    water_litres    = Column(Float, nullable=True)
    mood_score      = Column(Integer, nullable=True)   # 1–5
    notes           = Column(Text, nullable=True)

    # Timestamps
    created_at      = Column(String, default=func.now())
    updated_at      = Column(String, default=func.now(), onupdate=func.now())

    @property
    def total_calories(self) -> float:
        return (
            (self.cal_breakfast or 0)
            + (self.cal_lunch or 0)
            + (self.cal_dinner or 0)
            + (self.cal_misc or 0)
        )


class WatchData(Base):
    """Daily Galaxy Watch / Samsung Health data, pulled from Health Connect."""
    __tablename__ = "watch_data"

    id                  = Column(Integer, primary_key=True, index=True)
    date                = Column(String(10), unique=True, nullable=False, index=True)  # YYYY-MM-DD

    steps               = Column(Integer, nullable=True)
    distance_km         = Column(Float, nullable=True)
    active_calories     = Column(Float, nullable=True)
    total_calories      = Column(Float, nullable=True)

    resting_hr          = Column(Integer, nullable=True)
    avg_hr              = Column(Integer, nullable=True)
    min_hr              = Column(Integer, nullable=True)
    max_hr              = Column(Integer, nullable=True)

    sleep_minutes       = Column(Integer, nullable=True)   # sleep that ended on this date
    exercise_minutes    = Column(Integer, nullable=True)
    exercise_count      = Column(Integer, nullable=True)
    exercises           = Column(Text, nullable=True)      # JSON list of sessions

    created_at          = Column(String, default=func.now())
    updated_at          = Column(String, default=func.now(), onupdate=func.now())


class WorkoutSession(Base):
    """One gym session from the Exercise tab (plan day done on a date).
    The full log (sets, weights, reps, treadmill, notes) is kept as JSON."""
    __tablename__ = "workout_sessions"

    id              = Column(String(20), primary_key=True)                 # "YYYY-MM-DD-d3"
    date            = Column(String(10), nullable=False, index=True)
    plan_day        = Column(Integer, nullable=False)
    started_at      = Column(String, nullable=True)
    finished_at     = Column(String, nullable=True)
    data            = Column(Text, nullable=False)

    created_at      = Column(String, default=func.now())
    updated_at      = Column(String, default=func.now(), onupdate=func.now())
