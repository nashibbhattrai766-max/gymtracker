"""Food photo → estimated foods, portions, calories and protein (Groq vision)."""
import base64
import json
import re
from typing import List, Optional

import httpx
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from config import GROQ_API_KEY, GROQ_VISION_MODEL

router = APIRouter(prefix="/ai", tags=["ai"])

GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions"
MAX_IMAGE_BYTES = 4 * 1024 * 1024  # Groq's limit for base64 images; the app sends ~300 KB

PROMPT = """You are a nutrition expert estimating a meal from a photo for a calorie-tracking app.

Identify each distinct food or drink you can see. For each, estimate the portion
(use visual cues: plate ~26 cm, fork, hand, packaging), then the calories (kcal) and
protein (grams). Include cooking oil, sauces and dressings you can see, since they're easy to
miss. If something is uncertain, give your best realistic estimate rather than leaving it
out. Use common Australian portions and products.

Reply with JSON only, in exactly this shape:
{"items": [{"name": "Grilled chicken breast", "portion": "~150 g", "kcal": 248, "protein_g": 46}],
 "confidence": "low|medium|high",
 "note": "one short sentence on what was hard to judge, or empty"}

If the photo is not food, reply {"items": [], "confidence": "low", "note": "No food found in the photo."}"""


class FoodPhotoRequest(BaseModel):
    image_base64: str
    mime_type: str = Field(default="image/jpeg", pattern=r"^image/(jpeg|png|webp)$")
    meal: Optional[str] = None      # breakfast / lunch / dinner / misc (context only)
    hint: Optional[str] = None      # optional user note, e.g. "large bowl"


class FoodItem(BaseModel):
    name: str
    portion: str = ""
    kcal: float
    protein_g: float


class FoodPhotoResponse(BaseModel):
    items: List[FoodItem]
    total_kcal: float
    total_protein_g: float
    confidence: str
    note: str
    model: str


@router.post("/food-photo", response_model=FoodPhotoResponse)
def food_photo(req: FoodPhotoRequest):
    if not GROQ_API_KEY:
        raise HTTPException(status_code=503, detail="GROQ_API_KEY is not set on the server.")
    try:
        raw = base64.b64decode(req.image_base64, validate=True)
    except ValueError:
        raise HTTPException(status_code=422, detail="image_base64 is not valid base64")
    if len(raw) > MAX_IMAGE_BYTES:
        raise HTTPException(status_code=413, detail="Photo too large (max 4 MB)")

    text = PROMPT
    if req.meal:
        text += f"\n\nThis is the user's {req.meal}."
    if req.hint:
        text += f"\nUser note: {req.hint[:200]}"

    body = {
        "model": GROQ_VISION_MODEL,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": text},
                {"type": "image_url",
                 "image_url": {"url": f"data:{req.mime_type};base64,{req.image_base64}"}},
            ],
        }],
        "temperature": 0.2,
        "max_tokens": 1500,
        "response_format": {"type": "json_object"},
    }
    try:
        with httpx.Client(timeout=60.0) as client:
            res = client.post(
                GROQ_API_URL,
                headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
                json=body,
            )
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Groq timed out analysing the photo")
    except httpx.RequestError as e:
        raise HTTPException(status_code=502, detail=f"Network error reaching Groq: {e}")

    if res.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Groq API error {res.status_code}: {res.text}")

    content = res.json()["choices"][0]["message"].get("content") or ""
    parsed = _parse_json(content)
    if parsed is None:
        raise HTTPException(status_code=502, detail="Couldn't read the estimate from the AI. Try another photo.")

    items = []
    for it in parsed.get("items") or []:
        try:
            name = str(it.get("name") or "Food").strip()[:80]
            kcal = max(0.0, min(5000.0, float(it.get("kcal") or 0)))
            protein = max(0.0, min(300.0, float(it.get("protein_g") or 0)))
        except (TypeError, ValueError, AttributeError):
            continue
        items.append(FoodItem(name=name, portion=str(it.get("portion") or "")[:40],
                              kcal=round(kcal), protein_g=round(protein, 1)))

    confidence = str(parsed.get("confidence") or "medium").lower()
    return FoodPhotoResponse(
        items=items,
        total_kcal=sum(i.kcal for i in items),
        total_protein_g=round(sum(i.protein_g for i in items), 1),
        confidence=confidence if confidence in ("low", "medium", "high") else "medium",
        note=str(parsed.get("note") or "")[:300],
        model=GROQ_VISION_MODEL,
    )


def _parse_json(content: str) -> Optional[dict]:
    """The reply should be pure JSON, but tolerate reasoning tags or code fences."""
    content = re.sub(r"<think>.*?</think>", "", content, flags=re.S).strip()
    for candidate in (content, *re.findall(r"\{.*\}", content, flags=re.S)):
        try:
            value = json.loads(candidate)
            if isinstance(value, dict):
                return value
        except ValueError:
            continue
    return None
