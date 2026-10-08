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

    def test_shared_code_is_an_area_too(self):
        write(self.lib, 'shared/rooms/paging.dart', 'const i = Icons.arrow_drop_down_rounded;\n')
        _, raw, _ = ui.scan(self.lib)
        self.assertEqual(raw, {'shared': 1})

    def test_component_icons_listed_by_line(self):
        live_ui = Path(self.tmp.name) / 'live_ui/lib'
        write(live_ui, 'src/widgets/a.dart', "// Icons.add in a comment\nconst i = AppIcons.close;\nconst j = Icons.add;\n")
        write(live_ui, 'src/icons/app_icons.dart', 'static const IconData close = Icons.close;\n')
        self.assertEqual(ui.scan_component_icons(live_ui), ['lib/src/widgets/a.dart:3'])

    def test_text_roles_fixed_sizes_and_weights_outside_the_room(self):
        root = Path(self.tmp.name)
        lib = root / 'apps/pure_live/lib'
        live_ui = root / 'packages/live_ui/lib'
        write(lib, 'features/about/a.dart', 'x(fontSize: 20);\ny(fontSize: theme.size);\nz(fontWeight: FontWeight.w600);\n')
        write(lib, 'shared/b.dart', 'x(fontSize: tv ? 17 : 15);\ny(fontWeight: FontWeight.bold); // FontWeight.w500\n')
        write(lib, 'app/c.dart', 'x(fontWeight: FontWeight.w500);\n')
        write(lib, 'features/live_play/d.dart', 'x(fontSize: 13);\n')
        write(lib, 'tv/e.dart', 'x(fontSize: 13);\n')
        write(live_ui, 'src/widgets/f.dart', 'x(fontWeight: FontWeight.w700);\n')
        write(live_ui, 'src/widgets/record_glyph.dart', 'x(fontSize: 12);\n')
        hits = ui.scan_text_roles(lib, live_ui, root)
        self.assertEqual(
            [h.split(': ')[0] for h in hits],
            [
                'apps/pure_live/lib/features/about/a.dart:1',
                'apps/pure_live/lib/shared/b.dart:1',
                'apps/pure_live/lib/shared/b.dart:2',
                'apps/pure_live/lib/app/c.dart:1',
                'packages/live_ui/lib/src/widgets/f.dart:1',
            ],
        )

    def test_unused_icon_names(self):
        live_ui = Path(self.tmp.name) / 'live_ui/lib'
        write(live_ui, 'src/icons/app_icons.dart', 'static const IconData a = X;\nstatic const IconData b = Y;\n')
        write(live_ui, 'src/widgets/w.dart', 'Icon(AppIcons.a)\n')
        self.assertEqual(ui.unused_icons(live_ui, [live_ui]), ['b'])

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

    def test_component_icons_text_roles_and_unused_names_fail(self):
        problems = ui.check({}, set(), {}, [], ['lib/src/widgets/a.dart:3'], ['b'], ['x.dart:1: fontSize: 12'])
        text = '\n'.join(problems)
        self.assertIn('raw icon in a live_ui component, name it in AppIcons: lib/src/widgets/a.dart:3', text)
        self.assertIn('weight other than 400/600', text)
        self.assertIn('AppIcons.b is not used anywhere', text)

    def test_clean_tree_passes(self):
        self.assertEqual(ui.check({'cross_feature_imports': [], 'raw_styles': {}}, set(), {}, []), [])


if __name__ == '__main__':
    unittest.main()
