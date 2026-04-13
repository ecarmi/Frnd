# Frnd Backend

FastAPI + PostgreSQL + Redis backend for the Frnd app.

## Setup

### 1. Install dependencies

```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Configure environment

```bash
cp .env.example .env
# Edit .env with your database URL, Redis URL, and Twilio credentials
```

### 3. Start PostgreSQL and Redis

```bash
# Using Docker:
docker run -d --name frnd-postgres -e POSTGRES_USER=frnd -e POSTGRES_PASSWORD=password -e POSTGRES_DB=frnd_db -p 5432:5432 postgres:16
docker run -d --name frnd-redis -p 6379:6379 redis:7

# Or via Homebrew:
brew services start postgresql@16
brew services start redis
```

### 4. Run the server

```bash
uvicorn app.main:app --reload --port 8000
```

Tables are auto-created on first startup. For production, use Alembic migrations.

## API Docs

Visit `http://localhost:8000/docs` for the interactive Swagger UI.

## Key Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/auth/otp/request` | Request OTP (SMS in prod, console in dev) |
| POST | `/auth/otp/verify` | Verify OTP → returns JWT token |
| GET | `/feed` | Ranked personalized event feed |
| GET | `/events/search` | Full-text event search |
| GET | `/events/map` | Events in a bounding box |
| POST | `/events/{id}/rsvp` | RSVP to event |
| POST | `/events/{id}/save` | Save event |
| GET | `/plans` | User's plans |
| POST | `/plans` | Create a plan |
| WS | `/plans/{id}/stream` | Real-time plan chat |
| POST | `/users/me/onboarding` | Complete onboarding with vibe tags |

## Development OTP

In `ENVIRONMENT=development`, OTP codes are printed to the console instead of sent via SMS. No Twilio setup needed for local dev.
