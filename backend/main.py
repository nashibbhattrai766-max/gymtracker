from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pathlib import Path

from database import Base, engine, migrate
from routers import entries, analytics, ai, watch, workouts, food
import config

# Create all tables on startup
Base.metadata.create_all(bind=engine)
migrate()  # add new columns to existing tables

app = FastAPI(
    title="GymTracker API",
    description="Personal fitness & nutrition tracking backend",
    version="1.0.0",
)

# Allow all origins — fine for a private home LAN deployment
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(entries.router)
app.include_router(analytics.router)
app.include_router(ai.router)
app.include_router(watch.router)
app.include_router(workouts.router)
app.include_router(food.router)


@app.get("/health", tags=["system"])
def health_check():
    return {"status": "ok", "service": "GymTracker API"}


@app.get("/profile", tags=["system"])
def profile():
    """Height, goal etc. for the web dashboard (the phone app has its own copy)."""
    return {
        "name": config.USER_NAME or None,
        "height_cm": config.HEIGHT_CM,
        "target_weight_kg": config.TARGET_WEIGHT_KG,
        "birth_date": config.BIRTH_DATE or None,
        "sex": config.SEX or None,
    }


@app.get("/dashboard", include_in_schema=False)
def dashboard():
    """Web reporting dashboard (same data as the app, bigger screen)."""
    return FileResponse(Path(__file__).parent / "static" / "dashboard.html")


@app.get("/", tags=["system"])
def root():
    return {
        "message": "GymTracker API is running 💪",
        "dashboard": "/dashboard",
        "docs": "/docs",
        "health": "/health",
    }
