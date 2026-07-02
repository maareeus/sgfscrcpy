# SgfScrcpy — Simple GUI for Scrcpy

A modern, minimal desktop UI for [scrcpy](https://github.com/Genymobile/scrcpy).
On launch it detects connected Android devices and shows them as clean cards —
click one to start mirroring. Runs on **Windows, macOS and Linux**.

## Features

- Auto-detects connected devices via `adb devices -l` (USB + wireless).
- Card-based device grid (not a boring list) with live status dots.
- Detects when `scrcpy` or `adb` are missing and shows a setup screen.
- Surfaces launch/query errors inline instead of failing silently.
- One-click mirror launch per device.

## Requirements

The app shells out to two external tools that must be on your `PATH`:

- **scrcpy** — https://github.com/Genymobile/scrcpy (Windows builds bundle `adb`).
- **adb** (Android Platform Tools) — usually bundled with scrcpy on Windows;
  install separately on macOS/Linux (e.g. `brew install android-platform-tools`,
  `apt install adb`).

## Run

```bash
flutter pub get
flutter run -d windows   # or -d macos / -d linux
```

## Build

```bash
flutter build windows    # macos / linux
```

## Project layout

- `lib/models/device.dart` — device model + `adb devices -l` line parser.
- `lib/services/scrcpy_service.dart` — env detection, device listing, launch.
- `lib/screens/home_screen.dart` — main screen and all UI states.
- `lib/widgets/device_card.dart` — the device card.
- `lib/theme.dart` — dark Material 3 theme.
