# Moonraker Viewer

Simple Flutter app that shows your 3D printer's camera feed fullscreen with live print status overlay, in landscape immersive mode, with pinch-to-zoom. Read-only.

## Features

- Fullscreen MJPEG camera feed in landscape immersive mode
- Pinch-to-zoom + pan via `InteractiveViewer` (double-tap to reset)
- Tap to toggle overlay
- Live overlay via Moonraker WebSocket: state, filename, hotend/bed temps, elapsed/remaining time, ETA, progress bar, speed, flow rate, speed override, layer count
- Print thumbnail fetched from Moonraker and shown in the overlay
- Webcam URL auto-detected via Moonraker's `/server/webcams/list` API
- D-pad / Android TV remote support (select/enter toggles overlay; arrow keys navigate settings)
- Auto-reconnect on connection loss
- Settings persisted via SharedPreferences

## Setup

1. Clone the repo and run:
   ```sh
   flutter pub get
   flutter run
   ```

2. **iOS only — allow cleartext HTTP** (Moonraker typically runs without HTTPS on a LAN).

   Android is already configured. For iOS, add to `ios/Runner/Info.plist`:
   ```xml
   <key>NSAppTransportSecurity</key>
   <dict>
       <key>NSAllowsArbitraryLoads</key>
       <true/>
   </dict>
   ```

## First run

On first launch the settings screen opens:
- **Moonraker host**: e.g. `192.168.1.50` or `k1c.local`
- **Moonraker port**: defaults to `7125`

The camera stream URL is fetched automatically from Moonraker. Relative stream URLs are resolved against port 4408 (Creality K1/K1C nginx proxy).

## Controls

| Gesture / Input | Action |
|---|---|
| Tap | Toggle overlay |
| Pinch | Zoom |
| Pan (when zoomed) | Pan |
| Double-tap | Reset zoom |
| Tap gear icon | Open settings |
| D-pad select / Enter | Toggle overlay |
| D-pad arrows | Navigate settings fields |

## Moonraker objects subscribed

`print_stats`, `virtual_sdcard`, `display_status`, `extruder`, `heater_bed`, `gcode_move`. All read-only — no pause/resume/cancel controls by design.

## Known quirks

- Some K1C webcam endpoints serve multipart MJPEG with non-standard boundaries; if the feed is blank, test the URL in a browser first.
- `flutter_mjpeg` is sensitive to network hiccups. The error builder catches failures so the app doesn't crash, and WebSocket reconnects don't affect the camera stream (they are independent).
