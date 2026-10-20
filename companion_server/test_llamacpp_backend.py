"""The llama.cpp backend of `LlmService`, against a tiny fake `llama-server` (no model, no GPU).

What must hold: it is used when a server answers /health, it streams the reply and asks for non-thinking mode, it stops reading when
cancelled, and when the server is absent or goes away the built-in model takes over instead of the reply failing.
Run: python -m pytest test_llamacpp_backend.py
"""
import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Any, Dict, List

import pytest

import llm_service
from llm_service import LLAMACPP_URL_ENV, LlmService

MESSAGES = [{"role": "system", "content": "be kind"}, {"role": "user", "content": "hello"}]


class FakeLlamaServer:
    def __init__(self, pieces: List[str], health: str = "ok") -> None:
        self.pieces, self.health = pieces, health
        self.requests: List[Dict[str, Any]] = []
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):  # keep the test output quiet
                pass

            def do_GET(self):
                body = json.dumps({"status": outer.health}).encode()
                self.send_response(200 if outer.health == "ok" else 503)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                size = int(self.headers.get("Content-Length", 0))
                outer.requests.append(json.loads(self.rfile.read(size)))
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                try:
                    for piece in outer.pieces:
                        chunk = {"choices": [{"delta": {"content": piece}}]}
                        self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
                        self.wfile.flush()
                    self.wfile.write(b'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n\ndata: [DONE]\n\n')
                except OSError:
                    pass

        self.httpd = HTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()


@pytest.fixture
def fake(monkeypatch):
    servers: List[FakeLlamaServer] = []

    def make(pieces, health="ok"):
        s = FakeLlamaServer(pieces, health)
        servers.append(s)
        monkeypatch.setenv(LLAMACPP_URL_ENV, s.url)
        return s

    yield make
    for s in servers:
        s.close()


def test_streams_the_reply_and_asks_for_non_thinking_mode(fake, monkeypatch):
    monkeypatch.setenv("SOLACE_LLM_BACKEND", "llamacpp")
    server = fake(["That ", "sounds ", "lovely."])
    llm = LlmService()
    assert llm.initialize() is True and llm.backend == "llamacpp"
    reply = "".join(llm.generate_stream(MESSAGES, max_new_tokens=40, temperature=0.3, top_p=0.8))
    assert reply == "That sounds lovely."
    sent = server.requests[0]
    assert sent["messages"] == MESSAGES
    assert sent["chat_template_kwargs"] == {"enable_thinking": False}
    assert sent["stream"] is True and sent["max_tokens"] == 40 and sent["temperature"] == 0.3


def test_cancelling_stops_the_stream(fake, monkeypatch):
    monkeypatch.setenv("SOLACE_LLM_BACKEND", "llamacpp")
    fake([f"word{i} " for i in range(50)])
    llm = LlmService()
    llm.initialize()
    cancel = threading.Event()
    got: List[str] = []
    for piece in llm.generate_stream(MESSAGES, cancel=cancel):
        got.append(piece)
        if len(got) == 3:
            cancel.set()
    assert 3 <= len(got) < 50


def test_a_server_whose_model_is_not_loaded_is_not_used(fake, monkeypatch):
    monkeypatch.setenv("SOLACE_LLM_BACKEND", "llamacpp")
    fake(["x"], health="loading model")
    llm = LlmService()
    monkeypatch.setattr(llm, "_initialize_ct2", lambda: (_ for _ in ()).throw(RuntimeError("no built-in model in this test")))
    monkeypatch.setattr(llm, "_initialize_hf", lambda t0: False)
    assert llm.initialize() is False and llm._llama_url is None


def test_a_server_that_goes_away_hands_over_to_the_built_in_model(fake, monkeypatch):
    monkeypatch.setenv("SOLACE_LLM_BACKEND", "llamacpp")
    server = fake(["unused"])
    llm = LlmService()
    llm.initialize()
    server.close()  # the server dies after start-up

    def builtin():
        llm._ct2_generator = object()
        llm.backend, llm._is_ready = "ctranslate2", True

    monkeypatch.setattr(llm, "_initialize_ct2", builtin)
    monkeypatch.setattr(llm, "_generate_ct2", lambda *a, **k: iter(["from the built-in model"]))
    assert "".join(llm.generate_stream(MESSAGES)) == "from the built-in model"
    assert llm.backend == "ctranslate2" and llm._llama_url is None


def test_the_default_is_still_the_built_in_model_when_no_server_is_running(monkeypatch):
    monkeypatch.delenv("SOLACE_LLM_BACKEND", raising=False)
    monkeypatch.setenv(LLAMACPP_URL_ENV, "http://127.0.0.1:9")  # nothing listens here
    llm = LlmService()
    monkeypatch.setattr(llm, "_initialize_ct2", lambda: (setattr(llm, "backend", "ctranslate2"), setattr(llm, "_is_ready", True)))
    assert llm.initialize() is True and llm.backend == "ctranslate2"
    assert llm_service.DEFAULT_LLAMACPP_URL.startswith("http://127.0.0.1")
