"""No ffmpeg/processes: timestamp fixture writer preserves FLV packet identity."""
import importlib.util
import pathlib
import unittest

PATH = pathlib.Path(__file__).resolve().parents[1] / 'probes/generate_recording_clock_matrix.py'
SPEC = importlib.util.spec_from_file_location('clock_matrix_generator', PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def tag(kind, timestamp, payload):
    header = bytes([kind]) + len(payload).to_bytes(3, 'big')
    header += (timestamp & 0xffffff).to_bytes(3, 'big') + bytes([timestamp >> 24]) + b'\0\0\0'
    return header + payload + (11 + len(payload)).to_bytes(4, 'big')


HEADER = b'FLV\x01\x05\0\0\0\x09\0\0\0\0'


class JitterFixtureTest(unittest.TestCase):
    def test_changes_only_raw_aac_timestamps_including_extended_byte(self):
        prefix = HEADER + tag(8, 0, b'\xaf\0\x12\x10') + tag(9, 0, b'video')
        original = prefix
        expected = prefix
        for index, delta in enumerate((0, 4, -3, 2, -2, 5, -4)):
            timestamp = 0xffffff + index * 24
            payload = b'\xaf\x01' + bytes([index]) * 5
            original += tag(8, timestamp, payload)
            expected += tag(8, timestamp + delta, payload)
        result, count = MODULE.jitter_aac_timestamps(original)
        self.assertEqual(count, 7)
        self.assertEqual(result, expected)
        self.assertEqual(len(result), len(original))

    def test_invalid_framing_and_empty_aac_rejected(self):
        valid = HEADER + tag(8, 0, b'\xaf\1abc')
        for data in (b'', b'bad' + valid[3:], valid[:-1], valid[:-4] + b'\0\0\0\0',
                     HEADER, HEADER + tag(8, 0, b'\xaf\0abc'), HEADER[:8] + b'\xff' + HEADER[9:]):
            with self.subTest(data=data), self.assertRaises(ValueError):
                MODULE.jitter_aac_timestamps(data)

    def test_jitter_must_remain_monotonic_and_within_flv_range(self):
        for timestamps in ((0, 1, 2), (0xffffffff - 1, 0xffffffff)):
            data = HEADER + b''.join(tag(8, timestamp, b'\xaf\1x') for timestamp in timestamps)
            with self.subTest(timestamps=timestamps), self.assertRaises(ValueError):
                MODULE.jitter_aac_timestamps(data)


if __name__ == '__main__':
    unittest.main()
