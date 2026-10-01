import 'dart:typed_data';

/// FLV tag access (Adobe FLV specification v10.1 annex E, and the Enhanced
/// RTMP/FLV extension for HEVC/AV1).
///
/// A tag here is a complete packet as [FlvFramer] yields it: the 11-byte tag
/// header, the payload and the trailing 4-byte PreviousTagSize.
abstract final class FlvTag {
  /// Audio tag type.
  static const audio = 8;

  /// Video tag type.
  static const video = 9;

  /// Script data (onMetaData) tag type.
  static const script = 18;

  /// Tag header length.
  static const headerLength = 11;

  /// The tag type.
  static int type(Uint8List tag) => tag[0] & 0x1f;

  /// Payload length from the header.
  static int dataSize(Uint8List tag) => (tag[1] << 16) | (tag[2] << 8) | tag[3];

  /// Timestamp in milliseconds (24 bits plus the extension byte).
  static int timestamp(Uint8List tag) => (tag[7] << 24) | (tag[4] << 16) | (tag[5] << 8) | tag[6];

  /// A copy of [tag] with [timestamp] (wrapped to 32 bits).
  static Uint8List withTimestamp(Uint8List tag, int timestamp) {
    final copy = Uint8List.fromList(tag);
    final value = timestamp & 0xffffffff;
    copy[4] = (value >> 16) & 0xff;
    copy[5] = (value >> 8) & 0xff;
    copy[6] = value & 0xff;
    copy[7] = (value >> 24) & 0xff;
    return copy;
  }

  static bool _enhanced(Uint8List tag) => (tag[headerLength] & 0x80) != 0;

  static int _frameType(Uint8List tag) => (tag[headerLength] >> 4) & 0x07;

  /// A video decoder configuration: AVC/legacy-HEVC sequence header or an
  /// Enhanced FLV SequenceStart.
  static bool isVideoConfig(Uint8List tag) {
    if (type(tag) != video || tag.length < headerLength + 2 + 4) return false;
    if (_enhanced(tag)) return (tag[headerLength] & 0x0f) == 0;
    final codec = tag[headerLength] & 0x0f;
    return (codec == 7 || codec == 12) && tag[headerLength + 1] == 0;
  }

  /// A video keyframe carrying picture data (not a configuration or end-of-sequence).
  static bool isKeyframe(Uint8List tag) {
    if (type(tag) != video || tag.length < headerLength + 2 + 4 || _frameType(tag) != 1) return false;
    if (_enhanced(tag)) {
      final packetType = tag[headerLength] & 0x0f;
      return packetType == 1 || packetType == 3;
    }
    final codec = tag[headerLength] & 0x0f;
    if (codec == 7 || codec == 12) return tag[headerLength + 1] == 1;
    return true;
  }

  /// An AAC AudioSpecificConfig.
  static bool isAudioConfig(Uint8List tag) =>
      type(tag) == audio &&
      tag.length > headerLength + 2 + 4 &&
      (tag[headerLength] >> 4) == 10 &&
      tag[headerLength + 1] == 0;

  /// Whether two tags carry the same payload (timestamps may differ).
  static bool samePayload(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = headerLength; i < a.length - 4; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Builds a complete tag with its trailing PreviousTagSize.
  static Uint8List build({required int type, required int timestamp, required List<int> data}) {
    final tag = Uint8List(headerLength + data.length + 4);
    final size = data.length;
    final value = timestamp & 0xffffffff;
    tag
      ..[0] = type
      ..[1] = (size >> 16) & 0xff
      ..[2] = (size >> 8) & 0xff
      ..[3] = size & 0xff
      ..[4] = (value >> 16) & 0xff
      ..[5] = (value >> 8) & 0xff
      ..[6] = value & 0xff
      ..[7] = (value >> 24) & 0xff
      ..setRange(headerLength, headerLength + size, data);
    final previous = headerLength + size;
    ByteData.sublistView(tag).setUint32(headerLength + size, previous);
    return tag;
  }

  /// The FLV file header with audio and video flags, followed by PreviousTagSize0.
  static Uint8List fileHeader({bool audio = true, bool video = true}) =>
      Uint8List.fromList([0x46, 0x4C, 0x56, 1, (audio ? 4 : 0) | (video ? 1 : 0), 0, 0, 0, 9, 0, 0, 0, 0]);
}

/// Splits an FLV byte stream into packets: first the file header (with
/// PreviousTagSize0), then one complete tag per packet.
final class FlvFramer {
  var _buffer = Uint8List(64 * 1024);
  var _start = 0;
  var _end = 0;
  var _headerDone = false;

  /// Bytes received but not yet framed.
  int get pending => _end - _start;

