#!/usr/bin/env python3
"""
Mock Moonraker server for testing Moonraker Viewer without a real printer.

Serves:
  ws://host:7125/websocket       — Moonraker JSON-RPC (subscribe/query + push updates)
  GET http://host:7125/server/webcams/list   — returns the MJPEG stream URL
  GET http://host:7125/webcam                — MJPEG stream (from demo.mp4 or relayed)
  GET http://host:7125/server/files/metadata — returns empty thumbnails

Usage:
  # Serve from a local video file (requires ffmpeg):
  pip install aiohttp
  apt install ffmpeg  (or brew install ffmpeg)
  python3 mock_moonraker.py [--host 0.0.0.0] [--port 7125] [--video demo.mp4]

  # Relay a real printer's MJPEG stream (no ffmpeg needed, --video ignored):
  python3 mock_moonraker.py --relay-stream http://192.168.1.50:4408/webcam
"""

import argparse
import asyncio
import json
import logging
import math
import os
import subprocess
import time
from pathlib import Path

from aiohttp import web
import aiohttp

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("mock_moonraker")

# ── Simulated print state ────────────────────────────────────────────────────

FILENAME = "tfic-honeycomb_PLA_1h28m.gcode"
TOTAL_DURATION_S = 5280        # 88 min total print
START_PROGRESS = 0.56          # start at 56% (where we captured)
PRINT_SPEED = 16888.0          # mm/min

# Realistic console messages that appear during a print
CONSOLE_MESSAGES = [
    "// B:60.0 /60.0 T0:225.0 /225.0 @:115 B@:44",
    "// probe at 110.000,71.594 is z=0.018677",
    "// probe at 136.250,71.594 is z=0.018583",
    "// Move out of range: 247.00 248.00 10.60 [0.00]",
    "// Adapted mesh: mean 0.004, deviation 0.012",
    "// Extruder 0 temperature set to 225.",
    "// Bed temperature set to 60.",
    "// Print time: 1:22:05",
    "// Layer height: 0.20",
    "// Filament used: 5.83m",
    "// flow: 100%  speed: 100%",
    "// thermal runaway check ok",
]

class PrintSim:
    def __init__(self):
        self.start_time = time.monotonic()
        self.initial_print_duration = START_PROGRESS * TOTAL_DURATION_S
        self.msg_index = 0

    @property
    def elapsed(self):
        return time.monotonic() - self.start_time

    @property
    def print_duration(self):
        return self.initial_print_duration + self.elapsed

    @property
    def progress(self):
        return min(self.print_duration / TOTAL_DURATION_S, 1.0)

    @property
    def state(self):
        return "complete" if self.progress >= 1.0 else "printing"

    @property
    def extruder_temp(self):
        # slight oscillation around target
        return round(225.0 + 0.3 * math.sin(self.elapsed * 0.2), 2)

    @property
    def bed_temp(self):
        return round(60.0 + 0.05 * math.sin(self.elapsed * 0.1), 2)

    @property
    def extruder_power(self):
        return round(0.45 + 0.1 * math.sin(self.elapsed * 0.3), 4)

    @property
    def bed_power(self):
        return round(0.2 + 0.15 * math.sin(self.elapsed * 0.15), 4)

    @property
    def chamber_temp(self):
        return round(42.0 + 1.5 * math.sin(self.elapsed * 0.05), 2)

    def full_status(self):
        pd = self.print_duration
        return {
            "print_stats": {
                "filename": FILENAME,
                "total_duration": pd + 10,
                "print_duration": pd,
                "filament_used": pd * 1.332,
                "state": self.state,
                "message": "",
                "info": {"total_layer": None, "current_layer": None},
            },
            "virtual_sdcard": {
                "progress": self.progress,
                "is_active": self.state == "printing",
                "file_position": int(self.progress * 12667757),
                "file_size": 12667757,
            },
            "display_status": {
                "progress": round(self.progress, 2),
                "message": None,
            },
            "extruder": {
                "temperature": self.extruder_temp,
                "target": 225.0,
                "power": self.extruder_power,
                "can_extrude": True,
            },
            "heater_bed": {
                "temperature": self.bed_temp,
                "target": 60.0,
                "power": self.bed_power,
            },
            "gcode_move": {
                "speed_factor": 1.0,
                "speed": PRINT_SPEED,
                "extrude_factor": 1.0,
                "absolute_coordinates": True,
            },
            "heater_generic chamber": {
                "temperature": self.chamber_temp,
                "target": 45.0,
                "power": 0.1,
            },
        }

    def delta_status(self):
        """Partial update like real Moonraker sends."""
        pd = self.print_duration
        return {
            "print_stats": {
                "total_duration": pd + 10,
                "print_duration": pd,
            },
            "extruder": {
                "temperature": self.extruder_temp,
                "power": self.extruder_power,
            },
            "heater_bed": {
                "temperature": self.bed_temp,
                "power": self.bed_power,
            },
            "virtual_sdcard": {
                "progress": self.progress,
            },
            "heater_generic chamber": {
                "temperature": self.chamber_temp,
            },
        }

    def next_console_msg(self):
        msg = CONSOLE_MESSAGES[self.msg_index % len(CONSOLE_MESSAGES)]
        self.msg_index += 1
        return msg


