import 'dart:io';
import 'dart:typed_data';

import 'package:live_media/live_media.dart';

const int _h = FlvTag.headerLength;

/// Bytes of `test/fixtures/remux/<name>`.
Uint8List remuxFixture(String name) => File('test/fixtures/remux/$name').readAsBytesSync();

/// Hex string to bytes.
Uint8List hex(String text) {
  final clean = text.replaceAll(RegExp(r'\s'), '');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

/// The packets of an FLV file: the header first, then each tag.
List<Uint8List> flvPackets(Uint8List file) => FlvFramer().add(file);

/// An FLV file from [packets] (a header first, then tags).
Uint8List flvFile(Iterable<Uint8List> packets) {
  final out = BytesBuilder(copy: false);
  packets.forEach(out.add);
  return out.takeBytes();
}

/// The payload of [tag] (between header and PreviousTagSize).
Uint8List tagData(Uint8List tag) => Uint8List.sublistView(tag, _h, _h + FlvTag.dataSize(tag));

/// A legacy AVC (codec 7) or HEVC (codec 12) video tag.
Uint8List videoTag(int ts, List<int> payload, {int packetType = 1, bool key = false, int cts = 0, int codec = 7}) =>
    FlvTag.build(
      type: FlvTag.video,
      timestamp: ts,
      data: [(key ? 0x10 : 0x20) | codec, packetType, (cts >> 16) & 0xff, (cts >> 8) & 0xff, cts & 0xff, ...payload],
    );

/// An AAC tag: an AudioSpecificConfig ([packetType] 0) or a raw frame.
Uint8List aacTag(int ts, List<int> payload, {int packetType = 1}) =>
    FlvTag.build(type: FlvTag.audio, timestamp: ts, data: [0xaf, packetType, ...payload]);

/// A tiny AVC stream configuration (64x48 High profile, from the fixture).
Uint8List avcRecordOf(Uint8List fixture) {
  for (final tag in flvPackets(fixture).skip(1)) {
    if (FlvTag.isVideoConfig(tag)) return Uint8List.fromList(tagData(tag).sublist(5));
  }
  throw StateError('no video config');
}

/// Length-prefixed NAL units (4-byte lengths) from [units].
Uint8List nals(List<List<int>> units) {
  final out = BytesBuilder();
  for (final unit in units) {
    out
      ..add([(unit.length >> 24) & 0xff, (unit.length >> 16) & 0xff, (unit.length >> 8) & 0xff, unit.length & 0xff])
      ..add(unit);
  }
  return out.takeBytes();
}

/// Annex B from 4-byte length-prefixed [data].
Uint8List annexBOf(Uint8List data) {
  final out = BytesBuilder();
  var at = 0;
  while (at + 4 <= data.length) {
    final length = ByteData.sublistView(data, at, at + 4).getUint32(0);
    out
      ..add([0, 0, 0, 1])
      ..add(Uint8List.sublistView(data, at + 4, at + 4 + length));
    at += 4 + length;
  }
  return out.takeBytes();
}

/// An ADTS header for an AAC-LC frame of [payloadLength] bytes.
Uint8List adtsHeader(int payloadLength, {int rateIndex = 4, int channels = 2}) {
  final length = payloadLength + 7;
  return Uint8List.fromList([
    0xff,
    0xf1,
    (1 << 6) | (rateIndex << 2) | (channels >> 2),
    ((channels & 3) << 6) | (length >> 11),
    (length >> 3) & 0xff,
    ((length & 7) << 5) | 0x1f,
    0xfc,
  ]);
}
