"""Run the real wake guard against an in-process PowerShell fake, never ADB."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


WAKE = Path(__file__).resolve().parents[1] / "wake_android_device.ps1"
PWSH = shutil.which("pwsh")
HARNESS = r"""
$ErrorActionPreference='Stop'
$global:fixture=Get-Content -LiteralPath "$PSScriptRoot/config.json" -Raw | ConvertFrom-Json
$global:value=[string]$fixture.value
$global:failed=$false
$global:reads=0
function global:adb.exe {
    $a=@($args | ForEach-Object { [string]$_ })
    ConvertTo-Json -InputObject $a -Compress | Add-Content -LiteralPath "$PSScriptRoot/calls.jsonl"
    $global:LASTEXITCODE=0
    if (($a -join ' ') -eq 'devices') { "List of devices attached"; "192.0.2.10:5555`tdevice"; return }
    if ($a[0] -ne '-s' -or $a[1] -ne '192.0.2.10:5555') { throw 'Unexpected target' }
    $c=$a[2..($a.Count-1)] -join ' '
    switch -Regex ($c) {
        '^shell getprop ro.product.model$' { $fixture.model; return }
        '^shell getprop ro.product.device$' { $fixture.device; return }
        '^shell settings get global stay_on_while_plugged_in$' {
            $global:reads++
            if ($fixture.change_during_wake -and $global:reads -eq 2) { $global:value='3' }
            $global:value; return
        }
        '^shell settings put global stay_on_while_plugged_in (\d+)$' {
            $global:value=$Matches[1]
            if ($fixture.acquire_ack_failure -and -not $global:failed -and $global:value -eq '7') {
                $global:failed=$true; $global:LASTEXITCODE=1; 'fixture lost acknowledgement'
            }
            return
        }
        '^shell dumpsys window policy$' { 'mKeyguardShowing=false'; return }
        '^shell input keyevent KEYCODE_WAKEUP$' { return }
        '^shell wm dismiss-keyguard$' { return }
        default { throw "Unexpected command: $c" }
    }
}
$p=@{Serial='192.0.2.10:5555'}
if ($fixture.release) {
    $p.ReleaseStayAwake=$true
    if ($fixture.include_ownership) { $p.RestoreStayAwakeValue=[int]$fixture.original; $p.AcquiredStayAwakeValue=7 }
} else { $p.StayAwake=$true }
try { & $env:FIXTURE_WAKE @p } finally { $global:value | Set-Content -LiteralPath "$PSScriptRoot/value.txt" }
"""


@unittest.skipUnless(PWSH, "PowerShell is required")
class WakeGuardTests(unittest.TestCase):
    def run_guard(self, **overrides):
        config = dict(model="25102RKBEC", device="myron", value="0", release=False,
                      include_ownership=True, original=0, acquire_ack_failure=False, change_during_wake=False)
        config.update(overrides)
        with tempfile.TemporaryDirectory(prefix="purelive-wake-") as directory:
            root = Path(directory)
            (root / "config.json").write_text(json.dumps(config), encoding="utf-8")
            (root / "harness.ps1").write_text(HARNESS, encoding="utf-8")
            env = os.environ.copy()
            # No real SDK path exists here; adb.exe resolves only to our function.
            env["LOCALAPPDATA"] = directory
            env["FIXTURE_WAKE"] = str(WAKE)
            for key in ("PURELIVE_ADB_PAIR_ENDPOINT", "PURELIVE_ADB_PAIR_CODE", "PURELIVE_ADB_CONNECT_ENDPOINT"):
                env.pop(key, None)
            proc = subprocess.run([PWSH, "-NoProfile", "-File", str(root / "harness.ps1")],
                                  env=env, cwd=root, capture_output=True, timeout=30)
            calls = [json.loads(line) for line in (root / "calls.jsonl").read_text(encoding="utf-8-sig").splitlines()]
            value = (root / "value.txt").read_text(encoding="utf-8-sig").strip()
            return proc, calls, value

    def assert_read_only(self, calls):
        self.assertTrue(all(c == ["devices"] or c[2:4] == ["shell", "getprop"]
                            or c[2:5] == ["shell", "settings", "get"] for c in calls), calls)

    def test_wrong_model_or_codename_stops_before_input_and_cleanup(self):
        for field in ("model", "device"):
            for release in (False, True):
                with self.subTest(field=field, release=release):
                    p, calls, value = self.run_guard(**{field: "wrong", "release": release, "value": "2"})
                    self.assertNotEqual(p.returncode, 0)
                    self.assert_read_only(calls)
                    self.assertEqual(value, "2")

    def test_identity_and_original_value_precede_first_input(self):
        p, calls, value = self.run_guard(value="2")
        self.assertEqual(p.returncode, 0, p.stderr.decode())
        self.assertEqual(calls[1][2:], ["shell", "getprop", "ro.product.model"])
        self.assertEqual(calls[2][2:], ["shell", "getprop", "ro.product.device"])
        self.assertEqual(calls[3][2:], ["shell", "settings", "get", "global", "stay_on_while_plugged_in"])
        result = json.loads(p.stdout.decode("utf-8-sig").strip())
        self.assertEqual(result["OriginalStayAwakeValue"], 2)
        self.assertEqual(result["AcquiredStayAwakeValue"], 7)
        self.assertEqual(value, "7")

    def test_invalid_setting_is_preserved_without_input(self):
        for value in ("null", "16", "-1", "unexpected"):
            with self.subTest(value=value):
                p, calls, actual = self.run_guard(value=value)
                self.assertNotEqual(p.returncode, 0)
                self.assert_read_only(calls)
                self.assertEqual(actual, value)

    def test_restores_exact_zero_and_nonzero_settings_without_waking(self):
        for original in (0, 1, 2, 3, 7, 15):
            with self.subTest(original=original):
                p, calls, value = self.run_guard(release=True, value="7", original=original)
                self.assertEqual(p.returncode, 0, p.stderr.decode())
                self.assertEqual(value, str(original))
                self.assertFalse(any("input" in c or "wm" in c for c in calls))
                self.assertEqual(json.loads(p.stdout.decode("utf-8-sig").strip())["RestoredStayAwakeValue"], original)

    def test_cleanup_preserves_external_change(self):
        p, calls, value = self.run_guard(release=True, value="2", original=0)
        self.assertNotEqual(p.returncode, 0)
        self.assert_read_only(calls)
        self.assertEqual(value, "2")

    def test_cleanup_is_idempotent(self):
        p, calls, value = self.run_guard(release=True, value="2", original=2)
        self.assertEqual(p.returncode, 0, p.stderr.decode())
        self.assert_read_only(calls)
        self.assertEqual(value, "2")

    def test_cleanup_requires_ownership_values(self):
        p, calls, value = self.run_guard(release=True, value="7", include_ownership=False)
        self.assertNotEqual(p.returncode, 0)
        self.assert_read_only(calls)
        self.assertEqual(value, "7")

    def test_lost_acquisition_ack_rolls_back_before_wrapper_receives_state(self):
        p, calls, value = self.run_guard(value="2", acquire_ack_failure=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(value, "2")
        writes = [c[-1] for c in calls if c[2:5] == ["shell", "settings", "put"]]
        self.assertEqual(writes, ["7", "2"])

    def test_changed_setting_during_wake_is_preserved(self):
        p, calls, value = self.run_guard(value="2", change_during_wake=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(value, "3")
        self.assertFalse(any(c[2:5] == ["shell", "settings", "put"] for c in calls))


if __name__ == "__main__":
    unittest.main()
