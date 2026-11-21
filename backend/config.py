import os

# Groq API key — set in /opt/backend/.env (GROQ_API_KEY=gsk_...) and passed with
# `docker run --env-file`. Never hardcode it here.
GROQ_API_KEY = os.getenv("GROQ_API_KEY", "").strip()

# Preferred model. Optional override in .env (GROQ_MODEL=...). If Groq rejects it,
# routers/ai.py falls back to the best model this key can actually use.
GROQ_MODEL = os.getenv("GROQ_MODEL", "openai/gpt-oss-120b").strip()

# Model that can read photos (food photo → calories). Override in .env if Groq renames it.
GROQ_VISION_MODEL = os.getenv("GROQ_VISION_MODEL", "qwen/qwen3.8-27b").strip()

# Personal profile (single user) — set in .env, never in code. Used by the web
# dashboard (BMI, waist-to-height, goal) and the AI coach. Anything unset is
# simply left out. The phone app keeps its own copy (Home → Profile).
def _env_float(name: str):
    value = os.getenv(name, "").strip()
    return float(value) if value else None


USER_NAME = os.getenv("USER_NAME", "").strip()
HEIGHT_CM = _env_float("HEIGHT_CM")
TARGET_WEIGHT_KG = _env_float("TARGET_WEIGHT_KG")
BIRTH_DATE = os.getenv("BIRTH_DATE", "").strip()   # YYYY-MM-DD
SEX = os.getenv("SEX", "").strip()                 # male / female

# The container clock is UTC, so "today" must be computed in your local time here,
# never with date.today(). Set TZ_OFFSET_HOURS / TZ_NAME in .env (a fixed offset;
# fine for places without daylight saving).
from datetime import date as _date, datetime as _datetime, timedelta as _timedelta, timezone as _timezone

LOCAL_TZ = _timezone(_timedelta(hours=float(os.getenv("TZ_OFFSET_HOURS", "10"))),
                     os.getenv("TZ_NAME", "local"))


def today() -> _date:
    """Today's date in local time."""
    return _datetime.now(LOCAL_TZ).date()
