"""Model-free route integration tests; FastAPI/httpx required, no Firebase or ML models."""
import time
import unittest
from auth_service import AuthError, Identity

try:
    from fastapi import FastAPI
    from fastapi.testclient import TestClient
    from starlette.websockets import WebSocketDisconnect
    from auth_http import ServerAuth, protect_api
    from session_api import build_router as sessions_router
    from journal_api import build_router as journal_router
    from video_socket import serve_video
    AVAILABLE = True
except ImportError:
    AVAILABLE = False


@unittest.skipUnless(AVAILABLE, "Install FastAPI and httpx to run HTTP/WebSocket integration tests")
class AuthHttpTests(unittest.TestCase):
    def setUp(self):
        def verifier(token):
            if token not in {"alice", "bob"}:
                raise AuthError(401, "invalid")
            return Identity(token, int(time.time()) + 3600)
        self.auth = ServerAuth(verifier=verifier)
        self.live, self.model_calls = {}, []
        outer = self

        class FakeSession:
            def __init__(self, ws, sid):
                self.ws, self.sid = ws, sid
            def face_allowed(self):
                return True
            async def video_frame(self, jpeg):
                return {"usable": 1}
            async def run(self):
                await self.ws.accept()
                outer.live[self.sid] = self
                try:
                    await self.ws.send_json({"type": "ready"})
                    await self.ws.receive_text()
                finally:
                    if outer.live.get(self.sid) is self:
                        del outer.live[self.sid]

        class FakeEmotion:
            usable = False
        class FakeStt:
            def transcribe(self, *args):
                outer.model_calls.append("stt")
                return "hello", 1.0, "en"
        self.app = FastAPI()
        protect_api(self.app, self.auth)
        self.app.include_router(sessions_router(self.auth, FakeSession, self.live, serve_video))
        self.app.include_router(journal_router(FakeStt(), FakeEmotion(), authorize=self.auth.require_http_session))
        @self.app.get("/v1/model-probe")
        async def probe():
            self.model_calls.append("probe")
            return {"ok": True}
        self.client = TestClient(self.app)

    def headers(self, uid="alice"):
        return {"Authorization": "Bearer " + uid}

    def issue(self, purpose="chat", uid="alice"):
        response = self.client.post("/v1/sessions", headers=self.headers(uid), json={"purpose": purpose})
        self.assertEqual(response.status_code, 200)
        result = response.json()
        self.assertNotIn("token", result)
        self.assertIsInstance(result["expires_at"], int)
        return result["session_id"]

    def test_http_calls_require_identity_before_models(self):
        self.assertEqual(self.client.get("/v1/model-probe").status_code, 401)
        self.assertEqual(self.client.post("/v1/sessions", json={}).status_code, 401)
        self.assertEqual(self.model_calls, [])
        self.assertEqual(self.client.get("/v1/model-probe", headers=self.headers()).status_code, 200)

    def test_journal_rejects_foreign_and_wrong_purpose_sessions(self):
        journal, chat = self.issue("journal"), self.issue()
        for uid, sid in (("bob", journal), ("alice", chat), ("alice", "client-chosen-id")):
            response = self.client.post("/v1/journal/text", headers=self.headers(uid), json={"session_id": sid, "text": "hello"})
            self.assertEqual(response.status_code, 403)
        response = self.client.post("/v1/journal/text", headers=self.headers(), json={"session_id": journal, "text": "hello"})
        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.json()["emotion"])

    def test_every_journal_upload_requires_owner_before_body_processing(self):
        journal = self.issue("journal")
        for endpoint in ("audio", "frame", "face_features"):
            response = self.client.post("/v1/journal/" + endpoint, params={"session_id": journal},
                                        headers=self.headers("bob"), content=b"invalid")
            self.assertEqual(response.status_code, 403)
        self.assertEqual(self.model_calls, [])

    def test_expired_journal_lease_is_refused(self):
        self.auth.registry.ttl_s = 60
        journal = self.issue("journal")
        self.auth.registry.clock = lambda: time.time() + 120
        response = self.client.post("/v1/journal/text", headers=self.headers(), json={"session_id": journal, "text": "hello"})
        self.assertEqual(response.status_code, 403)

    def assertSocketDenied(self, url, headers, code):
        with self.assertRaises(WebSocketDisconnect) as caught:
            with self.client.websocket_connect(url, headers=headers):
                pass
        self.assertEqual(caught.exception.code, code)

    def test_websocket_requires_header_and_ownership(self):
        sid = self.issue()
        url = "/ws/v1/session?session_id=" + sid
        self.assertSocketDenied(url, {}, 4401)
        self.assertSocketDenied(url, self.headers("bob"), 4403)
        self.assertSocketDenied(url + "&token=alice", self.headers(), 4401)
        with self.client.websocket_connect(url, headers=self.headers()) as ws:
            self.assertEqual(ws.receive_json(), {"type": "ready"})
            self.assertSocketDenied(url, self.headers(), 4409)
            ws.send_text("end")

    def test_video_requires_same_owner_and_parent_call(self):
        sid = self.issue()
        url = "/ws/v1/video?session_id=" + sid
        self.assertSocketDenied(url, self.headers("bob"), 4403)
        with self.client.websocket_connect(url, headers=self.headers()) as ws:
            self.assertEqual(ws.receive_json()["reason"], "no_session")
        with self.client.websocket_connect("/ws/v1/session?session_id=" + sid, headers=self.headers()) as call:
            call.receive_json()
            with self.client.websocket_connect(url, headers=self.headers()) as video:
                video.send_json({"type": "video.start"})
                self.assertEqual(video.receive_json()["type"], "video.ready")
                video.send_json({"type": "video.stop"})
            call.send_text("end")


if __name__ == "__main__":
    unittest.main()
