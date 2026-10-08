"""tools/device/pl-adb.sh against a fake adb (Z04.1); never talks to a device."""

import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / 'tools' / 'device' / 'pl-adb.sh'
sys.path.insert(0, str(ROOT / 'tools' / 'device'))

import resize  # noqa: E402

FAKE_ADB = r'''#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_LOG"
case "$*" in
  *dumpsys\ window*) echo "  mCurrentFocus=Window{1a2b u0 $FAKE_FG/com.example.Main}" ;;
  *exec-out\ screencap*) cat "$FAKE_PNG" ;;
  *exec-out\ cat*) cat "$FAKE_UI" ;;
  *settings\ get\ system\ user_rotation*) echo "${FAKE_ROT:-0}" ;;
esac
exit 0
'''

FAKE_AAPT2 = r'''#!/usr/bin/env bash
echo "package: name='$FAKE_PKG' versionCode='5001' versionName='4.0.0'"
'''

TEST_APP = 'com.mystyle.purelive.v4dev'
USER_APP = 'com.mystyle.purelive'

HAS_IMAGING = resize.Image is not None or bool(shutil.which('ffmpeg') and shutil.which('ffprobe'))


def make_png(path, width, height):
    if resize.Image is not None:
        resize.Image.new('RGB', (width, height), 'white').save(path)
    else:
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-f', 'lavfi', '-i',
                        f'color=white:s={width}x{height}', '-frames:v', '1', str(path)], check=True)


def image_size(path):
    if resize.Image is not None:
        with resize.Image.open(path) as image:
            return image.size
    return resize._probe(path)


UI_XML = (
    '<hierarchy><node index="0" text="" resource-id="" class="android.view.View" '
    'package="com.mystyle.purelive.v4dev" content-desc="设置" checkable="false" '
    'bounds="[800,2200][1000,2400]" /><node index="1" text="关注" resource-id="" '
    'class="android.view.View" content-desc="" bounds="[0,2200][200,2400]" /></hierarchy>'
)


