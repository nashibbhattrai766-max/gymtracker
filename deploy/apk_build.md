# Building the GymTracker APK

## Prerequisites

1. **Install Flutter SDK** (if not already installed):
   - Download from https://docs.flutter.dev/get-started/install
   - Add Flutter to your PATH
   - Run `flutter doctor` — resolve any issues shown

2. **Install Android Studio** (for the Android SDK):
   - Download from https://developer.android.com/studio
   - In Android Studio: SDK Manager → install Android SDK 33+

3. **Accept Android licences**:
   ```bash
   flutter doctor --android-licenses
   ```

---

## Step 1 — Configure your backend URL

Before building, set your Proxmox server IP in the app:

Open `flutter_app/lib/config/api_config.dart` and update:

```dart
static const String defaultBaseUrl = 'http://10.0.0.50:8000';
//                                               ↑ Your Proxmox LXC IP
```

---

## Step 2 — Get dependencies

```bash
cd flutter_app
flutter pub get
```

---

## Step 3 — Build the APK

### Debug APK (for testing — no signing needed):

```bash
flutter build apk --debug
```

Output: `build/app/outputs/flutter-apk/app-debug.apk`

### Release APK (for daily use — smaller, faster):

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### Fat APK (works on all device architectures):

```bash
flutter build apk --release --no-shrink
```

---

## Step 4 — Install on your Android phone

### Method A — USB cable:

```bash
# Enable Developer Options on your phone:
# Settings → About Phone → tap Build Number 7 times
# Settings → Developer Options → enable USB Debugging

flutter install
# or:
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Method B — Transfer file:

1. Copy `app-release.apk` to your phone (via USB, Google Drive, etc.)
2. On your phone: Settings → Security → enable "Install from unknown sources"
3. Open the APK file and install

---

## Step 5 — First-time setup on phone

1. Open GymTracker
2. Go to **Home** tab → tap **Backend Settings** at the bottom
3. Enter your Proxmox URL: `http://10.0.0.50:8000`
4. The status icon (top-right) will turn green when connected ✅

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `flutter: command not found` | Add Flutter bin folder to PATH |
| Android SDK not found | Install Android Studio + SDK |
| APK installs but can't connect | Check Proxmox LXC IP, ensure container is running |
| "Install blocked" on phone | Enable "Install from unknown sources" in Settings |
| App shows offline icon | Your phone and Proxmox must be on the same WiFi network |

---

## Useful Flutter commands

```bash
flutter devices          # List connected devices
flutter run              # Run in debug mode on connected device
flutter run --release    # Run release version
flutter clean            # Clean build cache (fixes weird build errors)
flutter pub upgrade      # Update dependencies
```
