from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel
from typing import Optional
from datetime import date, timedelta
import httpx
import json
import re

from database import get_db
from models import Entry, WatchData, WorkoutSession
from config import GROQ_API_KEY, GROQ_MODEL, HEIGHT_CM, TARGET_WEIGHT_KG, BIRTH_DATE, SEX, USER_NAME
from config import today as local_today

router = APIRouter(prefix="/ai", tags=["ai"])

GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions"


# ── Schemas ───────────────────────────────────────────────────────────────────

class ChatTurn(BaseModel):
    role: str      # "user" or "assistant"
    content: str


class ChatRequest(BaseModel):
    question: str
    date: Optional[str] = None   # ISO date, defaults to today
    history: Optional[list[ChatTurn]] = None   # optional; the server also remembers recent turns


# ── Conversation memory ───────────────────────────────────────────────────────
# Single-user app, so the server keeps the last few turns itself. Without this every
# question was answered in isolation, and the coach repeated its stats instead of
# responding to what was just said ("you're not understanding me").
import time as _time
_MEMORY: list[dict] = []
_MEMORY_TURNS = 12              # messages kept (6 back-and-forths)
_MEMORY_IDLE_SECONDS = 3 * 3600  # forget the conversation after 3 h of silence
_last_chat = 0.0


def _remember(role: str, content: str) -> None:
    _MEMORY.append({"role": role, "content": content})
    del _MEMORY[:-_MEMORY_TURNS]


class ChatResponse(BaseModel):
    answer: str


# ── Helper — build data context ───────────────────────────────────────────────

