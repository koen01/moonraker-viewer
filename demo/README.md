# Mock Moonraker Server

Test server that simulates a Moonraker-connected 3D printer — no real printer needed.

## What it does

- Serves the Moonraker WebSocket API on port 7125
- Streams `demo.mp4` as a looping MJPEG feed
- Simulates a print in progress (starts at ~56%, slowly advancing)
- Pushes live temperature oscillations and status updates every 250ms
- Sends periodic Klipper console messages

## Requirements

```bash
pip install aiohttp
apt install ffmpeg   # or: brew install ffmpeg
```

## Run

```bash
python3 mock_moonraker.py
# or with custom options:
python3 mock_moonraker.py --host 0.0.0.0 --port 7125 --video demo.mp4
```

## Connect the app

In Moonraker Viewer settings, set:
- **Host**: IP or domain of the server running this script
- **Port**: `7125` (default)
