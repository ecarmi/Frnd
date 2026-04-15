import logging
import traceback
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from .database import engine
from .routers import auth, users, events, feed, plans, feedback, groups, activities, carpools

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting Frnd API")
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        logger.info("Database connectivity check passed")
    except Exception:
        logger.exception("Database connectivity check failed during startup")
    yield


app = FastAPI(
    title="Frnd API",
    description="Backend for Frnd — hyperlocal event discovery and social planning",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    tb = traceback.format_exc()
    logger.error("Unhandled exception on %s %s:\n%s", request.method, request.url.path, tb)
    return JSONResponse(status_code=500, content={"detail": f"{type(exc).__name__}: {exc}"})

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(events.router)
app.include_router(feed.router)
app.include_router(plans.router)
app.include_router(feedback.router)
app.include_router(groups.router)
app.include_router(activities.router)
app.include_router(carpools.router)


@app.get("/health")
async def health():
    return {"status": "ok", "app": "Frnd API"}
