"""The camera-frame socket (`/ws/v1/video`): upright JPEG frames for the emotion module, on a socket of their own so large images can
never delay the 20 ms microphone frames of the call socket.

Protocol (all additive; nothing here touches the call protocol)
  app -> server  text   {"type": "video.start", "codec": "jpeg", "width": 360, "height": 640, "fps": 5, "upright": true}
  app -> server  binary <uint32 little-endian seq><JPEG bytes>   (upright, no EXIF rotation needed, quality ~70)
  app -> server  text   {"type": "video.stop"}
  server -> app  text   {"type": "video.ready"}   or   {"type": "video.refused", "reason": "no_session" | "no_consent" | "bad_start"}
  server -> app  text   {"type": "video.ack", "seq": N, "usable": 0 | 1 | null, "dropped": K}   one per frame

Rules: consent is checked on the session and again on EVERY frame (revoking the camera in the app stops analysis at the next frame);
a refused frame is never decoded; at most one frame is in flight (the rest are dropped and counted); frames are not stored, logged or
written anywhere here (the emotion service keeps only derived numbers, in memory).
"""
import asyncio
import json
import logging
import struct
import time
from typing import Any, Dict

from fastapi import WebSocket, WebSocketDisconnect

logger = logging.getLogger("solace_companion.video")

MAX_FRAME_BYTES = 2_000_000
MIN_FRAME_GAP_S = 0.08  # more than ~12 frames per second is never useful and would only load the service
SEQ = struct.Struct("<I")
REFUSED_CODE = 4403


async def serve_video(websocket: WebSocket, session_id: str, live: Dict[str, Any]) -> None:
    await websocket.accept()
    session = live.get(session_id)
    if session is None or not session.face_allowed():
        await websocket.send_json({"type": "video.refused", "reason": "no_session" if session is None else "no_consent"})
        await websocket.close(code=REFUSED_CODE)
        return

    inflight: "asyncio.Task[None] | None" = None
    dropped, last_at, started = 0, 0.0, False

    async def forward(seq: int, jpeg: bytes) -> None:
        result = await session.video_frame(jpeg)
        if "refused" in result:
            await websocket.send_json({"type": "video.refused", "reason": result["refused"]})
            await websocket.close(code=REFUSED_CODE)
            return
        await websocket.send_json({"type": "video.ack", "seq": seq, "usable": result.get("usable"), "dropped": dropped})

    try:
        while True:
            message = await websocket.receive()
            if message.get("type") == "websocket.disconnect":
                break
            text, data = message.get("text"), message.get("bytes")
            if text is not None:
                try:
                    kind = json.loads(text).get("type")
                except (ValueError, AttributeError):
                    kind = None
                if kind == "video.start":
                    started = True
                    await websocket.send_json({"type": "video.ready"})
                elif kind == "video.stop":
                    break
                continue
            if data is None:
                continue
            if not started:
                await websocket.send_json({"type": "video.refused", "reason": "bad_start"})
                await websocket.close(code=REFUSED_CODE)
                return
            if not session.face_allowed():  # consent can be withdrawn mid-call: stop at the very next frame, decode nothing
                await websocket.send_json({"type": "video.refused", "reason": "no_consent"})
                await websocket.close(code=REFUSED_CODE)
                return
            now = time.monotonic()
            if len(data) <= SEQ.size or len(data) > MAX_FRAME_BYTES or now - last_at < MIN_FRAME_GAP_S or (inflight and not inflight.done()):
                dropped += 1
                continue
            last_at = now
            (seq,) = SEQ.unpack_from(data)
            inflight = asyncio.ensure_future(forward(seq, data[SEQ.size:]))
    except WebSocketDisconnect:
        pass
    except Exception as e:
        logger.warning(f"video socket for {session_id} ended: {type(e).__name__}")
    finally:
        if inflight is not None and not inflight.done():
            inflight.cancel()
