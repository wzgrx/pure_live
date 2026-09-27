"""Opt-in native cache comparison on identical synthetic FLV and arrival gaps.

Run under build_resource_guard. No CDN, credentials, phone or app operations.
The baseline properties come from a saved, sanitized native probe result;
they are an explicit experiment snapshot, not implicit production defaults.
"""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading
import time

from libmpv_continuity_probe import run


def packets(path):
    if path.stat().st_size > 8 * 1024 * 1024:
        raise ValueError('small synthetic FLV required')
    data = path.read_bytes()
    if len(data) > 8 * 1024 * 1024 or data[:3] != b'FLV':
        raise ValueError('small synthetic FLV required')
    start = int.from_bytes(data[5:9], 'big') + 4
    if not 13 <= start <= len(data):
        raise ValueError('FLV header length')
    result = [(0.0, data[:start])]
    previous_time = 0.0
    while start < len(data):
        if start + 11 > len(data):
            raise ValueError('truncated tag')
        size = int.from_bytes(data[start + 1:start + 4], 'big') + 15
        end = start + size
        if end > len(data) or int.from_bytes(data[end - 4:end], 'big') != size - 4:
            raise ValueError('invalid tag size')
        timestamp = int.from_bytes(data[start + 4:start + 7], 'big') | (data[start + 7] << 24)
        previous_time = max(previous_time, timestamp / 1000)
        result.append((previous_time, data[start:end]))
        start = end
    if previous_time < 35:
        raise ValueError('fixture must have at least 35 seconds of media')
    return result


class PacedFixture:
    def __init__(self, media, gap):
        self.stop = threading.Event()
        self.finished = threading.Event()
        self.opens = 0
        self.sent_bytes = 0
        self.injected = False
        self.error = None
        self.lock = threading.Lock()
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                with owner.lock:
                    if self.path != '/fixture.flv' or owner.opens:
                        self.send_error(409)
                        return
                    owner.opens += 1
                self.connection.settimeout(5)
                start = time.monotonic()
                try:
                    self.send_response(200)
                    self.send_header('Content-Type', 'video/x-flv')
                    self.end_headers()
                    for seconds, packet in media:
                        # At t=12 input delivery stops; backlog catches up at
                        # t=12+gap. Original media bytes and DTS are unchanged.
                        due = max(seconds, 12 + gap) if 12 <= seconds < 12 + gap else seconds
                        if owner.stop.wait(max(0.0, start + due - time.monotonic())):
                            return
                        if 12 <= seconds < 12 + gap:
                            owner.injected = True
                        self.wfile.write(packet)
                        owner.sent_bytes += len(packet)
                    owner.stop.wait(45)
                except (OSError, TimeoutError) as error:
                    # The native probe deliberately closes after 32 seconds,
                    # while this 40-second input still owns a bounded tail.
                    if time.monotonic() - start < 31:
                        owner.error = type(error).__name__
                finally:
                    owner.finished.set()

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}/fixture.flv'

    def close(self):
        self.stop.set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(2)
        if self.opens and not self.finished.wait(6):
            raise RuntimeError('fixture handler did not finish')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library', required=True, type=Path)
    parser.add_argument('--media', required=True, type=Path)
    parser.add_argument('--baseline-result', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    baseline = next(json.loads(line) for line in args.baseline_result.read_text(encoding='utf-8-sig').splitlines()
                    if line.startswith('{"probe"'))
    properties = baseline['bufferProperties']
    media = packets(args.media)
    results = []
    # A bounded delay can absorb a shorter arrival gap, not arbitrary outages.
    for name, initial, gap in [('baseline-short', 0, 2.4), ('reserve3-short', 3, 2.4), ('reserve3-long', 3, 8)]:
        fixture = PacedFixture(media, gap)
        options = dict(properties)
        if initial:
            options.update({'cache-pause-initial': 'yes', 'cache-pause-wait': str(initial)})
        try:
            result = run({'library': str(args.library), 'seconds': 32, 'url': fixture.url,
                          'headers': {}, 'bufferProperties': options, 'syntheticFixture': True})
        finally:
            fixture.close()
        runtime_starts = [e for e in result['timeline'] if e['event'] == 'cache_pause_start' and e['seconds'] >= 10]
        result.update({'case': name, 'injectedGapSeconds': gap, 'runtimePauseEpisodes': len(runtime_starts),
                       'fixtureOpens': fixture.opens, 'fixtureBytes': fixture.sent_bytes,
                       'injectionCompleted': fixture.injected, 'fixtureError': fixture.error,
                       'fixtureHandlerFinished': fixture.finished.is_set()})
        results.append(result)
        args.output.write_text(json.dumps(results, indent=2), encoding='utf-8')
        print(json.dumps({k: result[k] for k in ('case', 'durationMs', 'runtimePauseEpisodes', 'timeline')}), flush=True)
        if result['endEvents'] or fixture.error or not fixture.injected or fixture.opens != 1:
            raise RuntimeError('fixture transport acceptance failed')
    if not (results[0]['runtimePauseEpisodes'] > 0 and results[1]['runtimePauseEpisodes'] == 0
            and results[2]['runtimePauseEpisodes'] > 0):
        raise RuntimeError('candidate did not satisfy bounded jitter comparison')


if __name__ == '__main__':
    main()
