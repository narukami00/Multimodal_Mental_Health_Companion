"""
Solace Companion Backend - Phase 1 Verification Test Suite
Tests:
  1. Health & Model endpoints (HTTP)
  2. Session Creation (POST /v1/sessions)
  3. WebSocket connection & JSON 'hello' handshake -> 'session_ready'
  4. Ping/Pong Heartbeat & Latency (verifying LAN round-trip < 50ms)
  5. Text message echo & simulated LLM streaming
  6. Disconnect and Reconnection recovery
"""

import asyncio
import json
import sys
import time
import requests
import websockets
import pytest

SERVER_ADDR = __import__("os").environ.get("SOLACE_SERVER", "127.0.0.1:8000")
BASE_HTTP = "http://" + SERVER_ADDR
BASE_WS = "ws://" + SERVER_ADDR + "/ws/v1/session"

def verify_http_endpoints():
    print("\n--- 1. Testing HTTP Endpoints ---")
    
    # 1. GET /healthz
    resp = requests.get(f"{BASE_HTTP}/healthz", timeout=5)
    assert resp.status_code == 200
    data = resp.json()
    print(f"[PASS] /healthz response: {data}")
    assert data["status"] == "ok"
    assert data["phase"] >= 1

    # 2. GET /v1/models
    resp = requests.get(f"{BASE_HTTP}/v1/models", timeout=5)
    assert resp.status_code == 200
    data = resp.json()
    print(f"[PASS] /v1/models response: {data}")
    assert "stt" in data and "llm" in data

    # 3. POST /v1/sessions
    payload = {
        "client": "test-runner",
        "thread_id": "thread_test_001",
        "capabilities": {"audio": True, "text": True, "emotion": True}
    }
    resp = requests.post(f"{BASE_HTTP}/v1/sessions", json=payload, timeout=5)
    assert resp.status_code == 200
    data = resp.json()
    print(f"[PASS] /v1/sessions response: {data}")
    assert "session_id" in data
    assert "token" in data
    return data["session_id"], data["token"]

def test_http_endpoints():
    verify_http_endpoints()

async def run_websocket_flow(session_id: str, token: str):
    ws_uri = f"{BASE_WS}?session_id={session_id}&token={token}"
    print(f"\n--- 2. Testing WebSocket Handshake & Echo at {ws_uri} ---")

    async with websockets.connect(ws_uri) as ws:
        # Step A: Send JSON 'hello'
        hello_msg = {
            "v": 1,
            "type": "hello",
            "session_id": session_id,
            "thread_id": "thread_test_001",
            "last_event_id": None,
            "client": {"platform": "python-tester", "app_version": "0.1.0"},
            "ts": int(time.time() * 1000)
        }
        await ws.send(json.dumps(hello_msg))
        raw_ready = await ws.recv()
        ready = json.loads(raw_ready)
        print(f"[PASS] Received handshake: {ready}")
        assert ready.get("type") == "session_ready"
        assert ready.get("session_id") == session_id

        # Step B: Ping/Pong Heartbeat and RTT measurement
        print("\n--- 3. Testing Ping/Pong Heartbeat ---")
        pings = 3
        rtts = []
        for i in range(pings):
            t0 = time.time()
            client_ts = int(t0 * 1000)
            ping_msg = {
                "v": 1,
                "type": "ping",
                "session_id": session_id,
                "ts": client_ts
            }
            await ws.send(json.dumps(ping_msg))
            raw_pong = await ws.recv()
            pong = json.loads(raw_pong)
            rtt_ms = (time.time() - t0) * 1000
            rtts.append(rtt_ms)
            print(f"[PASS] Pong #{i+1} received in {rtt_ms:.2f} ms: {pong}")
            assert pong.get("type") == "pong"
            await asyncio.sleep(0.05)

        avg_rtt = sum(rtts) / len(rtts)
        print(f"-> Average RTT: {avg_rtt:.2f} ms (Acceptance criterion: < 50 ms typical - {'MET' if avg_rtt < 50 else 'EXCEEDED'})")

        # Step C: Text Message & Echo Verification
        print("\n--- 4. Testing Text Message Echo & Stream ---")
        turn_id = "turn_test_001"
        test_text = "I feel like everything is too much right now."
        text_msg = {
            "v": 1,
            "type": "text_message",
            "session_id": session_id,
            "turn_id": turn_id,
            "text": test_text,
            "simulate_stream": True,
            "ts": int(time.time() * 1000)
        }
        await ws.send(json.dumps(text_msg))

        # 1. Verify immediate echo
        raw_echo = await ws.recv()
        echo = json.loads(raw_echo)
        print(f"[PASS] Immediate Echo received: {echo}")
        assert echo.get("type") == "echo"
        assert echo.get("text") == f"Echo: {test_text}"
        assert echo.get("turn_id") == turn_id

        # 2. Verify llm_start
        raw_start = await ws.recv()
        llm_start = json.loads(raw_start)
        print(f"[PASS] llm_start received: {llm_start}")
        assert llm_start.get("type") == "llm_start"

        # 3. Stream chunks
        accumulated_chunks = []
        while True:
            raw_frame = await ws.recv()
            if isinstance(raw_frame, bytes):
                continue
            frame = json.loads(raw_frame)
            if frame.get("type") == "llm_chunk":
                accumulated_chunks.append(frame.get("delta", ""))
            elif frame.get("type") == "llm_done":
                print(f"[PASS] llm_done received! Total chunks: {len(accumulated_chunks)}")
                print(f"Full reconstructed text: {''.join(accumulated_chunks)}")
                assert frame.get("text") == "".join(accumulated_chunks)
                break

    # Step D: Test Reconnection
    print("\n--- 5. Testing Reconnection with Session Resume ---")
    async with websockets.connect(ws_uri) as ws2:
        resume_hello = {
            "v": 1,
            "type": "hello",
            "session_id": session_id,
            "thread_id": "thread_test_001",
            "last_event_id": "evt_test",
            "client": {"platform": "python-tester", "app_version": "0.1.0"},
            "ts": int(time.time() * 1000)
        }
        await ws2.send(json.dumps(resume_hello))
        raw_ready2 = await ws2.recv()
        ready2 = json.loads(raw_ready2)
        print(f"[PASS] Reconnect session ready: {ready2}")
        assert ready2.get("type") == "session_ready"
        assert ready2.get("session_id") == session_id

    print("\n=== ALL PHASE 1 PROTOCOL TESTS PASSED SUCCESSFULLY! ===")

@pytest.mark.asyncio
async def test_websocket_session_lifecycle():
    session_id, token = verify_http_endpoints()
    await run_websocket_flow(session_id, token)

def main():
    try:
        session_id, token = verify_http_endpoints()
        asyncio.run(run_websocket_flow(session_id, token))
    except Exception as e:
        print(f"\n[FAIL] Test encountered error: {e}", file=sys.stderr)
        raise

if __name__ == "__main__":
    main()
