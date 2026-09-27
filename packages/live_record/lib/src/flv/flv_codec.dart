import 'dart:typed_data';

import 'package:live_media/live_media.dart';

const int _h = FlvTag.headerLength;
const _hvc1 = [0x68, 0x76, 0x63, 0x31];

/// Codec-level helpers for FLV video tags (spec §6.6, §6.7).
abstract final class FlvCodec {
  /// Whether [tag] is a legacy codec-id-12 HEVC video tag.
  static bool isLegacyHevc(Uint8List tag) =>
      FlvTag.type(tag) == FlvTag.video && tag.length > _h + 4 + 1 && (tag[_h] & 0x80) == 0 && (tag[_h] & 0x0f) == 12;

  /// Rewrites a legacy codec-12 HEVC tag as Enhanced FLV (FourCC `hvc1`):
  /// sequence header → SequenceStart, NALU → CodedFrames keeping the
  /// composition time, end of sequence → SequenceEnd; payload copied as is.
  /// Any other tag is returned unchanged (spec §6.6).
  static Uint8List rewriteLegacyHevc(Uint8List tag) {
    if (!isLegacyHevc(tag)) return tag;
    final size = FlvTag.dataSize(tag);
    if (size < 5) return tag;
    final frameType = (tag[_h] >> 4) & 0x07;
    final packetType = tag[_h + 1];
    final payload = Uint8List.sublistView(tag, _h + 5, _h + size);
    final List<int> data;
    switch (packetType) {
      case 0:
        data = [0x80 | (frameType << 4), ..._hvc1, ...payload];
      case 1:
        data = [0x80 | (frameType << 4) | 1, ..._hvc1, tag[_h + 2], tag[_h + 3], tag[_h + 4], ...payload];
      case 2:
        data = [0x80 | (frameType << 4) | 2, ..._hvc1];
      default:
        return tag;
    }
    // Keep the stream id bytes as they were.
    return FlvTag.build(type: FlvTag.video, timestamp: FlvTag.timestamp(tag), data: data)..setRange(8, 11, tag, 8);
  }

  /// NALU length field size announced by a video configuration tag (AVC or
  /// HEVC decoder configuration record); 4 when unknown.
  static int naluLengthSize(Uint8List? config) {
    if (config == null) return 4;
    final enhanced = (config[_h] & 0x80) != 0;
    if (enhanced) {
      // Enhanced SequenceStart: flag byte, FourCC, then the record.
      const record = _h + 5;
      final isHevc = _fourCc(config) == 'hvc1';
      if (isHevc && config.length > record + 21 + 4) return (config[record + 21] & 0x03) + 1;
      if (_fourCc(config) == 'avc1' && config.length > record + 4 + 4) return (config[record + 4] & 0x03) + 1;
      return 4;
    }
    final codec = config[_h] & 0x0f;
    const record = _h + 5;
    if (codec == 7 && config.length > record + 4 + 4) return (config[record + 4] & 0x03) + 1;
    if (codec == 12 && config.length > record + 21 + 4) return (config[record + 21] & 0x03) + 1;
    return 4;
  }

  static String _fourCc(Uint8List tag) => String.fromCharCodes(tag.sublist(_h + 1, _h + 5));

  /// Whether a video frame tag holds only non-picture NAL units (SEI, SPS,
  /// PPS, AUD and the like), which must not end a file (spec §6.7,
  /// REG-RECORD-009). Unknown codecs and unparsable payloads count as pictures.
  static bool isPrefixOnly(Uint8List tag, {int lengthSize = 4}) {
    if (FlvTag.type(tag) != FlvTag.video) return false;
    final size = FlvTag.dataSize(tag);
    if (size < 2 || tag.length < _h + size) return false;
    final first = tag[_h];
    int start;
    bool hevc;
    if ((first & 0x80) != 0) {
      final packetType = first & 0x0f;
      final fourCc = size >= 5 ? _fourCc(tag) : '';
      if (fourCc == 'hvc1') {
        hevc = true;
      } else if (fourCc == 'avc1') {
        hevc = false;
      } else {
        return false;
      }
      if (packetType == 1) {
        start = _h + 8;
      } else if (packetType == 3) {
        start = _h + 5;
      } else {
        return false;
      }
    } else {
      final codec = first & 0x0f;
      if ((codec != 7 && codec != 12) || tag[_h + 1] != 1) return false;
      hevc = codec == 12;
      start = _h + 5;
    }
    final end = _h + size;
    if (start >= end) return false;
    var offset = start;
    var sawNal = false;
    while (offset + lengthSize <= end) {
      var length = 0;
      for (var i = 0; i < lengthSize; i++) {
        length = (length << 8) | tag[offset + i];
      }
      offset += lengthSize;
      if (length <= 0 || offset + length > end) return false;
      final header = tag[offset];
      final type = hevc ? (header >> 1) & 0x3f : header & 0x1f;
      final picture = hevc ? type <= 31 : (type >= 1 && type <= 5) || type == 20 || type == 21;
      if (picture) return false;
      sawNal = true;
      offset += length;
    }
    return sawNal && offset == end;
  }
}
