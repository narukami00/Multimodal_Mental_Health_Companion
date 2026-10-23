import asyncio
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

from emotion_client import EmotionClient


def run(coro):
    return asyncio.run(coro)


class _Service:
    """A stand-in for the emotion service's /healthz."""

    def __init__(self, body, status=200):
        outer = self
        self.calls = 0

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                outer.calls += 1
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(body).encode())

            def log_message(self, *args):
                pass

        self.server = HTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.server.shutdown()


def test_a_server_that_does_not_use_the_emotion_service_says_off():
    assert run(EmotionClient(enabled=False).health()) == {"state": "off", "face": False}


def test_switched_on_but_nothing_answering_says_unavailable_not_off():
    c = EmotionClient(base_url="http://127.0.0.1:9", timeout_s=0.2, enabled=True)  # nothing listens on port 9
    assert run(c.health()) == {"state": "unavailable", "face": False}


def test_a_ready_service_says_ready_and_whether_it_reads_faces():
    s = _Service({"ready": True, "face": True})
    try:
        assert run(EmotionClient(base_url=s.url, enabled=True).health()) == {"state": "ready", "face": True}
    finally:
        s.close()


def test_a_service_that_is_still_loading_is_not_ready():
    s = _Service({"ready": False, "face": False})
    try:
        assert run(EmotionClient(base_url=s.url, enabled=True).health())["state"] == "unavailable"
    finally:
        s.close()


def test_a_service_error_is_unavailable_and_does_not_trip_the_breaker():
    s = _Service({"detail": "boom"}, status=500)
    try:
        c = EmotionClient(base_url=s.url, enabled=True)
        assert run(c.health())["state"] == "unavailable"
        assert c.usable  # asking for health never switches the emotion service off for real work
    finally:
        s.close()


def test_the_answer_is_remembered_for_a_few_seconds():
    s = _Service({"ready": True, "face": False})
    try:
        async def twice():
            c = EmotionClient(base_url=s.url, enabled=True)
            return await c.health(), await c.health()
        a, b = run(twice())
        assert a == b and s.calls == 1
    finally:
        s.close()
