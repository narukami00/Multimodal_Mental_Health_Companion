"""Firebase identity verification and owner-bound ephemeral inference sessions.

No ML imports. The only development mode is the explicit Firebase Auth emulator;
there is no anonymous or static-token authentication fallback.
"""
from dataclasses import dataclass
import ipaddress
import os
import secrets
import threading
import time
from typing import Callable, Optional
from urllib.parse import urlsplit


class AuthError(Exception):
    def __init__(self, status: int, detail: str):
        super().__init__(detail)
        self.status, self.detail = status, detail


@dataclass(frozen=True)
class Identity:
    uid: str
    expires_at: int


@dataclass(frozen=True)
class AuthSettings:
    project_id: str
    mode: str = "firebase"
    emulator_host: str = ""

    @classmethod
    def from_env(cls):
        settings = cls(os.environ.get("SOLACE_FIREBASE_PROJECT_ID", "").strip(),
                       os.environ.get("SOLACE_AUTH_MODE", "firebase").strip(),
                       os.environ.get("FIREBASE_AUTH_EMULATOR_HOST", "").strip())
        settings.validate()
        return settings

    def validate(self):
        if not self.project_id or self.mode not in {"firebase", "emulator"}:
            raise AuthError(503, "Configure a Firebase project and a supported authentication mode")
        if self.mode == "firebase" and self.emulator_host:
            raise AuthError(503, "Emulator configuration is forbidden in Firebase production mode")
        if self.mode == "emulator":
            parsed = urlsplit("//" + self.emulator_host)
            try:
                loopback = parsed.hostname == "localhost" or ipaddress.ip_address(parsed.hostname or "").is_loopback
                valid = loopback and parsed.port is not None and parsed.port > 0 and not parsed.path and not parsed.query and not parsed.fragment and not parsed.username and not parsed.password
            except ValueError:
                valid = False
            if not valid:
                raise AuthError(503, "Emulator mode requires a loopback FIREBASE_AUTH_EMULATOR_HOST host:port")


class FirebaseVerifier:
    def __init__(self, settings: AuthSettings):
        settings.validate()
        self.settings = settings
        self._app = None
        self._lock = threading.Lock()

    def __call__(self, token: str) -> Identity:
        try:
            if os.environ.get("FIREBASE_AUTH_EMULATOR_HOST", "").strip() != self.settings.emulator_host:
                raise AuthError(503, "Authentication environment changed; restart the server")
            import firebase_admin
            from firebase_admin import auth
            with self._lock:
                if self._app is None:
                    # ADC for production; emulator also uses the SDK's explicit emulator path.
                    credential = None
                    if self.settings.mode == "emulator":
                        from firebase_admin import credentials
                        from google.auth.credentials import AnonymousCredentials

                        class EmulatorCredential(credentials.Base):
                            def get_credential(self):
                                return AnonymousCredentials()

                        credential = EmulatorCredential()
                    self._app = firebase_admin.initialize_app(credential, options={"projectId": self.settings.project_id},
                                                              name="solace-" + secrets.token_hex(8))
            raw_revoked = os.environ.get("SOLACE_FIREBASE_CHECK_REVOKED", "").strip().lower()
            check_revoked = (
                self.settings.mode == "firebase"
                if raw_revoked == ""
                else raw_revoked in {"1", "true", "yes", "on"}
            )
            claims = auth.verify_id_token(token, app=self._app, check_revoked=check_revoked)
            uid, expiry = claims.get("uid"), claims.get("exp")
            if not isinstance(uid, str) or not uid or not isinstance(expiry, (int, float)) or expiry <= time.time():
                raise AuthError(401, "Invalid or expired identity token")
            return Identity(uid, int(expiry))
        except AuthError:
            raise
        except ImportError:
            raise AuthError(503, "Firebase authentication dependencies are unavailable") from None
        except Exception as exc:
            # Never return SDK diagnostics containing token, account or credential details.
            if type(exc).__name__ in {"InvalidIdTokenError", "ExpiredIdTokenError", "RevokedIdTokenError", "UserDisabledError", "UserNotFoundError", "ValueError"}:
                raise AuthError(401, "Invalid or expired identity token") from None
            raise AuthError(503, "Identity verification is temporarily unavailable") from None


def bearer_identity(authorization: Optional[str], verifier: Callable[[str], Identity]) -> Identity:
    if not authorization or len(authorization) > 16384:
        raise AuthError(401, "Sign in to use the companion server")
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise AuthError(401, "A Firebase bearer identity token is required")
    return verifier(parts[1])


@dataclass(frozen=True)
class Lease:
    session_id: str
    owner_uid: str
    purpose: str
    expires_at: int


class SessionRegistry:
    def __init__(self, clock=time.time, ttl_s=3600, capacity=10000):
        self.clock, self.ttl_s, self.capacity = clock, ttl_s, capacity
        self._leases = {}

    def _prune(self):
        for sid in [sid for sid, lease in self._leases.items() if lease.expires_at <= self.clock()]:
            del self._leases[sid]

    def create(self, identity: Identity, purpose="chat") -> Lease:
        self._prune()
        if purpose not in {"chat", "journal"}:
            raise AuthError(400, "Unknown session purpose")
        if identity.expires_at <= self.clock():
            raise AuthError(401, "Identity token has expired")
        if len(self._leases) >= self.capacity:
            raise AuthError(503, "Session capacity reached; try again later")
        sid = "sess_" + secrets.token_urlsafe(24)
        lease = Lease(sid, identity.uid, purpose, min(identity.expires_at, int(self.clock()) + self.ttl_s))
        self._leases[sid] = lease
        return lease

    def require(self, identity: Identity, session_id: str, purpose: str) -> Lease:
        self._prune()
        lease = self._leases.get(session_id)
        if identity.expires_at <= self.clock():
            raise AuthError(401, "Identity token has expired")
        if lease is None or lease.owner_uid != identity.uid or lease.purpose != purpose:
            # Do not disclose whether another person's session exists.
            raise AuthError(403, "Session is unavailable or does not belong to this account")
        return lease
