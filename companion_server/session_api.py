"""Authenticated session issuance and native WebSocket routes; models injected by main."""
import asyncio
import time
from typing import Any, Dict, List, Optional, Literal
from fastapi import APIRouter, Query, Request, WebSocket, HTTPException
from pydantic import BaseModel, Field
from auth_service import AuthError

class CreateSessionRequest(BaseModel):
    purpose: Literal["chat", "journal"] = "chat"
    client: str = Field(default="flutter-client", description="Client identifier/platform")
    thread_id: Optional[str] = Field(default=None, description="Thread or conversation ID")
    capabilities: Optional[Dict[str, bool]] = Field(
        default_factory=lambda: {"audio": True, "text": True, "emotion": True}
    )

class CreateSessionResponse(BaseModel):
    session_id: str
    ws_url: str
    expires_at: int


class ConversationTitleRequest(BaseModel):
    turns: List[Dict[str, str]] = Field(default_factory=list)


class ConversationTitleResponse(BaseModel):
    title: str


def build_router(auth, session_factory, live, video_handler, llm=None):
    router = APIRouter()
    connecting = set()
    @router.post("/v1/sessions", response_model=CreateSessionResponse)
    async def create_session(req: CreateSessionRequest, request: Request):
        """Session initiation endpoint per specifications section 11."""
        try:
            lease = auth.registry.create(await auth.http_identity(request), req.purpose)
        except AuthError as exc:
            raise HTTPException(exc.status, exc.detail) from None
        return CreateSessionResponse(
            session_id=lease.session_id,
            ws_url="/ws/v1/session",
            expires_at=lease.expires_at
        )


    @router.websocket("/ws/v1/session")
    async def websocket_session(
        websocket: WebSocket,
        session_id: str = Query(...),
    ):
        """One client connection: chat, push-to-talk voice and live duplex calls.

        The protocol and the turn-taking live in `session.Session`.
        """
        identity = await auth.websocket_identity(websocket)
        if identity is None:
            return
        try:
            lease = auth.registry.require(identity, session_id, "chat")
        except AuthError:
            await websocket.close(code=4403)
            return
        if session_id in live or session_id in connecting:
            await websocket.close(code=4409)  # one active transport per issued chat session
            return
        connecting.add(session_id)
        try:
            await asyncio.wait_for(session_factory(websocket, session_id).run(),
                                   timeout=max(0.01, min(lease.expires_at, identity.expires_at) - time.time()))
        except asyncio.TimeoutError:
            await websocket.close(code=4401)
        finally:
            connecting.discard(session_id)


    @router.websocket("/ws/v1/video")
    async def websocket_video(websocket: WebSocket, session_id: str = Query(...)):
        """Camera frames for the optional emotion module (own socket; refused without the app's separate camera consent)."""
        identity = await auth.websocket_identity(websocket)
        if identity is None:
            return
        try:
            lease = auth.registry.require(identity, session_id, "chat")
        except AuthError:
            await websocket.close(code=4403)
            return
        try:
            await asyncio.wait_for(video_handler(websocket, session_id, live),
                                   timeout=max(0.01, min(lease.expires_at, identity.expires_at) - time.time()))
        except asyncio.TimeoutError:
            await websocket.close(code=4401)

    @router.post("/v1/conversations/title", response_model=ConversationTitleResponse)
    async def conversation_title(req: ConversationTitleRequest, request: Request):
        """Generate a short 2-5 word thread title via the companion LLM."""
        try:
            await auth.http_identity(request)
        except AuthError as exc:
            raise HTTPException(exc.status, exc.detail) from None
        title = await llm.generate_title_async(req.turns) if llm is not None else ""
        return ConversationTitleResponse(title=title)


    return router
