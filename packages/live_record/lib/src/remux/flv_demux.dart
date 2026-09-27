import 'dart:convert';
import 'dart:typed_data';

import 'package:live_media/live_media.dart';
import 'package:live_record/src/remux.dart';
import 'package:live_record/src/remux/codec_config.dart';

const int _h = FlvTag.headerLength;

/// One audio or video access unit from an FLV tag.
final class FlvSample {
  /// Creates a sample.
  const new({
    required this.video,
    required this.dtsMs,
    required this.ctsMs,
    required this.keyframe,
    required this.data,
  });

  /// Video (true) or audio.
  final bool video;

  /// Decode timestamp in milliseconds (the tag timestamp).
  final int dtsMs;

  /// Composition time offset in milliseconds (0 for audio).
  final int ctsMs;

  /// Whether the tag is a keyframe (always true for audio).
  final bool keyframe;

  /// The sample payload: length-prefixed NAL units or a raw AAC frame.
  final Uint8List data;
}

/// Turns FLV tags (as `FlvFramer` yields them) into samples and codec
/// configurations: legacy AVC (codec 7) and HEVC (codec 12), Enhanced FLV
/// `avc1`/`hvc1`, AAC (raw or ADTS-wrapped). Sequence headers set the
/// configuration; a later one must describe the same stream. Throws
/// [RemuxException] for anything it cannot copy faithfully.
final class FlvDemuxer {
  /// The video decoder configuration once seen.
  VideoConfig? video;

  /// The AAC configuration once seen.
  AacConfig? audio;

  /// `onMetaData` of the first script tag (numbers, strings and booleans only); empty when absent or unreadable.
  Map<String, Object> metadata = const {};

  var _sawScript = false;

  /// Video tags dropped because no configuration preceded them.
  int videoWithoutConfig = 0;

  /// Audio tags dropped because no configuration preceded them.
  int audioWithoutConfig = 0;

  /// Tags skipped on purpose: empty, end of sequence, command frames, metadata.
  int skipped = 0;

  /// The sample [tag] carries, or null for configurations and skipped tags.
  /// [offset] is the tag's position in the file, for error messages.
  FlvSample? add(Uint8List tag, int offset) {
    if ((tag[0] & 0x20) != 0) throw RemuxException('encrypted FLV tag at offset $offset');
    final size = FlvTag.dataSize(tag);
    final type = FlvTag.type(tag);
    if (size == 0) {
      skipped++;
      return null;
    }
    switch (type) {
      case FlvTag.video:
        return _video(tag, size, offset);
      case FlvTag.audio:
        return _audio(tag, size, offset);
      default:
        if (!_sawScript) {
          _sawScript = true;
          metadata = readOnMetaData(Uint8List.sublistView(tag, _h, _h + size));
        }
        return null;
    }
  }

  FlvSample? _video(Uint8List tag, int size, int offset) {
    final first = tag[_h];
    final frameType = (first >> 4) & 0x07;
    final VideoCodec codec;
    final int packetType;
    var cts = 0;
    int dataStart;
    if ((first & 0x80) != 0) {
      packetType = first & 0x0f;
      if (packetType > 4) throw RemuxException('unsupported Enhanced FLV packet type $packetType at offset $offset');
      if (size < 5) throw RemuxException('short Enhanced FLV video tag at offset $offset');
      final fourCc = String.fromCharCodes(tag, _h + 1, _h + 5);
      if (frameType == 5 || packetType == 4 || packetType == 2) {
        // Command frame, metadata, end of sequence: no picture.
        skipped++;
        return null;
      }
      codec = switch (fourCc) {
        'avc1' => VideoCodec.avc,
        'hvc1' => VideoCodec.hevc,
        _ => throw RemuxException('unsupported video codec $fourCc at offset $offset'),
      };
      switch (packetType) {
        case 0:
          dataStart = _h + 5;
        case 1:
          if (size < 8) throw RemuxException('short video tag at offset $offset');
          cts = _si24(tag, _h + 5);
          dataStart = _h + 8;
        case 3:
          dataStart = _h + 5;
        default:
          throw RemuxException('unsupported Enhanced FLV packet type $packetType at offset $offset');
      }
    } else {
      final id = first & 0x0f;
      if (frameType == 5) {
        skipped++;
        return null;
      }
      codec = switch (id) {
        7 => VideoCodec.avc,
        12 => VideoCodec.hevc,
        _ => throw RemuxException('unsupported video codec id $id at offset $offset'),
      };
      if (size < 5) throw RemuxException('short video tag at offset $offset');
      packetType = tag[_h + 1];
      cts = _si24(tag, _h + 2);
      dataStart = _h + 5;
      if (packetType == 2) {
        skipped++;
        return null;
      }
      if (packetType > 2) throw RemuxException('bad AVC packet type $packetType at offset $offset');
    }
    final data = Uint8List.sublistView(tag, dataStart, _h + size);
    if (packetType == 0) {
      final VideoConfig config;
      try {
        final record = Uint8List.fromList(data);
        config = isAnnexB(record) ? VideoConfig.fromAnnexB(codec, record) : VideoConfig.parse(codec, record);
      } on FormatException catch (error) {
        throw RemuxException('${error.message} at offset $offset');
      }
      final current = video;
      if (current == null) {
        video = config;
      } else if (!current.sameAs(config)) {
        throw RemuxException('video configuration changes at offset $offset');
      }
      return null;
    }
    final config = video;
    if (config == null) {
      videoWithoutConfig++;
      return null;
    }
    if (config.codec != codec) throw RemuxException('video codec changes at offset $offset');
    if (data.isEmpty) {
      skipped++;
      return null;
    }
    var payload = data;
    final prefixed = isLengthPrefixed(data, config.lengthSize);
    if (isAnnexB(data) && (config.annexB || !prefixed)) {
      try {
        payload = lengthPrefixed(splitAnnexB(data), config.lengthSize);
      } on FormatException catch (error) {
        throw RemuxException('${error.message} at offset $offset');
      }
    } else if (!prefixed) {
      throw RemuxException('malformed NAL units in the video tag at offset $offset');
    }
    return FlvSample(video: true, dtsMs: FlvTag.timestamp(tag), ctsMs: cts, keyframe: frameType == 1, data: payload);
  }

