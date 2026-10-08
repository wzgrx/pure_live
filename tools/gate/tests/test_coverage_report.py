"""tools/coverage/report.py on a small fake workspace (S01.2)."""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'coverage'))

import report  # noqa: E402

PUBSPEC = '''name: workspace
workspace:
  - apps/pure_live
  - packages/live_x

# comment
dependency_overrides:
  foo: 1
'''

APP_LCOV = '''SF:lib/features/search/search_page.dart
DA:1,1
DA:2,0
LF:2
LH:1
end_of_record
SF:lib/shared/util.dart
DA:1,0
DA:2,0
DA:3,0
LF:3
LH:0
end_of_record
'''

# format_coverage writes absolute paths and may leave out LF/LH.
PKG_LCOV = '''SF:{root}/packages/live_x/lib/src/a.dart
DA:1,3
DA:2,1
DA:3,0
DA:4,2
end_of_record
'''

WAIT_TEST = '''void main() {
  Future<void> settle([int ms = 20]) => Future<void>.delayed(Duration(milliseconds: ms));
  test('a', () async {
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(1, 1);
  });
  test('b', () async {
    await settle();
    await until(() => done);
    expect(1, 1);
  });
  test('c', () async {
    await Future<void>.delayed(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(1, 1);
  });
  Future<void> flush() => pumpEventQueue();
  Future<void> wait(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }
  testWidgets('d', (tester) async {
    await flush();
    expect(1, 1);
    await wait(tester);
    expect(1, 1);
    await _until(() => true);
    expect(1, 1);
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(1, 1);
  });
}

Future<void> _until(bool Function() condition) async {
  while (!condition()) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
'''


BARREL = '''/// Library docs.
library;

/* block
   comment */
export 'src/a.dart'
    show f;
'''


class ParseTest(unittest.TestCase):
    def test_barrel_has_no_code(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'x.dart'
            path.write_text(BARREL, encoding='utf-8')
            self.assertFalse(report.has_code(path))
            path.write_text(BARREL + 'const x = 1;\n', encoding='utf-8')
            self.assertTrue(report.has_code(path))

    def test_members_stop_at_next_key(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'pubspec.yaml').write_text(PUBSPEC, encoding='utf-8')
            self.assertEqual(report.members(root), ['apps/pure_live', 'packages/live_x'])

    def test_lcov_with_and_without_totals(self):
        files = report.parse_lcov(APP_LCOV + PKG_LCOV.format(root='/r'))
        self.assertEqual(files['lib/features/search/search_page.dart'], (2, 1))
        self.assertEqual(files['/r/packages/live_x/lib/src/a.dart'], (4, 3))

    def test_normalise_absolute_path(self):
        self.assertEqual(report.normalise('packages/live_x', '/r/packages/live_x/lib/src/a.dart'),
                         'lib/src/a.dart')

    def test_run_count(self):
        self.assertEqual(report.run_count('00:01 +3: x\n03:57 +1026: All tests passed!\n'),
                         (1026, 0, 0, True))
        self.assertEqual(report.run_count('01:00 +10 ~2 -1: Some tests failed.\nformat done\n'),
                         (10, 2, 1, False))
        self.assertIsNone(report.run_count('nothing'))

    def test_groups(self):
        self.assertEqual(report.group_of('apps/pure_live', 'lib/features/live_play/logic/a.dart'),
                         'lib/features/live_play')
        self.assertEqual(report.group_of('apps/pure_live', 'lib/shared/rooms/a.dart'), 'lib/shared')
        self.assertEqual(report.group_of('apps/pure_live', 'lib/main.dart'), 'lib/main.dart')
        self.assertEqual(report.group_of('packages/live_core', 'lib/src/sites/douyu/api.dart'),
                         'lib/src/sites')
        self.assertEqual(report.group_of('packages/live_core', 'lib/src/aes.dart'), 'lib/src')


class WorkspaceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = self.root = Path(self.tmp.name) / 'repo'
        out = self.out = Path(self.tmp.name) / 'out'
        out.mkdir()
        for directory in ('apps/pure_live/lib/features/search', 'apps/pure_live/lib/features/about',
                          'apps/pure_live/lib/shared', 'apps/pure_live/test', 'packages/live_x/lib/src'):
            (root / directory).mkdir(parents=True)
        (root / 'pubspec.yaml').write_text(PUBSPEC, encoding='utf-8')
        for path in ('features/search/search_page.dart', 'features/about/about_page.dart', 'shared/util.dart'):
            (root / 'apps/pure_live/lib' / path).write_text('void f() {}\n', encoding='utf-8')
        (root / 'packages/live_x/lib/src/a.dart').write_text('void f() {}\n', encoding='utf-8')
        (root / 'packages/live_x/lib/live_x.dart').write_text(BARREL, encoding='utf-8')
        (root / 'apps/pure_live/test/wait_test.dart').write_text(WAIT_TEST, encoding='utf-8')
        (out / 'pure_live.lcov').write_text(APP_LCOV, encoding='utf-8')
        (out / 'pure_live.log').write_text('00:10 +7: All tests passed!\n', encoding='utf-8')
        (out / 'live_x.lcov').write_text(PKG_LCOV.format(root=root), encoding='utf-8')

    def test_collect_and_tables(self):
        app, pkg = data = report.collect(self.out, self.root)
        self.assertEqual(app['tests'], (7, 0, 0, True))
        self.assertEqual(app['test_files'], 1)
        self.assertEqual(report.totals(app['files']),
                         {'files': 3, 'loaded': 2, 'found': 5, 'hit': 1, 'pct': 20.0})
        self.assertEqual([f['path'] for f in report.zero_files(app)],
                         ['lib/features/about/about_page.dart', 'lib/shared/util.dart'])
        self.assertEqual(report.totals(pkg['files']),
                         {'files': 1, 'loaded': 1, 'found': 4, 'hit': 3, 'pct': 75.0})
        text = report.markdown(data)
        self.assertIn('| `apps/pure_live` | 1 | 7 | 20.0% | 1/5 | 3 | 1 |', text)
        low = text.split('低于')[1].split('0% 的文件')[0]
        self.assertIn('| `apps/pure_live` | `lib/features/about` | 0.0% | 0/0 | 0/1 |', low)
        self.assertNotIn('lib/features/search', low)
        self.assertIn('| `apps/pure_live` | `lib/features/about/about_page.dart` | 没加载 |', text)
        self.assertIn('| `apps/pure_live` | `lib/shared/util.dart` | 0/3 行 |', text)

    def test_waits(self):
        waits, conditional = report.scan_waits(self.root / 'apps/pure_live/test', self.root)
        self.assertEqual([(w['line'], w['wait'], w['direct']) for w in waits],
                         [(4, '50 milliseconds', True), (9, 'settle()', False), (14, '1 seconds', False),
                          (30, 'wait()', True)])
        self.assertEqual(conditional, ['apps/pure_live/test/wait_test.dart'])


if __name__ == '__main__':
    unittest.main()
