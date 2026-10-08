import io
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stderr
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'docs'))

import owners  # noqa: E402

REGISTRY = '''
[[group]]
id = "A"
title = "界面设计"

[[sub]]
id = "A07"
title = "直播间界面"

[[sub]]
id = "C01"
title = "进房和房间逻辑"

[[sub]]
id = "D01"
title = "平台弹幕协议"

[[sub]]
id = "D05"
title = "弹幕设置生效"

[[sub]]
id = "E01"
title = "国内五大平台"

[[sub]]
id = "L01"
title = "网络电视"

[[sub]]
id = "O02"
title = "画中画"

[[sub]]
id = "Z02"
title = "门禁"

[[task]]
id = "C01.1"
title = "进房"

[[task]]
id = "D01.2"
title = "哔哩哔哩 弹幕"
'''

TABLE = '''
path = [
  { glob = "apps/pure_live/lib/features/live_play/logic/", sub = "C01" },
  { glob = "apps/pure_live/lib/features/live_play/", sub = "A07" },
  { glob = "apps/pure_live/lib/platform/", sub = "O02" },
  { glob = "packages/live_core/", sub = "E01" },
  { glob = "packages/live_store/", sub = "D05" },
  { glob = "tools/**/*.py", sub = "Z02" },
]
site = [
  { id = "bilibili", play = "E01", danmaku = "D01" },
  { id = "iptv", play = "L01", danmaku = "无" },
]
channel = [
  { name = "pure_live/pip", sub = "O02" },
]
setting = [
  { key = "youtubeShowAllChat", sub = "D01" },
]

[setting_sections]
danmaku = "D05"
player = "C01"
'''

SETTINGS = '''
abstract final class Settings {
  // ---- danmaku ----
  static const danmakuSpeed = DoubleSetting('danmakuSpeed', section: 'danmaku', defaultValue: 8.0);
  static const youtubeShowAllChat = BoolSetting(
    'youtubeShowAllChat',
    section: 'danmaku',
    defaultValue: (false),
  );
  static const preferResolution = StringSetting('preferResolution', section: 'player', defaultValue: '原画');
  static const List<Setting<Object>> player = [preferResolution];
  static const List<Setting<Object>> all = [
    danmakuSpeed,
    youtubeShowAllChat,
    ...player,
  ];
}
'''

SITES = '''
abstract final class SiteIds {
  static const String bilibili = 'bilibili';
  static const String iptv = 'iptv';
  static const String all = 'all';
  static const List<String> supported = [
    bilibili,
    iptv,
  ];
}
'''

FEATURES = '''# 功能清点

| 编号 | 功能 | v3 位置 | Android | v4 现状 | 依据 | 备注 |
|---|---|---|---|---|---|---|
| F-ROOM-01 | 进房 | `a.dart` | 是 | 完成 | `logic/`（C01.1） | 弹幕 → D01.2 |

| 编号 | 功能 | v3 位置 |
|---|---|---|
| F-WIN-01 | 标题栏 | `b.dart` |
'''


