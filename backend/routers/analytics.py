from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session
from typing import Optional
from datetime import date, timedelta
import calendar

from database import get_db
from models import Entry
from schemas import WeeklyAnalytics, MonthlyAnalytics, StreakInfo, DataPoint
from analytics_engine import (
    calculate_streak,
    calculate_longest_streak,
    performance_score,
    generate_weekly_message,
    generate_monthly_highlights,
)
from routers.entries import _to_response
from config import today as local_today

router = APIRouter(prefix="/analytics", tags=["analytics"])


# ── Weekly ────────────────────────────────────────────────────────────────────

@router.get("/weekly", response_model=WeeklyAnalytics)
def weekly_analytics(
    date_str: Optional[str] = Query(default=None, alias="date", pattern=r"^\d{4}-\d{2}-\d{2}$"),
    db: Session = Depends(get_db),
):
    ref_date = _parse_date(date_str) if date_str else local_today()

    # Monday–Sunday of the reference week
    week_start = ref_date - timedelta(days=ref_date.weekday())
    week_end   = week_start + timedelta(days=6)

    entries = (
        db.query(Entry)
        .filter(Entry.date >= str(week_start), Entry.date <= str(week_end))
        .order_by(Entry.date.asc())
        .all()
    )

    days_logged   = len(entries)
    gym_days      = sum(1 for e in entries if e.gym_attended)
    total_cal     = sum(e.total_calories for e in entries)
    avg_cal       = total_cal / days_logged if days_logged else 0

    weights = [e.weight_kg for e in entries if e.weight_kg is not None]
    waists  = [e.waist_cm  for e in entries if e.waist_cm  is not None]
    sleeps  = [e.sleep_hours  for e in entries if e.sleep_hours  is not None]
    waters  = [e.water_litres for e in entries if e.water_litres is not None]
    moods   = [e.mood_score   for e in entries if e.mood_score   is not None]

    avg_weight       = _avg(weights)
    avg_waist        = _avg(waists)
    weight_change    = (weights[-1] - weights[0]) if len(weights) >= 2 else None
    waist_change     = (waists[-1]  - waists[0])  if len(waists)  >= 2 else None

    # Streak requires all entries up to today
    all_entries = db.query(Entry).order_by(Entry.date.desc()).all()
    current_streak = calculate_streak(all_entries)

    score = performance_score(
        gym_days=gym_days,
        days_logged=days_logged,
        weight_change_kg=weight_change,
        current_streak=current_streak,
        avg_calories=avg_cal,
    )

    message = generate_weekly_message(
        score=score,
        gym_days=gym_days,
        days_in_week=days_logged,
        weight_change_kg=weight_change,
        waist_change_cm=waist_change,
        current_streak=current_streak,
    )

    return WeeklyAnalytics(
        week_start=str(week_start),
        week_end=str(week_end),
        days_logged=days_logged,
        gym_days=gym_days,
        gym_streak=current_streak,
        avg_weight_kg=avg_weight,
        weight_change_kg=weight_change,
        avg_waist_cm=avg_waist,
        waist_change_cm=waist_change,
        total_calories=total_cal,
        avg_daily_calories=avg_cal,
        avg_sleep_hours=_avg(sleeps),
        avg_water_litres=_avg(waters),
        avg_mood_score=_avg(moods),
        motivation_message=message,
        performance_score=score,
        entries=[_to_response(e) for e in entries],
    )


# ── Monthly ───────────────────────────────────────────────────────────────────

@router.get("/monthly", response_model=MonthlyAnalytics)
def monthly_analytics(
    month: Optional[str] = Query(default=None, pattern=r"^\d{4}-\d{2}$"),
    db: Session = Depends(get_db),
):
    today = local_today()
    if month:
        y, m = int(month[:4]), int(month[5:7])
    else:
        y, m = today.year, today.month

    month_start = date(y, m, 1)
    month_end   = date(y, m, calendar.monthrange(y, m)[1])

    entries = (
        db.query(Entry)
        .filter(Entry.date >= str(month_start), Entry.date <= str(month_end))
        .order_by(Entry.date.asc())
        .all()
    )

    days_logged = len(entries)
    gym_days    = sum(1 for e in entries if e.gym_attended)

    # Series data
    weight_series  = [DataPoint(date=e.date, value=e.weight_kg) for e in entries if e.weight_kg]
    calorie_series = [DataPoint(date=e.date, value=e.total_calories) for e in entries]
    waist_series   = [DataPoint(date=e.date, value=e.waist_cm)  for e in entries if e.waist_cm]
    mood_series    = [DataPoint(date=e.date, value=e.mood_score) for e in entries if e.mood_score]

    weights = [e.weight_kg for e in entries if e.weight_kg]
    waists  = [e.waist_cm  for e in entries if e.waist_cm]
    calories= [e.total_calories for e in entries]

    start_w = weights[0]  if weights else None
    end_w   = weights[-1] if weights else None
    w_change = (end_w - start_w) if (start_w and end_w) else None
    w_change_pct = (w_change / start_w * 100) if (w_change and start_w) else None

    start_wt = waists[0]  if waists else None
    end_wt   = waists[-1] if waists else None
    wt_change = (end_wt - start_wt) if (start_wt and end_wt) else None

    avg_cal = sum(calories) / len(calories) if calories else 0

    # Best streak within this month
    best_streak = calculate_longest_streak(entries)

    highlights = generate_monthly_highlights(
        gym_days=gym_days,
        days_logged=days_logged,
        weight_change_kg=w_change,
        waist_change_cm=wt_change,
        best_streak=best_streak,
        avg_calories=avg_cal,
    )

    # Simple monthly motivation message
    if gym_days >= days_logged * 0.8:
        message = f"What a month! {gym_days} gym sessions — you're building an unstoppable habit 🏆"
    elif gym_days >= days_logged * 0.5:
        message = f"Solid month with {gym_days} gym sessions. Build on this momentum next month! 💪"
    else:
        message = "Every month is a fresh start. Let's make next month your best yet! 🌟"

    return MonthlyAnalytics(
        month=f"{y:04d}-{m:02d}",
        days_logged=days_logged,
        gym_days=gym_days,
        gym_attendance_pct=(gym_days / days_logged * 100) if days_logged else 0,
        start_weight_kg=start_w,
        end_weight_kg=end_w,
        weight_change_kg=w_change,
        weight_change_pct=w_change_pct,
        start_waist_cm=start_wt,
        end_waist_cm=end_wt,
        waist_change_cm=wt_change,
        avg_daily_calories=avg_cal,
        best_gym_streak=best_streak,
        weight_series=weight_series,
        calorie_series=calorie_series,
        waist_series=waist_series,
        mood_series=mood_series,
        highlights=highlights,
        motivation_message=message,
    )


# ── Streak ────────────────────────────────────────────────────────────────────

@router.get("/streak", response_model=StreakInfo)
def streak_info(db: Session = Depends(get_db)):
    all_entries = db.query(Entry).order_by(Entry.date.desc()).all()
    gym_entries = [e for e in all_entries if e.gym_attended]

    current = calculate_streak(all_entries)
    longest = calculate_longest_streak(all_entries)
    last_gym = gym_entries[0].date if gym_entries else None

    return StreakInfo(
        current_streak=current,
        longest_streak=longest,
        last_gym_date=last_gym,
        total_gym_days=len(gym_entries),
    )


# ── Helpers ───────────────────────────────────────────────────────────────────

def _avg(values):
    return round(sum(values) / len(values), 2) if values else None


def _parse_date(s: str) -> date:
    y, m, d = s.split("-")
    return date(int(y), int(m), int(d))
