"""Generate bounded synthetic recorder inputs; invoke under build_resource_guard.

The Weibo input is a previously retained local FLV, never a live URL.
Existing manifests are verified rather than overwritten. No user media is edited.
"""

import argparse
import hashlib
import json
import math
import pathlib
import subprocess
from datetime import datetime, timezone


def jitter_aac_timestamps(data):
    """Change only AAC raw-packet FLV timestamps; keep payloads/tag layout intact."""
    if len(data) > 64 * 1024 * 1024 or len(data) < 13 or data[:3] != b"FLV":
        raise ValueError("FLV fixture header or budget")
    offset = int.from_bytes(data[5:9], "big")
    if offset < 9 or offset + 4 > len(data) or data[offset:offset + 4] != b"\0\0\0\0":
        raise ValueError("FLV fixture initial offset")
    result = bytearray(data)
    offset += 4
    count = 0
    previous = -1
    adjustments = (0, 4, -3, 2, -2, 5, -4)
    while offset < len(data):
        if offset + 15 > len(data):
            raise ValueError("FLV fixture truncated tag")
        size = int.from_bytes(data[offset + 1:offset + 4], "big")
        end = offset + 11 + size
        if end + 4 > len(data) or int.from_bytes(data[end:end + 4], "big") != 11 + size:
            raise ValueError("FLV fixture tag size")
        payload = data[offset + 11:end]
        if data[offset] == 8 and len(payload) >= 2 and payload[0] >> 4 == 10 and payload[1] == 1:
            timestamp = int.from_bytes(data[offset + 4:offset + 7], "big") | data[offset + 7] << 24
            timestamp += adjustments[count % len(adjustments)]
            if not previous < timestamp <= 0xffffffff:
                raise ValueError("FLV fixture non-monotonic jitter")
            result[offset + 4:offset + 7] = (timestamp & 0xffffff).to_bytes(3, "big")
            result[offset + 7] = timestamp >> 24
            previous = timestamp
            count += 1
        offset = end + 4
    if not count:
        raise ValueError("FLV fixture has no raw AAC packets")
    return bytes(result), count


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def metadata(executable, path):
    result = subprocess.run(
        [executable, "-v", "error", "-show_streams", "-show_format", "-of", "json", str(path)],
        capture_output=True, timeout=30, check=True,
    )
    if result.stderr or len(result.stdout) > 1024 * 1024:
        raise RuntimeError("Unexpected probe diagnostics or metadata budget")
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ffmpeg", required=True)
    parser.add_argument("--ffprobe", required=True)
    parser.add_argument("--output-directory", required=True)
    parser.add_argument("--weibo-input", required=True)
    args = parser.parse_args()
    root = pathlib.Path(args.output_directory).resolve()
    root.mkdir(parents=True, exist_ok=True)
    manifest_path = root / "manifest.json"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        for case in manifest["cases"]:
            if digest(pathlib.Path(case["input"])) != case["sha256"]:
                raise RuntimeError("Existing fixture identity changed")
        print("Verified existing immutable matrix:", manifest_path)
        return
    report = {"createdAtUtc": datetime.now(timezone.utc).isoformat(), "cases": []}

    def add_case(name, path, expected, generation=None, legacy_repro=False):
        info = metadata(args.ffprobe, path)
        (root / f"{name}.metadata.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
        streams = [stream for stream in info["streams"] if stream["codec_type"] in ("audio", "video")]
        # FLV can declare audio before video. Identity is per media ordinal,
        # never the cross-type stream ordering changed by an explicit -map.
        if sorted(stream["codec_name"] for stream in streams) != sorted(expected):
            raise RuntimeError("Unexpected source codecs: " + name)
        ordinals = {"video": 0, "audio": 0}
        tracks = []
        for stream in streams:
            kind = stream["codec_type"]
            ordinal = ordinals[kind]
            ordinals[kind] += 1
            tracks.append({
                "label": f"{kind}_{ordinal}", "selector": f"0:{kind[0]}:{ordinal}",
                "kind": kind, "codec": stream["codec_name"],
                "sampleRate": int(stream["sample_rate"]) if kind == "audio" else None,
                "channels": stream.get("channels"), "width": stream.get("width"),
                "height": stream.get("height"), "pixelFormat": stream.get("pix_fmt"),
            })
        # Captured live FLV metadata need not describe the retained interval.
        # This value is a merge-deadline hint, not the decoded-content oracle.
        duration = 30.0 if legacy_repro else float(info["format"]["duration"])
        if not math.isfinite(duration) or not 10 < duration < 60:
            raise RuntimeError("Unexpected generated fixture duration")
        entry = {
            "id": name, "input": str(path.resolve()), "sha256": digest(path),
            "bytes": path.stat().st_size, "recordedSeconds": math.ceil(duration),
            "minimumSegments": 2, "tracks": tracks, "legacyRepro": legacy_repro,
            "sourceMetadata": info,
        }
        if generation:
            entry["generation"] = generation
        report["cases"].append(entry)
        # Preserve partial generation evidence separately if a later encoder fails.
        (root / "generation-progress.json").write_text(json.dumps(report, indent=2), encoding="utf-8")

    add_case("weibo-retained", pathlib.Path(args.weibo_input), ["h264", "aac"], legacy_repro=True)
    for name in ["hevc-aac48-stereo", "hevc10-aac48", "h264-dual-audio", "h264-ts-wrap"]:
        target = root / f"{name}.ts"
        if target.exists():
            raise RuntimeError("Partial fixture already exists; inspect evidence before choosing a new output directory")
        hevc = name.startswith("hevc")
        dual = name == "h264-dual-audio"
        command = [args.ffmpeg, "-v", "error", "-n", "-f", "lavfi", "-i",
                   "testsrc2=size=160x96:rate=20:duration=26", "-itsoffset", "-0.055",
                   "-f", "lavfi", "-i", "sine=frequency=997:sample_rate=48000:duration=26"]
        if dual:
            command += ["-itsoffset", "0.035", "-f", "lavfi", "-i", "sine=frequency=1234:sample_rate=44100:duration=26"]
        command += ["-map", "0:v:0", "-map", "1:a:0"]
        if dual:
            command += ["-map", "2:a:0"]
        command += ["-c:v", "libx265" if hevc else "libx264", "-preset", "ultrafast", "-threads", "4",
                    "-crf", "23", "-bf", "3", "-g", "61", "-pix_fmt", "yuv420p10le" if name.startswith("hevc10") else "yuv420p"]
        if hevc:
            command += ["-x265-params", "pools=4:frame-threads=2:log-level=error:keyint=61:min-keyint=61:scenecut=0:b-adapt=0:open-gop=0"]
        else:
            command += ["-x264-params", "keyint=61:min-keyint=61:scenecut=0:b-adapt=0:open-gop=0"]
        command += ["-c:a", "aac", "-b:a", "96k", "-ar:a:0", "48000", "-ac:a:0", "2"]
        if dual:
            command += ["-ar:a:1", "44100", "-ac:a:1", "1"]
        if name == "h264-ts-wrap":
            command += ["-output_ts_offset", "95430"]
        command += ["-t", "26", "-f", "mpegts", str(target)]
        result = subprocess.run(command, capture_output=True, timeout=90)
        (root / f"{name}.stderr").write_bytes(result.stderr)
        if result.returncode:
            raise RuntimeError("Synthetic generation failed: " + name)
        add_case(name, target, ["hevc" if hevc else "h264", "aac"] + (["aac"] if dual else []),
                 {"command": command, "exitCode": result.returncode, "stderrBytes": len(result.stderr)})
    # AAC frames become very small during silence. This defeats a misleading
    # PES-size-only workaround: each timestamp must survive even below 170 B.
    clean = root / "aac-jitter-silence-clean.flv"
    target = root / "aac-jitter-silence.flv"
    if clean.exists() or target.exists():
        raise RuntimeError("Partial jitter fixture exists; retain it and use a new output directory")
    command = [args.ffmpeg, "-v", "error", "-n", "-f", "lavfi", "-i",
               "testsrc2=size=160x96:rate=20:duration=26", "-f", "lavfi", "-i",
               "sine=frequency=997:sample_rate=48000:duration=26", "-map", "0:v:0", "-map", "1:a:0",
               "-c:v", "libx264", "-preset", "ultrafast", "-threads", "4", "-crf", "23", "-bf", "3", "-g", "61",
               "-x264-params", "keyint=61:min-keyint=61:scenecut=0:b-adapt=0:open-gop=0",
               "-af", "volume=if(between(t\\,9\\,14)\\,0\\,1):eval=frame",
               "-c:a", "aac", "-b:a", "96k", "-ac:a", "1", "-t", "26", "-f", "flv", str(clean)]
    result = subprocess.run(command, capture_output=True, timeout=90)
    (root / "aac-jitter-silence.stderr").write_bytes(result.stderr)
    if result.returncode:
        raise RuntimeError("Synthetic jitter generation failed")
    changed, packets = jitter_aac_timestamps(clean.read_bytes())
    target.write_bytes(changed)
    add_case("aac-jitter-silence", target, ["h264", "aac"],
             {"command": command, "exitCode": result.returncode, "cleanSha256": digest(clean),
              "timestampJitterMs": [0, 4, -3, 2, -2, 5, -4], "modifiedAacPackets": packets})
    report["runtimeHashes"] = {name: digest(pathlib.Path(getattr(args, name))) for name in ("ffmpeg", "ffprobe")}
    manifest_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"manifest": str(manifest_path), "cases": [case["id"] for case in report["cases"]]}))


if __name__ == "__main__":
    main()