class DeviceTest(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        bin_dir = self.dir / 'bin'
        bin_dir.mkdir()
        for name, body in (('adb', FAKE_ADB), ('aapt2', FAKE_AAPT2)):
            path = bin_dir / name
            path.write_text(body, encoding='utf-8')
            path.chmod(0o755)
        self.log = self.dir / 'adb.log'
        self.log.write_text('', encoding='utf-8')
        ui = self.dir / 'ui.xml'
        ui.write_text(UI_XML, encoding='utf-8')
        self.env = {
            'PATH': f'{bin_dir}{os.pathsep}{os.environ.get("PATH", "")}',
            'HOME': str(self.dir),
            'FAKE_LOG': str(self.log),
            'FAKE_FG': TEST_APP,
            'FAKE_UI': str(ui),
            'FAKE_PKG': TEST_APP,
            'PL_DEVICE': 'fake-device',
            'PL_FRONT_WAIT': '0',
            'PL_SHOTS': str(self.dir / 'shots'),
        }

    def run_sh(self, command, **env):
        merged = dict(self.env)
        for key, value in env.items():
            if value is None:
                merged.pop(key, None)
            else:
                merged[key] = value
        return subprocess.run(['bash', '-c', f'source "{SCRIPT}"; {command}'], env=merged,
                              cwd=self.dir, capture_output=True, text=True, timeout=30)

    def calls(self):
        return self.log.read_text(encoding='utf-8').splitlines()

    def test_tap_refused_when_another_app_is_in_front(self):
        result = self.run_sh('pl_tap 1 2', FAKE_FG='com.bilibili.app')
        self.assertEqual(result.returncode, 1)
        self.assertIn('ABORT: foreground is com.bilibili.app', result.stdout)
        self.assertFalse([c for c in self.calls() if 'input' in c], self.calls())

    def test_every_input_refused_when_another_app_is_in_front(self):
        for command in ('pl_key 4', 'pl_text abc', 'pl_swipe 1 2 3 4', 'pl_hold 1 2',
                        'pl_tapl 设置', 'pl_shot x', 'pl_ui'):
            result = self.run_sh(command, FAKE_FG='com.android.launcher')
            self.assertEqual(result.returncode, 1, command)
            self.assertIn('ABORT', result.stdout, command)
        sent = [c for c in self.calls() if 'dumpsys' not in c]
        self.assertEqual(sent, [])

    def test_tap_sent_when_test_build_is_in_front(self):
        result = self.run_sh('pl_tap 1 2')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('-s fake-device shell input tap 1 2', self.calls())

    def test_users_own_install_refused(self):
        for command in ('pl_front', 'pl_tap 1 2', 'pl_fg', 'pl_net off', 'pl_install x.apk'):
            result = self.run_sh(command, PL_APP=USER_APP, FAKE_FG=USER_APP)
            self.assertEqual(result.returncode, 1, command)
            self.assertIn('REFUSED', result.stderr, command)
        self.assertEqual(self.calls(), [])

    def test_no_device_refused(self):
        result = self.run_sh('pl_tap 1 2', PL_DEVICE=None, D=None)
        self.assertEqual(result.returncode, 1)
        self.assertIn('PL_DEVICE', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_device_falls_back_to_d(self):
        self.run_sh('pl_tap 1 2', PL_DEVICE=None, D='other-device')
        self.assertIn('-s other-device shell input tap 1 2', self.calls())

    def test_front_starts_activity_then_checks(self):
        result = self.run_sh('pl_front')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'front: {TEST_APP}', result.stdout)
        self.assertIn(f'-s fake-device shell am start -n {TEST_APP}/com.mystyle.purelive.MainActivity',
                      self.calls())

    def test_install_refuses_other_package(self):
        apk = self.dir / 'app.apk'
        apk.write_bytes(b'PK')
        for package in (USER_APP, 'com.mystyle.purelive.next'):
            result = self.run_sh(f'pl_install "{apk}"', FAKE_PKG=package)
            self.assertEqual(result.returncode, 1, package)
            self.assertIn('not a .v4dev test build', result.stderr)
        self.assertEqual(self.calls(), [])

    def test_install_test_build(self):
        apk = self.dir / 'app.apk'
        apk.write_bytes(b'PK')
        result = self.run_sh(f'pl_install "{apk}"')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'-s fake-device install -r {apk}', self.calls())

    def test_tap_by_label_hits_centre(self):
        result = self.run_sh('pl_tapl 设置')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('-s fake-device shell input tap 900 2300', self.calls())

    def test_tap_by_label_not_found(self):
        result = self.run_sh('pl_tapl 录制')
        self.assertEqual(result.returncode, 1)
        self.assertIn('NOTFOUND: 录制', result.stdout)
        self.assertFalse([c for c in self.calls() if 'input' in c])

    def test_ui_warns_about_frozen_rotation(self):
        result = self.run_sh('pl_ui', FAKE_ROT='3')
        self.assertIn('text="关注" "[0,2200][200,2400]"', result.stdout)
        self.assertIn('user_rotation is 3', result.stderr)

    def test_text_spaces_and_refusals(self):
        self.run_sh("pl_text 'ab cd'")
        self.assertIn('-s fake-device shell input text ab%scd', self.calls())
        for value in ('中文', 'a;reboot', '$(id)'):
            result = self.run_sh(f"pl_text '{value}'")
            self.assertEqual(result.returncode, 2, value)
        self.assertEqual(len([c for c in self.calls() if 'input text' in c]), 1)

    def test_net_cut_only_the_test_build(self):
        self.run_sh('pl_net off')
        self.assertEqual(self.calls(), [
            '-s fake-device shell cmd connectivity set-chain3-enabled true',
            f'-s fake-device shell cmd connectivity set-package-networking-enabled false {TEST_APP}',
        ])

    @unittest.skipUnless(HAS_IMAGING, 'neither Pillow nor ffmpeg is installed')
    def test_shot_is_540_wide(self):
        png = self.dir / 'screen.png'
        make_png(png, 1440, 3200)
        result = self.run_sh('pl_shot 01', FAKE_PNG=str(png))
        self.assertEqual(result.returncode, 0, result.stderr)
        shot = self.dir / 'shots' / '01.jpg'
        self.assertEqual(tuple(image_size(shot)), (540, 1200))
        self.assertFalse((self.dir / 'shots' / '01.png').exists())

    @unittest.skipIf(shutil.which('shellcheck') is None, 'shellcheck is not installed')
    def test_shellcheck(self):
        result = subprocess.run(['shellcheck', str(SCRIPT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout)


class ResizeTest(unittest.TestCase):
    def test_scaled_height_even(self):
        self.assertEqual(resize.scaled_height(1440, 3200, 540), 1200)
        self.assertEqual(resize.scaled_height(1000, 1001, 540), 542)

    @unittest.skipUnless(HAS_IMAGING, 'neither Pillow nor ffmpeg is installed')
    def test_row_pads_shorter_images(self):
        with tempfile.TemporaryDirectory() as directory:
            tall, short = Path(directory) / 'a.png', Path(directory) / 'b.png'
            make_png(tall, 1080, 2400)
            make_png(short, 1080, 1080)
            out = Path(directory) / 'row.jpg'
            with contextlib.redirect_stdout(io.StringIO()):
                resize.row(out, 540, [tall, short])
            self.assertEqual(tuple(image_size(out)), (1080, 1200))


if __name__ == '__main__':
    unittest.main()
