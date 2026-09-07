"""Real orchestration/restore wrappers with fake children; no ADB or network."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[1]
PWSH = shutil.which('pwsh')
CONFIGURE = r'''
param($Serial,$Mode,$Port=7897,$EvidenceDirectory,$SessionPath,[switch]$KeepAppOpen)
$ErrorActionPreference='Stop'
if($Mode -eq 'LocalClash'){
 if($env:FAIL_SETUP -eq 'before'){throw 'setup-before-journal'}
 @{serial=$Serial;port=$Port} | ConvertTo-Json | Set-Content -LiteralPath $SessionPath
}
$actualPort=if($SessionPath -and (Test-Path -LiteralPath $SessionPath)){
 (Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json).port
}else{$Port}
@{serial=$Serial;mode=$Mode;port=$actualPort;session=$SessionPath;keep=[bool]$KeepAppOpen} |
 ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $PSScriptRoot '../calls.jsonl')
if($Mode -eq 'LocalClash' -and $env:FAIL_SETUP -eq 'after'){throw 'setup-after-journal'}
if($Mode -eq 'Restore' -and $env:FAIL_RESTORE -eq '1'){throw 'restore-failure'}
$global:LASTEXITCODE=0
'''
SMOKE = r'''
param($Serial,$Platform,$RecordSeconds,$PlatformLoadTimeoutSeconds,[switch]$RequireLiveDanmaku,[switch]$ExerciseStreamSelection)
@{serial=$Serial;mode='smoke';platform=$Platform} | ConvertTo-Json -Compress |
 Add-Content -LiteralPath (Join-Path $PSScriptRoot '../calls.jsonl')
if($env:FAIL_SMOKE -eq '1'){throw 'smoke-failure'}
$global:LASTEXITCODE=0
'''

@unittest.skipUnless(PWSH, 'PowerShell required')
class ProxyWrapperTests(unittest.TestCase):
    def run_wrapper(self, *, setup='', smoke=False, restore=False):
        with tempfile.TemporaryDirectory(prefix='purelive-proxy-wrapper-') as temp:
            root = Path(temp)
            (root / 'tool').mkdir()
            for name in ('android_foreign_recording_smoke.ps1', 'android_restore_proxy_defaults.ps1'):
                shutil.copyfile(TOOL / name, root / 'tool' / name)
            (root / 'tool/android_configure_proxy.ps1').write_text(CONFIGURE, encoding='utf-8')
            (root / 'tool/android_recording_smoke.ps1').write_text(SMOKE, encoding='utf-8')
            env = os.environ.copy()
            env.update(FAIL_SETUP=setup, FAIL_SMOKE=str(int(smoke)), FAIL_RESTORE=str(int(restore)))
            run = subprocess.run([PWSH, '-NoProfile', '-File', str(root / 'tool/android_foreign_recording_smoke.ps1'),
                                  '-Serial', '192.0.2.10:5555', '-Platform', 'picarto', '-ProxyPort', '7909'],
                                 cwd=root, env=env, capture_output=True, text=True, encoding='utf-8', timeout=45)
            path = root / 'calls.jsonl'
            calls = [json.loads(line) for line in path.read_text(encoding='utf-8-sig').splitlines()] if path.exists() else []
            return run.returncode, calls, run.stdout + run.stderr

    def test_custom_port_and_exact_session_survive_restore_wrapper(self):
        code, calls, _ = self.run_wrapper()
        self.assertEqual(code, 0)
        self.assertEqual([c['mode'] for c in calls], ['LocalClash', 'smoke', 'Restore'])
        self.assertEqual(calls[0]['session'], calls[2]['session'])
        self.assertEqual(calls[0]['port'], 7909)
        self.assertEqual(calls[2]['port'], 7909)
        self.assertTrue(calls[0]['keep'])
        self.assertTrue(all(c['serial'] == '192.0.2.10:5555' for c in calls))

    def test_setup_failure_before_journal_performs_no_blind_restore(self):
        code, calls, _ = self.run_wrapper(setup='before')
        self.assertNotEqual(code, 0)
        self.assertEqual(calls, [])

    def test_partial_setup_restores_same_journal_without_running_smoke(self):
        code, calls, _ = self.run_wrapper(setup='after')
        self.assertNotEqual(code, 0)
        self.assertEqual([c['mode'] for c in calls], ['LocalClash', 'Restore'])
        self.assertEqual(calls[0]['session'], calls[1]['session'])

    def test_smoke_failure_still_restores(self):
        code, calls, output = self.run_wrapper(smoke=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(calls[-1]['mode'], 'Restore')
        self.assertIn('smoke-failure', output)

    def test_restore_failure_fails_an_otherwise_successful_smoke(self):
        code, calls, output = self.run_wrapper(restore=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(calls[-1]['mode'], 'Restore')
        self.assertIn('restore-failure', output)

    def test_primary_and_cleanup_failures_are_both_preserved(self):
        code, _, output = self.run_wrapper(smoke=True, restore=True)
        self.assertNotEqual(code, 0)
        self.assertIn('smoke-failure', output)
        self.assertIn('restore-failure', output)

if __name__ == '__main__':
    unittest.main()