class OwnersTest(unittest.TestCase):
    """owners.py on a small repository of its own (Z03.2)."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        self.write('docs/tasks.toml', REGISTRY)
        self.write(owners.TABLE, TABLE)
        self.write(owners.SETTINGS, SETTINGS)
        self.write(owners.SITES, SITES)
        self.write(owners.FEATURES, FEATURES)
        self.write('apps/pure_live/lib/features/live_play/live_play_page.dart', '')
        self.write('apps/pure_live/lib/features/live_play/logic/room_controller.dart', '')
        self.write('apps/pure_live/lib/platform/pip.dart', "const c = MethodChannel('pure_live/pip');\n")
        self.write('tools/gate/check.py', '')
        # Not code files: other suffixes, hidden and build directories.
        self.write('apps/pure_live/lib/notes.md', '')
        self.write('apps/pure_live/lib/.dart_tool/x.dart', '')
        self.write('packages/live_core/build/y.dart', '')
        self.write('tools/gate/__pycache__/check.py', '')

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')

    def problems(self):
        return owners.Owners(self.root).problems

    def run_main(self, *args):
        err = io.StringIO()
        with redirect_stderr(err):
            code = owners.main(list(args), root=self.root)
        return code, err.getvalue()

    def assertProblem(self, text):
        problems = self.problems()
        self.assertTrue(any(text in p for p in problems), f'{text!r} not in {problems}')

    def test_clean_tree_passes(self):
        self.assertEqual(self.problems(), [])
        self.assertEqual(self.run_main(), (0, ''))
        self.assertEqual(self.run_main('--check'), (0, ''))
        page = (self.root / owners.OUTPUT).read_text(encoding='utf-8')
        self.assertIn('不要手改', page)
        self.assertIn('## C01 进房和房间逻辑', page)
        self.assertIn('`preferResolution`', page)

    def test_code_files(self):
        self.assertEqual(owners.code_files(self.root), [
            'apps/pure_live/lib/features/live_play/live_play_page.dart',
            'apps/pure_live/lib/features/live_play/logic/room_controller.dart',
            'apps/pure_live/lib/platform/pip.dart',
            'packages/live_core/lib/src/sites.dart',
            'packages/live_store/lib/src/settings/settings.dart',
            'tools/gate/check.py',
        ])

    def test_unowned_file(self):
        self.write('apps/pure_live/lib/features/home/home_page.dart', '')
        self.assertProblem('unowned: apps/pure_live/lib/features/home/home_page.dart')
        self.assertEqual(self.run_main('--check')[0], 1)

    def test_first_rule_wins(self):
        o = owners.Owners(self.root)
        self.assertEqual(o.file_owner['apps/pure_live/lib/features/live_play/logic/room_controller.dart'], 'C01')
        self.assertEqual(o.file_owner['apps/pure_live/lib/features/live_play/live_play_page.dart'], 'A07')

    def test_rule_matching_nothing(self):
        # Every file of the second rule is taken by the first one.
        self.write(owners.TABLE, TABLE.replace(
            '{ glob = "apps/pure_live/lib/features/live_play/logic/", sub = "C01" },',
            '{ glob = "apps/pure_live/lib/features/", sub = "C01" },'))
        self.assertProblem("path 'apps/pure_live/lib/features/live_play/' matches no file")

    def test_glob(self):
        rx = owners.glob_rx
        self.assertTrue(rx('tools/**/*.py').match('tools/a/b/c.py'))
        self.assertTrue(rx('tools/**/*.py').match('tools/c.py'))
        self.assertFalse(rx('tools/*.py').match('tools/a/c.py'))
        self.assertTrue(rx('a/system_*.dart').match('a/system_access.dart'))
        self.assertFalse(rx('a/system_*.dart').match('a/b/system_access.dart'))
        self.assertTrue(rx('a/b/').match('a/b/c/d.dart'))
        self.assertFalse(rx('a/b/').match('a/bc/d.dart'))
        self.assertFalse(rx('a/b.dart').match('a/b.dart.bak'))

    def test_unknown_sub(self):
        self.write(owners.TABLE, TABLE.replace('sub = "Z02"', 'sub = "Z99"'))
        self.assertProblem("path 'tools/**/*.py' names Z99, which is not a sub-category")

    def test_settings_by_section_and_override(self):
        o = owners.Owners(self.root)
        self.assertEqual(o.setting_owner, {'danmakuSpeed': 'D05', 'youtubeShowAllChat': 'D01', 'preferResolution': 'C01'})

    def test_parse_settings(self):
        found, problems = owners.parse_settings(SETTINGS)
        self.assertEqual(found, [('danmakuSpeed', 'danmaku'), ('youtubeShowAllChat', 'danmaku'),
                                 ('preferResolution', 'player')])
        self.assertEqual(problems, [])
        _, problems = owners.parse_settings(SETTINGS.replace('    ...player,\n', '    ...gone,\n'))
        self.assertEqual(problems, ['settings: Settings.all spreads unknown list gone'])

    def test_new_section_without_default(self):
        self.write(owners.SETTINGS, SETTINGS.replace("section: 'player'", "section: 'tv'"))
        self.assertProblem("unowned setting: preferResolution (section 'tv' has no default")
        self.assertProblem("setting section 'player' has no setting")

    def test_override_of_a_missing_setting(self):
        self.write(owners.TABLE, TABLE.replace('key = "youtubeShowAllChat"', 'key = "gone"'))
        self.assertProblem("setting 'gone' is not in Settings.all")

    def test_site_without_owner(self):
        self.write(owners.SITES, SITES.replace('    iptv,\n', '    iptv,\n    kick,\n').replace(
            "static const String all", "static const String kick = 'kick';\n  static const String all"))
        self.assertProblem('unowned site: kick')

    def test_site_danmaku(self):
        self.assertNotIn('iptv', ' '.join(self.problems()))
        self.write(owners.TABLE, TABLE.replace(', danmaku = "无"', ''))
        self.assertProblem("site 'iptv' has no danmaku sub-category")

    def test_site_gone(self):
        self.write(owners.SITES, SITES.replace('    iptv,\n', ''))
        self.assertProblem("site 'iptv' is not in SiteIds.supported")

    def test_channels(self):
        self.write('apps/pure_live/android/app/src/main/kotlin/Main.kt', 'val C = "pure_live/recorder"\n')
        self.write(owners.TABLE, TABLE.replace('{ glob = "packages/live_core/"',
                                               '{ glob = "apps/pure_live/android/", sub = "O02" },\n  '
                                               '{ glob = "packages/live_core/"'))
        self.assertProblem('unowned channel: pure_live/recorder (apps/pure_live/android/app/src/main/kotlin/Main.kt:1)')
        self.write('apps/pure_live/lib/platform/pip.dart', "import 'package:pure_live/x.dart';\n")
        self.assertProblem("channel 'pure_live/pip' is not named in the code")

    def test_feature_with_unknown_task(self):
        self.write(owners.FEATURES, FEATURES.replace('D01.2', 'D01.99'))
        self.assertProblem('FEATURES.md:5: F-ROOM-01 names D01.99, which is not a task')

    def test_feature_ids(self):
        # A second row under the first header; the Windows table has no 依据 or 备注 column.
        text = FEATURES.replace('| 弹幕 → D01.2 |\n', '| 弹幕 → D01.2 |\n| F-ROOM-01 | 再一次 | | | | E01.1 | |\n')
        ids, problems = owners.feature_ids(text + '| F-WIN-02 | 托盘 | E01.9 |\n')
        self.assertEqual([t for _, _, t in ids], ['C01.1', 'D01.2', 'E01.1'])
        self.assertEqual(problems, ['docs/inventory/FEATURES.md:6: F-ROOM-01 also on line 5'])

    def test_stale_page(self):
        self.assertEqual(self.run_main()[0], 0)
        self.write(owners.TABLE, TABLE.replace('player = "C01"', 'player = "A07"'))
        code, err = self.run_main('--check')
        self.assertEqual(code, 1)
        self.assertIn('OWNERS.md is stale', err)

    def test_who(self):
        o = owners.Owners(self.root)
        self.assertEqual(o.who('apps/pure_live/lib/platform/new.dart'),
                         ["O02 画中画  (path 'apps/pure_live/lib/platform/')"])
        self.assertEqual(o.who('youtubeShowAllChat'), ['D01 平台弹幕协议  (setting)'])
        self.assertEqual(o.who('pip'), ['O02 画中画  (channel)'])
        self.assertEqual(o.who('iptv'), ['play L01, danmaku 无  (site)'])


if __name__ == '__main__':
    unittest.main()
