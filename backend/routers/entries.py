from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List, Optional
from datetime import date, timedelta

from database import get_db
from models import Entry
from schemas import EntryCreate, EntryResponse

router = APIRouter(prefix="/entries", tags=["entries"])


# ── Create / Update (upsert) ──────────────────────────────────────────────────

@router.post("/", response_model=EntryResponse, status_code=201)
def upsert_entry(payload: EntryCreate, db: Session = Depends(get_db)):
    """Create a new entry or update an existing one for the same date."""
    existing = db.query(Entry).filter(Entry.date == payload.date).first()

    if existing:
        for field, value in payload.model_dump().items():
            setattr(existing, field, value)
        existing.updated_at = str(func.now())
        db.commit()
        db.refresh(existing)
        entry = existing
    else:
        entry = Entry(**payload.model_dump())
        db.add(entry)
        db.commit()
        db.refresh(entry)

    return _to_response(entry)


# ── Read single entry ─────────────────────────────────────────────────────────

@router.get("/{entry_date}", response_model=EntryResponse)
def get_entry(entry_date: str, db: Session = Depends(get_db)):
    entry = db.query(Entry).filter(Entry.date == entry_date).first()
    if not entry:
        raise HTTPException(status_code=404, detail=f"No entry found for {entry_date}")
    return _to_response(entry)


# ── Read range ────────────────────────────────────────────────────────────────

@router.get("/", response_model=List[EntryResponse])
def get_entries(
    start: Optional[str] = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
    end:   Optional[str] = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
    db:    Session = Depends(get_db),
):
    query = db.query(Entry)
    if start:
        query = query.filter(Entry.date >= start)
    if end:
        query = query.filter(Entry.date <= end)
    entries = query.order_by(Entry.date.asc()).all()
    return [_to_response(e) for e in entries]


# ── Delete ────────────────────────────────────────────────────────────────────

@router.delete("/{entry_date}", status_code=204)
def delete_entry(entry_date: str, db: Session = Depends(get_db)):
    entry = db.query(Entry).filter(Entry.date == entry_date).first()
    if not entry:
        raise HTTPException(status_code=404, detail=f"No entry found for {entry_date}")
    db.delete(entry)
    db.commit()


# ── Helper ────────────────────────────────────────────────────────────────────

def _to_response(entry: Entry) -> dict:
    data = {c.name: getattr(entry, c.name) for c in entry.__table__.columns}
    data["total_calories"] = entry.total_calories
    return data
