import 'dart:typed_data';

import 'package:live_media/live_media.dart';
import 'package:live_record/src/files.dart';
import 'package:meta/meta.dart';

/// What a scan of an FLV file found (spec §14.1).
@immutable
final class FlvScan {
  /// Creates a result.
  const new({required this.validLength, required this.length, required this.mediaTags, required this.lastTimestamp});

  /// Bytes up to the end of the last complete tag (0 when the header is bad).
  final int validLength;

  /// File length before repair.
  final int length;

  /// Complete audio and video tags.
  final int mediaTags;

  /// Timestamp of the last complete media tag, in ms.
  final int lastTimestamp;

  /// Whether the file ends in a partial tag.
  bool get truncated => validLength < length;
}

/// Walks [path] tag by tag and reports where the last complete tag ends. A
/// tag is complete when its header, payload and PreviousTagSize are all there
/// and the PreviousTagSize matches.
Future<FlvScan> scanFlv(RecordFiles files, String path) async {
  final reader = await files.open(path);
  try {
    final length = reader.length;
    final header = await reader.read(0, 13);
    if (header.length < 13 || header[0] != 0x46 || header[1] != 0x4C || header[2] != 0x56) {
      return FlvScan(validLength: 0, length: length, mediaTags: 0, lastTimestamp: 0);
    }
    final dataOffset = ByteData.sublistView(header, 5, 9).getUint32(0);
    var offset = dataOffset + 4;
    var valid = offset <= length ? offset : 0;
    var media = 0;
    var last = 0;
    while (offset + FlvTag.headerLength <= length) {
      final head = await reader.read(offset, FlvTag.headerLength);
      if (head.length < FlvTag.headerLength) break;
      final type = head[0] & 0x1f;
      if (type != FlvTag.audio && type != FlvTag.video && type != FlvTag.script) break;
      final size = (head[1] << 16) | (head[2] << 8) | head[3];
      final end = offset + FlvTag.headerLength + size + 4;
      if (end > length) break;
      final previous = await reader.read(end - 4, 4);
      if (ByteData.sublistView(previous).getUint32(0) != FlvTag.headerLength + size) break;
      if (type != FlvTag.script) {
        media++;
        last = (head[7] << 24) | (head[4] << 16) | (head[5] << 8) | head[6];
      }
      offset = end;
      valid = end;
    }
    return FlvScan(validLength: valid, length: length, mediaTags: media, lastTimestamp: last);
  } finally {
    await reader.close();
  }
}

/// Truncates [path] after its last complete tag (spec §14.1) and returns the scan.
Future<FlvScan> repairFlv(RecordFiles files, String path) async {
  final scan = await scanFlv(files, path);
  if (scan.truncated) await files.truncate(path, scan.validLength);
  return scan;
}
