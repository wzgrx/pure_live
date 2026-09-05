"""Opt-in headless libmpv decode/clock probe; input credentials stay on stdin.

The Dart Huya probe supplies production URLs, headers and LiveBufferPolicy.
This exercises the supplied native library, NOT Flutter texture presentation,
hardware decoding, the OS audio device or audible-gap acceptance.
"""
import ctypes as c
import hashlib
import json
import math
import os
from pathlib import Path
import sys
import time
from flv_observation_relay import FlvObservationRelay


class Event(c.Structure):
    _fields_ = [("event_id", c.c_int), ("error", c.c_int),
                ("reply_userdata", c.c_uint64), ("data", c.c_void_p)]


class EndFile(c.Structure):
    _fields_ = [("reason", c.c_int), ("error", c.c_int)]


class Node(c.Structure):
    pass


class NodeList(c.Structure):
    _fields_ = [("num", c.c_int), ("values", c.POINTER(Node)), ("keys", c.POINTER(c.c_char_p))]


class NodeValue(c.Union):
    _fields_ = [("string", c.c_char_p), ("flag", c.c_int), ("int64", c.c_int64),
                ("double", c.c_double), ("list", c.POINTER(NodeList)), ("pointer", c.c_void_p)]


Node._fields_ = [("u", NodeValue), ("format", c.c_int)]


class MemoryCounters(c.Structure):
    _fields_ = [("cb", c.c_ulong), ("PageFaultCount", c.c_ulong)] + [
        (name, c.c_size_t) for name in (
            "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage",
            "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage",
            "PagefileUsage", "PeakPagefileUsage", "PrivateUsage")]


def memory_bytes():
    kernel = c.WinDLL("kernel32", use_last_error=True)
    kernel.GetCurrentProcess.restype = c.c_void_p
    psapi = c.WinDLL("psapi", use_last_error=True)
    psapi.GetProcessMemoryInfo.argtypes = [c.c_void_p, c.POINTER(MemoryCounters), c.c_ulong]
    value = MemoryCounters()
    value.cb = c.sizeof(value)
    if not psapi.GetProcessMemoryInfo(kernel.GetCurrentProcess(), c.byref(value), value.cb):
        raise OSError("process memory query failed")
    return {"rss": value.WorkingSetSize, "private": value.PrivateUsage}


