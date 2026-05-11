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

Source files live under `lib/`:

```
lib/
  main.dart                     # entry point, orientation lock, immersive mode, theme
  models/printer_state.dart     # data model + Moonraker JSON parsing
  services/moonraker_service.dart
  screens/viewer_screen.dart    # top-level screen; single or split layout
  screens/settings_screen.dart
  widgets/printer_pane.dart     # self-contained pane for one printer (feed + overlay + service)
  widgets/info_overlay.dart
```

**Data flow:**

1. `SettingsScreen` saves host/port (and optional second printer host/port) to `SharedPreferences`.
2. `ViewerScreen` loads those prefs on init, decides between single-pane and split-screen layout, and renders one or two `PrinterPane` widgets.
3. `PrinterPane` owns a `MoonrakerService` instance, fetches the webcam URL and print thumbnail from Moonraker HTTP endpoints, manages the 15-line console buffer, and holds the `TransformationController` for zoom/pan. It rebuilds when host/port props change.
4. `MoonrakerService` connects via WebSocket (default port 7125), subscribes to six Moonraker objects (`print_stats`, `virtual_sdcard`, `display_status`, `extruder`, `heater_bed`, `gcode_move`), merges partial updates, emits `PrinterState` on a `StreamController`. Also listens for `notify_gcode_response` notifications and emits raw strings on `consoleStream`.
5. `InfoOverlay` consumes the stream and shows temperatures, progress, elapsed/remaining time, ETA wall clock, speed/flow/speed-override, layer count, print thumbnail, and connection state. Optionally shows a console overlay (last 15 Klipper messages, bottom-right).

**Key implementation notes:**

- No state management library — plain Dart streams + `setState`.
- Auto-reconnect: 3-second retry loop on WebSocket disconnect.
- Keepalive: periodic query every 20 seconds to prevent server timeout.
- `main.dart` locks orientation to landscape and enables `SystemUiMode.immersiveSticky`.
- **Split-screen mode**: when "Enable second printer" is on and a second host is configured, `ViewerScreen` renders two `PrinterPane` widgets in a `Row`. Tapping a pane (or pressing D-pad select) focuses it full-screen; back/back-gesture returns to split view.
- `PrinterPane` has a `compact` prop: in split mode each pane is compact (no `InteractiveViewer`, minimal overlay); focused/single mode uses full zoom/pan and the regular overlay.
- `InteractiveViewer` wraps the MJPEG widget for pinch-zoom (1×–6×) and pan; double-tap resets; single-tap toggles overlay.
- Webcam URL is auto-fetched via `GET /server/webcams/list`. Relative stream URLs are resolved against port 4408 (Creality K1/K1C nginx proxy).
- Print thumbnail is fetched via `GET /server/files/metadata?filename=<file>` and displayed in the overlay top-left.
- `PrinterState` also parses `gcode_move` (speed, speedFactor, extrudeFactor) and `print_stats.info` (currentLayer, totalLayer).
- D-pad / keyboard navigation for Android TV remotes: in split mode left/right arrows highlight a pane and select enters it; in single mode select/enter/gameButtonA toggles the overlay; arrow keys navigate settings fields.
- Cleartext HTTP is required for LAN printer connections — configured via `AndroidManifest.xml` (`android:usesCleartextTraffic="true"`) and `Info.plist` ATS exemption on iOS.
- Console overlay: `MoonrakerService` emits `notify_gcode_response` messages on `consoleStream`; `PrinterPane` maintains a 15-line rolling buffer (with `HH:MM:SS` timestamps) passed to `InfoOverlay` as `consoleLines`. Toggled via `show_console` in `SharedPreferences`. Console is hidden in compact (split) mode.
- SharedPreferences keys: `moonraker_host`, `moonraker_port`, `keep_screen_on`, `show_console`, `second_printer_enabled`, `moonraker_host_2`, `moonraker_port_2`.
