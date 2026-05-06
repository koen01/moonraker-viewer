# Architecture

> Simplified arc42-style architecture document for Moonraker Viewer.

## 1. Overview

Moonraker Viewer is a read-only Flutter app (Android + iOS) that shows a 3D printer's MJPEG camera feed fullscreen with a live status overlay. It connects to a [Moonraker](https://moonraker.readthedocs.io) API server over WebSocket and HTTP.

No backend, no authentication, no write operations — purely observational.

---

## 2. Folder Structure

```
lib/
├── main.dart                      # App entry point
├── models/
│   └── printer_state.dart         # Data model
├── services/
│   └── moonraker_service.dart     # WebSocket client
├── screens/
│   ├── viewer_screen.dart         # Main screen
│   └── settings_screen.dart      # Configuration screen
└── widgets/
    └── info_overlay.dart          # Status overlay UI
```

---

## 3. Building Blocks

### `main.dart`
Entry point. Locks orientation to landscape, enables full-screen immersive mode (`SystemUiMode.immersiveSticky`), applies a dark Material3 theme, and boots `ViewerScreen`.

---

### `models/PrinterState`
Pure data class. Holds a snapshot of printer state parsed from Moonraker's JSON. No logic beyond parsing and formatting helpers.

**Fields:**

| Field | Source object | Description |
|---|---|---|
| `state` | `print_stats` | Printer state string (`printing`, `paused`, `standby`, etc.) |
| `filename` | `print_stats` | Currently loaded file |
| `progress` | `display_status` / `virtual_sdcard` | 0.0–1.0 |
| `printDuration` | `print_stats` | Seconds spent printing |
| `totalDuration` | `print_stats` | Total session duration |
| `estimatedTotalTime` | Derived | `printDuration / progress` |
| `extruderTemp/Target/Power` | `extruder` | Hotend temperatures |
| `bedTemp/Target/Power` | `heater_bed` | Bed temperatures |
| `speed` | `gcode_move` | Current move speed in mm/s |
| `speedFactor` | `gcode_move` | Speed override multiplier |
| `extrudeFactor` | `gcode_move` | Flow rate multiplier |
| `currentLayer` / `totalLayer` | `print_stats.info` | Layer counters |
| `message` | `display_status` | Display message string |

**Factory constructors:**
- `PrinterState.idle()` — zero-value default used before first data arrives
- `PrinterState.fromMoonraker(Map status)` — parses a merged Moonraker status map

**Formatting helpers:** `formatElapsed`, `formatRemaining`, `etaWallClock`

---

### `services/MoonrakerService`
Manages the WebSocket connection to Moonraker. Owns all reconnect and keepalive logic.

**Responsibilities:**
- Connect to `ws://<host>:<port>/websocket`
- Subscribe to six printer objects: `print_stats`, `virtual_sdcard`, `display_status`, `extruder`, `heater_bed`, `gcode_move`
- Merge partial status updates into a single accumulated map
- Emit `PrinterState` snapshots on `stateStream`
- Emit connection status booleans on `connectionStream`
- Auto-reconnect after 3 seconds on disconnect or error
- Send a keepalive query every 20 seconds to prevent server timeout

**Public API:**

```dart
MoonrakerService({required String host, int port = 7125})

Stream<PrinterState> get stateStream
Stream<bool>         get connectionStream

void connect()
void dispose()
```

**Does not** handle webcam URLs or thumbnails — those are fetched by `ViewerScreen` via plain HTTP.

---

### `screens/ViewerScreen`
The main screen and top-level state owner. Rendered immediately on launch.

**Responsibilities:**
- Load saved settings from `SharedPreferences`
- Create and own the `MoonrakerService` instance
- Fetch the webcam stream URL from `GET /server/webcams/list`
- Fetch print thumbnails from `GET /server/files/metadata?filename=<file>`
- Render the MJPEG stream via `flutter_mjpeg`
- Pass printer state and thumbnail URL down to `InfoOverlay`
- Handle tap/double-tap/pinch gestures and D-pad key events

**State fields:**

