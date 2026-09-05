"""Exercise release input handling locally; never build, sign or publish.

Requires PyYAML and Bash (BASH_EXE may select Git Bash on Windows).
Only the tag-validation and Markdown-rendering steps are executed, in temporary
directories. All other workflow steps are outside this test's execution scope.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from validate_agent_workflow import Loader
import yaml

ROOT = Path(__file__).resolve().parents[2]
BASH = os.environ.get('BASH_EXE')
if not BASH and os.name == 'nt':
    git = shutil.which('git')
    candidate = Path(git).resolve().parents[1] / 'bin/bash.exe' if git else None
    BASH = str(candidate) if candidate and candidate.is_file() else None
elif not BASH:
    BASH = shutil.which('bash')
WORKFLOWS = ('feature-build.yml', 'build_pure_live_release.yml')


def step_script(workflow, name):
    doc = yaml.load((ROOT / '.github/workflows' / workflow).read_text(encoding='utf-8'), Loader=Loader)
    return next(s['run'] for s in doc['jobs']['publish-release']['steps'] if s.get('name') == name)


def run_step(script, directory, **values):
    return subprocess.run(
        [BASH, '--noprofile', '--norc'], input=script, encoding='utf-8',
        cwd=directory, env={**os.environ, **values}, capture_output=True, timeout=10,
    )


@unittest.skipUnless(BASH, 'Set BASH_EXE to a local Bash executable')
class ReleaseWorkflowDataTest(unittest.TestCase):
    def test_tag_validation_treats_input_as_data(self):
        cases = (('v3.2.0', 0), ('', 1), ('v3.2', 1), ('$(touch INJECTION_MARKER)', 1))
        for workflow in WORKFLOWS:
            for tag, expected in cases:
                with self.subTest(workflow=workflow, tag=tag), tempfile.TemporaryDirectory() as directory:
                    result = run_step(step_script(workflow, 'Validate release tag'), directory, TAG=tag)
                    self.assertEqual(result.returncode, expected, result.stderr)
                    self.assertFalse((Path(directory) / 'INJECTION_MARKER').exists())

    def test_release_markdown_is_preserved_without_execution(self):
        descriptions = (
            '- 中文更新\n- Preserve `inline code`, $variables and "quotes".',
            'EOF\ntouch INJECTION_MARKER\n$(touch INJECTION_MARKER)\n`touch INJECTION_MARKER`',
        )
        for workflow in WORKFLOWS:
            for description in descriptions:
                with self.subTest(workflow=workflow, description=description), tempfile.TemporaryDirectory() as directory:
                    result = run_step(
                        step_script(workflow, 'Build Release Body'), directory,
                        RELEASE_TAG='v3.2.0', RELEASE_DESCRIPTION=description,
                        GITHUB_OUTPUT='step-output.txt',
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    body = (Path(directory) / 'release_body.txt').read_text(encoding='utf-8')
                    self.assertIn('# 纯粹直播 v3.2.0', body)
                    self.assertIn(description, body)
                    self.assertNotIn('${{', body)
                    self.assertFalse((Path(directory) / 'INJECTION_MARKER').exists())
                    self.assertIn('body_path=', (Path(directory) / 'step-output.txt').read_text())


if __name__ == '__main__':
    unittest.main()
