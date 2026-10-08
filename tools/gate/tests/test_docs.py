import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

DOCS_PY = Path(__file__).resolve().parents[2] / 'docs' / 'docs.py'

REGISTRY = '''
[[group]]
id = "A"
title = "界面设计"
scope = "界面。"

[[sub]]
id = "A01"
title = "设计系统"
scope = "颜色。"
code = "`packages/`"

[[task]]
id = "A01.1"
title = "颜色"
type = "界面"
status = "未开始"
tier = 1
'''


class DocsTest(unittest.TestCase):
    """docs.py on a small repository of its own (Z06.4)."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        (self.root / 'tools' / 'docs').mkdir(parents=True)
        shutil.copy(DOCS_PY, self.root / 'tools' / 'docs' / 'docs.py')
        (self.root / 'docs').mkdir()
        self.write('docs/tasks.toml', REGISTRY)
        (self.root / 'docs' / 'A-界面设计' / 'A01-设计系统').mkdir(parents=True)
        # The documents the generated pages link to.
        for rel in ('PROCESS.md', 'PLAN.md', 'DECISIONS.md', 'inventory/README.md', 'inventory/FEATURES.md',
                    'specs/ENGINEERING.md', 'specs/UI.md', 'specs/UPGRADES.md', 'templates/group.md',
                    'templates/sub.md'):
            self.write(f'docs/{rel}', '# x\n')
        for d in ('apps', 'packages', 'fixtures'):
            (self.root / d).mkdir()
        self.assertEqual(self.run_docs().returncode, 0, 'a fresh repository generates cleanly')

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        return path

    def run_docs(self, *args):
        return subprocess.run(
            [sys.executable, str(self.root / 'tools' / 'docs' / 'docs.py'), *args],
            cwd=self.root, capture_output=True, text=True, check=False)

    def check(self):
        result = self.run_docs('--check')
        return result.returncode, result.stderr

    def test_generated_files_pass(self):
        self.assertEqual(self.check(), (0, ''))

    def test_stale_generated_file(self):
        status = self.root / 'docs' / 'STATUS.md'
        status.write_text(status.read_text(encoding='utf-8') + '\n手改\n', encoding='utf-8')
        code, err = self.check()
        self.assertEqual(code, 1)
        self.assertIn('生成的文件不是最新的', err)
        self.assertIn('STATUS.md', err)

    def test_broken_link(self):
        self.write('docs/A-界面设计/note.md', '[看这里](missing.md)\n')
        code, err = self.check()
        self.assertEqual(code, 1)
        self.assertIn('链接找不到 missing.md', err)

    def test_missing_code_path(self):
        self.write('apps/a.dart', '// See docs/A-界面设计/A99-没有.\n')
        code, err = self.check()
        self.assertEqual(code, 1)
        self.assertIn('提到的 docs/A-界面设计/A99-没有 不存在', err)

    def test_path_cut_at_a_slash(self):
        # The regex stops before the '/', and docs/README.md exists: it passed before Z06.4.
        self.write('docs/README.md', '# docs\n')
        self.write('packages/b.dart', '/// The bar (docs/README.md/\n/// compare/U.1c c8).\n')
        code, err = self.check()
        self.assertEqual(code, 1)
        self.assertIn('docs/README.md/ 在注释里换行了', err)

    def test_fixture_readmes_are_checked(self):
        self.write('fixtures/x/README.md', '见 docs/modules/M5.1-bilibili.md。\n')
        code, err = self.check()
        self.assertEqual(code, 1)
        self.assertIn('fixtures/x/README.md：提到的 docs/modules/M5.1-bilibili.md 不存在', err)

    def test_folder_named_unlike_the_registry(self):
        self.write('docs/tasks.toml', REGISTRY.replace('title = "设计系统"', 'title = "设计系统和颜色"'))
        code, err = self.check()
        self.assertEqual(code, 1)
        self.assertIn('子分类文件夹名应为 A01-设计系统和颜色', err)

    def test_unregistered_task_folder(self):
        (self.root / 'docs' / 'A-界面设计' / 'A01-设计系统' / 'A01.9-没登记').mkdir(parents=True)
        code, err = self.check()
        self.assertEqual(code, 1)
        self.assertIn('没登记的任务文件夹', err)


if __name__ == '__main__':
    unittest.main()
