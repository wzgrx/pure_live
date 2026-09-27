"""Dependency-direction check: the real workspace passes, violations are caught."""
import importlib.util
from pathlib import Path
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("check_deps", ROOT / "tool/check_deps.py")
deps = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(deps)


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(text), encoding="utf-8")


class CheckDepsTest(unittest.TestCase):
    def workspace(self, members):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        listing = "".join(f"  - {member}\n" for member in members)
        write(root / "pubspec.yaml", f"name: pure_live\nworkspace:\n{listing}dependencies:\n  meta: ^1.0.0\n")
        return root

    def test_repository_workspace_passes(self):
        errors, members = deps.check(ROOT)
        self.assertEqual(errors, [])
        self.assertIn("packages/live_core", members)

    def test_pure_dart_package_must_not_use_flutter(self):
        root = self.workspace(["packages/live_core"])
        write(root / "packages/live_core/pubspec.yaml", """\
            name: live_core
            dependencies:
              flutter:
                sdk: flutter
            """)
        write(root / "packages/live_core/test/a_test.dart", "import 'package:flutter_test/flutter_test.dart';\n")
        errors, _ = deps.check(root)
        self.assertEqual(len(errors), 2, errors)
        self.assertIn("Flutter SDK", errors[0])
        self.assertIn("package:flutter_test", errors[1])

    def test_upward_dependency_is_rejected(self):
        root = self.workspace(["packages/live_core", "packages/live_net"])
        write(root / "packages/live_core/pubspec.yaml", "name: live_core\n")
        write(root / "packages/live_net/pubspec.yaml", "name: live_net\ndependencies:\n  live_core: any\n")
        write(root / "packages/live_net/lib/net.dart", "import 'package:live_core/live_core.dart';\n")
        errors, _ = deps.check(root)
        self.assertEqual(len(errors), 2, errors)
        self.assertTrue(all("live_core" in error for error in errors))

    def test_unknown_member_needs_a_decision(self):
        root = self.workspace(["packages/live_extra"])
        write(root / "packages/live_extra/pubspec.yaml", "name: live_extra\n")
        errors, _ = deps.check(root)
        self.assertEqual(len(errors), 1)
        self.assertIn("ALLOWED", errors[0])

    def test_legacy_lib_is_checked_but_member_folders_are_not_double_counted(self):
        root = self.workspace(["packages/live_ui"])
        write(root / "packages/live_ui/pubspec.yaml", "name: live_ui\n")
        write(root / "lib/main.dart", "import 'package:live_ui/live_ui.dart';\n")
        errors, _ = deps.check(root)
        self.assertEqual(len(errors), 1, errors)
        self.assertTrue(errors[0].startswith("lib/main.dart:1"))


if __name__ == "__main__":
    unittest.main()
