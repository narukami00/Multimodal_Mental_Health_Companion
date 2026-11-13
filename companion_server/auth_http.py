"""FastAPI adapters around the model-free authentication service."""
import asyncio
from fastapi import HTTPException, Request, WebSocket
from fastapi.responses import JSONResponse
from auth_service import AuthError, AuthSettings, FirebaseVerifier, SessionRegistry, bearer_identity


class ServerAuth:
    def __init__(self, verifier=None, registry=None):
        self.verifier = verifier
        self.registry = registry if registry is not None else SessionRegistry()

    async def identity(self, authorization):
        try:
            if self.verifier is None:
                self.verifier = FirebaseVerifier(AuthSettings.from_env())
            return await asyncio.to_thread(bearer_identity, authorization, self.verifier)
        except AuthError as exc:
            raise HTTPException(exc.status, exc.detail, headers={"WWW-Authenticate": "Bearer"} if exc.status == 401 else None) from None

    async def http_identity(self, request: Request):
        identity = getattr(request.state, "identity", None)
        return identity if identity is not None else await self.identity(request.headers.get("authorization"))

    async def require_http_session(self, request: Request, session_id: str, purpose="journal"):
        identity = await self.http_identity(request)
        try:
            return self.registry.require(identity, session_id, purpose)
        except AuthError as exc:
            raise HTTPException(exc.status, exc.detail) from None

    async def websocket_identity(self, websocket: WebSocket):
        # Native Flutter supports Authorization headers. Reusable identity tokens must never appear in URLs.
        if any(key in websocket.query_params for key in ("token", "access_token", "id_token")):
            await websocket.close(code=4401)
            return None
        try:
            return await self.identity(websocket.headers.get("authorization"))
        except HTTPException as exc:
            await websocket.close(code=4401 if exc.status_code == 401 else 1013)
            return None


server_auth = ServerAuth()


def protect_api(app, auth=server_auth):
    @app.middleware("http")
    async def authenticate_api(request: Request, call_next):
        if request.url.path.startswith("/v1/") and request.method != "OPTIONS":
            try:
                request.state.identity = await auth.identity(request.headers.get("authorization"))
            except HTTPException as exc:
                return JSONResponse({"detail": exc.detail}, status_code=exc.status_code, headers=exc.headers)
        return await call_next(request)
