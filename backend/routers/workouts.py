from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy import func
from typing import List, Optional
from pydantic import BaseModel, Field
import json

from database import get_db
from models import WorkoutSession

router = APIRouter(prefix="/workouts", tags=["workouts"])


class WorkoutIn(BaseModel):
    id:          str = Field(..., pattern=r"^\d{4}-\d{2}-\d{2}-d\d$")
    date:        str = Field(..., pattern=r"^\d{4}-\d{2}-\d{2}$")
    plan_day:    int = Field(..., ge=1, le=9)
    started_at:  Optional[str] = None
    finished_at: Optional[str] = None
    data:        str            # JSON from the app


class WorkoutOut(WorkoutIn):
    created_at: str
    updated_at: str


@router.post("/", response_model=WorkoutOut, status_code=201)
def upsert_workout(payload: WorkoutIn, db: Session = Depends(get_db)):
    """Create or replace a session (the app re-sends it after every edit)."""
    try:
        json.loads(payload.data)
    except ValueError:
        raise HTTPException(status_code=422, detail="data must be valid JSON")

    row = db.get(WorkoutSession, payload.id)
    if row:
        for field, value in payload.model_dump().items():
            setattr(row, field, value)
        row.updated_at = str(func.now())
    else:
        row = WorkoutSession(**payload.model_dump())
        db.add(row)
    db.commit()
    db.refresh(row)
    return _out(row)


@router.get("/", response_model=List[WorkoutOut])
def list_workouts(
    start: Optional[str] = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
    end:   Optional[str] = Query(default=None, pattern=r"^\d{4}-\d{2}-\d{2}$"),
    db:    Session = Depends(get_db),
):
    query = db.query(WorkoutSession)
    if start:
        query = query.filter(WorkoutSession.date >= start)
    if end:
        query = query.filter(WorkoutSession.date <= end)
    return [_out(r) for r in query.order_by(WorkoutSession.date.asc(), WorkoutSession.plan_day.asc()).all()]


def _out(row: WorkoutSession) -> dict:
    return {c.name: getattr(row, c.name) for c in row.__table__.columns}
