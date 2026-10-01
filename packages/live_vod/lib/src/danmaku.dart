import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_vod/src/models.dart';

/// How long one danmaku segment covers (`dm_seg.page_size`, 6 minutes).
const Duration danmakuSegmentLength = Duration(minutes: 6);

/// On-demand danmaku parsing: the segmented protobuf (`x/v2/dm/wbi/web/seg.so`
/// → `DmSegMobileReply`), the view reply (`x/v2/dm/web/view` →
/// `DmWebViewReply`) and the whole-file XML fallback (`comment.bilibili.com/
/// {cid}.xml`).
///
/// The wire reader follows `live_danmaku`'s `ProtoMessage` (M5.4); this
/// package may not depend on `live_danmaku`, so the few lines it needs are
/// here. pure_live_TV `b9d2f739` `bilibili_danmaku_api.dart` skipped unknown
/// fields of a danmaku by re-reading the key instead of the value, so any
/// string field it did not know (midHash, action, idStr) shifted the rest of
/// the element: fixed by skipping by wire type.
abstract final class VodDanmakuParse {
  /// `DmWebViewReply`: the number of segments (field 4 `dm_sge` → 2
  /// `total`) and the segment length (→ 1 `page_size`, ms). [duration]
  /// gives the count when the reply has none.
  static ({int segments, Duration segmentLength}) view(List<int> bytes, {Duration duration = Duration.zero}) {
    var segments = 0;
    var length = danmakuSegmentLength;
    try {
      for (final field in _fields(bytes)) {
        if (field.number != 4 || field.bytes == null) continue;
        for (final inner in _fields(field.bytes!)) {
          if (inner.number == 1 && inner.value != null && inner.value! > 0) {
            length = Duration(milliseconds: inner.value!);
          }
          if (inner.number == 2 && inner.value != null) segments = inner.value!;
        }
      }
    } on FormatException {
      segments = 0;
    }
    if (segments <= 0 && duration > Duration.zero) {
      segments = (duration.inMilliseconds / length.inMilliseconds).ceil();
    }
    return (segments: segments, segmentLength: length);
  }

  /// `DmSegMobileReply.elems` (field 1), sorted by time. Element fields: 1 id,
  /// 2 progress (ms), 3 mode, 4 fontsize, 5 color, 6 midHash, 7 content, 8
  /// ctime, 9 weight, 10 action, 11 pool, 12 idStr. A malformed tail keeps
  /// what was read before it.
  static List<VodDanmaku> segment(List<int> bytes) {
    final out = <VodDanmaku>[];
    try {
      for (final field in _fields(bytes)) {
        if (field.number != 1 || field.bytes == null) continue;
        var progress = 0;
        var mode = 1;
        var size = 25;
        var color = 0xFFFFFF;
        var weight = 0;
        var pool = 0;
        var text = '';
        var id = '';
        for (final inner in _fields(field.bytes!)) {
          switch (inner.number) {
            case 2:
              progress = inner.value ?? progress;
            case 3:
              mode = inner.value ?? mode;
            case 4:
              size = inner.value ?? size;
            case 5:
              color = inner.value ?? color;
            case 7 when inner.bytes != null:
              text = utf8.decode(inner.bytes!, allowMalformed: true);
            case 9:
              weight = inner.value ?? weight;
            case 11:
              pool = inner.value ?? pool;
            case 12 when inner.bytes != null:
              id = utf8.decode(inner.bytes!, allowMalformed: true);
            case 1 when id.isEmpty && inner.value != null:
              id = '${inner.value}';
          }
        }
        if (text.isEmpty) continue;
        out.add(
          VodDanmaku(
            progress: Duration(milliseconds: progress),
            text: text,
            id: id,
            mode: mode,
            fontSize: size,
            color: color & 0xFFFFFF,
            weight: weight,
            pool: pool,
          ),
        );
      }
    } on FormatException {
      // Keep what was read.
    }
    return out..sort((a, b) => a.progress.compareTo(b.progress));
  }

  static final RegExp _row = RegExp('<d p="([^"]*)">([^<]*)</d>');

  /// The XML file: `<d p="time,mode,size,color,ctime,pool,midHash,dmid,weight">text</d>`,
  /// sorted by time.
  static List<VodDanmaku> xml(String text) {
    final out = <VodDanmaku>[];
    for (final match in _row.allMatches(text)) {
      final fields = match.group(1)!.split(',');
      final seconds = double.tryParse(fields.firstOrNull ?? '');
      final body = decodeHtmlEntities(match.group(2)!).trim();
      if (seconds == null || seconds < 0 || body.isEmpty) continue;
      int at(int index, int fallback) => index < fields.length ? int.tryParse(fields[index]) ?? fallback : fallback;
      out.add(
        VodDanmaku(
          progress: Duration(microseconds: (seconds * 1000000).round()),
          text: body,
          mode: at(1, 1),
          fontSize: at(2, 25),
          color: at(3, 0xFFFFFF) & 0xFFFFFF,
          pool: at(5, 0),
          id: fields.length > 7 ? fields[7] : '',
          weight: at(8, 0),
        ),
      );
    }
    return out..sort((a, b) => a.progress.compareTo(b.progress));
  }

  /// One level of protobuf fields: varints as `value`, length-delimited as
  /// `bytes`; fixed32/64 skipped. Throws [FormatException] when truncated.
  static Iterable<({int number, int? value, Uint8List? bytes})> _fields(List<int> source) sync* {
    final data = source is Uint8List ? source : Uint8List.fromList(source);
    var offset = 0;
    int varint() {
      var result = 0;
      for (var shift = 0; shift < 70; shift += 7) {
        if (offset >= data.length) throw const FormatException('Truncated protobuf varint');
        final byte = data[offset++];
        result |= (byte & 0x7F) << shift;
        if (byte < 0x80) return result;
      }
      throw const FormatException('Protobuf varint longer than ten bytes');
    }

    while (offset < data.length) {
      final key = varint();
      final number = key >> 3;
      switch (key & 7) {
        case 0:
          yield (number: number, value: varint(), bytes: null);
        case 1:
          offset += 8;
        case 2:
          final length = varint();
          if (length < 0 || offset + length > data.length) throw const FormatException('Truncated protobuf field');
          yield (number: number, value: null, bytes: Uint8List.sublistView(data, offset, offset + length));
          offset += length;
        case 5:
          offset += 4;
        default:
          throw FormatException('Unsupported protobuf wire type ${key & 7}');
      }
      if (offset > data.length) throw const FormatException('Truncated protobuf field');
    }
  }
}
