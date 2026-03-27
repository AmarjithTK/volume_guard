# Volume Guard 🛡️🔊

An advanced, enterprise-grade Android background service built with **Flutter** and **Kotlin** that protects your hearing and screen by enforcing strict bounding boxes around your system volumes and display brightness.

## ✨ Core Features

* **Absolute Volume Locking:** Declare min/max safe ranges (e.g., 8% to 60%) for Media, Ringtone, Alarm, Notification, and Voice Calls.
* **Accessibility Service Persistence:** Runs as a native `AccessibilityService` instead of a standard foreground service to bypass aggressive OEM battery savers (Xiaomi, Redmi, etc.) ensuring locks survive 24/7.
* **Bluetooth Connect Protection:** Built-in `BroadcastReceiver` instantly drops your volume to a safe percentage the exact millisecond a Bluetooth headset or wired earbud connects. Avoids blown out eardrums.
* **Live Hardware Sync:** Live `EventChannel` feeds your system volume to the app. If a lock is disabled, the Flutter UI physically follows your hardware volume rocker button presses.
* **True Display Ratio (Non-255 Systems):** Correctly auto-scales your brightness locking range on modern 4095-scale hardware devices which typically break standard Android display interactions.
* **Quick Toggle Notifications:** Control locks directly from your Android notification tray with 3 instant action buttons without opening the app window.

## 🛠 Tech Stack

* **UI Layer:** Flutter (Dart) 3.19+ | Modern Material 3 Card Designs
* **Native Layer:** Kotlin | `AccessibilityService` | `ContentObserver` | `BroadcastReceiver`

## 🚀 Building / Installation

Dependencies:
* Flutter SDK
* Android SDK (Target 34 / Minimum 24)

```bash
flutter pub get

# To build standard unified APK
flutter build apk

# To build optimized Split-ABI APKs for reduced file sizes
flutter build apk --split-per-abi
```

## 🔄 GitHub Actions Deployment

This repository includes a fully-configured CI/CD pipeline! Creating a release tag (e.g., `v1.0.0`) and pushing it automatically:
1. Runs the Flutter Action builder inside Ubuntu containers.
2. Builds `apk --split-per-abi` reducing total download sizes for specific chipsets.
3. Automatically publishes the `armeabi-v7a`, `arm64-v8a`, and `x86_64` artifacts to the GitHub Release page.

## ✅ Permissions Needed

- `Notification Permission`: To maintain the foreground service tray.
- `Write Settings`: To modify and enforce `SCREEN_BRIGHTNESS`.
- `Accessibility Service`: The core persistent router necessary to watch and enforce volume limits asynchronously.
