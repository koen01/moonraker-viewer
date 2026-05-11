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
│   ├── viewer_screen.dart         # Top-level screen; single or split layout
│   └── settings_screen.dart      # Configuration screen
└── widgets/
    ├── printer_pane.dart          # Self-contained pane for one printer
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
- Emit raw `notify_gcode_response` strings on `consoleStream`
- Auto-reconnect after 3 seconds on disconnect or error
- Send a keepalive query every 20 seconds to prevent server timeout

**Public API:**

```dart
MoonrakerService({required String host, int port = 7125})

Stream<PrinterState> get stateStream
Stream<bool>         get connectionStream
Stream<String>       get consoleStream

void connect()
void dispose()
```

**Does not** handle webcam URLs or thumbnails — those are fetched by `PrinterPane` via plain HTTP.

---

### `widgets/PrinterPane`
Self-contained widget for a single printer. Owns everything needed to display one printer's feed and status. `ViewerScreen` creates one or two of these depending on whether split-screen mode is active.

**Responsibilities:**
- Create and own the `MoonrakerService` instance for its printer
- Fetch the webcam stream URL from `GET /server/webcams/list`
- Fetch print thumbnails from `GET /server/files/metadata?filename=<file>`
- Maintain the 15-line rolling console buffer
- Own the `TransformationController` for `InteractiveViewer`
- Render the MJPEG stream (with or without zoom/pan depending on `compact`)
- Pass state down to `InfoOverlay`
- Reconnect when `host` or `port` props change

**Props:**

| Prop | Type | Description |
|---|---|---|
| `host` / `port` | `String` / `int` | Printer connection settings |
| `compact` | `bool` | If true, renders without `InteractiveViewer` and with a minimal overlay (used in split view) |
| `showOverlay` | `bool` | Whether `InfoOverlay` is visible |
| `showConsole` | `bool` | Whether the console box is shown |
| `onSettings` | `VoidCallback` | Opens `SettingsScreen` |
| `settingsFocusNode` | `FocusNode?` | Focus node for the settings gear button (TV remote) |
| `onTap` | `VoidCallback?` | Called on tap in compact mode (used to focus a split pane) |
| `onToggleOverlay` | `VoidCallback?` | Called on tap in full mode to toggle the overlay |

**Webcam URL resolution:**
1. Call `GET /server/webcams/list`
2. Use the first enabled webcam's `stream_url`
3. If the URL is relative, resolve it against `http://<host>:4408` (Creality K1/K1C nginx proxy)

**Thumbnail resolution:**
1. When `PrinterState.filename` changes, call `GET /server/files/metadata?filename=<file>`
2. Sort returned thumbnails by width descending, pick the largest
3. Resolve the `relative_path` against the file's directory under `/server/files/gcodes/`

---

### `screens/ViewerScreen`
Top-level screen. Orchestrates layout and user interactions; delegates all per-printer logic to `PrinterPane`.

**Responsibilities:**
- Load saved settings from `SharedPreferences`
- Choose between single-pane and split-screen layout
- Handle D-pad key events for pane selection (split mode) and overlay toggle (single mode)
- Manage `PopScope` so back navigates: focused pane → split view → overlay hidden

**State fields:**

| Field | Purpose |
|---|---|
| `_host` / `_port` | Primary printer connection settings |
| `_host2` / `_port2` | Second printer connection settings |
| `_secondPrinterEnabled` | Whether split-screen mode is available |
| `_showOverlay` | Whether `InfoOverlay` is visible in single/focused mode |
| `_showConsole` | Whether the console overlay is enabled |
| `_focusedPane` | `null` = split view; `0`/`1` = that pane is expanded full-screen |
| `_highlightedPane` | D-pad cursor in split mode (0 or 1) |

**Split-screen mode** is active when `_secondPrinterEnabled` is true, `_host2` is set, and `_focusedPane` is null. The view renders two `PrinterPane` widgets in a `Row` separated by a 1 px divider. Tapping a pane (or pressing D-pad select) sets `_focusedPane` and expands that pane full-screen.

---

### `screens/SettingsScreen`
Form to configure both printers. Persists values to `SharedPreferences` on save and returns `true` so `ViewerScreen` knows to reload.

**Fields saved:**