sim = PrintSim()
connected_ws: set = set()

# ── WebSocket handler ────────────────────────────────────────────────────────

async def ws_handler(request):
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    connected_ws.add(ws)
    log.info("WebSocket client connected")

    try:
        async for msg in ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                data = json.loads(msg.data)
                method = data.get("method", "")
                msg_id = data.get("id")

                if method in ("printer.objects.subscribe", "printer.objects.query"):
                    await ws.send_str(json.dumps({
                        "jsonrpc": "2.0",
                        "result": {
                            "eventtime": time.monotonic(),
                            "status": sim.full_status(),
                        },
                        "id": msg_id,
                    }))
            elif msg.type == aiohttp.WSMsgType.ERROR:
                break
    finally:
        connected_ws.discard(ws)
        log.info("WebSocket client disconnected")

    return ws

# ── Push update loop ─────────────────────────────────────────────────────────

async def push_loop():
    tick = 0
    while True:
        await asyncio.sleep(0.25)
        tick += 1
        if not connected_ws:
            continue

        update = json.dumps({
            "jsonrpc": "2.0",
            "method": "notify_status_update",
            "params": [sim.delta_status(), time.monotonic()],
        })

        # console message every ~15 seconds
        console = None
        if tick % 60 == 0:
            console = json.dumps({
                "jsonrpc": "2.0",
                "method": "notify_gcode_response",
                "params": [sim.next_console_msg()],
            })

        dead = set()
        for ws in list(connected_ws):
            try:
                await ws.send_str(update)
                if console:
                    await ws.send_str(console)
            except Exception:
                dead.add(ws)
        connected_ws.difference_update(dead)

# ── MJPEG stream via ffmpeg ──────────────────────────────────────────────────

