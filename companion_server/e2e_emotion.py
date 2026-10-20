"""End-to-end check of the emotion integration against the RUNNING companion copy (ws://127.0.0.1:8010) and emotion service (:8766).

For text messages and one recorded voice turn it prints what the app would see (emotion.update, safety.flag), the reply, and the time
from the end of the user's turn to the start of the reply, once WITH the app's opt-in and once WITHOUT it (the A/B shows the extra
delay and the change in the reply).  Validation-split clips only.
  face/Scripts/python e2e_emotion.py
"""
import asyncio
import json
import struct
import sys
import time

import numpy as np
import websockets

sys.path.insert(0, "F:/__Downloads/dataset/scripts/modeling")
from bench_common import load_audio  # noqa: E402
from fusion_data import manifest  # noqa: E402

URL = "ws://127.0.0.1:8010/ws/v1/session"
STREAM_ID = 1001


async def session(emotion: bool):
    ws = await websockets.connect(URL, max_size=None)
    await ws.send(json.dumps({"type": "hello", "session_id": "e2e", "thread_id": "t"}))
    events = []

    async def pump():
        async for m in ws:
            if isinstance(m, bytes):
                continue
            e = json.loads(m)
            e["_t"] = time.monotonic()
            events.append(e)
    task = asyncio.create_task(pump())
    cfg = {"type": "session.configure", "mode": "duplex_call", "tts": {"enabled": False}}
    if emotion:
        cfg["emotion"] = {"enabled": True}
    await ws.send(json.dumps(cfg))
    await wait(events, "session.ready")
    return ws, events, task


async def wait(events, kind, after=0, timeout=40):
    t0 = time.monotonic()
    while time.monotonic() - t0 < timeout:
        for e in events[after:]:
            if e["type"] == kind:
                return e
        await asyncio.sleep(0.02)
    raise TimeoutError(f"no {kind}; saw {[e['type'] for e in events][-12:]}")


def reply_text(events, after=0):
    parts = []
    for e in events[after:]:
        if e["type"] in ("llm_chunk", "llm_token", "llm_delta"):
            parts.append(e.get("text") or e.get("delta") or e.get("chunk") or "")
    return "".join(parts).strip()


async def text_turn(emotion: bool, text: str):
    ws, events, task = await session(emotion)
    n = len(events)
    t0 = time.monotonic()
    await ws.send(json.dumps({"type": "text_message", "turn_id": "t1", "text": text}))
    await wait(events, "llm_done", n)
    start = await wait(events, "llm_start", n)
    upd = [e for e in events[n:] if e["type"] == "emotion.update"]
    flag = [e for e in events[n:] if e["type"] == "safety.alert"]
    out = dict(first_reply_ms=int(1000 * (start["_t"] - t0)), reply=reply_text(events, n)[:230], update=upd[0] if upd else None, flag=flag[0] if flag else None)
    task.cancel()
    await ws.close()
    return out


async def voice_turn(emotion: bool, pcm16: np.ndarray):
    ws, events, task = await session(emotion)
    await ws.send(json.dumps({"type": "call.listen", "sample_rate": 16000, "barge_in": False}))
    await wait(events, "call.listening")
    n = len(events)
    seq = 0
    frames = list(pcm16.reshape(-1, 320)) + [np.zeros(320, np.int16)] * 90  # 1.8 s of silence ends the turn
    for f in frames:
        await ws.send(struct.pack("<II", STREAM_ID, seq) + f.astype("<i2").tobytes())
        seq += 1
        await asyncio.sleep(0.004)  # faster than real time; the server's VAD counts samples, not wall-clock
    ended = await wait(events, "turn.endpointed", n)
    start = await wait(events, "llm_start", n)
    await wait(events, "llm_done", n)
    upd = [e for e in events[n:] if e["type"] == "emotion.update"]
    flag = [e for e in events[n:] if e["type"] == "safety.alert"]
    tf = [e for e in events[n:] if e["type"] == "transcript_final"]
    out = dict(endpoint_to_reply_ms=int(1000 * (start["_t"] - ended["_t"])), transcript=tf[0]["text"] if tf else None,
               reply=reply_text(events, n)[:230], update=upd[0] if upd else None, flag=flag[0] if flag else None)
    task.cancel()
    await ws.close()
    return out


def show(title, o):
    u = o.get("update")
    print(f"  {title}: " + (f"emotion.update mood={u['mood']!r} tier={u['tier']} pattern={u['pattern']} val={u['valence']:+.2f} aro={u['arousal']:+.2f} cue_used={u['cue_used']}" if u else "no emotion.update")
          + (f" | SAFETY FLAG {o['flag']['level']}" if o.get("flag") else ""))
    print(f"     timing: {o.get('first_reply_ms', o.get('endpoint_to_reply_ms'))} ms to reply start | reply: {o['reply']!r}")


async def main():
    print("TEXT TURNS")
    for text in ["I feel so alone and exhausted lately.", "I got the job today and I am so happy about it!", "I will kill myself."]:
        print(f"\n> {text!r}")
        show("emotion OFF", await text_turn(False, text))
        show("emotion ON ", await text_turn(True, text))
    man = manifest().set_index("sample_id")
    for sid in ["iemocap__Ses04F_impro01_F008", "mosei__-571d8cVauQ__0"]:
        r = man.loc[sid]
        w = load_audio(r.audio_relpath, max_s=30)
        w = np.concatenate([np.zeros(3200, np.float32), w])
        pcm = (np.clip(w, -1, 1) * 32767).astype(np.int16)
        pcm = pcm[: len(pcm) // 320 * 320]
        print(f"\nVOICE TURN {sid} (label {r.emo_label}), {len(w) / 16000:.1f} s")
        show("emotion OFF", await voice_turn(False, pcm))
        show("emotion ON ", await voice_turn(True, pcm))


if __name__ == "__main__":
    asyncio.run(main())