| Key | Type | Default |
|---|---|---|
| `moonraker_host` | String | — |
| `moonraker_port` | int | 7125 |
| `keep_screen_on` | bool | true |
| `show_console` | bool | false |
| `second_printer_enabled` | bool | false |
| `moonraker_host_2` | String | — |
| `moonraker_port_2` | int | 7125 |

Second-printer fields are shown/hidden with `AnimatedCrossFade` when the toggle changes. Includes D-pad / arrow-key navigation between fields for Android TV remote support.

---

### `widgets/InfoOverlay`
Stateless widget. Renders a heads-up display over the camera feed.

**Layout:**
- **Top bar** (gradient, top-aligned): thumbnail, status dot, state label, filename, ETA, speed/flow/override info, settings gear button
- **Bottom bar** (gradient, bottom-aligned): temperature chips, layer chip, elapsed/remaining chips, progress bar + percentage
- **Console box** (optional, bottom-right, above bottom bar): last 15 Klipper messages with `HH:MM:SS` timestamps, semi-transparent background

**Inputs:**

| Prop | Type | Description |
|---|---|---|
| `state` | `PrinterState` | Current printer state |
| `connected` | `bool` | WebSocket connection status |
| `thumbnailUrl` | `String?` | URL for the print thumbnail image |
| `onSettings` | `VoidCallback` | Opens `SettingsScreen` |
| `consoleLines` | `List<String>?` | Rolling console buffer; `null` hides the console box |
| `compact` | `bool` | Reduced layout for split-screen panes (hides thumbnail, console, and detail fields) |

Contains three private helpers:
- `_Thumbnail` — renders the thumbnail image with a placeholder fallback
- `_FocusableIconButton` — icon button with animated focus ring for TV remote navigation
- `_ConsoleBox` — monospace log display for Klipper console messages

---

## 4. Data Flow

```
SharedPreferences
      │  host, port, host2, port2, second_printer_enabled, …
      ▼
ViewerScreen
      │  single pane or split Row
      ▼
PrinterPane (×1 or ×2) ────────────────────────────────────────────┐
      │                                                             │
      │ creates                                                     │ HTTP GET
      ▼                                                             ▼
MoonrakerService                                        /server/webcams/list
      │  ws://host:port/websocket                       /server/files/metadata
      │
      │  subscribe (6 objects)
      │◄─────────────────── Moonraker server
      │  notify_status_update
      │  notify_gcode_response
      │
      │ merge partial updates
      │ emit PrinterState     → PrinterPane._state
      │ emit bool             → PrinterPane._connected
      │ emit String           → PrinterPane._consoleLines (rolling 15)
      ▼
PrinterPane._state        ──► InfoOverlay
PrinterPane._connected    ──► InfoOverlay
PrinterPane._consoleLines ──► InfoOverlay (when show_console=true)
PrinterPane._webcamUrl    ──► Mjpeg widget (via InteractiveViewer or plain)
PrinterPane._thumbnailUrl ──► InfoOverlay
```

---

## 5. State Management

No third-party state management library. The app uses:

- **`StreamController.broadcast()`** in `MoonrakerService` to push updates
- **`setState()`** in `PrinterPane` to re-render on new `PrinterState` or connection changes; `ViewerScreen` uses `setState` only for layout-level changes (split/focus mode, overlay visibility)
- **`SharedPreferences`** for persistent configuration

This is intentional — the app is simple enough that a full state management solution would add unnecessary complexity.

---

## 6. Key Dependencies

| Package | Version | Purpose |
|---|---|---|
| `flutter_mjpeg` | ^2.0.4 | MJPEG stream rendering |
| `web_socket_channel` | ^3.0.3 | WebSocket client |
| `shared_preferences` | ^2.2.3 | Persistent settings storage |
| `wakelock_plus` | ^1.5.2 | Keep screen on while viewing |

---

## 7. Platform Notes

### Android
- `android:usesCleartextTraffic="true"` is set in `AndroidManifest.xml` — required for plain HTTP to LAN printers
- `android.software.leanback` feature declared (not required) for Android TV compatibility
- `LEANBACK_LAUNCHER` intent filter registered so the app appears in TV launchers

### iOS
- `NSAllowsArbitraryLoads` must be added manually to `Info.plist` (not committed) — see README
- Orientation locked to landscape via `UISupportedInterfaceOrientations` in `Info.plist`
