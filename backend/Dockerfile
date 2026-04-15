FROM python:3.12-slim

WORKDIR /app

# Disable Python output buffering so all logs appear in Railway immediately
ENV PYTHONUNBUFFERED=1

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN chmod +x start.sh

CMD ["./start.sh"]
