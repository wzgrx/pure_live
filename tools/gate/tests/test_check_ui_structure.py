import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import check_ui_structure as ui  # noqa: E402


def write(root, rel, text):
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')


class ScanTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.lib = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_entry_page_imports_are_allowed_internals_are_not(self):
        write(self.lib, 'features/home/home_page.dart', "import 'package:pure_live/features/popular/popular_page.dart';\n")
        write(self.lib, 'features/popular/popular_page.dart', "import 'package:pure_live/features/home/home_menu.dart';\n")
        cross, _, _ = ui.scan(self.lib)
        self.assertEqual(cross, {'popular -> home/home_menu.dart'})

    def test_raw_styles_counted_per_area_comments_ignored(self):
        write(self.lib, 'features/search/a.dart', "final a = Colors.red; // Colors.blue\nconst i = Icons.add;\n")
        write(self.lib, 'tv/b.dart', 'const c = Color(0xFF000000); final r = Remix.heart_3_line;\n')
        _, raw, _ = ui.scan(self.lib)
        self.assertEqual(raw, {'search': 2, 'tv': 2})

    def test_logic_must_not_import_material(self):
        write(self.lib, 'features/live_play/logic/room.dart', "import 'package:flutter/material.dart';\n")
        write(self.lib, 'features/live_play/logic/ok.dart', "import 'package:flutter/foundation.dart';\n")
        _, _, logic = ui.scan(self.lib)
        self.assertEqual(logic, ['features/live_play/logic/room.dart'])


class CheckTest(unittest.TestCase):
    def test_ratchet_both_ways(self):
        baseline = {'cross_feature_imports': ['a -> b/x.dart', 'gone -> c/y.dart'], 'raw_styles': {'a': 3, 'b': 5}}
        problems = ui.check(baseline, {'a -> b/x.dart', 'new -> d/z.dart'}, {'a': 4, 'b': 2, 'c': 1}, [])
        text = '\n'.join(problems)
        self.assertIn('new cross-feature import: new -> d/z.dart', text)
        self.assertIn('is gone, remove it: gone -> c/y.dart', text)
        self.assertIn('a: 4 raw colours/icons, baseline allows 3', text)
        self.assertIn('b: raw colours/icons dropped to 2, lower the baseline from 5', text)
        self.assertIn('c: 1 raw colours/icons, baseline allows 0', text)

    def test_clean_tree_passes(self):
        self.assertEqual(ui.check({'cross_feature_imports': [], 'raw_styles': {}}, set(), {}, []), [])


if __name__ == '__main__':
    unittest.main()
