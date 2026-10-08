import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'release'))

import check_version  # noqa: E402


class CheckVersionTest(unittest.TestCase):
    def test_reads_pubspec(self):
        self.assertEqual(check_version.pubspec_version('name: x\nversion: 4.0.1+5002\n'), ('4.0.1', 5002))
        with self.assertRaises(ValueError):
            check_version.pubspec_version('version: 4.0.1\n')

    def test_reads_the_android_block(self):
        data = {'version': '3.2.11', 'build_number': 4134,
                'platforms': {'android': {'version': 'v4.0.0', 'build_number': 5001}}}
        self.assertEqual(check_version.published_version(data), ('4.0.0', 5001))

    def test_a_new_version_passes(self):
        self.assertEqual(check_version.check(('4.0.1', 5002), ('4.0.0', 5001), allow_same=False), [])

    def test_the_same_version_is_refused_unless_allowed(self):
        problems = check_version.check(('4.0.0', 5002), ('4.0.0', 5001), allow_same=False)
        self.assertEqual(len(problems), 1)
        self.assertIn('--allow-same-version', problems[0])
        self.assertEqual(check_version.check(('4.0.0', 5002), ('4.0.0', 5001), allow_same=True), [])

    def test_the_build_must_rise(self):
        self.assertIn('构建号', check_version.check(('4.0.1', 5001), ('4.0.0', 5001), allow_same=False)[0])


if __name__ == '__main__':
    unittest.main()