def _build_context(db: Session, ref_date: str) -> str:
    today = ref_date or str(local_today())

    # Last 30 days of entries
    start = str(date.fromisoformat(today) - timedelta(days=30))
    entries = (
        db.query(Entry)
        .filter(Entry.date >= start, Entry.date <= today)
        .order_by(Entry.date.desc())
        .all()
    )

    watch = (
        db.query(WatchData)
        .filter(WatchData.date >= start, WatchData.date <= today)
        .order_by(WatchData.date.desc())
        .all()
    )

    if not entries and not watch:
        return "No fitness data has been logged yet."

    lines = ["USER FITNESS DATA (last 30 days):"]
    lines.append(f"Today's date: {today}")
    lines.append(f"Total days logged: {len(entries)}")

    gym_days = sum(1 for e in entries if e.gym_attended)
    lines.append(f"Gym sessions in last 30 days: {gym_days}")

    # Recent entries summary
    lines.append("\nDAILY LOG (most recent first):")
    for e in entries[:14]:  # last 14 days max to keep context concise
        total_cal = (e.cal_breakfast or 0) + (e.cal_lunch or 0) + (e.cal_dinner or 0) + (e.cal_misc or 0)
        parts = [f"Date: {e.date}"]
        parts.append(f"Gym: {'Yes' if e.gym_attended else 'No'}")
        parts.append(f"Calories: {total_cal:.0f} (B:{e.cal_breakfast or 0:.0f} L:{e.cal_lunch or 0:.0f} D:{e.cal_dinner or 0:.0f} Misc:{e.cal_misc or 0:.0f})")
        if e.weight_kg:
            parts.append(f"Weight: {e.weight_kg}kg")
        if e.waist_cm:
            parts.append(f"Waist: {e.waist_cm}cm")
        if e.body_fat_pct is not None:
            parts.append(f"Body fat: {e.body_fat_pct:.1f}% (smart scale)")
        if e.muscle_pct is not None:
            parts.append(f"Skeletal muscle: {e.muscle_pct:.1f}%")
        if e.sleep_hours:
            parts.append(f"Sleep: {e.sleep_hours}hrs")
        if e.water_litres:
            parts.append(f"Water: {e.water_litres}L")
        if e.mood_score:
            mood_map = {1: "Rough", 2: "Meh", 3: "Okay", 4: "Good", 5: "Amazing"}
            parts.append(f"Mood: {mood_map.get(e.mood_score, e.mood_score)}")
        if e.protein_g is not None:
            parts.append(f"Protein: {e.protein_g:.0f}g"
                         + (f" (target {e.protein_target_g:.0f}g)" if e.protein_target_g else ""))
        if e.calorie_target and total_cal > 0:
            diff = e.calorie_target - total_cal
            parts.append(f"Calorie target {e.calorie_target:.0f}: "
                         + (f"{diff:.0f} under" if diff >= 0 else f"{-diff:.0f} OVER"))
        items = _meal_items(e)
        if items:
            parts.append("Foods (photo estimates): " + ", ".join(
                f"{i.get('meal')}: {i.get('name')} {i.get('kcal', 0):.0f}kcal" for i in items[:8]))
        if e.notes:
            parts.append(f"Notes: {e.notes}")
        lines.append(" | ".join(parts))

    # Weight trend
    weights = [(e.date, e.weight_kg) for e in entries if e.weight_kg]
    if len(weights) >= 2:
        oldest_w = weights[-1][1]
        newest_w = weights[0][1]
        change = newest_w - oldest_w
        lines.append(f"\nWEIGHT TREND: {oldest_w}kg → {newest_w}kg (change: {change:+.1f}kg over 30 days)")

    # Waist trend
    waists = [(e.date, e.waist_cm) for e in entries if e.waist_cm]
    if len(waists) >= 2:
        oldest_wt = waists[-1][1]
        newest_wt = waists[0][1]
        change = newest_wt - oldest_wt
        lines.append(f"WAIST TREND: {oldest_wt}cm → {newest_wt}cm (change: {change:+.1f}cm over 30 days)")

    # Calorie average
    cals = [(e.cal_breakfast or 0) + (e.cal_lunch or 0) + (e.cal_dinner or 0) + (e.cal_misc or 0) for e in entries]
    if cals:
        lines.append(f"AVERAGE DAILY CALORIES: {sum(cals)/len(cals):.0f} kcal")

    # Calorie and protein targets (the targets are saved with each day)
    targeted = [(e, c) for e, c in zip(entries, cals) if e.calorie_target and c > 0]
    if targeted:
        under = sum(1 for e, c in targeted if c <= e.calorie_target)
        avg_gap = sum(e.calorie_target - c for e, c in targeted) / len(targeted)
        lines.append(f"CALORIE TARGET: {targeted[0][0].calorie_target:.0f} kcal/day (for weight loss). "
                     f"Under target on {under} of {len(targeted)} logged days; "
                     f"average {abs(avg_gap):.0f} kcal {'under' if avg_gap >= 0 else 'OVER'}.")
    proteins = [e.protein_g for e in entries if e.protein_g is not None]
    if proteins:
        target = next((e.protein_target_g for e in entries if e.protein_target_g), None)
        lines.append(f"AVERAGE DAILY PROTEIN: {sum(proteins)/len(proteins):.0f} g"
                     + (f" (target {target:.0f} g)" if target else ""))

    lines.extend(_body_context(db))
    lines.extend(_workout_context(db, today))
    lines.extend(_watch_context(watch))
    return "\n".join(lines)


def _meal_items(e: Entry) -> list:
    try:
        items = json.loads(e.meal_items or "[]")
        return items if isinstance(items, list) else []
    except ValueError:
        return []


PLAN_DAYS = {1: "Push", 2: "Legs", 3: "Pull", 4: "Glutes & hamstrings", 5: "Full-body circuit"}


