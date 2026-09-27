import 'dart:typed_data';

import 'package:live_record/src/files.dart';
import 'package:live_record/src/remux/ts_demux.dart';
import 'package:meta/meta.dart';

/// What a scan of an HLS recording file (MPEG-TS or fragmented MP4) found (spec §14.1).
@immutable
final class HlsScan {
  /// Creates a result.
  const new({required this.validLength, required this.length, required this.media, required this.durationMs});

  /// Bytes to keep.
  final int validLength;

  /// File length before repair.
  final int length;

  /// Media units kept (PES packets, fragments); 0 means the file holds no media.
  final int media;

  /// Media time kept, roughly (first to last timestamp), in ms.
  final int durationMs;

  /// Whether the file loses bytes in the repair.
  bool get truncated => validLength < length;
}

/// Scans an MPEG-TS recording: whole 188-byte packets up to the first lost
/// sync. With more than one PAT the end is cut further, because a crash may
/// have cut a unit anywhere and a cut unit would not decode (§14.1): when
/// the last PAT sits on a video unit boundary (an HLS segment starts with
/// one) the last segment goes; when it sits inside a frame (continuous TS,
/// §8) the file ends before the last video PES instead.
Future<HlsScan> scanTs(RecordFiles files, String path, {int blockSize = 1 << 20}) async {
  final reader = await files.open(path);
  try {
    final length = reader.length;
    final size = blockSize - blockSize % tsPacketSize;
    var offset = 0;
    var valid = 0;
    final pats = <int>[];
    // Media PES starts and their PTS, with the offset of each.
    final starts = <({int offset, int? pts})>[];
    // Video PIDs (PES stream ids 0xE0–0xEF), the last video PES start, and
    // whether the first video packet after the last PAT starts a PES.
    final videoPids = <int>{};
    int? lastVideo;
    bool? patOnBoundary;
    var synced = true;
    while (offset < length && synced) {
      final block = await reader.read(offset, length - offset < size ? length - offset : size);
      if (block.isEmpty) break;
      for (var at = 0; at + tsPacketSize <= block.length; at += tsPacketSize) {
        if (block[at] != tsSync) {
          synced = false;
          break;
        }
        final unitStart = (block[at + 1] & 0x40) != 0;
        final pid = ((block[at + 1] & 0x1F) << 8) | block[at + 2];
        if (unitStart) {
          if (pid == 0) {
            pats.add(offset + at);
            patOnBoundary = null;
          } else if (pid != 0x1FFF) {
            final pts = _pesPts(block, at);
            final pes = pts != null || _isPesStart(block, at);
            if (pes) starts.add((offset: offset + at, pts: pts));
            if (pes && _isVideoPes(block, at)) {
              videoPids.add(pid);
              lastVideo = offset + at;
            }
          }
        }
        if (videoPids.contains(pid) && pats.isNotEmpty && patOnBoundary == null) patOnBoundary = unitStart;
        valid = offset + at + tsPacketSize;
      }
      offset += block.length - block.length % tsPacketSize;
      if (block.length % tsPacketSize != 0) break;
    }
    var keep = valid;
    if (pats.length > 1) {
      final video = lastVideo;
      keep = patOnBoundary == false && video != null ? video : pats.last;
    }
    final kept = starts.where((start) => start.offset < keep).toList();
    final times = [for (final start in kept) ?start.pts];
    var duration = 0;
    if (times.length > 1) {
      final first = times.reduce((a, b) => a < b ? a : b);
      final last = times.reduce((a, b) => a > b ? a : b);
      duration = (last - first) ~/ 90;
    }
    return HlsScan(validLength: kept.isEmpty ? 0 : keep, length: length, media: kept.length, durationMs: duration);
  } finally {
    await reader.close();
  }
}

bool _isPesStart(Uint8List packet, int at) {
  final payload = _payloadStart(packet, at);
  return payload != null &&
      payload + 3 <= at + tsPacketSize &&
      packet[payload] == 0 &&
      packet[payload + 1] == 0 &&
      packet[payload + 2] == 1;
}

bool _isVideoPes(Uint8List packet, int at) {
  final payload = _payloadStart(packet, at);
  return payload != null && payload + 4 <= at + tsPacketSize && (packet[payload + 3] & 0xF0) == 0xE0;
}

int? _payloadStart(Uint8List packet, int at) {
  final control = (packet[at + 3] >> 4) & 0x03;
  if (control == 0 || control == 2) return null;
  var start = at + 4;
  if (control == 3) start += 1 + packet[at + 4];
  return start < at + tsPacketSize ? start : null;
}

