FROM python:3.12-slim

WORKDIR /app

ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["/bin/sh", "-c", "echo '=== FRND API STARTING ===' && echo 'DB URL prefix:' ${DATABASE_URL:0:20} && uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000} --log-level debug"]
