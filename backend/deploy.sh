#!/bin/bash
# Build and (re)start the GymTracker API in Docker. Run inside the LXC, from this folder.
# The SQLite database lives in /opt/backend/data on the host, so rebuilds never touch your data.
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] || { echo "Create .env first (cp .env.example .env) and set GROQ_API_KEY"; exit 1; }
mkdir -p /opt/backend/data
docker build -t gymtracker-backend .
docker rm -f gymtracker 2>/dev/null || true
docker run -d --name gymtracker --restart unless-stopped -p 8000:8000 \
  --env-file .env -v /opt/backend/data:/data gymtracker-backend
sleep 3; curl -fsS http://localhost:8000/health && echo