def _workout_context(db: Session, today: str) -> list:
    """Recent gym sessions from the Exercise tab: what was done and the weights used."""
    start = str(date.fromisoformat(today) - timedelta(days=21))
    sessions = (
        db.query(WorkoutSession)
        .filter(WorkoutSession.date >= start, WorkoutSession.date <= today)
        .order_by(WorkoutSession.date.desc())
        .limit(8)
        .all()
    )
    lines = ["\nTRAINING PLAN: 5-day rotation, each session 30 min treadmill + 30 min weights: "
             + ", ".join(f"Day {d} {n}" for d, n in PLAN_DAYS.items()) + "."]
    finished = [s for s in sessions if s.finished_at]
    if finished:
        nxt = finished[0].plan_day % 5 + 1
        lines.append(f"Next workout in the rotation: Day {nxt} {PLAN_DAYS.get(nxt, '')}.")
    if not sessions:
        lines.append("No workouts logged in the Exercise tab in the last 3 weeks.")
        return lines

    lines.append("RECENT WORKOUTS (most recent first, top set per exercise):")
    for s in sessions:
        try:
            data = json.loads(s.data)
        except ValueError:
            continue
        parts = [f"{s.date} Day {s.plan_day} {data.get('title') or PLAN_DAYS.get(s.plan_day, '')}"
                 + ("" if s.finished_at else " (unfinished)")]
        tm = data.get("treadmill") or {}
        if tm.get("done"):
            tm_bits = [f"{tm['minutes']:.0f} min" if tm.get("minutes") else "done",
                       f"{tm['speed_kmh']} km/h" if tm.get("speed_kmh") else None,
                       f"{tm['incline_pct']}% incline" if tm.get("incline_pct") else None]
            parts.append("treadmill " + " ".join(b for b in tm_bits if b))
        for ex in data.get("exercises") or []:
            sets = [st for st in ex.get("sets") or [] if st.get("reps") or st.get("weight_kg")]
            if not sets:
                continue
            top = max(sets, key=lambda st: (st.get("weight_kg") or 0, st.get("reps") or 0))
            w = f"{top['weight_kg']:g}kg x " if top.get("weight_kg") else ""
            parts.append(f"{ex.get('name')}: {w}{top.get('reps') or '?'} ({len(sets)} sets)"
                         + (f" [note: {ex['notes'][:60]}]" if ex.get("notes") else ""))
        lines.append(" | ".join(parts))
    return lines


def _body_context(db: Session) -> list:
    """Profile, goal progress + latest smart-scale body composition (any date).
    Profile values come from .env; anything not set is left out."""
    profile = [p for p in (
        SEX or None,
        f"height {HEIGHT_CM:.0f}cm" if HEIGHT_CM else None,
        f"born {BIRTH_DATE}" if BIRTH_DATE else None,
        f"target weight {TARGET_WEIGHT_KG:.0f}kg" if TARGET_WEIGHT_KG else None,
    ) if p]
    lines = [f"\nPROFILE: {', '.join(profile)}"] if profile else ["\n"]

    first = db.query(Entry).filter(Entry.weight_kg.isnot(None)).order_by(Entry.date.asc()).first()
    last = db.query(Entry).filter(Entry.weight_kg.isnot(None)).order_by(Entry.date.desc()).first()
    if last:
        progress = f"WEIGHT: started {first.weight_kg}kg on {first.date}, now {last.weight_kg}kg on {last.date}"
        if TARGET_WEIGHT_KG:
            to_go = last.weight_kg - TARGET_WEIGHT_KG
            progress += f", {to_go:.1f}kg still to lose" if to_go > 0 else ", goal reached"
        if HEIGHT_CM:
            progress += f". BMI {last.weight_kg / (HEIGHT_CM / 100) ** 2:.1f}"
        lines.append(progress)

    comp = db.query(Entry).filter(Entry.body_fat_pct.isnot(None), Entry.weight_kg.isnot(None)).order_by(Entry.date.desc()).first()
    if comp:
        fat_kg = comp.weight_kg * comp.body_fat_pct / 100
        lines.append(
            f"LATEST BODY COMPOSITION ({comp.date}, smart scale estimate): body fat {comp.body_fat_pct:.1f}% "
            f"= {fat_kg:.1f}kg fat, {comp.weight_kg - fat_kg:.1f}kg lean mass"
            + (f", skeletal muscle {comp.muscle_pct:.1f}%" if comp.muscle_pct is not None else "")
            + (f", water {comp.water_pct:.1f}%" if comp.water_pct is not None else "")
        )

    waist = db.query(Entry).filter(Entry.waist_cm.isnot(None)).order_by(Entry.date.desc()).first()
    if waist and HEIGHT_CM:
        whtr = waist.waist_cm / HEIGHT_CM
        label = "healthy" if whtr < 0.5 else "increased risk" if whtr < 0.6 else "high risk"
        lines.append(f"WAIST-TO-HEIGHT RATIO: {whtr:.2f} ({label}; aim below 0.50)")
    return lines