| Field | Purpose |
|---|---|
| `_moonrakerHost` / `_moonrakerPort` | Connection settings |
| `_webcamUrl` | Resolved stream URL (fetched from Moonraker) |
| `_thumbnailUrl` | URL of the current print's largest thumbnail |
| `_state` | Latest `PrinterState` from the service stream |
| `_connected` | Latest connection status |
| `_showOverlay` | Whether `InfoOverlay` is visible |
| `_transform` | `TransformationController` for `InteractiveViewer` |

**Webcam URL resolution:**
1. Call `GET /server/webcams/list`
2. Use the first enabled webcam's `stream_url`
3. If the URL is relative, resolve it against `http://<host>:4408` (Creality K1/K1C nginx proxy)

**Thumbnail resolution:**
1. When `PrinterState.filename` changes, call `GET /server/files/metadata?filename=<file>`
2. Sort returned thumbnails by width descending, pick the largest
3. Resolve the `relative_path` against the file's directory under `/server/files/gcodes/`

---

### `screens/SettingsScreen`
Simple form to configure the Moonraker host and port. Persists values to `SharedPreferences` on save and returns `true` to the caller so `ViewerScreen` knows to reconnect.

**Fields saved:**

| Key | Type | Default |
|---|---|---|
| `moonraker_host` | String | — |
| `moonraker_port` | int | 7125 |

Includes D-pad / arrow-key navigation between fields for Android TV remote support.

---

### `widgets/InfoOverlay`
Stateless widget. Renders a heads-up display over the camera feed.

**Layout:**
- **Top bar** (gradient, top-aligned): thumbnail, status dot, state label, filename, ETA, speed/flow/override info, settings gear button
- **Bottom bar** (gradient, bottom-aligned): temperature chips, layer chip, elapsed/remaining chips, progress bar + percentage

**Inputs:**

| Prop | Type | Description |
|---|---|---|
| `state` | `PrinterState` | Current printer state |
| `connected` | `bool` | WebSocket connection status |
| `thumbnailUrl` | `String?` | URL for the print thumbnail image |
| `onSettings` | `VoidCallback` | Opens `SettingsScreen` |

Contains two private helpers:
- `_Thumbnail` — renders the thumbnail image with a placeholder fallback
- `_FocusableIconButton` — icon button with animated focus ring for TV remote navigation

---

## 4. Data Flow

```
SharedPreferences
      │  host, port
      ▼
ViewerScreen ──────────────────────────────────────────────────────┐
      │                                                             │
      │ creates                                                     │ HTTP GET
      ▼                                                             ▼
MoonrakerService                                        /server/webcams/list
      │  ws://host:port/websocket                       /server/files/metadata
      │
      │  subscribe (6 objects)
      │◄─────────────────── Moonraker server
      │  notify_status_update
      │
      │ merge partial updates
      │ emit PrinterState
      ▼
ViewerScreen._state  ──► InfoOverlay
ViewerScreen._connected ──► InfoOverlay
ViewerScreen._webcamUrl ──► Mjpeg widget
ViewerScreen._thumbnailUrl ──► InfoOverlay
```

---

## 5. State Management

No third-party state management library. The app uses:

- **`StreamController.broadcast()`** in `MoonrakerService` to push updates
- **`setState()`** in `ViewerScreen` to re-render on new `PrinterState` or connection changes
- **`SharedPreferences`** for persistent configuration

This is intentional — the app is simple enough that a full state management solution would add unnecessary complexity.

---

## 6. Key Dependencies

| Package | Purpose |
|---|---|
| `flutter_mjpeg` | MJPEG stream rendering |
| `web_socket_channel` | WebSocket client |
| `shared_preferences` | Persistent settings storage |

---

## 7. Platform Notes

### Android
- `android:usesCleartextTraffic="true"` is set in `AndroidManifest.xml` — required for plain HTTP to LAN printers
- `android.software.leanback` feature declared (not required) for Android TV compatibility
- `LEANBACK_LAUNCHER` intent filter registered so the app appears in TV launchers

### iOS
- `NSAllowsArbitraryLoads` must be added manually to `Info.plist` (not committed) — see README
- Orientation locked to landscape via `UISupportedInterfaceOrientations` in `Info.plist`