  /// Adds [chunk] and returns every packet it completed. Throws
  /// [FormatException] when the stream is not FLV or a tag type is invalid.
  List<Uint8List> add(List<int> chunk) {
    _append(chunk);
    final packets = <Uint8List>[];
    while (true) {
      final available = _end - _start;
      if (!_headerDone) {
        if (available < 9) break;
        if (_buffer[_start] != 0x46 || _buffer[_start + 1] != 0x4C || _buffer[_start + 2] != 0x56) {
          throw const FormatException('Not an FLV stream');
        }
        final dataOffset = ByteData.sublistView(_buffer, _start + 5, _start + 9).getUint32(0);
        if (dataOffset < 9 || dataOffset > 1024) throw FormatException('Bad FLV header length $dataOffset');
        if (available < dataOffset + 4) break;
        packets.add(Uint8List.fromList(Uint8List.sublistView(_buffer, _start, _start + dataOffset + 4)));
        _start += dataOffset + 4;
        _headerDone = true;
        continue;
      }
      if (available < FlvTag.headerLength) break;
      final type = _buffer[_start] & 0x1f;
      if (type != FlvTag.audio && type != FlvTag.video && type != FlvTag.script) {
        throw FormatException('Bad FLV tag type $type');
      }
      final size = (_buffer[_start + 1] << 16) | (_buffer[_start + 2] << 8) | _buffer[_start + 3];
      final total = FlvTag.headerLength + size + 4;
      if (available < total) break;
      packets.add(Uint8List.fromList(Uint8List.sublistView(_buffer, _start, _start + total)));
      _start += total;
    }
    if (_start == _end) {
      _start = 0;
      _end = 0;
    }
    return packets;
  }

  void _append(List<int> chunk) {
    final needed = _end + chunk.length;
    if (needed > _buffer.length) {
      final live = _end - _start;
      if (live + chunk.length <= _buffer.length && _start > 0) {
        _buffer.setRange(0, live, _buffer, _start);
      } else {
        var capacity = _buffer.length;
        while (capacity < live + chunk.length) {
          capacity *= 2;
        }
        final grown = Uint8List(capacity)..setRange(0, live, _buffer, _start);
        _buffer = grown;
      }
      _start = 0;
      _end = live;
    }
    _buffer.setRange(_end, _end + chunk.length, chunk);
    _end += chunk.length;
  }
}

/// Rewrites legacy "codec id 12" HEVC video tags into Enhanced FLV (3.x's
/// `FlvLegacyHevcTagRewriter`, unchanged).
///
/// Several CDNs (Kuaishou, 17LIVE, Inke) put HEVC into classic FLV as codec
/// id 12 before Enhanced RTMP existed. FFmpeg learned that id in 8.0; an
/// older FFmpeg drops the video. Enhanced FLV (`hvc1`) is understood since
/// FFmpeg 6.1, so only the tag header changes: NAL payloads and the decoder
/// configuration record are copied.
final class FlvLegacyHevcRewriter {
  static const int _legacyHevcCodecId = 12;
  static const List<int> _hvc1 = [0x68, 0x76, 0x63, 0x31];

  int _rewrittenTags = 0;

  /// Tags rewritten so far.
  int get rewrittenTags => _rewrittenTags;

  /// [tag] (a complete tag as [FlvFramer] yields it) in Enhanced FLV when it
  /// is a legacy HEVC tag; anything else unchanged.
  Uint8List rewrite(Uint8List tag) {
    if (tag.length < 11 + 5 + 4 || (tag[0] & 0x1f) != FlvTag.video) return tag;
    final flags = tag[11];
    if ((flags & 0x80) != 0 || (flags & 0x0f) != _legacyHevcCodecId) return tag;
    final dataSize = FlvTag.dataSize(tag);
    if (dataSize < 5 || 11 + dataSize + 4 != tag.length) return tag;
    final frameType = (flags >> 4) & 0x07;
    // Legacy: flags, AVCPacketType, CompositionTime(3), data.
    // Enhanced: flags|packetType, FourCC, [CompositionTime(3) for coded frames], data.
    final (List<int> prefix, int payloadStart) = switch (tag[12]) {
      0 => ([0x80 | (frameType << 4), ..._hvc1], 16),
      1 => ([0x80 | (frameType << 4) | 1, ..._hvc1, tag[13], tag[14], tag[15]], 16),
      2 => ([0x80 | (frameType << 4) | 2, ..._hvc1], 11 + dataSize),
      _ => (const <int>[], -1),
    };
    if (payloadStart < 0) return tag;
    final payloadLength = 11 + dataSize - payloadStart;
    final newDataSize = prefix.length + payloadLength;
    if (newDataSize > 0xffffff) return tag;
    final out = Uint8List(11 + newDataSize + 4)..setRange(0, 11, tag);
    out[1] = (newDataSize >> 16) & 0xff;
    out[2] = (newDataSize >> 8) & 0xff;
    out[3] = newDataSize & 0xff;
    out
      ..setRange(11, 11 + prefix.length, prefix)
      ..setRange(11 + prefix.length, 11 + newDataSize, tag, payloadStart);
    ByteData.sublistView(out).setUint32(11 + newDataSize, 11 + newDataSize);
    _rewrittenTags++;
    return out;
  }
}