def _watch_context(watch: list) -> list:
    """Galaxy Watch data (Samsung Health via Health Connect), most recent first."""
    if not watch:
        return []

    lines = ["\nGALAXY WATCH DATA (automatic, most recent first):"]
    for w in watch[:14]:
        parts = [f"Date: {w.date}"]
        if w.steps is not None:
            parts.append(f"Steps: {w.steps}")
        if w.distance_km is not None:
            parts.append(f"Distance: {w.distance_km:.1f}km")
        if w.active_calories is not None:
            parts.append(f"Active calories burned: {w.active_calories:.0f}")
        if w.sleep_minutes is not None:
            parts.append(f"Sleep (night ending this day): {w.sleep_minutes // 60}h{w.sleep_minutes % 60:02d}m")
        if w.resting_hr is not None:
            parts.append(f"Resting HR: {w.resting_hr}bpm")
        if w.avg_hr is not None:
            parts.append(f"Avg HR: {w.avg_hr}bpm")
        try:
            sessions = json.loads(w.exercises or "[]")
        except ValueError:
            sessions = []
        if sessions:
            parts.append("Workouts: " + ", ".join(
                f"{s.get('title') or s.get('type')} {s.get('minutes')}min at {s.get('start')}" for s in sessions))
        lines.append(" | ".join(parts))

    def _avg(values):
        values = [v for v in values if v is not None]
        return sum(values) / len(values) if values else None

    steps = _avg([w.steps for w in watch])
    sleep = _avg([w.sleep_minutes for w in watch])
    rhr = _avg([w.resting_hr for w in watch])
    if steps is not None:
        lines.append(f"AVERAGE DAILY STEPS: {steps:.0f}")
    if sleep is not None:
        lines.append(f"AVERAGE SLEEP: {sleep / 60:.1f} hours")
    if rhr is not None:
        lines.append(f"AVERAGE RESTING HEART RATE: {rhr:.0f} bpm")
    return lines


# ── Endpoint ──────────────────────────────────────────────────────────────────

@router.post("/chat", response_model=ChatResponse)
def chat(request: ChatRequest, db: Session = Depends(get_db)):
    global _active_model
    if not request.question.strip():
        raise HTTPException(status_code=400, detail="Question cannot be empty")

    context = _build_context(db, request.date or str(local_today()))

    system_prompt = """You are Coach, {name}'s personal trainer and nutrition coach inside the GymTracker app.
Think of yourself as a supportive friend who happens to be a great PT: warm, encouraging,
human, a little witty, and genuinely on {name}'s side. You care about how {name} feels,
not just the numbers.

Read the conversation first, then decide what kind of reply is needed:
- If {name} is sharing feelings, frustration or pushback ("you don't understand me",
  "I'm struggling", "I'm tired"), respond to the feeling first. Acknowledge it in your
  own words, agree where they have a point, and do NOT re-list their stats. Keep it short
  and kind, then offer one small, easy next step, or ask what would help.
- If they ask about their data or progress, answer with their real numbers.
- Never repeat an analysis you already gave earlier in the conversation.

Coaching style:
- Building a habit takes time, and starting is the hardest part. Treat any showing up
  as a real win and say so specifically ("you went twice this month, that's the habit
  starting").
- Prefer tiny, realistic steps that stack on routines {name} already has ("after you get
  home, put your gym bag by the door") over big targets. One change at a time.
- Frame progress around consistency and identity ("becoming someone who trains"), not
  perfection. A missed day is normal; the goal is never to miss twice.
- Be honest about what's off track, but gently, and always pair it with encouragement.

You can see {name}'s real data below: daily logs (calories by meal, weight, waist, gym
attendance, mood, notes), smart-scale body composition, goal progress, and Galaxy Watch
data (steps, distance, active calories, sleep, heart rate, workouts). Dates are local time.

How to answer:
- For data questions, lead with the direct answer, backed by {name}'s actual numbers and dates. Compare with
  earlier periods and connect the dots when it's useful (e.g. short sleep before skipped
  gym days, calorie averages against the weight trend, steps on rest days).
- Finish with one or two specific, doable next steps ("add a 10-minute walk after
  dinner"), never vague advice ("move more"). For emotional messages, one step at most.
- Match the length to the question: quick facts in a sentence or two; "how am I going",
  plans or analysis can run to about 200 words.
- Vary your openings and wording. Don't start with "Great question" or repeat the question.
- If data is missing, say exactly what's missing and how to log it in the app.
- Scale body-composition numbers are estimates: talk about trends, not single readings.
- You're not a doctor. For anything medical (pain, dizziness, very low intake under about
  1,200 kcal/day, or sustained loss faster than about 1 kg a week) suggest seeing a GP.

Formatting: plain text only, because the phone app doesn't render markdown. Use short
paragraphs; simple "- " bullet lines are fine. No **bold**, headings or tables.""".replace(
        "{name}", USER_NAME or "the user")

    user_message = f"""{context}

USER QUESTION: {request.question}"""

    if not GROQ_API_KEY:
        raise HTTPException(
            status_code=503,
            detail="GROQ_API_KEY is not set. Add it to /opt/backend/.env and recreate the container.",
        )

    # Conversation so far: what the app sent, or what the server remembers
    global _last_chat
    if _last_chat and _time.time() - _last_chat > _MEMORY_IDLE_SECONDS:
        _MEMORY.clear()
    if request.history:
        past = [{"role": t.role, "content": t.content} for t in request.history
                if t.role in ("user", "assistant")][-_MEMORY_TURNS:]
    else:
        past = list(_MEMORY)

    messages = [{"role": "system", "content": system_prompt}, *past,
                {"role": "user", "content": user_message}]

    try:
        with httpx.Client(timeout=30.0) as client:
            model = _active_model or GROQ_MODEL
            response = _complete(client, model, messages)

            # Model retired or not enabled for this key → switch to one it can use
            if response.status_code == 404 and "model_not_found" in response.text:
                fallback = _pick_available_model(client, exclude=model)
                if fallback:
                    response = _complete(client, fallback, messages)
                    if response.status_code == 200:
                        _active_model = fallback

        if response.status_code != 200:
            raise HTTPException(
                status_code=502,
                detail=f"Groq API error {response.status_code}: {response.text}"
            )

        data = response.json()
        answer = _strip_thinking(data["choices"][0]["message"].get("content") or "")
        if not answer:
            answer = "Sorry, I couldn't come up with an answer to that — try asking again."
        _remember("user", request.question)       # store the question, not the bulky data context
        _remember("assistant", answer)
        _last_chat = _time.time()
        return ChatResponse(answer=answer)

    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Groq API timed out")
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Network error reaching Groq: {str(e)}")