def run(config):
    relay = None
    dll = Path(config["library"]).resolve(strict=True)
    duration = max(130, min(600, int(config["seconds"])))
    mpv = c.CDLL(str(dll))
    signatures = {
        "mpv_create": (c.c_void_p, []),
        "mpv_initialize": (c.c_int, [c.c_void_p]),
        "mpv_set_option_string": (c.c_int, [c.c_void_p, c.c_char_p, c.c_char_p]),
        "mpv_command": (c.c_int, [c.c_void_p, c.POINTER(c.c_char_p)]),
        "mpv_get_property_string": (c.c_void_p, [c.c_void_p, c.c_char_p]),
        "mpv_set_property": (c.c_int, [c.c_void_p, c.c_char_p, c.c_int, c.c_void_p]),
        "mpv_get_property": (c.c_int, [c.c_void_p, c.c_char_p, c.c_int, c.c_void_p]),
        "mpv_free_node_contents": (None, [c.POINTER(Node)]),
        "mpv_free": (None, [c.c_void_p]),
        "mpv_wait_event": (c.POINTER(Event), [c.c_void_p, c.c_double]),
        "mpv_terminate_destroy": (None, [c.c_void_p]),
    }
    for name, (result, args) in signatures.items():
        function = getattr(mpv, name)
        function.restype, function.argtypes = result, args
    handle = mpv.mpv_create()
    if not handle:
        raise RuntimeError("native allocation failed")

    def get(name):
        pointer = mpv.mpv_get_property_string(handle, name.encode())
        if not pointer:
            return None
        try:
            return c.string_at(pointer).decode("utf-8", errors="replace")
        finally:
            mpv.mpv_free(pointer)

    def number(name):
        try:
            value = float(get(name))
            return value if math.isfinite(value) else None
        except (TypeError, ValueError):
            return None

    def native_value(node):
        if node.format == 1:
            return node.u.string.decode('utf-8', errors='replace')
        if node.format == 3:
            return bool(node.u.flag)
        if node.format == 4:
            return node.u.int64
        if node.format == 5:
            return node.u.double
        if node.format in (7, 8):
            items = node.u.list.contents
            values = [native_value(items.values[index]) for index in range(items.num)]
            if node.format == 7:
                return values
            return {items.keys[index].decode(): value for index, value in enumerate(values)}
        return None

    def cache_state():
        value = Node()
        if mpv.mpv_get_property(handle, b'demuxer-cache-state', 6, c.byref(value)) < 0:
            return {}
        try:
            data = native_value(value)
            return {key: data[key] for key in (
                'fw-bytes', 'total-bytes', 'cache-duration', 'seekable-ranges',
                'bof-cached', 'eof-cached', 'idle', 'underrun') if key in data}
        finally:
            mpv.mpv_free_node_contents(c.byref(value))

    try:
        options = {
            "config": "no", "terminal": "no", "msg-level": "all=no",
            "vo": "null", "ao": "null", "hwdec": "no", "idle": "yes",
            "force-window": "no", "demuxer-lavf-probesize": "2097152",
            "demuxer-lavf-analyzeduration": "2", "network-timeout": "15",
            **config["bufferProperties"],
        }
        for name, value in options.items():
            if mpv.mpv_set_option_string(handle, name.encode(), str(value).encode()) < 0:
                raise RuntimeError(f"native option rejected: {name}")
        if mpv.mpv_initialize(handle) < 0:
            raise RuntimeError("native initialization failed")
        # Match media_kit's typed-node API. The HYSDK User-Agent contains a
        # comma; joining header strings would silently split it into two fields.
        header_bytes = [f"{key}: {value}".encode() for key, value in config["headers"].items()]
        entries = (Node * len(header_bytes))()
        for entry, value in zip(entries, header_bytes):
            entry.format, entry.u.string = 1, value
        header_list = NodeList(len(entries), entries, None)
        headers = Node(NodeValue(list=c.pointer(header_list)), 7)
        if mpv.mpv_set_property(handle, b"http-header-fields", 6, c.byref(headers)) < 0:
            raise RuntimeError("native headers rejected")
        actual = Node()
        if mpv.mpv_get_property(handle, b"http-header-fields", 6, c.byref(actual)) < 0:
            raise RuntimeError("native headers verification failed")
        try:
            if actual.format != 7:
                raise RuntimeError("native headers format differs")
            values = actual.u.list.contents
            if [values.values[i].u.string for i in range(values.num)] != header_bytes:
                raise RuntimeError("native headers round trip differs")
        finally:
            mpv.mpv_free_node_contents(c.byref(actual))
        version = get("mpv-version")
        initialized_memory = memory_bytes()
        cache_options = {name: get(name) for name in (
            'demuxer-donate-buffer', 'cache-on-disk', 'cache-secs',
            'demuxer-max-bytes', 'demuxer-max-back-bytes')}
        start, cpu_start = time.monotonic(), time.process_time()
        media_url = config["url"]
        if config.get('observeFlvTransport'):
            relay = FlvObservationRelay(media_url, config['headers'], start)
            media_url = relay.url
        command = (c.c_char_p * 4)(b"loadfile", media_url.encode(), b"replace", None)
        if mpv.mpv_command(handle, command) < 0:
            raise RuntimeError("native open failed")
        first_progress = last_progress = previous_position = initial_position = None
        last_sample, max_clock_gap, samples = start, 0.0, 0
        cache_pause_samples = pause_samples = end_events = 0
        stats, memory_samples = {}, []
        timeline = []
        last_cache_pause = False
        previous_drops = 0
        max_poll_interval = 0.0

        def mark(kind, now, position, **fields):
            # Bounded, token-free timeline. Samples are observations, not
            # individual rendered frames or a count of separate stalls.
            if len(timeline) < 64:
                timeline.append({"event": kind, "seconds": round(now - start, 3),
                                 "position": position, **fields})

        termination = "duration_limit"
        while time.monotonic() - start < duration:
            event = mpv.mpv_wait_event(handle, 0.20).contents
            if event.event_id == 7:
                end_events += 1
                end = c.cast(event.data, c.POINTER(EndFile)).contents
                termination = f"end_file:{end.reason}:{end.error}"
                break
            now = time.monotonic()
            if now - last_sample < 0.20:
                continue
            poll_interval = now - last_sample
            max_poll_interval = max(max_poll_interval, poll_interval)
            last_sample = now
            position = number("time-pos")
            if position is not None and (previous_position is None or position > previous_position + 0.0001):
                if first_progress is None:
                    first_progress, initial_position = now, position
                elif last_progress is not None:
                    max_clock_gap = max(max_clock_gap, now - last_progress)
                last_progress, previous_position = now, position
            samples += 1
            cache_paused = get("paused-for-cache") == "yes"
            cache_pause_samples += cache_paused
            if cache_paused != last_cache_pause:
                mark("cache_pause_start" if cache_paused else "cache_pause_end",
                     now, position, cache=cache_state())
                last_cache_pause = cache_paused
            if poll_interval > 0.75:
                mark("slow_poll", now, position, intervalMs=round(poll_interval * 1000))
            pause_samples += get("pause") == "yes"
            if samples % 5 == 0:
                memory_samples.append({"seconds": round(now - start, 2),
                                       **memory_bytes(), "cache": cache_state()})
            stats = {name: number(name) for name in (
                "width", "height", "estimated-vf-fps", "frame-drop-count",
                "decoder-frame-drop-count", "demuxer-cache-duration", "avsync")}
            drops = stats.get("frame-drop-count") or 0
            if drops > previous_drops:
                mark("presenter_drop_count", now, position, count=drops,
                     cachePaused=cache_paused, avsync=stats.get("avsync"))
            previous_drops = drops
        elapsed = time.monotonic() - start
        if last_progress is not None:
            max_clock_gap = max(max_clock_gap, time.monotonic() - last_progress)
        with dll.open("rb") as library_file:
            library_hash = hashlib.file_digest(library_file, "sha256").hexdigest()
        result = {
            "probe": "production-huya-headless-libmpv", "libraryVersion": version,
            "librarySha256": library_hash,
            "durationMs": round(elapsed * 1000), "termination": termination,
            "endEvents": end_events, "firstClockMs": None if first_progress is None else round((first_progress - start) * 1000),
            "maxClockProgressGapMs": round(max_clock_gap * 1000),
            "clockAdvancedSeconds": None if previous_position is None else round(previous_position - initial_position, 3),
            "sampleCount": samples, "cachePauseSamples": cache_pause_samples, "pauseSamples": pause_samples,
            "maxPollIntervalMs": round(max_poll_interval * 1000), "timeline": timeline,
            "cpuPercentMachine": round((time.process_time() - cpu_start) / elapsed / (os.cpu_count() or 1) * 100, 3),
            "nativeStats": stats, "memorySamples": memory_samples,
            "bufferProperties": config["bufferProperties"], "secretsPersisted": False,
            "flutterTextureTested": False, "audibleOutputTested": False,
            "headerRoundTripVerified": True,
            "initializedMemory": initialized_memory, "nativeCacheOptions": cache_options,
        }
        # Preserve the sampled playback result before explicitly stopping this
        # probe instance. Observe resource release without touching any app.
        if relay:
            relay.stop.set()  # Attribute the following consumer close to us.
        stop = (c.c_char_p * 2)(b'stop', None)
        if mpv.mpv_command(handle, stop) < 0:
            raise RuntimeError('native stop failed')
        stop_start = time.monotonic()
        while time.monotonic() - stop_start < 3:
            mpv.mpv_wait_event(handle, 0.20)
        result['stoppedMemory'] = memory_bytes()
        result['stoppedCache'] = cache_state()
        mpv.mpv_terminate_destroy(handle)
        handle = None
        result['destroyedMemory'] = memory_bytes()
        if relay:
            relay.close()
            result['flvTransport'] = relay.summary()
            relay = None
        return result
    finally:
        if handle:
            mpv.mpv_terminate_destroy(handle)
        if relay:
            relay.close()


if __name__ == "__main__":
    try:
        result = run(json.load(sys.stdin))
        print(json.dumps(result), flush=True)
        sys.exit(0 if result["termination"] == "duration_limit" and result["clockAdvancedSeconds"] else 1)
    except Exception as error:
        # Never print native exceptions or input, which may contain a signed URL.
        print(json.dumps({"probe": "headless-libmpv", "errorType": type(error).__name__}), flush=True)
        sys.exit(1)