  FlvSample? _audio(Uint8List tag, int size, int offset) {
    final format = tag[_h] >> 4;
    if (format != 10) throw RemuxException('unsupported audio format $format at offset $offset');
    if (size < 2) throw RemuxException('short AAC tag at offset $offset');
    final packetType = tag[_h + 1];
    var data = Uint8List.sublistView(tag, _h + 2, _h + size);
    if (packetType == 0) {
      final AacConfig config;
      try {
        config = AacConfig.parse(data);
      } on FormatException catch (error) {
        throw RemuxException('${error.message} at offset $offset');
      }
      _setAudio(config, offset);
      return null;
    }
    if (packetType != 1) throw RemuxException('bad AAC packet type $packetType at offset $offset');
    final adts = AacConfig.adtsHeaderLength(data);
    if (adts > 0) {
      if (audio == null) {
        try {
          _setAudio(AacConfig.fromAdts(data), offset);
        } on FormatException catch (error) {
          throw RemuxException('${error.message} at offset $offset');
        }
      }
      data = Uint8List.sublistView(data, adts);
    }
    if (audio == null) {
      audioWithoutConfig++;
      return null;
    }
    if (data.isEmpty) {
      skipped++;
      return null;
    }
    return FlvSample(video: false, dtsMs: FlvTag.timestamp(tag), ctsMs: 0, keyframe: true, data: data);
  }

  void _setAudio(AacConfig config, int offset) {
    final current = audio;
    if (current == null) {
      audio = config;
    } else if (!current.sameAs(config)) {
      throw RemuxException('audio configuration changes at offset $offset');
    }
  }

  static int _si24(Uint8List bytes, int at) {
    final value = (bytes[at] << 16) | (bytes[at + 1] << 8) | bytes[at + 2];
    return value >= 0x800000 ? value - 0x1000000 : value;
  }
}

/// Reads the `onMetaData` values of an AMF0 script payload: numbers, strings
/// and booleans at the top level. Anything unreadable yields what was read so far.
Map<String, Object> readOnMetaData(Uint8List payload) {
  final values = <String, Object>{};
  final data = ByteData.sublistView(payload);
  var at = 0;
  String readString(int length) {
    final text = utf8.decode(Uint8List.sublistView(payload, at, at + length), allowMalformed: true);
    at += length;
    return text;
  }

  // Skips one AMF0 value; returns it when it is a number, string or boolean.
  Object? value(int depth) {
    if (depth > 16) throw const FormatException('AMF0 nesting too deep');
    final marker = payload[at++];
    switch (marker) {
      case 0:
        at += 8;
        return data.getFloat64(at - 8);
      case 1:
        return payload[at++] != 0;
      case 2:
        final length = data.getUint16(at);
        at += 2;
        return readString(length);
      case 3 || 8:
        if (marker == 8) at += 4;
        while (true) {
          final length = data.getUint16(at);
          at += 2;
          if (length == 0 && payload[at] == 9) {
            at++;
            return null;
          }
          at += length;
          value(depth + 1);
        }
      case 5 || 6:
        return null;
      case 10:
        final count = data.getUint32(at);
        at += 4;
        for (var i = 0; i < count; i++) {
          value(depth + 1);
        }
        return null;
      case 11:
        at += 10;
        return null;
      case 12:
        final length = data.getUint32(at);
        at += 4;
        return readString(length);
      default:
        throw FormatException('AMF0 marker $marker');
    }
  }

  try {
    if (value(0) != 'onMetaData') return values;
    final marker = payload[at++];
    if (marker != 3 && marker != 8) return values;
    if (marker == 8) at += 4;
    while (at + 3 <= payload.length) {
      final length = data.getUint16(at);
      at += 2;
      if (length == 0 && payload[at] == 9) break;
      final key = readString(length);
      final item = value(1);
      if (item != null) values[key] = item;
    }
  } on Object {
    // Metadata is advisory: keep what was read.
  }
  return values;
}