int? _pesPts(Uint8List packet, int at) {
  if (!_isPesStart(packet, at)) return null;
  final payload = _payloadStart(packet, at)!;
  if (payload + 14 > at + tsPacketSize) return null;
  if ((packet[payload + 7] >> 6) < 2) return null;
  final p = payload + 9;
  return ((packet[p] >> 1) & 0x07) * (1 << 30) +
      (packet[p + 1] << 22) +
      ((packet[p + 2] >> 1) << 15) +
      (packet[p + 3] << 7) +
      (packet[p + 4] >> 1);
}

/// Scans a fragmented MP4 recording: the initialisation section, then only
/// whole fragments (a `moof` and the `mdat` after it).
Future<HlsScan> scanFmp4(RecordFiles files, String path) async {
  final reader = await files.open(path);
  try {
    final length = reader.length;
    var offset = 0;
    var valid = 0;
    var init = false;
    var fragments = 0;
    var inFragment = false;
    int? timescale;
    int? trackId;
    int? firstTime;
    int? lastTime;
    int? pendingTime;
    while (offset + 8 <= length) {
      final head = await reader.read(offset, 16);
      final data = ByteData.sublistView(head);
      var size = data.getUint32(0);
      final type = String.fromCharCodes(head, 4, 8);
      if (size == 1 && head.length >= 16) size = data.getUint32(8) * 0x100000000 + data.getUint32(12);
      if (size == 0) size = length - offset;
      if (size < 8 || offset + size > length) break;
      switch (type) {
        case 'moov':
          final moov = await reader.read(offset, size);
          (timescale, trackId) = _firstTrack(moov);
          init = true;
          valid = offset + size;
        case 'moof':
          inFragment = true;
          pendingTime = trackId == null ? null : _fragmentTime(await reader.read(offset, size), trackId);
        case 'mdat':
          if (inFragment && init) {
            fragments++;
            valid = offset + size;
            if (pendingTime != null) {
              firstTime ??= pendingTime;
              lastTime = pendingTime;
            }
          }
          inFragment = false;
        default:
          // styp, sidx, prft, emsg… belong to the next fragment: kept only with it.
          break;
      }
      offset += size;
    }
    final duration = timescale == null || firstTime == null || lastTime == null
        ? 0
        : (lastTime - firstTime) * 1000 ~/ timescale;
    return HlsScan(validLength: fragments == 0 ? 0 : valid, length: length, media: fragments, durationMs: duration);
  } finally {
    await reader.close();
  }
}

/// Timescale and id of the first track in [moov].
(int?, int?) _firstTrack(Uint8List moov) {
  final data = ByteData.sublistView(moov);
  int? find(int from, int to, List<String> path) {
    var at = from;
    while (at + 8 <= to) {
      final size = data.getUint32(at);
      final type = String.fromCharCodes(moov, at + 4, at + 8);
      if (size < 8 || at + size > to) return null;
      if (type == path.first) return path.length == 1 ? at : find(at + 8, at + size, path.sublist(1));
      at += size;
    }
    return null;
  }

  final tkhd = find(8, moov.length, ['trak', 'tkhd']);
  final mdhd = find(8, moov.length, ['trak', 'mdia', 'mdhd']);
  if (tkhd == null || mdhd == null) return (null, null);
  final id = data.getUint32(tkhd + 8 + (moov[tkhd + 8] == 1 ? 20 : 12));
  final timescale = data.getUint32(mdhd + 8 + (moov[mdhd + 8] == 1 ? 20 : 12));
  return (timescale, id);
}

/// `baseMediaDecodeTime` of track [trackId] in [moof], if present.
int? _fragmentTime(Uint8List moof, int trackId) {
  final data = ByteData.sublistView(moof);
  var at = 8;
  while (at + 8 <= moof.length) {
    final size = data.getUint32(at);
    if (size < 8 || at + size > moof.length) return null;
    if (String.fromCharCodes(moof, at + 4, at + 8) == 'traf') {
      var inner = at + 8;
      int? id;
      int? time;
      while (inner + 8 <= at + size) {
        final innerSize = data.getUint32(inner);
        if (innerSize < 8 || inner + innerSize > at + size) break;
        final type = String.fromCharCodes(moof, inner + 4, inner + 8);
        if (type == 'tfhd') id = data.getUint32(inner + 12);
        if (type == 'tfdt') {
          time = moof[inner + 8] == 1
              ? data.getUint32(inner + 12) * 0x100000000 + data.getUint32(inner + 16)
              : data.getUint32(inner + 12);
        }
        inner += innerSize;
      }
      if (id == trackId) return time;
    }
    at += size;
  }
  return null;
}

/// Cuts [path] (an MPEG-TS or fragmented MP4 recording) to what [scanTs] or
/// [scanFmp4] keeps (spec §14.1) and returns the scan.
Future<HlsScan> repairHlsRecording(RecordFiles files, String path, {required bool fmp4}) async {
  final scan = fmp4 ? await scanFmp4(files, path) : await scanTs(files, path);
  if (scan.media > 0 && scan.truncated) await files.truncate(path, scan.validLength);
  return scan;
}
