import base64
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import check_fixtures  # noqa: E402


class LeaksTest(unittest.TestCase):
    def test_plain_public_address(self):
        self.assertEqual(check_fixtures.leaks('8.8.4.4'), ['8.8.4.4'])

    def test_forwarded_list(self):
        self.assertEqual(check_fixtures.leaks('10.0.0.1, 8.8.4.4'), ['8.8.4.4'])

    def test_base64_address(self):
        encoded = base64.b64encode(b'8.8.4.4').decode()
        self.assertEqual(check_fixtures.leaks(f'{encoded},1.0'), ['8.8.4.4'])

    def test_scrub_replacements_and_private_ranges_pass(self):
        encoded = base64.b64encode(b'203.0.113.7').decode()
        for value in ('203.0.113.7', '198.51.100.3', '192.168.1.2', '127.0.0.1', f'{encoded},1.0'):
            self.assertEqual(check_fixtures.leaks(value), [], value)


class CheckTest(unittest.TestCase):
    def _meta(self, directory, headers):
        path = Path(directory) / 'meta.json'
        path.write_text(json.dumps({'response': {'headers': headers}}), encoding='utf-8')
        return path

    def test_client_header_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            meta = self._meta(directory, {'x-ksclient-ip': '8.8.4.4', 'xhs-real-ip': '9.9.9.9'})
            self.assertEqual(len(check_fixtures.check([meta])), 2)

    def test_body_fields_with_underscores_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'body.json'
            path.write_text(json.dumps({'data': {'client_ip': '8.8.4.4', 'deviceInfo': {'publicIP': '9.9.9.9'}}}), encoding='utf-8')
            self.assertEqual(len(check_fixtures.check([path])), 2)

    def test_server_address_headers_are_ignored(self):
        with tempfile.TemporaryDirectory() as directory:
            meta = self._meta(directory, {'lb': '8.8.4.4', 'x-server-ip': '8.8.4.4'})
            self.assertEqual(check_fixtures.check([meta]), [])


if __name__ == '__main__':
    unittest.main()
