"""
Motivational analytics engine.
Generates personalised messages and performance scores from entry data.
"""
from typing import List, Optional
from models import Entry


# ── Streak Calculator ─────────────────────────────────────────────────────────

def calculate_streak(entries: List[Entry]) -> int:
    """Return current gym streak from a list of entries sorted by date DESC."""
    from datetime import timedelta
    from config import today as local_today

    gym_dates = sorted(
        [e.date for e in entries if e.gym_attended],
        reverse=True
    )
    if not gym_dates:
        return 0

    today = str(local_today())
    yesterday = str(local_today() - timedelta(days=1))

    # Streak must include today or yesterday to be "current"
    if gym_dates[0] not in (today, yesterday):
        return 0

    streak = 1
    for i in range(1, len(gym_dates)):
        prev = _date_from_str(gym_dates[i - 1])
        curr = _date_from_str(gym_dates[i])
        if (prev - curr).days == 1:
            streak += 1
        else:
            break
    return streak


def calculate_longest_streak(entries: List[Entry]) -> int:
    """Return all-time longest gym streak."""
    from datetime import timedelta

    gym_dates = sorted([e.date for e in entries if e.gym_attended])
    if not gym_dates:
        return 0

    longest = streak = 1
    for i in range(1, len(gym_dates)):
        prev = _date_from_str(gym_dates[i - 1])
        curr = _date_from_str(gym_dates[i])
        if (curr - prev).days == 1:
            streak += 1
            longest = max(longest, streak)
        else:
            streak = 1
    return longest


def _date_from_str(s: str):
    from datetime import date
    y, m, d = s.split("-")
    return date(int(y), int(m), int(d))


# ── Performance Score ─────────────────────────────────────────────────────────

def performance_score(
    gym_days: int,
    days_logged: int,
    weight_change_kg: Optional[float],
    current_streak: int,
    avg_calories: float,
    target_calories: float = 2000.0,
) -> int:
    """Return 0–100 performance score for a week."""
    score = 0.0

    # Gym attendance (40 pts)
    if days_logged > 0:
        score += (gym_days / days_logged) * 40

    # Calorie adherence (25 pts) — within ±15% of target is perfect
    if avg_calories > 0 and target_calories > 0:
        ratio = avg_calories / target_calories
        if 0.85 <= ratio <= 1.15:
            score += 25
        elif ratio < 0.85:
            score += max(0, 25 - (0.85 - ratio) * 100)
        else:
            score += max(0, 25 - (ratio - 1.15) * 80)

    # Weight trend (20 pts)
    if weight_change_kg is not None:
        if weight_change_kg <= -0.1:
            score += 20
        elif weight_change_kg <= 0.2:
            score += 12   # maintaining
        else:
            score += 4    # gaining

    # Streak bonus (15 pts)
    score += min(current_streak / 7, 1) * 15

    return min(100, int(score))


# ── Message Generator ─────────────────────────────────────────────────────────

def generate_weekly_message(
    score: int,
    gym_days: int,
    days_in_week: int,
    weight_change_kg: Optional[float],
    waist_change_cm: Optional[float],
    current_streak: int,
) -> str:
    parts = []

    # Tier opener
    if score >= 80:
        openers = [
            "You're absolutely CRUSHING it this week 🔥",
            "Beast mode: fully activated 💪",
            "Elite performance this week — you should be proud 🏆",
        ]
    elif score >= 60:
        openers = [
            "Solid week — you're building real momentum 💪",
            "Strong effort this week. The results are coming 📈",
            "Consistency is your superpower — keep going 🌟",
        ]
    elif score >= 40:
        openers = [
            "Good start — every step forward counts 👊",
            "Progress is progress, no matter the pace 🚀",
            "You showed up — that's half the battle ✅",
        ]
    else:
        openers = [
            "Every champion has tough weeks. Your comeback starts now 💫",
            "Reset. Refocus. Reload — you've got this 🌱",
            "The journey isn't linear. Keep moving forward 🎯",
        ]

    import random
    parts.append(random.choice(openers))

    # Gym callout
    if gym_days == days_in_week and days_in_week >= 5:
        parts.append(f"Perfect gym week — {gym_days}/{days_in_week} days! 🎉")
    elif gym_days > 0:
        parts.append(f"You hit the gym {gym_days} day{'s' if gym_days != 1 else ''} this week.")

    # Streak milestone
    if current_streak >= 30:
        parts.append(f"30-DAY STREAK 🔥🔥🔥 You're a machine!")
    elif current_streak >= 14:
        parts.append(f"{current_streak}-day streak — absolutely incredible!")
    elif current_streak >= 7:
        parts.append(f"One full week streak — that's serious discipline! 🗓️")
    elif current_streak >= 3:
        parts.append(f"{current_streak}-day streak going strong 🔥")

    # Body metrics
    if weight_change_kg is not None and weight_change_kg < -0.1:
        parts.append(f"Down {abs(weight_change_kg):.1f}kg — real progress! 📉")
    if waist_change_cm is not None and waist_change_cm < -0.1:
        parts.append(f"Waist down {abs(waist_change_cm):.1f}cm — your body is changing! 📏")

    return " ".join(parts)


def generate_monthly_highlights(
    gym_days: int,
    days_logged: int,
    weight_change_kg: Optional[float],
    waist_change_cm: Optional[float],
    best_streak: int,
    avg_calories: float,
) -> List[str]:
    highlights = []
    attendance_pct = (gym_days / days_logged * 100) if days_logged > 0 else 0

    if attendance_pct >= 80:
        highlights.append(f"Gym attendance: {attendance_pct:.0f}% 🏆 World-class consistency!")
    elif attendance_pct >= 60:
        highlights.append(f"Gym attendance: {attendance_pct:.0f}% 💪 Solid month!")
    elif gym_days > 0:
        highlights.append(f"Gym attendance: {attendance_pct:.0f}% — {gym_days} sessions logged.")

    if weight_change_kg is not None and weight_change_kg < 0:
        highlights.append(f"Lost {abs(weight_change_kg):.1f}kg this month 🎉")
    elif weight_change_kg is not None and abs(weight_change_kg) <= 0.3:
        highlights.append("Weight maintained — great discipline! ⚖️")

    if waist_change_cm is not None and waist_change_cm < -0.5:
        highlights.append(f"Waist -{abs(waist_change_cm):.1f}cm — visible progress! 📏")

    if best_streak >= 7:
        highlights.append(f"Best streak: {best_streak} days in a row 🔥")

    if not highlights:
        highlights.append("You logged your data — that's the first step. Keep going! 💫")

    return highlights
