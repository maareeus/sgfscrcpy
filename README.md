<div align="center">

# Simple Gui For Scrcpy

**SgfScrcpy** — a modern, minimal desktop UI to mirror your Android devices.

[![Build & Release](https://github.com/maareeus/sgfscrcpy/actions/workflows/release.yml/badge.svg)](https://github.com/maareeus/sgfscrcpy/actions/workflows/release.yml)
[![Version](https://img.shields.io/badge/version-0.0.1-6C5CE7.svg)](https://github.com/maareeus/sgfscrcpy/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-informational.svg)](#requirements)
[![Flutter](https://img.shields.io/badge/Flutter-3.44%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.12%2B-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#contributing)

</div>

---

SgfScrcpy wraps [scrcpy](https://github.com/Genymobile/scrcpy) in a clean desktop app.
On launch it detects your connected Android devices and shows them as cards — click one to
start mirroring. No command line, no fiddling with paths.

## ✨ Features

- **Device grid** — connected devices (USB *and* wireless) shown as modern cards with live
  status dots, not a boring list.
- **One-click mirroring** — tap a card to launch scrcpy for that device.
- **Session tracking** — cards flip to *Mirroring* and reset automatically when you close the
  scrcpy window.
- **Self-configuring** — if scrcpy/adb are missing, SgfScrcpy detects it and helps you fix it:
  - **Windows** — one-click download & extract of the official scrcpy build (adb included).
  - **macOS** — install via Homebrew in one click.
  - **Linux** — detects your package manager and shows the exact command to run.
- **Auto-update** — checks GitHub for new scrcpy releases and offers an in-app update.
- **No stray terminals** — on Windows, scrcpy is launched via a Win32 `CreateProcess` call with
  `CREATE_NO_WINDOW`, so no console window ever pops up.

## 📦 Requirements

SgfScrcpy drives two external tools; it can install them for you, or you can provide them:

| Tool | Purpose | Notes |
|------|---------|-------|
| [scrcpy](https://github.com/Genymobile/scrcpy) | Screen mirroring | Windows builds bundle `adb`. |
| adb (Android Platform Tools) | Device communication | Bundled with scrcpy on Windows. |

On the device: enable **Developer options → USB debugging**.

## 🚀 Getting started

```bash
flutter pub get
flutter run -d windows   # or: -d macos / -d linux
```

If scrcpy isn't installed, the app opens on a **Setup** screen — follow the on-screen action for
your platform.

## 🛠️ Build

```bash
flutter build windows    # → build/windows/x64/runner/Release/
flutter build macos      # → build/macos/Build/Products/Release/
flutter build linux      # → build/linux/x64/release/bundle/
```

## 🧭 Project structure

```
lib/
├── main.dart                    # App entry, window setup, theme
├── theme.dart                   # Dark Material 3 theme
├── models/
│   └── device.dart              # Device model + `adb devices -l` parser
├── services/
│   ├── scrcpy_service.dart      # Env detection, device listing, launch, path persistence
│   ├── scrcpy_updater.dart      # GitHub release check + Windows download/extract
│   └── win_process.dart         # Win32 FFI launcher (CREATE_NO_WINDOW) + liveness
├── screens/
│   └── home_screen.dart         # Main screen and all UI states
└── widgets/
    └── device_card.dart         # Device card
```

## 🤝 Contributing

Contributions are welcome. Open an issue to discuss a change, or send a pull request.
Run `flutter analyze` and `flutter test` before submitting.

## 📄 License

Released under the [MIT License](LICENSE). Use it however you like.

## 🙏 Acknowledgements

Built on top of the excellent [scrcpy](https://github.com/Genymobile/scrcpy) by Genymobile.
SgfScrcpy is an independent GUI and is not affiliated with the scrcpy project.
