# Deploying GymTracker Backend on Proxmox

## Option A — Docker inside an LXC container (Recommended)

### 1. Create the LXC container

In Proxmox UI:
- Download Ubuntu 22.04 template (if not already present)
- Create LXC:
  - Memory: 512 MB (256 MB is fine too)
  - Disk: 4 GB
  - CPU: 1 core
  - Network: bridge to your LAN (e.g. `vmbr0`)
  - **Enable Nesting** in Options → Features (required for Docker)

### 2. Install Docker inside the LXC

```bash
# Update and install Docker
apt update && apt upgrade -y
apt install -y docker.io docker-compose curl

# Start Docker
systemctl enable docker
systemctl start docker

# Verify
docker --version
```

### 3. Deploy GymTracker

```bash
# Create a directory for the app
mkdir -p /opt/gymtracker
cd /opt/gymtracker

# Copy your backend folder contents here
# (use scp, sftp, or mount a share)
# scp -r /path/to/backend/* root@<proxmox-ip>:/opt/gymtracker/

# Build the Docker image
docker build -t gymtracker-api .

# Run with persistent database storage
docker run -d \
  --name gymtracker \
  --restart unless-stopped \
  -p 8000:8000 \
  -v /opt/gymtracker/data:/data \
  gymtracker-api
```

### 4. Verify it's running

```bash
# Check logs
docker logs gymtracker

# Test the health endpoint
curl http://localhost:8000/health
# Should return: {"status":"ok","service":"GymTracker API"}

# View auto-generated API docs
# Open in browser: http://<proxmox-ip>:8000/docs
```

### 5. Find your Proxmox host IP

```bash
ip addr show | grep 'inet ' | grep -v '127.0.0.1'
```

Note this IP — you'll enter it in the app settings (e.g. `http://10.0.0.50:8000`).

---

## Option B — Run directly with Python (no Docker)

```bash
apt update && apt install -y python3-pip python3-venv

mkdir -p /opt/gymtracker
cd /opt/gymtracker

# Copy backend files here
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Run
uvicorn main:app --host 0.0.0.0 --port 8000 --reload &
```

To auto-start on boot, create `/etc/systemd/system/gymtracker.service`:

```ini
[Unit]
Description=GymTracker API
After=network.target

[Service]
WorkingDirectory=/opt/gymtracker
ExecStart=/opt/gymtracker/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
User=root

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable gymtracker
systemctl start gymtracker
```

---

## Updating the backend

```bash
# With Docker:
cd /opt/gymtracker
docker stop gymtracker && docker rm gymtracker
docker build -t gymtracker-api .
docker run -d --name gymtracker --restart unless-stopped \
  -p 8000:8000 -v /opt/gymtracker/data:/data gymtracker-api

# Without Docker:
cd /opt/gymtracker
git pull  # or copy new files
systemctl restart gymtracker
```

---

## Firewall / Access

By default the container is on your LAN — no internet exposure needed. If you want to access it from outside your home network, consider a WireGuard VPN rather than exposing port 8000 directly.

```bash
# Allow port 8000 through UFW (if enabled)
ufw allow 8000/tcp
```

---

## Database backup

The SQLite database is stored at `/opt/gymtracker/data/gymtracker.db`.

```bash
# Simple backup script
#!/bin/bash
cp /opt/gymtracker/data/gymtracker.db \
   /opt/gymtracker/data/backups/gymtracker_$(date +%Y%m%d).db
```

Add to cron for daily backups:
```
0 2 * * * /opt/gymtracker/backup.sh
```