async def mjpeg_handler(request):
    video_path = request.app["video_path"]
    response = web.StreamResponse(
        headers={
            "Content-Type": "multipart/x-mixed-replace; boundary=frame",
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
        }
    )
    await response.prepare(request)

    loop = asyncio.get_event_loop()
    log.info("MJPEG stream started")

    try:
        while True:
            proc = await asyncio.create_subprocess_exec(
                "ffmpeg", "-re", "-i", str(video_path),
                "-f", "image2pipe", "-vcodec", "mjpeg",
                "-q:v", "5", "-r", "15", "-",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            buf = b""
            while True:
                chunk = await proc.stdout.read(65536)
                if not chunk:
                    break
                buf += chunk
                # Split on JPEG boundaries
                while True:
                    start = buf.find(b"\xff\xd8")
                    if start == -1:
                        buf = b""
                        break
                    end = buf.find(b"\xff\xd9", start + 2)
                    if end == -1:
                        buf = buf[start:]
                        break
                    frame = buf[start:end + 2]
                    buf = buf[end + 2:]
                    try:
                        await response.write(
                            b"--frame\r\n"
                            b"Content-Type: image/jpeg\r\n"
                            b"Content-Length: " + str(len(frame)).encode() + b"\r\n\r\n"
                            + frame + b"\r\n"
                        )
                    except Exception:
                        proc.kill()
                        return response
            # video ended — loop
            try:
                proc.kill()
            except Exception:
                pass
    except asyncio.CancelledError:
        pass

    return response

# ── MJPEG relay (fan-out from a single upstream connection) ──────────────────

# One asyncio.Queue per connected relay viewer. Frames are distributed to all
# queues; if a client falls behind, the oldest queued frame is dropped so it
# stays close to live without blocking the others.
_relay_clients: set = set()
_RELAY_QUEUE_DEPTH = 3


async def relay_upstream_loop(url: str):
    """Maintain one connection to the real printer and fan frames out to all clients."""
    while True:
        try:
            log.info(f"Connecting to relay stream: {url}")
            # Total timeout disabled (None) so long-lived MJPEG streams don't
            # get cut off; sock_read covers individual read stalls only.
            timeout = aiohttp.ClientTimeout(connect=10, total=None, sock_read=30)
            async with aiohttp.ClientSession(timeout=timeout) as session:
                async with session.get(url) as resp:
                    log.info(f"Relay upstream connected (HTTP {resp.status})")
                    buf = b""
                    while True:
                        chunk = await resp.content.read(65536)
                        if not chunk:
                            log.info("Relay upstream stream ended")
                            break
                        buf += chunk
                        # Extract complete JPEG frames via SOI/EOI markers.
                        while True:
                            start = buf.find(b"\xff\xd8")
                            if start == -1:
                                buf = b""
                                break
                            end = buf.find(b"\xff\xd9", start + 2)
                            if end == -1:
                                buf = buf[start:]
                                break
                            frame = buf[start:end + 2]
                            buf = buf[end + 2:]
                            for q in list(_relay_clients):
                                try:
                                    q.put_nowait(frame)
                                except asyncio.QueueFull:
                                    # Client is lagging — drop the oldest frame.
                                    try:
                                        q.get_nowait()
                                        q.put_nowait(frame)
                                    except Exception:
                                        pass
        except asyncio.CancelledError:
            return
        except Exception as e:
            log.warning(f"Relay upstream error: {e}")

        log.info("Reconnecting in 3s")
        await asyncio.sleep(3)


async def mjpeg_relay_handler(request):
    """Send the relayed stream to one viewer."""
    response = web.StreamResponse(headers={
        "Content-Type": "multipart/x-mixed-replace; boundary=frame",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
    })
    await response.prepare(request)

    q: asyncio.Queue = asyncio.Queue(maxsize=_RELAY_QUEUE_DEPTH)
    _relay_clients.add(q)
    log.info(f"Relay viewer connected ({len(_relay_clients)} total)")

    try:
        while True:
            frame = await q.get()
            await response.write(
                b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: "
                + str(len(frame)).encode()
                + b"\r\n\r\n"
                + frame
                + b"\r\n"
            )
    except (asyncio.CancelledError, Exception):
        pass
    finally:
        _relay_clients.discard(q)
        log.info(f"Relay viewer disconnected ({len(_relay_clients)} remaining)")

    return response


# ── HTTP endpoints ───────────────────────────────────────────────────────────

async def webcams_handler(request):
    host = request.host.split(":")[0]
    port = request.app["port"]
    return web.json_response({
        "result": {
            "webcams": [{
                "name": "Demo Camera",
                "enabled": True,
                "service": "mjpegstreamer",
                "stream_url": f"http://{host}:{port}/webcam",
                "snapshot_url": f"http://{host}:{port}/webcam",
                "flip_horizontal": False,
                "flip_vertical": False,
                "rotation": 0,
            }]
        }
    })

async def metadata_handler(request):
    return web.json_response({"result": {"thumbnails": []}})

# ── App setup ────────────────────────────────────────────────────────────────

async def main():
    parser = argparse.ArgumentParser(description="Mock Moonraker server")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=7125)
    parser.add_argument("--video", default=str(Path(__file__).parent / "demo.mp4"),
                        help="Local video file for the MJPEG stream (requires ffmpeg)")
    parser.add_argument("--relay-stream", default=None, metavar="URL",
                        help="Relay a real printer's MJPEG stream instead of serving "
                             "from a local file. Example: http://192.168.1.50:4408/webcam")
    args = parser.parse_args()

    relay_url = args.relay_stream

    if relay_url is None and not Path(args.video).exists():
        log.error(f"Video file not found: {args.video}  (pass --relay-stream URL to relay a real printer instead)")
        return

    app = web.Application()
    app["port"] = args.port

    webcam_handler = mjpeg_relay_handler if relay_url else mjpeg_handler
    if not relay_url:
        app["video_path"] = args.video

    app.router.add_get("/websocket", ws_handler)
    app.router.add_get("/webcam", webcam_handler)
    app.router.add_get("/server/webcams/list", webcams_handler)
    app.router.add_get("/server/files/metadata", metadata_handler)

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, args.host, args.port)
    await site.start()

    log.info(f"Mock Moonraker running on {args.host}:{args.port}")
    if relay_url:
        log.info(f"Relaying stream from: {relay_url}")
    else:
        log.info(f"Streaming video: {args.video}")

    tasks = [push_loop()]
    if relay_url:
        tasks.append(relay_upstream_loop(relay_url))
    tasks.append(asyncio.Event().wait())  # run forever

    await asyncio.gather(*tasks)

if __name__ == "__main__":
    asyncio.run(main())
