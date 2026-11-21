import os

from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker, DeclarativeBase

# Must match the Dockerfile ENV and the docker run mount (-v /opt/backend/data:/data)
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:////data/gymtracker.db")

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},
)

# Enable WAL mode for better concurrent read performance
@event.listens_for(engine, "connect")
def set_sqlite_pragma(dbapi_connection, connection_record):
    cursor = dbapi_connection.cursor()
    cursor.execute("PRAGMA journal_mode=WAL")
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


# ── Lightweight migrations ───────────────────────────────────────────────────
# create_all() only creates missing tables; it never adds columns to an existing
# one. New nullable columns are listed here and added on startup if missing.

_NEW_COLUMNS = {
    "entries": {
        "body_fat_pct":  "FLOAT",
        "water_pct":     "FLOAT",
        "muscle_pct":    "FLOAT",
        "bone_kg":       "FLOAT",
        "bmr_kcal":      "FLOAT",
        "impedance_ohm": "INTEGER",
        "protein_g":        "FLOAT",
        "calorie_target":   "FLOAT",
        "protein_target_g": "FLOAT",
        "meal_items":       "TEXT",
    },
}


def migrate():
    with engine.begin() as conn:
        for table, columns in _NEW_COLUMNS.items():
            existing = {row[1] for row in conn.exec_driver_sql(f"PRAGMA table_info({table})")}
            for name, sql_type in columns.items():
                if name not in existing:
                    conn.exec_driver_sql(f"ALTER TABLE {table} ADD COLUMN {name} {sql_type}")
