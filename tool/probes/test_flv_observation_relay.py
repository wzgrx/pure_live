import threading
import time
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from flv_observation_relay import FlvObserver, FlvObservationRelay


def tag(kind, timestamp, payload):
    head = bytes([kind]) + len(payload).to_bytes(3, 'big')
    head += (timestamp & 0xffffff).to_bytes(3, 'big') + bytes([timestamp >> 24]) + b'\0\0\0'
    return head + payload + (11 + len(payload)).to_bytes(4, 'big')


HEADER = b'FLV\x01\x05\0\0\0\x09\0\0\0\0'
AVC = b'\x17\x01\0\0\0data'
AAC = b'\xaf\x01data'


class ObserverTests(unittest.TestCase):
    def test_every_split_preserves_tag_boundaries_and_signed_cts(self):
        data = HEADER + tag(9, 1000, b'\x27\x01\xff\xff\xf6data') + tag(8, 1000, AAC)
        for cut in range(len(data) + 1):
            parser = FlvObserver()
            parser.feed(data[:cut], 0)
            parser.feed(data[cut:], 1)
            self.assertIsNone(parser.error)
            self.assertEqual(parser.tags, 2)
            self.assertEqual(parser.last['video']['pts'], 990)
            self.assertEqual(parser.last['audio']['dts'], 1000)

    def test_wrap_is_not_a_reset_and_sequence_headers_are_not_frames(self):
        parser = FlvObserver()
        parser.feed(HEADER + tag(9, 0, b'\x17\x00\0\0\0config') +
                    tag(9, 0xfffffff0, AVC) + tag(9, 10, AVC), 1)
        self.assertEqual(parser.max_delta['video'], 26)
        self.assertEqual(list(parser.discontinuities), [])

    def test_jumps_resets_and_history_bounds(self):
        parser = FlvObserver()
        parser.feed(HEADER, 0)
        for i in range(800):
            parser.feed(tag(8, (i % 2) * 2000, AAC), i)
        self.assertEqual(len(parser.discontinuities), 64)
        self.assertEqual(len(parser.samples), 700)
        self.assertEqual(parser.pending, b'')

    def test_invalid_size_is_diagnostic_only(self):
        parser = FlvObserver()
        data = bytearray(HEADER + tag(9, 12, AVC))
        data[-1] ^= 1
        parser.feed(data, 0)
        self.assertEqual(parser.error, 'previous_tag_size')
        parser.feed(b'anything', 1)
        self.assertEqual(parser.pending, b'')

    def test_extended_codec_payload_is_not_misread_as_legacy_avc(self):
        parser = FlvObserver()
        parser.feed(HEADER + tag(9, 1000, b'\x97\x01\0\0\0data'), 1)
        self.assertEqual(parser.tags, 1)
        self.assertEqual(parser.last, {})

    def test_invalid_header_size_has_bounded_failure(self):
        parser = FlvObserver()
        parser.feed(b'FLV\x01\x05\xff\xff\xff\xff', 1)
        self.assertEqual(parser.error, 'header_length')
        self.assertEqual(len(parser.pending), 0)

    def test_single_connection_relay_is_byte_identical_and_releases_handler(self):
        data = HEADER + tag(9, 1000, AVC) + tag(8, 1000, AAC)
        requests = []

        class Source(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                requests.append(self.headers.get('User-Agent'))
                self.send_response(200)
                self.end_headers()
                for byte in data:
                    self.wfile.write(bytes([byte]))

        server = ThreadingHTTPServer(('127.0.0.1', 0), Source)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        relay = FlvObservationRelay(f'http://127.0.0.1:{server.server_port}/test',
                                   {'User-Agent': 'fixture, exact'}, time.monotonic())
        try:
            with urllib.request.urlopen(relay.url, timeout=5) as response:
                self.assertEqual(response.read(), data)
            with self.assertRaises(urllib.error.HTTPError) as caught:
                urllib.request.urlopen(relay.url, timeout=5)
            caught.exception.close()
        finally:
            relay.close()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)
        self.assertEqual(requests, ['fixture, exact'])
        self.assertEqual(relay.summary()['opens'], 1)
        self.assertTrue(relay.summary()['handlerFinished'])
        self.assertIsNone(relay.summary()['parseError'])
        self.assertFalse(relay.thread.is_alive())


if __name__ == '__main__':
    unittest.main()
