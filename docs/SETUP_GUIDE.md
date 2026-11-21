# GymTracker — Complete Setup Guide
### From zero to running app on your phone

---

> **Reading order:** Do these parts in order. Part 1 and 2 happen on your
> Proxmox server. Part 3 happens on your Windows PC.

---

# PART 1 — Create the Proxmox LXC Container

## What you need before starting
- Proxmox VE installed and accessible in your browser (e.g. `https://10.0.0.10:8006`)
- Your Proxmox login credentials
- Internet connection on the Proxmox host

---

## Step 1 — Download the Ubuntu 22.04 template

1. Open Proxmox in your browser and log in
2. In the left panel, click your **node name** (e.g. `pve`)
3. Click on **local** (or whichever storage shows "Content")
4. Click the **CT Templates** button at the top
5. Click **Templates**
6. In the search box type `ubuntu-22`
7. Click **ubuntu-22.04-standard** and then click **Download**
8. Wait for the download to finish (you'll see a progress log — wait for `TASK OK`)

---

## Step 2 — Create the LXC container

1. Click the **Create CT** button in the top-right of Proxmox
2. Fill in each tab as follows:

### General tab
| Field | Value |
|-------|-------|
| CT ID | `100` (or any number you like) |
| Hostname | `gymtracker` |
| Password | Choose a strong root password — **write it down** |
| Confirm password | Same as above |

Click **Next**

### Template tab
| Field | Value |
|-------|-------|
| Storage | `local` |
| Template | `ubuntu-22.04-standard` (the one you just downloaded) |

Click **Next**

### Disks tab
| Field | Value |
|-------|-------|
| Storage | `local-lvm` |
| Disk size | `8` GB |

Click **Next**

### CPU tab
| Field | Value |
|-------|-------|
| Cores | `1` |

Click **Next**

### Memory tab
| Field | Value |
|-------|-------|
| Memory | `512` MB |
| Swap | `512` MB |

Click **Next**

### Network tab
| Field | Value |
|-------|-------|
| Bridge | `vmbr0` |
| IPv4 | `DHCP` |

> DHCP means the router assigns an IP automatically. You'll find out what it is in Step 4.

Click **Next**

### DNS tab
Leave as default. Click **Next**

### Confirm tab
- Review the settings
- **Do NOT tick "Start after created" yet**
- Click **Finish**
- Wait for `TASK OK` in the log

---

## Step 3 — Enable Nesting (required for Docker)

1. In the left panel, find your new container `100 (gymtracker)` and click it
2. Click **Options** in the menu
3. Double-click **Features**
4. Tick the checkbox next to **Nesting**
5. Click **OK**

> ⚠️ This step is essential. Docker will not work inside LXC without nesting enabled.

---

## Step 4 — Start the container and find its IP

1. Click **Start** (the green play button at the top)
2. Wait 5–10 seconds
3. Click **Console** in the menu
4. You'll see a login prompt. Log in:
   - Login: `root`
   - Password: the password you set in Step 2
5. Once logged in, run this command to find the container's IP:
   ```
   ip addr show eth0 | grep 'inet '
   ```
   You'll see something like:
   ```
   inet 10.0.0.60/24
   ```
   **Write down this IP address** — you'll need it in Part 3.

---

## Step 5 — Update the system

Still in the Proxmox Console, run these commands one at a time:

```bash
apt update
```
```bash
apt upgrade -y
```

Wait for each to finish before typing the next one. When asked any questions, press **Enter** to accept defaults.

---

# PART 2 — Deploy the GymTracker Backend

## Step 6 — Install Docker

Still in the console (logged in as root), run each of these commands:

```bash
apt install -y docker.io curl
```
```bash
systemctl enable docker
```
```bash
systemctl start docker
```
```bash
docker --version
```

The last command should print something like `Docker version 24.x.x` — this confirms Docker is working.

---

## Step 7 — Transfer your backend files to the container

You need to copy the `backend` folder from your Windows PC to the container. The easiest way is using **WinSCP** (free).

### Install WinSCP on Windows
1. Go to https://winscp.net and download WinSCP
2. Install and open it

### Connect to your container
1. In WinSCP, click **New Site**
2. Fill in:
   - **File protocol:** SCP
   - **Host name:** `10.0.0.60` ← your container IP from Step 4
   - **Port:** `22`
   - **User name:** `root`
   - **Password:** your container password
3. Click **Login** (accept the host key warning)

### Copy the files
1. On the **left panel** (your Windows PC), navigate to:
   `<project folder>\`
2. On the **right panel** (your container), navigate to `/opt/`
3. Drag the `backend` folder from left to right
4. Wait for the copy to finish

---

## Step 8 — Build and run the Docker container

Back in the Proxmox Console (or you can SSH using PuTTY), run:

```bash
cd /opt/backend
```
```bash
mkdir -p /opt/gymtracker-data
```
```bash
docker build -t gymtracker-api .
```

> This step downloads Python and installs dependencies. It will take 1–3 minutes the first time. You'll see lots of output — that's normal. Wait for `Successfully built` or `naming to docker.io/library/gymtracker-api`.

```bash
docker run -d \
  --name gymtracker \
  --restart unless-stopped \
  -p 8000:8000 \
  -v /opt/gymtracker-data:/data \
  gymtracker-api
```

---

## Step 9 — Verify the backend is running

Run this command:

```bash
curl http://localhost:8000/health
```

You should see:
```json
{"status":"ok","service":"GymTracker API"}
```

**If you see that — your backend is live! 🎉**

### Also test from your Windows PC browser
Open your browser and go to:
```
http://10.0.0.60:8000/docs
```
(Replace `10.0.0.60` with your actual container IP)

You should see the **FastAPI interactive docs** page — a full list of all API endpoints you can test directly in the browser.

---

## Step 10 — Make sure it survives reboots

The `--restart unless-stopped` flag in Step 8 already handles this — Docker will automatically restart the container after a reboot. You can verify by running:

```bash
docker ps
```

You should see `gymtracker` listed with status `Up`.

---

## Useful backend commands (for future reference)

```bash
# Check if backend is running
docker ps

# View live logs
docker logs -f gymtracker

# Restart the backend
docker restart gymtracker

# Stop the backend
docker stop gymtracker

# Update backend after changing code:
docker stop gymtracker
docker rm gymtracker
docker build -t gymtracker-api /opt/backend/
docker run -d --name gymtracker --restart unless-stopped \
  -p 8000:8000 -v /opt/gymtracker-data:/data gymtracker-api
```

---

# PART 3 — Build the Flutter App & Install on Android

## What you need
- Your Windows PC
- An Android phone
- A USB cable
- ~5 GB of free disk space (Android Studio + Flutter SDK are large)

---

## Step 11 — Install Git for Windows

Flutter requires Git. If you don't have it:

1. Go to https://git-scm.com/download/win
2. Download and run the installer
3. Click **Next** through all the defaults
4. When finished, open **Command Prompt** and type:
   ```
   git --version
   ```
   You should see `git version 2.x.x`

---

## Step 12 — Install Flutter SDK

1. Go to https://docs.flutter.dev/get-started/install/windows
2. Click **Download Flutter SDK** (the blue button)
3. Extract the downloaded zip to `C:\flutter`
   > ⚠️ Do NOT put it in `C:\Program Files` — Flutter needs write access to its folder

4. Add Flutter to your PATH:
   - Press **Windows key**, search `environment variables`, click **Edit the system environment variables**
   - Click **Environment Variables**
   - Under **User variables**, find **Path** and double-click it
   - Click **New**
   - Type: `C:\flutter\bin`
   - Click **OK** on all dialogs

5. Open a **new** Command Prompt (close any open ones first) and run:
   ```
   flutter --version
   ```
   You should see Flutter version info.

---

## Step 13 — Install Android Studio

1. Go to https://developer.android.com/studio
2. Download and install Android Studio
3. Open Android Studio — it will run a first-time setup wizard
4. In the wizard, choose **Standard** installation and click through
5. Let it download the Android SDK (this takes a few minutes)

### Install the required SDK version
1. Open Android Studio
2. Go to **Tools → SDK Manager**
3. In the **SDK Platforms** tab, tick **Android 13.0 (API Level 33)**
4. In the **SDK Tools** tab, make sure these are ticked:
   - Android SDK Build-Tools
   - Android SDK Command-line Tools
   - Android Emulator
   - Android SDK Platform-Tools
5. Click **Apply** → **OK** → let it install

---

## Step 14 — Accept Android licences

Open **Command Prompt** and run:

```
flutter doctor --android-licenses
```

Press `y` and **Enter** to accept each licence (there are about 5–7 of them).

---

## Step 15 — Run flutter doctor

```
flutter doctor
```

You should see something like:
```
[✓] Flutter (Channel stable)
[✓] Android toolchain
[✓] Android Studio
[!] VS Code (optional — you can ignore this)
[!] Connected device (no phone plugged in yet — that's fine)
```

The important ones to be green are **Flutter** and **Android toolchain**. If anything shows `[✗]`, let me know and I can help fix it.

---

## Step 16 — Configure your backend URL in the app

1. Open this file in Notepad (or any text editor):
   ```
   <project folder>\flutter_app\lib\config\api_config.dart
   ```

2. Find this line:
   ```dart
   static const String defaultBaseUrl = 'http://10.0.0.60:8000';
   ```

   > ✅ This is already set to your correct IP — no changes needed!

4. Save the file.

---

## Step 17 — Get Flutter dependencies

Open **Command Prompt** and run:

```
cd "<project folder>\flutter_app"
```
```
flutter pub get
```

You'll see it downloading packages. Wait for `Got dependencies!`

---

## Step 18 — Build the APK

Still in the same Command Prompt window:

```
flutter build apk --release
```

This takes 2–5 minutes. When finished you'll see:
```
✓ Built build\app\outputs\flutter-apk\app-release.apk
```

Your APK file is now at:
```
<project folder>\flutter_app\build\app\outputs\flutter-apk\app-release.apk
```

---

## Step 19 — Enable Developer Mode on your Android phone

1. Go to **Settings → About Phone**
2. Find **Build Number**
3. Tap **Build Number** 7 times rapidly
4. You'll see "You are now a developer!"
5. Go back to **Settings → Developer Options** (now visible)
6. Enable **USB Debugging**

---

## Step 20 — Install the APK on your phone

### Method A — USB (fastest)

1. Plug your phone into your PC with a USB cable
2. On your phone, when prompted, select **File Transfer** (or **MTP**)
3. In Command Prompt (in the flutter_app folder), run:
   ```
   flutter install
   ```
   If it asks which device, select your phone.

### Method B — Copy the file manually

1. Copy `app-release.apk` to your phone via USB (drag it to your phone in File Explorer)
2. On your phone, open a file manager and find the APK
3. Tap it to install
4. If blocked, go to **Settings → Security → Install unknown apps** and allow your file manager

---

## Step 21 — First launch and connect to backend

1. Open **GymTracker** on your phone
2. Make sure your phone is on the **same WiFi network** as your Proxmox server
3. The cloud icon in the top-right should turn **green** within a few seconds
4. If it stays grey/orange, go to **Home → Backend Settings** and verify the URL matches your container IP

---

## ✅ You're done!

Your full stack is now running:

```
[Your Android Phone]
        ↕  WiFi
[Proxmox LXC Container]
  └── Docker → FastAPI → SQLite DB
```

---

## Quick Troubleshooting

| Problem | Fix |
|---------|-----|
| App shows cloud with X (offline) | Check phone is on same WiFi. Run `docker ps` on Proxmox to confirm container is up |
| `flutter doctor` shows Android error | Re-run `flutter doctor --android-licenses` |
| WinSCP can't connect | Make sure SSH is running: `systemctl start ssh` in the LXC console |
| APK won't install on phone | Enable "Install unknown apps" for your file manager in phone Settings |
| `docker build` fails | Run `apt update && apt install -y docker.io` again in the LXC console |
| Container IP changed after reboot | Set a static IP in your router's DHCP settings for the container's MAC address |

---

## Setting a Static IP (Recommended — do this once)

Your container's IP might change if your router restarts. To fix this permanently:

1. Log into your **router** (usually `10.0.0.1` or `192.168.0.1` in your browser)
2. Find **DHCP Reservations** or **Static DHCP** (location varies by router brand)
3. Find the entry for `gymtracker` or its MAC address
4. Assign it a fixed IP (e.g. `10.0.0.60`)
5. Update `api_config.dart` and rebuild the APK if the IP changes

---

*GymTracker Setup Guide — home lab setup*
