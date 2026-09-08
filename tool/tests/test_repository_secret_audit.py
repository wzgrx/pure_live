"""Narrow public-fixture exception; ordinary secret scanning stays strict."""
import hashlib
import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("repository_audit", ROOT / "tool/audit_repository.py")
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)
FIXTURE = "test/fixtures/tls/localhost-key.pem"


class RepositorySecretAuditTest(unittest.TestCase):
    def scan(self, path, data):
        return audit.secret_findings(path, data.decode("utf-8"), hashlib.sha256(data).hexdigest())

    def test_exact_reviewed_fixture_is_reported_but_not_a_secret_failure(self):
        errors, notes = self.scan(FIXTURE, (ROOT / FIXTURE).read_bytes())
        self.assertEqual(errors, [])
        self.assertEqual(len(notes), 1)
        self.assertEqual(notes[0]["rule"], "reviewed_public_tls_test_key")

    def test_same_public_key_outside_the_exact_path_is_rejected(self):
        data = (ROOT / FIXTURE).read_bytes()
        for path in ("android/key.pem", "test/fixtures/tls/other-key.pem", "test/another/key.pem"):
            with self.subTest(path=path):
                errors, notes = self.scan(path, data)
                self.assertEqual(errors[0]["rule"], "private_key")
                self.assertEqual(notes, [])

    def test_modified_or_replaced_key_at_fixture_path_is_rejected(self):
        data = (ROOT / FIXTURE).read_bytes()
        for changed in (data + b"\n", data.replace(b"\n", b"\r\n"), data.replace(b"M", b"N", 1)):
            with self.subTest(size=len(changed)):
                errors, notes = self.scan(FIXTURE, changed)
                self.assertEqual(errors[0]["rule"], "private_key")
                self.assertEqual(notes, [])

    def test_missing_digest_never_exempts_a_fixture(self):
        errors, notes = audit.secret_findings(FIXTURE, (ROOT / FIXTURE).read_text())
        self.assertEqual(errors[0]["rule"], "private_key")
        self.assertEqual(notes, [])

    def test_appending_a_token_triggers_both_rules(self):
        data = (ROOT / FIXTURE).read_bytes() + ("ghp_" + "A" * 30).encode()
        errors, notes = self.scan(FIXTURE, data)
        self.assertEqual({e["rule"] for e in errors}, {"private_key", "github_token"})
        self.assertEqual(notes, [])

    def test_other_secret_types_are_never_exempted_even_with_a_matching_digest(self):
        digest = audit.PUBLIC_TLS_TEST_KEYS[FIXTURE]
        for token, rule in (("ghp_" + "A" * 30, "github_token"), ("AKIA" + "A" * 16, "aws_access_key")):
            errors, notes = audit.secret_findings(FIXTURE, token, digest)
            self.assertEqual(errors[0]["rule"], rule)
            self.assertEqual(notes, [])


if __name__ == "__main__":
    unittest.main()
