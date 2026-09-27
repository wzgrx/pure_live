"""Exercise the real wrapper with a fake wake guard; never invoke ADB."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


WRAPPER = Path(__file__).resolve().parents[1] / "run_android_device_test_turn.ps1"
PWSH = shutil.which("pwsh")
WAKE_FIXTURE = r"""
param([string]$Serial, [switch]$StayAwake, [switch]$ReleaseStayAwake, [int]$RestoreStayAwakeValue, [int]$AcquiredStayAwakeValue)
if ([string]::IsNullOrWhiteSpace($Serial) -and $env:FIXTURE_DEFAULT_SERIAL) { $Serial=$env:FIXTURE_DEFAULT_SERIAL }
if ($ReleaseStayAwake -and ($RestoreStayAwakeValue -ne [int]$env:FIXTURE_ORIGINAL_STAYAWAKE -or $AcquiredStayAwakeValue -ne 7)) { throw 'Wrong stay-awake ownership passed to cleanup' }
@{ serial=$Serial; release=[bool]$ReleaseStayAwake } | ConvertTo-Json -Compress |
    Add-Content -LiteralPath (Join-Path $PSScriptRoot '../calls.jsonl')
if ($env:FIXTURE_WAKE_FAIL -eq '1' -and -not $ReleaseStayAwake) { exit 7 }
if ([string]::IsNullOrWhiteSpace($Serial)) { throw 'Multiple fixture transports; explicit serial required' }
@{ Serial=$Serial; StayAwake=[bool]$StayAwake; OriginalStayAwakeValue=[int]$env:FIXTURE_ORIGINAL_STAYAWAKE; AcquiredStayAwakeValue=7 } | ConvertTo-Json -Compress
exit 0
"""


@unittest.skipUnless(PWSH, "PowerShell is required")
class DeviceTurnTests(unittest.TestCase):
    def run_turn(self, *, environment_serial=None, explicit_serial=None,
                 wake_fail=False, command_fail=False, default_serial=None,
                 mutate_body_serial=False, original_stayawake=0):
        with tempfile.TemporaryDirectory(prefix="purelive-device-turn-") as directory:
            root = Path(directory)
            (root / "tool").mkdir()
            wrapper = root / "tool" / WRAPPER.name
            shutil.copyfile(WRAPPER, wrapper)
            (root / "tool/wake_android_device.ps1").write_text(WAKE_FIXTURE, encoding="utf-8")
            env = os.environ.copy()
            env.pop("PURELIVE_ADB_SERIAL", None)
            if environment_serial is not None:
                env["PURELIVE_ADB_SERIAL"] = environment_serial
            env["FIXTURE_ORIGINAL_STAYAWAKE"] = str(original_stayawake)
            env["FIXTURE_WAKE_FAIL"] = "1" if wake_fail else "0"
            env["FIXTURE_DEFAULT_SERIAL"] = default_serial or ""
            body = "$env:PURELIVE_ADB_SERIAL | Set-Content -LiteralPath body.txt; "
            if mutate_body_serial:
                body += "$env:PURELIVE_ADB_SERIAL='192.0.2.99:5555'; "
            body += "throw 'fixture body failure'" if command_fail else "$global:LASTEXITCODE=0"
            args = [PWSH, "-NoProfile", "-File", str(wrapper), "-NoRotation", "-CommandLine", body]
            if explicit_serial is not None:
                args.extend(["-Serial", explicit_serial])
            result = subprocess.run(args, cwd=root, env=env, capture_output=True, timeout=30)
            calls_file = root / "calls.jsonl"
            calls = [json.loads(line) for line in calls_file.read_text(encoding="utf-8-sig").splitlines()] if calls_file.exists() else []
            body_file = root / "body.txt"
            body_value = body_file.read_text(encoding="utf-8-sig").strip() if body_file.exists() else None
            return result.returncode, calls, body_value

    def test_environment_serial_reaches_wake_body_and_cleanup(self):
        code, calls, body = self.run_turn(environment_serial="192.0.2.10:5555")
        self.assertEqual(code, 0)
        self.assertEqual(body, "192.0.2.10:5555")
        self.assertEqual(calls, [{"serial": body, "release": False}, {"serial": body, "release": True}])

    def test_explicit_serial_overrides_environment(self):
        code, calls, body = self.run_turn(environment_serial="192.0.2.10:5555", explicit_serial="192.0.2.11:5555")
        self.assertEqual(code, 0)
        self.assertEqual(body, "192.0.2.11:5555")
        self.assertTrue(all(call["serial"] == body for call in calls))

    def test_failed_wake_does_not_run_body_or_release_an_unacquired_target(self):
        code, calls, body = self.run_turn(environment_serial="192.0.2.10:5555", wake_fail=True)
        self.assertNotEqual(code, 0)
        self.assertIsNone(body)
        self.assertEqual(calls, [{"serial": "192.0.2.10:5555", "release": False}])

    def test_body_failure_still_releases_the_selected_target(self):
        code, calls, body = self.run_turn(environment_serial="192.0.2.10:5555", command_fail=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(body, "192.0.2.10:5555")
        self.assertEqual(calls[-1], {"serial": body, "release": True})

    def test_serial_is_data_not_interpolated_powershell(self):
        serial = "fixture'; throw 'interpolated'; #"
        code, calls, body = self.run_turn(explicit_serial=serial)
        self.assertEqual(code, 0)
        self.assertEqual(body, serial)
        self.assertTrue(all(call["serial"] == serial for call in calls))

    def test_unique_automatic_selection_still_flows_to_body_and_cleanup(self):
        code, calls, body = self.run_turn(default_serial="192.0.2.12:5555")
        self.assertEqual(code, 0)
        self.assertEqual(body, "192.0.2.12:5555")
        self.assertEqual(calls[-1], {"serial": body, "release": True})

    def test_cleanup_uses_acquired_target_not_body_mutated_environment(self):
        code, calls, body = self.run_turn(environment_serial="192.0.2.10:5555", mutate_body_serial=True)
        self.assertEqual(code, 0)
        self.assertEqual(calls[-1], {"serial": body, "release": True})

    def test_nonzero_original_stayawake_reaches_cleanup_on_success_and_failure(self):
        for fail in (False, True):
            with self.subTest(command_fail=fail):
                code, calls, body = self.run_turn(explicit_serial="192.0.2.10:5555", command_fail=fail, original_stayawake=2)
                self.assertEqual(code == 0, not fail)
                self.assertEqual(calls[-1], {"serial": body, "release": True})


if __name__ == "__main__":
    unittest.main()
