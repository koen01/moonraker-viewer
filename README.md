# Moonraker Viewer

Super-simpele Flutter app om de camera feed van je 3D printer fullscreen te tonen met live print info erover, in landscape, met pinch-to-zoom. Read-only.

## Features
- Fullscreen MJPEG camera feed in landscape, immersive mode
- Pinch-to-zoom + pan via `InteractiveViewer` (dubbeltik = reset)
- Tap = overlay aan/uit
- Live overlay via Moonraker WebSocket: state, filename, hotend/bed temps, elapsed/remaining, progress bar
- Auto-reconnect bij wegvallen verbinding
- Settings worden persistent opgeslagen

## Setup

1. Maak een leeg Flutter project en kopieer dit project erover (of gebruik direct):
   ```sh
   flutter create --org nl.koen moonraker_viewer
   cd moonraker_viewer
   # vervang lib/ en pubspec.yaml met die uit deze repo
   flutter pub get
   ```

2. **Cleartext HTTP toestaan** (Moonraker is meestal geen HTTPS op je LAN).

   **Android** — in `android/app/src/main/AndroidManifest.xml` binnen het `<application>` element:
   ```xml
   <application
       android:label="Moonraker Viewer"
       android:usesCleartextTraffic="true"
       ...>
   ```

   **iOS** — in `ios/Runner/Info.plist`:
   ```xml
   <key>NSAppTransportSecurity</key>
   <dict>
       <key>NSAllowsArbitraryLoads</key>
       <true/>
   </dict>
   <key>UISupportedInterfaceOrientations</key>
   <array>
       <string>UIInterfaceOrientationLandscapeLeft</string>
       <string>UIInterfaceOrientationLandscapeRight</string>
   </array>
   ```

3. Run:
   ```sh
   flutter run
   ```

## Eerste keer

Bij de eerste start opent de settings pagina:
- **Moonraker host**: bv `192.168.1.50` (port 7125 wordt automatisch toegevoegd) of `k1c.local`
- **Camera stream URL**: leeglaten voor `http://<host>/webcam/?action=stream`. Voor je rooted K1C met crowsnest is dat meestal `http://<host>:8080/?action=stream`.

## Bediening

| Gebaar | Actie |
|---|---|
| Tik | Overlay aan/uit |
| Pinch | Zoomen |
| Pan na zoom | Verschuiven |
| Dubbeltik | Zoom resetten |
| Tap op tandwiel | Settings |

## Moonraker objects die we subscriben

`print_stats`, `virtual_sdcard`, `display_status`, `extruder`, `heater_bed`. Alles read-only, geen pause/resume/cancel knoppen — bewust.

## Bekende quirks

- Sommige K1C webcam endpoints serveren multipart MJPEG met afwijkende boundaries; als de feed leeg blijft, test eerst de URL in een browser.
- `flutter_mjpeg` is gevoelig voor netwerk hiccups. De error builder vangt het op zodat de app niet crasht, en bij reconnect van de WebSocket blijft de stream gewoon draaien (apart van elkaar).
