from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os

from app.database import Base, engine, SessionLocal
from app.routers import expenses, categories
from app import crud


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: create tables and seed default categories
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    try:
        crud.seed_default_categories(db)
    finally:
        db.close()
    yield
    # Shutdown: nothing to clean up


app = FastAPI(
    title="Expense Tracker API",
    description="Track your personal expenses",
    version="1.0.1",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(expenses.router)
app.include_router(categories.router)


@app.get("/health", tags=["health"])
def health():
    return {"status": "ok"}


# Mount frontend LAST so API routes above always take priority.
# html=True makes StaticFiles serve index.html for "/" automatically,
# and all relative paths (css/style.css, js/app.js) resolve correctly.
frontend_path = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "..", "frontend")
)
if os.path.exists(frontend_path):
    app.mount("/", StaticFiles(directory=frontend_path, html=True), name="frontend")
