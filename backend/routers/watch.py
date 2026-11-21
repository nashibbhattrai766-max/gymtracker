from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List, Optional

from database import get_db
from models import WatchData
from schemas import WatchDataCreate, WatchDataResponse

router = APIRouter(prefix="/watch", tags=["watch"])


# ── Create / Update (upsert) ──────────────────────────────────────────────────

@router.post("/", response_model=WatchDataResponse, status_code=201)
def upsert_watch_data(payload: WatchDataCreate, db: Session = Depends(get_db)):
    """Create or replace the watch data for a date (re-syncing a day is safe)."""
    existing = db.query(WatchData).filter(WatchData.date == payload.date).first()

    if existing:
        for field, value in payload.model_dump().items():
            setattr(existing, field, value)
        existing.updated_at = str(func.now())
        row = existing
    else:
        row = WatchData(**payload.model_dump())
        db.add(row)

    db.commit()
    db.refresh(row)
    return _to_response(row)


# ── Read single day ───────────────────────────────────────────────────────────

@router.get("/{watch_date}", response_model=WatchDataResponse)
def get_watch_data(watch_date: str, db: Session = Depends(get_db)):
    row = db.query(WatchData).filter(WatchData.date == watch_date).first()
    if not row:
        raise HTTPException(status_code=404, detail=f"No watch data for {watch_date}")
    return _to_response(row)


# ── Read range ────────────────────────────────────────────────────────────────

@router.get("/", response_model=List[WatchDataResponse])
def list_watch_data(
    start: Optional[str] = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
    end:   Optional[str] = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
    db:    Session = Depends(get_db),
):
    query = db.query(WatchData)
    if start:
        query = query.filter(WatchData.date >= start)
    if end:
        query = query.filter(WatchData.date <= end)
    return [_to_response(r) for r in query.order_by(WatchData.date.asc()).all()]


# ── Helper ────────────────────────────────────────────────────────────────────

def _to_response(row: WatchData) -> dict:
    return {c.name: getattr(row, c.name) for c in row.__table__.columns}
