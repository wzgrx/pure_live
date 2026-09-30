import base64
import gzip
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

    def test_unknown_header_with_public_address_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            meta = self._meta(directory, {'x-from-src': '8.8.4.4'})
            self.assertEqual(len(check_fixtures.check([meta])), 1)

    def test_server_headers_and_versions_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            meta = self._meta(directory, {
                'lb': '8.8.4.4',
                'x-app-server-addr': '8.8.4.4',
                'server': 'openresty/1.13.6.1',
                'user-agent': 'Mozilla/5.0 Chrome/140.0.0.0 Safari/537.36',
            })
            self.assertEqual(check_fixtures.check([meta]), [])


class FramesTest(unittest.TestCase):
    """Danmaku frames (`*.jsonl`) and addresses written as integers."""

    # 8.8.4.4 as a little-endian uint32 (BIGO's clientIp) and big-endian.
    LITTLE = int.from_bytes(bytes([8, 8, 4, 4]), 'little')
    BIG = int.from_bytes(bytes([8, 8, 4, 4]), 'big')

    def _frames(self, directory, *records):
        path = Path(directory) / 'frames.jsonl'
        path.write_text(''.join(json.dumps(record) + '\n' for record in records), encoding='utf-8')
        return path

    def test_integer_fields_fail_in_either_byte_order(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'body.json'
            path.write_text(json.dumps({'a': {'clientIp': self.LITTLE}, 'b': {'client_ip': str(self.BIG)}}), encoding='utf-8')
            self.assertEqual(len(check_fixtures.check([path])), 2)

    def test_scrub_replacements_and_counters_pass_as_integers(self):
        replacement = int.from_bytes(bytes([198, 51, 100, 200]), 'little')
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'body.json'
            path.write_text(json.dumps({'a': {'clientIp': replacement}, 'b': {'clientIp': 0}, 'c': {'clientIp': '12345'}}), encoding='utf-8')
            self.assertEqual(check_fixtures.check([path]), [])

    def test_fields_inside_frame_text_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            text = '512535' + json.dumps({'res': '200', 'clientIp': str(self.LITTLE)})
            escaped = json.dumps({'x-real-ip': '8.8.4.4'})
            path = self._frames(directory, {'dir': 'in', 'text': text}, {'dir': 'in', 'text': json.dumps({'body': escaped})})
            problems = check_fixtures.check([path])
            self.assertEqual(len(problems), 2, problems)
            self.assertIn('frames.jsonl:1', problems[0])
            self.assertIn('frames.jsonl:2', problems[1])

    def test_fields_inside_compressed_base64_payloads_fail(self):
        payload = base64.b64encode(gzip.compress(json.dumps({'clientIp': '8.8.4.4'}).encode())).decode()
        with tempfile.TemporaryDirectory() as directory:
            path = self._frames(directory, {'dir': 'in', 'b64': payload})
            self.assertEqual(len(check_fixtures.check([path])), 1)

    def test_scrubbed_frames_pass(self):
        payload = base64.b64encode(gzip.compress(json.dumps({'clientIp': '203.0.113.7'}).encode())).decode()
        with tempfile.TemporaryDirectory() as directory:
            path = self._frames(
                directory,
                {'dir': 'in', 'b64': payload},
                {'dir': 'in', 'text': '512535{"clientIp":"3362010054","roomId":"12345678901"}'},
                {'dir': 'out', 'text': 'not json at all'},
            )
            self.assertEqual(check_fixtures.check([path]), [])


if __name__ == '__main__':
    unittest.main()
