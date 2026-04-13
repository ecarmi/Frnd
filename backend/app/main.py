from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .database import engine, Base
from .routers import auth, users, events, feed, plans, feedback, groups, activities, carpools


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create all tables on startup (use Alembic for production migrations)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
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
