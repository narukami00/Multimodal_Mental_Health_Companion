"""Standard-library tests: no models, Firebase network or external packages."""
import os
import sys
import types
import unittest
from unittest.mock import patch
from auth_service import AuthError, AuthSettings, FirebaseVerifier, Identity, SessionRegistry, bearer_identity


class AuthServiceTests(unittest.TestCase):
    def setUp(self):
        self.now = 1000
        self.registry = SessionRegistry(clock=lambda: self.now, ttl_s=60, capacity=2)
        self.alice = Identity("alice", 2000)
        self.bob = Identity("bob", 2000)

    def assertDenied(self, status, fn):
        with self.assertRaises(AuthError) as caught:
            fn()
        self.assertEqual(caught.exception.status, status)

    def test_owner_and_purpose_are_required(self):
        lease = self.registry.create(self.alice, "journal")
        self.assertEqual(self.registry.require(self.alice, lease.session_id, "journal"), lease)
        self.assertDenied(403, lambda: self.registry.require(self.bob, lease.session_id, "journal"))
        self.assertDenied(403, lambda: self.registry.require(self.alice, lease.session_id, "chat"))

    def test_missing_and_foreign_sessions_are_indistinguishable(self):
        lease = self.registry.create(self.alice)
        errors = []
        for sid in (lease.session_id, "missing"):
            try:
                self.registry.require(self.bob, sid, "chat")
            except AuthError as exc:
                errors.append((exc.status, exc.detail))
        self.assertEqual(errors[0], errors[1])

    def test_expired_sessions_are_refused_and_pruned(self):
        lease = self.registry.create(self.alice)
        self.now = lease.expires_at
        self.assertDenied(403, lambda: self.registry.require(self.alice, lease.session_id, "chat"))
        self.assertFalse(self.registry._leases)

    def test_expired_identity_is_refused_even_for_existing_session(self):
        lease = self.registry.create(self.alice)
        self.assertDenied(401, lambda: self.registry.require(Identity("alice", 999), lease.session_id, "chat"))

    def test_lease_cannot_outlive_identity(self):
        self.assertEqual(self.registry.create(Identity("alice", 1010)).expires_at, 1010)

    def test_random_server_session_ids_and_capacity(self):
        a, b = self.registry.create(self.alice), self.registry.create(self.alice)
        self.assertNotEqual(a.session_id, b.session_id)
        self.assertGreater(len(a.session_id), 30)
        self.assertDenied(503, lambda: self.registry.create(self.bob))

    def test_unknown_purpose_and_expired_create(self):
        self.assertDenied(400, lambda: self.registry.create(self.alice, "arbitrary"))
        self.assertDenied(401, lambda: self.registry.create(Identity("alice", 1000)))

    def test_bearer_is_mandatory_no_static_token_fallback(self):
        def verify(token):
            if token != "fake-valid-token":
                raise AuthError(401, "invalid")
            return self.alice
        for header in (None, "", "Basic fake-valid-token", "Bearer", "Bearer a b", "Bearer local-auth-token", "x" * 17000):
            self.assertDenied(401, lambda: bearer_identity(header, verify))
        self.assertEqual(bearer_identity("Bearer fake-valid-token", verify), self.alice)

    def test_production_rejects_emulator_and_unknown_mode(self):
        for settings in (AuthSettings(""), AuthSettings("p", "none"), AuthSettings("p", "firebase", "127.0.0.1:9099")):
            self.assertDenied(503, settings.validate)
        AuthSettings("p").validate()

    def test_emulator_requires_explicit_loopback_host(self):
        for host in ("", "192.168.1.2:9099", "https://localhost:9099", "localhost", "localhost:9099/path", "u@localhost:9099"):
            self.assertDenied(503, AuthSettings("demo-test", "emulator", host).validate)
        for host in ("localhost:9099", "127.0.0.1:9099", "[::1]:9099"):
            AuthSettings("demo-test", "emulator", host).validate()

    def test_sdk_receives_revocation_check_and_correct_project(self):
        calls = {}
        def initialize(credential, options, name):
            calls["project"] = options["projectId"]
            return object()
        def verify(token, app, check_revoked):
            calls["revoked"] = check_revoked
            return {"uid": "alice", "exp": 9999999999}
        sdk = types.ModuleType("firebase_admin")
        sdk.initialize_app, sdk.auth = initialize, types.SimpleNamespace(verify_id_token=verify)
        with patch.dict(sys.modules, {"firebase_admin": sdk}), patch.dict(os.environ, {}, clear=True):
            self.assertEqual(FirebaseVerifier(AuthSettings("project-test"))("opaque").uid, "alice")
        self.assertEqual(calls, {"project": "project-test", "revoked": True})

    def test_environment_cannot_switch_existing_verifier_to_emulator(self):
        verifier = FirebaseVerifier(AuthSettings("project-test"))
        with patch.dict(os.environ, {"FIREBASE_AUTH_EMULATOR_HOST": "127.0.0.1:9099"}):
            self.assertDenied(503, lambda: verifier("opaque"))

    def test_sdk_rejects_expired_or_missing_uid_claims(self):
        sdk = types.ModuleType("firebase_admin")
        sdk.initialize_app = lambda *args, **kwargs: object()
        with patch.dict(sys.modules, {"firebase_admin": sdk}), patch.dict(os.environ, {}, clear=True):
            for claims in ({"uid": "alice", "exp": 1}, {"exp": 9999999999}, {"uid": "", "exp": 9999999999}):
                sdk.auth = types.SimpleNamespace(verify_id_token=lambda *args, **kwargs: claims)
                self.assertDenied(401, lambda: FirebaseVerifier(AuthSettings("project-test"))("opaque"))

    def test_sdk_errors_do_not_leak_credentials_or_diagnostics(self):
        sdk = types.ModuleType("firebase_admin")
        sdk.initialize_app = lambda *args, **kwargs: object()
        with patch.dict(sys.modules, {"firebase_admin": sdk}), patch.dict(os.environ, {}, clear=True):
            for name, status in (("RevokedIdTokenError", 401), ("UserDisabledError", 401), ("CertificateFetchError", 503)):
                error_class = type(name, (Exception,), {})
                def verify(*args, **kwargs):
                    raise error_class("secret bearer and credential path")
                sdk.auth = types.SimpleNamespace(verify_id_token=verify)
                try:
                    FirebaseVerifier(AuthSettings("project-test"))("opaque")
                    self.fail("Expected authentication failure")
                except AuthError as exc:
                    self.assertEqual(exc.status, status)
                    self.assertNotIn("secret", exc.detail)


if __name__ == "__main__":
    unittest.main()