# ── Groq model handling ───────────────────────────────────────────────────────

# Best first. Used only when the configured model is rejected.
_FALLBACK_MODELS = [
    "openai/gpt-oss-120b",
    "llama-3.3-70b-versatile",
    "openai/gpt-oss-20b",
    "llama-3.1-8b-instant",
]
_active_model: Optional[str] = None   # remembered after a successful fallback


def _strip_thinking(text: str) -> str:
    """Remove any <think>…</think> reasoning a model includes in its reply."""
    text = re.sub(r"<think>.*?</think>", "", text, flags=re.S)
    if "<think>" in text:            # cut off mid-thought: keep only what came before
        text = text.split("<think>")[0]
    return text.strip()


def _complete(client: httpx.Client, model: str, messages: list) -> httpx.Response:
    body = {
        "model": model,
        "messages": messages,
        "temperature": 0.7,
        "max_tokens": 512,
    }
    if model.startswith("openai/gpt-oss"):
        # Reasoning model: a little thinking improves answers; the budget covers
        # reasoning plus a ~200-word reply
        body["reasoning_effort"] = "medium"
        body["max_tokens"] = 2048
    elif model.startswith("qwen/"):
        # Qwen can think out loud before answering; leave room so the reply
        # isn't cut off (the thinking is stripped before it reaches the app)
        body["max_tokens"] = 1500
    return client.post(
        GROQ_API_URL,
        headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
        json=body,
    )


def _pick_available_model(client: httpx.Client, exclude: str) -> Optional[str]:
    """Best model from _FALLBACK_MODELS that this API key can use."""
    res = client.get(
        "https://api.groq.com/openai/v1/models",
        headers={"Authorization": f"Bearer {GROQ_API_KEY}"},
    )
    if res.status_code != 200:
        return None
    available = {m.get("id") for m in res.json().get("data", [])}
    for model in _FALLBACK_MODELS:
        if model != exclude and model in available:
            return model
    return None


@router.delete("/chat")
def reset_chat():
    """Forget the conversation (call this when the app's chat is cleared)."""
    _MEMORY.clear()
    return {"status": "cleared"}


@router.get("/model")
def current_model():
    """Which Groq model the coach is using (handy for troubleshooting)."""
    return {"configured": GROQ_MODEL, "active": _active_model or GROQ_MODEL}
