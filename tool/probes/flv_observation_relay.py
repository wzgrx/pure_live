"""Opt-in, byte-preserving loopback observation of one FLV media connection.

No packet rewriting, media files, URL/header logging, retries or alternate CDN.
The relay changes the HTTP/TLS client, so results are not direct-mpv equivalence.
"""
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading
import time
import urllib.request


class FlvObserver:
    def __init__(self):
        self.pending = bytearray()
        self.header = False
        self.tags = 0
        self.last = {}
        self.max_delta = {}
        self.discontinuities = deque(maxlen=64)
        self.samples = deque(maxlen=700)
        self.last_sample = -1
        self.error = None

    def feed(self, chunk, seconds):
        if self.error:
            return
        self.pending.extend(chunk)
        try:
            if not self.header:
                if len(self.pending) < 9:
                    return
                if self.pending[:3] != b'FLV':
                    raise ValueError('signature')
                offset = int.from_bytes(self.pending[5:9], 'big')
                if not 9 <= offset <= 4096:
                    raise ValueError('header_length')
                if len(self.pending) < offset + 4:
                    return
                if self.pending[offset:offset + 4] != b'\0\0\0\0':
                    raise ValueError('initial_previous_size')
                del self.pending[:offset + 4]
                self.header = True
            while len(self.pending) >= 11:
                data_size = int.from_bytes(self.pending[1:4], 'big')
                total = 11 + data_size + 4
                if len(self.pending) < total:
                    break
                if int.from_bytes(self.pending[total - 4:total], 'big') != total - 4:
                    raise ValueError('previous_tag_size')
                kind = self.pending[0] & 31
                dts = int.from_bytes(self.pending[4:7], 'big') | (self.pending[7] << 24)
                payload = self.pending[11:11 + min(data_size, 5)]
                self.tags += 1
                # Only interpret legacy AVC/AAC media packets, not sequence
                # headers, metadata or unknown/enhanced payload layouts.
                is_audio = kind == 8 and len(payload) >= 2 and payload[0] >> 4 == 10 and payload[1] == 1
                is_video = (kind == 9 and len(payload) >= 5 and not payload[0] & 128
                            and payload[0] & 15 == 7 and payload[1] == 1)
                if is_audio or is_video:
                    track = 'audio' if is_audio else 'video'
                    previous = self.last.get(track)
                    delta = None if previous is None else ((dts - previous['dts'] + 2**31) % 2**32) - 2**31
                    cts = int.from_bytes(payload[2:5], 'big', signed=True) if is_video else 0
                    self.last[track] = {'dts': dts, 'pts': dts + cts, 'receivedSeconds': round(seconds, 3)}
                    if delta is not None:
                        self.max_delta[track] = max(self.max_delta.get(track, 0), delta)
                        if delta < 0 or delta > 500:
                            self.discontinuities.append({'seconds': round(seconds, 3), 'track': track, 'dtsDeltaMs': delta})
                del self.pending[:total]
            if int(seconds) != self.last_sample:
                self.last_sample = int(seconds)
                self.samples.append({'seconds': round(seconds, 3), **self.last})
        except ValueError as error:
            self.error = str(error)  # Fixed parser labels only, never payload.
            self.pending.clear()

    def summary(self):
        return {'tags': self.tags, 'pendingBytes': len(self.pending), 'parseError': self.error,
                'maxDtsDeltaMs': dict(self.max_delta), 'discontinuities': list(self.discontinuities),
                'mediaTimeline': list(self.samples)}


class FlvObservationRelay:
    def __init__(self, url, headers, start):
        self.start = start
        self.observer = FlvObserver()
        self.events = deque(maxlen=128)
        self.byte_count = 0
        self.opens = 0
        self.max_read_ms = self.max_write_ms = 0
        self.end = 'not_started'
        self.stop = threading.Event()
        self.response = None
        self.finished = threading.Event()
        self.lock = threading.Lock()
        owner = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = 'HTTP/1.0'

            def log_message(self, *args):
                pass

            def do_GET(self):
                self.connection.settimeout(15)
                with owner.lock:
                    if self.path != '/observe.flv' or owner.opens:
                        self.send_error(409)
                        return
                    owner.opens += 1
                try:
                    request = urllib.request.Request(url, headers=headers)
                    with urllib.request.urlopen(request, timeout=15) as response:
                        owner.response = response
                        if response.status != 200:
                            raise ValueError('upstream_status')
                        self.send_response(200)
                        self.send_header('Content-Type', 'video/x-flv')
                        self.send_header('Connection', 'close')
                        self.end_headers()
                        owner.end = 'reading'
                        while not owner.stop.is_set():
                            before = time.monotonic()
                            chunk = response.read1(65536)
                            arrived = time.monotonic()
                            read_ms = round((arrived - before) * 1000)
                            owner.max_read_ms = max(owner.max_read_ms, read_ms)
                            if not chunk:
                                owner.end = 'upstream_eof'
                                break
                            owner.byte_count += len(chunk)
                            owner.observer.feed(chunk, arrived - start)
                            writing = time.monotonic()
                            self.wfile.write(chunk)
                            write_ms = round((time.monotonic() - writing) * 1000)
                            owner.max_write_ms = max(owner.max_write_ms, write_ms)
                            if read_ms >= 300 or write_ms >= 300:
                                owner.events.append({'seconds': round(arrived - start, 3),
                                                     'readWaitMs': read_ms, 'writeWaitMs': write_ms,
                                                     'bytes': len(chunk)})
                        if owner.stop.is_set():
                            owner.end = 'probe_stop'
                except Exception as error:
                    owner.end = 'probe_stop' if owner.stop.is_set() else type(error).__name__
                finally:
                    owner.response = None
                    owner.finished.set()

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}/observe.flv'

    def close(self):
        self.stop.set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        # An outstanding remote read has a finite socket timeout. No kill of
        # another process, unbounded join or forced close of user connections.
        if self.opens:
            self.finished.wait(timeout=16)

    def summary(self):
        return {'opens': self.opens, 'bytes': self.byte_count, 'end': self.end,
                'handlerFinished': self.finished.is_set(), 'maxReadWaitMs': self.max_read_ms,
                'maxWriteWaitMs': self.max_write_ms, 'ioTimeline': list(self.events),
                **self.observer.summary()}
