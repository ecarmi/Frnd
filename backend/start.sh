#!/bin/sh
# Run migrations with a 30-second timeout so a hung DB connection
# doesn't prevent uvicorn from starting.
echo "==> Running migrations..."
python -c "
import subprocess, sys
try:
    r = subprocess.run(['alembic', 'upgrade', 'head'], timeout=30)
    sys.exit(r.returncode)
except subprocess.TimeoutExpired:
    print('WARNING: migration timed out (DB unreachable?), starting server anyway', flush=True)
except Exception as e:
    print(f'WARNING: migration error: {e}, starting server anyway', flush=True)
"

echo "==> Starting uvicorn..."
exec uvicorn app.main:app \
    --host 0.0.0.0 \
    --port "${PORT:-8000}" \
    --log-level info
