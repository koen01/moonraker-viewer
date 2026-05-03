# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter mobile app (iOS + Android) that displays a 3D printer's MJPEG camera feed fullscreen with a live overlay of print status pulled from a Moonraker server over WebSocket.

## Commands

```bash
flutter pub get          # install dependencies
flutter run              # run on connected device/emulator
flutter build apk        # build Android APK
flutter build ios        # build iOS
flutter test             # run tests
dart format .            # format Dart code
flutter analyze          # lint
```

## Architecture

All source files currently live flat in the project root (not under `lib/`). The intended canonical structure (from the zip archive) is:

```
lib/
  main.dart                     # entry point, orientation lock, theme
  models/printer_state.dart     # data model + Moonraker JSON parsing
  services/moonraker_service.dart
  screens/viewer_screen.dart
  screens/settings_screen.dart
  widgets/info_overlay.dart
```

**Data flow:**

1. `SettingsScreen` saves host + stream URL to `SharedPreferences`.
2. `ViewerScreen` loads those prefs on init, opens `MoonrakerService`, renders `Mjpeg` + `InfoOverlay`.
3. `MoonrakerService` connects via WebSocket (default port 7125), subscribes to five Moonraker objects (`print_stats`, `virtual_sdcard`, `display_status`, `extruder`, `heater_bed`), merges partial updates, emits `PrinterState` on a `StreamController`.
4. `InfoOverlay` consumes the stream and shows temperatures, progress, elapsed/remaining time, and connection state.

**Key implementation notes:**

- No state management library — plain Dart streams + `setState`.
- Auto-reconnect: 3-second retry loop on WebSocket disconnect.
- Keepalive: periodic query every 20 seconds to prevent server timeout.
- `InteractiveViewer` wraps the MJPEG widget for pinch-zoom (1×–6×) and pan; double-tap resets; single-tap toggles overlay.
- Cleartext HTTP is required for LAN printer connections — configured via `AndroidManifest.xml` (`android:usesCleartextTraffic="true"`) and `Info.plist` ATS exemption on iOS.
- Camera stream URL defaults to `http://<host>/webcam/?action=stream` but can be overridden in settings.
