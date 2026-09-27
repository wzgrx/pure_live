import 'dart:typed_data';

/// MSB-first bit reader (H.264/HEVC RBSP, AAC AudioSpecificConfig). Throws
/// [FormatException] when the data runs out.
final class BitReader {
  /// Reads [_bytes] from the first bit.
  new(this._bytes);

  final Uint8List _bytes;
  var _bit = 0;

  /// Bits not read yet.
  int get bitsLeft => _bytes.length * 8 - _bit;

  /// The next [count] bits (at most 32) as an unsigned value.
  int bits(int count) {
    if (count > bitsLeft) throw const FormatException('bitstream too short');
    var value = 0;
    for (var i = 0; i < count; i++) {
      value = (value << 1) | ((_bytes[_bit >> 3] >> (7 - (_bit & 7))) & 1);
      _bit++;
    }
    return value;
  }

  /// The next bit as a flag.
  bool flag() => bits(1) == 1;

  /// Skips [count] bits.
  void skip(int count) {
    if (count > bitsLeft) throw const FormatException('bitstream too short');
    _bit += count;
  }

  /// Unsigned Exp-Golomb value.
  int ue() {
    var zeros = 0;
    while (bits(1) == 0) {
      if (++zeros > 31) throw const FormatException('bad Exp-Golomb code');
    }
    return zeros == 0 ? 0 : (1 << zeros) - 1 + bits(zeros);
  }

  /// Signed Exp-Golomb value.
  int se() {
    final value = ue();
    return value.isOdd ? (value + 1) >> 1 : -(value >> 1);
  }
}

/// The RBSP of [nal] after its [headerLength]-byte NAL header, with the
/// emulation prevention bytes (`00 00 03`) removed.
Uint8List unescapeRbsp(Uint8List nal, int headerLength) {
  final out = Uint8List(nal.length);
  var length = 0;
  var zeros = 0;
  for (var i = headerLength; i < nal.length; i++) {
    final byte = nal[i];
    if (zeros >= 2 && byte == 3) {
      zeros = 0;
      continue;
    }
    zeros = byte == 0 ? zeros + 1 : 0;
    out[length++] = byte;
  }
  return Uint8List.sublistView(out, 0, length);
}

/// Whether [data] starts with an Annex B start code (`00 00 01` or `00 00 00 01`).
bool isAnnexB(Uint8List data) =>
    data.length >= 4 && data[0] == 0 && data[1] == 0 && (data[2] == 1 || (data[2] == 0 && data[3] == 1));

/// The NAL units of an Annex B byte stream, without start codes and trailing zero bytes.
List<Uint8List> splitAnnexB(Uint8List data) {
  final units = <Uint8List>[];
  void add(int start, int end) {
    var last = end;
    while (last > start && data[last - 1] == 0) {
      last--;
    }
    if (last > start) units.add(Uint8List.sublistView(data, start, last));
  }

  var start = -1;
  var i = 0;
  while (i + 2 < data.length) {
    if (data[i + 2] > 1) {
      i += 3;
    } else if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) {
      if (start >= 0) add(start, i);
      i += 3;
      start = i;
    } else {
      i++;
    }
  }
  if (start >= 0) add(start, data.length);
  return units;
}

/// [units] with [lengthSize]-byte big-endian length prefixes (MP4 sample format).
Uint8List lengthPrefixed(List<Uint8List> units, int lengthSize) {
  var total = 0;
  for (final unit in units) {
    if (unit.length >= 1 << (8 * lengthSize)) throw FormatException('NAL unit of ${unit.length} bytes');
    total += lengthSize + unit.length;
  }
  final out = Uint8List(total);
  var at = 0;
  for (final unit in units) {
    for (var i = lengthSize - 1; i >= 0; i--) {
      out[at++] = (unit.length >> (8 * i)) & 0xff;
    }
    out.setRange(at, at + unit.length, unit);
    at += unit.length;
  }
  return out;
}

/// Whether [data] is a sequence of NAL units with [lengthSize]-byte length
/// prefixes that ends exactly at its end (trailing zero bytes allowed).
bool isLengthPrefixed(Uint8List data, int lengthSize) {
  var at = 0;
  while (at + lengthSize <= data.length) {
    var length = 0;
    for (var i = 0; i < lengthSize; i++) {
      length = (length << 8) | data[at + i];
    }
    at += lengthSize;
    if (length > data.length - at) return false;
    at += length;
  }
  for (; at < data.length; at++) {
    if (data[at] != 0) return false;
  }
  return true;
}

/// Video codecs the remuxer copies.
enum VideoCodec {
  /// H.264 (`avc1` + `avcC`).
  avc,

  /// H.265 (`hvc1` + `hvcC`).
  hevc,
}

/// A parsed decoder configuration record: `AVCDecoderConfigurationRecord` or
/// `HEVCDecoderConfigurationRecord` (ISO/IEC 14496-15), as FLV carries it.
final class VideoConfig {
  new _(
    this.codec,
    this.record,
    this.lengthSize,
    this.parameterSets,
    this.width,
    this.height,
    this.sarWidth,
    this.sarHeight, {
    this.annexB = false,
  });

  /// Parses [record]; throws [FormatException] when it is malformed.
  factory parse(VideoCodec codec, Uint8List record) =>
      codec == VideoCodec.avc ? VideoConfig._avc(record) : VideoConfig._hevc(record);

  /// Builds the configuration record from the parameter sets of an Annex B
  /// sequence header (some CDNs send start codes instead of a record, and
  /// Annex B samples with it); samples then get 4-byte length prefixes.
  factory fromAnnexB(VideoCodec codec, Uint8List data) {
    final units = splitAnnexB(data);
    final record = codec == VideoCodec.avc ? _avcRecord(units) : _hevcRecord(units);
    final config = VideoConfig.parse(codec, record);
    return VideoConfig._(
      codec,
      record,
      config.lengthSize,
      config.parameterSets,
      config.width,
      config.height,
      config.sarWidth,
      config.sarHeight,
      annexB: true,
    );
  }

  factory _avc(Uint8List record) {
    if (record.length < 7 || record[0] != 1) throw const FormatException('bad AVCDecoderConfigurationRecord');
    final lengthSize = (record[4] & 0x03) + 1;
    if (lengthSize == 3) throw const FormatException('bad NAL length size 3');
    final sets = <Uint8List>[];
    final sps = <Uint8List>[];
    var offset = 5;
    for (final isSps in const [true, false]) {
      if (offset >= record.length) throw const FormatException('truncated AVCDecoderConfigurationRecord');
      final count = isSps ? record[offset] & 0x1f : record[offset];
      offset++;
      for (var i = 0; i < count; i++) {
        if (offset + 2 > record.length) throw const FormatException('truncated AVCDecoderConfigurationRecord');
        final length = (record[offset] << 8) | record[offset + 1];
        offset += 2;
        if (length == 0 || offset + length > record.length) throw const FormatException('bad parameter set length');
        final nal = Uint8List.sublistView(record, offset, offset + length);
        sets.add(nal);
        if (isSps) sps.add(nal);
        offset += length;
      }
    }
    if (sps.isEmpty) throw const FormatException('AVCDecoderConfigurationRecord without SPS');
    AvcSps? info;
    try {
      info = AvcSps.parse(sps.first);
    } on Object {
      // Dimensions stay unknown; the stream itself still decodes.
    }
    return VideoConfig._(
      VideoCodec.avc,
      record,
      lengthSize,
      List.unmodifiable(sets),
      info?.width ?? 0,
      info?.height ?? 0,
      info?.sarWidth ?? 1,
      info?.sarHeight ?? 1,
    );
  }

  factory _hevc(Uint8List record) {
    if (record.length < 23 || record[0] != 1) throw const FormatException('bad HEVCDecoderConfigurationRecord');
    final lengthSize = (record[21] & 0x03) + 1;
    if (lengthSize == 3) throw const FormatException('bad NAL length size 3');
    final arrays = record[22];
    final sets = <Uint8List>[];
    Uint8List? sps;
    var offset = 23;
    for (var a = 0; a < arrays; a++) {
      if (offset + 3 > record.length) throw const FormatException('truncated HEVCDecoderConfigurationRecord');
      final type = record[offset] & 0x3f;
      final count = (record[offset + 1] << 8) | record[offset + 2];
      offset += 3;
      for (var i = 0; i < count; i++) {
        if (offset + 2 > record.length) throw const FormatException('truncated HEVCDecoderConfigurationRecord');
        final length = (record[offset] << 8) | record[offset + 1];
        offset += 2;
        if (length == 0 || offset + length > record.length) throw const FormatException('bad parameter set length');
        final nal = Uint8List.sublistView(record, offset, offset + length);
        sets.add(nal);
        if (type == 33) sps ??= nal;
        offset += length;
      }
    }
    if (sps == null) throw const FormatException('HEVCDecoderConfigurationRecord without SPS');
    HevcSps? info;
    try {
      info = HevcSps.parse(sps);
    } on Object {
      // Dimensions stay unknown; the stream itself still decodes.
    }
    return VideoConfig._(
      VideoCodec.hevc,
      record,
      lengthSize,
      List.unmodifiable(sets),
      info?.width ?? 0,
      info?.height ?? 0,
      1,
      1,
    );
  }

  /// The codec.
  final VideoCodec codec;

  /// The record bytes for `avcC` / `hvcC`.
  final Uint8List record;

  /// Size of the NAL unit length prefix in samples (1, 2 or 4).
  final int lengthSize;

  /// VPS, SPS and PPS NAL units in record order.
  final List<Uint8List> parameterSets;

  /// Coded width after cropping; 0 when the SPS could not be read.
  final int width;

  /// Coded height after cropping; 0 when the SPS could not be read.
  final int height;

  /// Sample aspect ratio numerator (1 when unknown).
  final int sarWidth;

  /// Sample aspect ratio denominator (1 when unknown).
  final int sarHeight;

  /// Whether the FLV carried Annex B (start codes) instead of a record.
  final bool annexB;

  /// Whether [other] describes the same stream: same codec, NAL length size
  /// and parameter sets (the record may differ in padding or reserved bits).
  bool sameAs(VideoConfig other) {
    if (codec != other.codec || lengthSize != other.lengthSize) return false;
    if (parameterSets.length != other.parameterSets.length) return false;
    for (var i = 0; i < parameterSets.length; i++) {
      if (!_bytesEqual(parameterSets[i], other.parameterSets[i])) return false;
    }
    return true;
  }

  static void _array(BytesBuilder out, List<Uint8List> units) {
    for (final unit in units) {
      if (unit.length > 0xffff) throw const FormatException('parameter set too long');
      out
        ..addByte(unit.length >> 8)
        ..addByte(unit.length & 0xff)
        ..add(unit);
    }
  }

  static Uint8List _avcRecord(List<Uint8List> units) {
    final sps = [
      for (final unit in units)
        if (unit[0] & 0x1f == 7) unit,
    ];
    final pps = [
      for (final unit in units)
        if (unit[0] & 0x1f == 8) unit,
    ];
    if (sps.isEmpty || pps.isEmpty || sps.first.length < 4) {
      throw const FormatException('Annex B AVC sequence header without SPS and PPS');
    }
    if (sps.length > 31 || pps.length > 255) throw const FormatException('too many parameter sets');
    final first = sps.first;
    final out = BytesBuilder()..add([1, first[1], first[2], first[3], 0xff, 0xe0 | sps.length]);
    _array(out, sps);
    out.addByte(pps.length);
    _array(out, pps);
    if (_highProfiles.contains(first[1])) {
      final info = AvcSps.parse(first);
      out.add([0xfc | info.chromaFormat, 0xf8 | (info.bitDepthLuma - 8), 0xf8 | (info.bitDepthChroma - 8), 0]);
    }
    return out.takeBytes();
  }

  static Uint8List _hevcRecord(List<Uint8List> units) {
    final arrays = [
      for (final nalType in const [32, 33, 34])
        [
          for (final unit in units)
            if ((unit[0] >> 1) & 0x3f == nalType) unit,
        ],
    ];
    if (arrays[1].isEmpty || arrays[2].isEmpty) {
      throw const FormatException('Annex B HEVC sequence header without SPS and PPS');
    }
    final sps = arrays[1].first;
    final info = HevcSps.parse(sps);
    final rbsp = unescapeRbsp(sps, 2);
    final out = BytesBuilder()
      ..addByte(1)
      // general_profile_space … general_level_idc: the 12 bytes after the first SPS byte.
      ..add(Uint8List.sublistView(rbsp, 1, 13))
      ..add([
        0xf0,
        0x00, // min_spatial_segmentation_idc: unknown (0)
        0xfc, // parallelismType: unknown (0)
        0xfc | info.chromaFormat,
        0xf8 | (info.bitDepthLuma - 8),
        0xf8 | (info.bitDepthChroma - 8),
        0,
        0, // avgFrameRate: unknown
        (info.subLayers << 3) | (info.temporalIdNesting ? 0x04 : 0) | 0x03,
        arrays.where((array) => array.isNotEmpty).length,
      ]);
    for (var i = 0; i < arrays.length; i++) {
      if (arrays[i].isEmpty) continue;
      out
        ..addByte(0x80 | (32 + i))
        ..addByte(arrays[i].length >> 8)
        ..addByte(arrays[i].length & 0xff);
      _array(out, arrays[i]);
    }
    return out.takeBytes();
  }
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

const _sarTable = [
  (0, 0), (1, 1), (12, 11), (10, 11), (16, 11), (40, 33), (24, 11), (20, 11), (32, 11), //
  (80, 33), (18, 11), (15, 11), (64, 33), (160, 99), (4, 3), (3, 2), (2, 1),
];

const _highProfiles = {100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135};

/// What the remuxer needs from an H.264 SPS (ITU-T H.264 7.3.2.1.1).
final class AvcSps {
  new _({
    required this.width,
    required this.height,
    required this.sarWidth,
    required this.sarHeight,
    required this.chromaFormat,
    required this.bitDepthLuma,
    required this.bitDepthChroma,
  });

  /// Parses the SPS NAL unit [nal] (with its header byte); throws [FormatException].
  factory parse(Uint8List nal) {
    final r = BitReader(unescapeRbsp(nal, 1));
    final profile = r.bits(8);
    r
      ..skip(16)
      ..ue();
    var chroma = 1;
    var separatePlanes = false;
    var depthLuma = 8;
    var depthChroma = 8;
    if (_highProfiles.contains(profile)) {
      chroma = r.ue();
      if (chroma > 3) throw FormatException('bad chroma_format_idc $chroma');
      if (chroma == 3) separatePlanes = r.flag();
      depthLuma = r.ue() + 8;
      depthChroma = r.ue() + 8;
      r.skip(1);
      if (r.flag()) {
        for (var i = 0; i < (chroma == 3 ? 12 : 8); i++) {
          if (!r.flag()) continue;
          var last = 8;
          var next = 8;
          for (var j = 0; j < (i < 6 ? 16 : 64); j++) {
            if (next != 0) next = (last + r.se() + 256) % 256;
            last = next == 0 ? last : next;
          }
        }
      }
    }
    r.ue();
    final pocType = r.ue();
    if (pocType == 0) {
      r.ue();
    } else if (pocType == 1) {
      r
        ..skip(1)
        ..se()
        ..se();
      final cycle = r.ue();
      for (var i = 0; i < cycle; i++) {
        r.se();
      }
    }
    r
      ..ue()
      ..skip(1);
    final widthMbs = r.ue() + 1;
    final heightMapUnits = r.ue() + 1;
    final frameMbsOnly = r.flag();
    if (!frameMbsOnly) r.skip(1);
    r.skip(1);
    var cropLeft = 0;
    var cropRight = 0;
    var cropTop = 0;
    var cropBottom = 0;
    if (r.flag()) {
      cropLeft = r.ue();
      cropRight = r.ue();
      cropTop = r.ue();
      cropBottom = r.ue();
    }
    final arrayType = separatePlanes ? 0 : chroma;
    final subWidth = arrayType == 1 || arrayType == 2 ? 2 : 1;
    final subHeight = arrayType == 1 ? 2 : 1;
    final fieldFactor = frameMbsOnly ? 1 : 2;
    final cropX = arrayType == 0 ? 1 : subWidth;
    final cropY = (arrayType == 0 ? 1 : subHeight) * fieldFactor;
    final width = widthMbs * 16 - cropX * (cropLeft + cropRight);
    final height = fieldFactor * heightMapUnits * 16 - cropY * (cropTop + cropBottom);
    var sarWidth = 1;
    var sarHeight = 1;
    if (r.bitsLeft > 1 && r.flag() && r.flag()) {
      final idc = r.bits(8);
      if (idc == 255) {
        sarWidth = r.bits(16);
        sarHeight = r.bits(16);
      } else if (idc > 0 && idc < _sarTable.length) {
        (sarWidth, sarHeight) = _sarTable[idc];
      }
      if (sarWidth == 0 || sarHeight == 0) (sarWidth, sarHeight) = (1, 1);
    }
    if (width <= 0 || height <= 0) throw const FormatException('bad SPS size');
    return AvcSps._(
      width: width,
      height: height,
      sarWidth: sarWidth,
      sarHeight: sarHeight,
      chromaFormat: chroma,
      bitDepthLuma: depthLuma,
      bitDepthChroma: depthChroma,
    );
  }

  /// Cropped width.
  final int width;

  /// Cropped height.
  final int height;

  /// Sample aspect ratio numerator.
  final int sarWidth;

  /// Sample aspect ratio denominator.
  final int sarHeight;

  /// `chroma_format_idc`.
  final int chromaFormat;

  /// Luma bit depth.
  final int bitDepthLuma;

  /// Chroma bit depth.
  final int bitDepthChroma;
}

/// What the remuxer needs from an H.265 SPS (ITU-T H.265 7.3.2.2.1).
final class HevcSps {
  new _({
    required this.width,
    required this.height,
    required this.chromaFormat,
    required this.bitDepthLuma,
    required this.bitDepthChroma,
    required this.subLayers,
    required this.temporalIdNesting,
  });

  /// Parses the SPS NAL unit [nal] (with its 2-byte header); throws [FormatException].
  factory parse(Uint8List nal) {
    final r = BitReader(unescapeRbsp(nal, 2))..skip(4);
    final maxSubLayersMinus1 = r.bits(3);
    final nesting = r.flag();
    r.skip(2 + 1 + 5 + 32 + 48 + 8);
    final profilePresent = <bool>[];
    final levelPresent = <bool>[];
    for (var i = 0; i < maxSubLayersMinus1; i++) {
      profilePresent.add(r.flag());
      levelPresent.add(r.flag());
    }
    if (maxSubLayersMinus1 > 0) r.skip(2 * (8 - maxSubLayersMinus1));
    for (var i = 0; i < maxSubLayersMinus1; i++) {
      if (profilePresent[i]) r.skip(88);
      if (levelPresent[i]) r.skip(8);
    }
    r.ue();
    final chroma = r.ue();
    if (chroma > 3) throw FormatException('bad chroma_format_idc $chroma');
    var separatePlanes = false;
    if (chroma == 3) separatePlanes = r.flag();
    final width = r.ue();
    final height = r.ue();
    var cropLeft = 0;
    var cropRight = 0;
    var cropTop = 0;
    var cropBottom = 0;
    if (r.flag()) {
      cropLeft = r.ue();
      cropRight = r.ue();
      cropTop = r.ue();
      cropBottom = r.ue();
    }
    final depthLuma = r.ue() + 8;
    final depthChroma = r.ue() + 8;
    final arrayType = separatePlanes ? 0 : chroma;
    final subWidth = arrayType == 1 || arrayType == 2 ? 2 : 1;
    final subHeight = arrayType == 1 ? 2 : 1;
    final w = width - subWidth * (cropLeft + cropRight);
    final h = height - subHeight * (cropTop + cropBottom);
    if (w <= 0 || h <= 0) throw const FormatException('bad SPS size');
    return HevcSps._(
      width: w,
      height: h,
      chromaFormat: chroma,
      bitDepthLuma: depthLuma,
      bitDepthChroma: depthChroma,
      subLayers: maxSubLayersMinus1 + 1,
      temporalIdNesting: nesting,
    );
  }

  /// Cropped width.
  final int width;

  /// Cropped height.
  final int height;

  /// `chroma_format_idc`.
  final int chromaFormat;

  /// Luma bit depth.
  final int bitDepthLuma;

  /// Chroma bit depth.
  final int bitDepthChroma;

  /// `sps_max_sub_layers_minus1` + 1.
  final int subLayers;

  /// `sps_temporal_id_nesting_flag`.
  final bool temporalIdNesting;
}

const _aacRates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350];

/// Object types whose AudioSpecificConfig carries a GASpecificConfig.
const _gaObjectTypes = {1, 2, 3, 4, 6, 7, 17, 19, 20, 21, 22, 23};

/// A parsed AAC AudioSpecificConfig (ISO/IEC 14496-3 1.6.2.1).
final class AacConfig {
  new _(this.asc, this.objectType, this.sampleRate, this.channelConfig, this.frameSamples);

  /// Parses [asc]; throws [FormatException] when it is malformed.
  factory parse(Uint8List asc) {
    final r = BitReader(asc);
    int objectType() {
      final type = r.bits(5);
      return type == 31 ? 32 + r.bits(6) : type;
    }

    int rate() {
      final index = r.bits(4);
      if (index == 15) return r.bits(24);
      if (index >= _aacRates.length) throw FormatException('bad AAC sampling frequency index $index');
      return _aacRates[index];
    }

    var type = objectType();
    final sampleRate = rate();
    final channels = r.bits(4);
    if (type == 5 || type == 29) {
      // Explicit SBR/PS: the first rate is the core rate; the core object type follows.
      rate();
      type = objectType();
      if (type == 22) r.skip(4);
    }
    var frame = 1024;
    if (_gaObjectTypes.contains(type) && r.bitsLeft > 0 && r.flag()) frame = 960;
    if (sampleRate <= 0) throw const FormatException('bad AAC sampling frequency');
    return AacConfig._(Uint8List.fromList(asc), type, sampleRate, channels, frame);
  }

  /// The AudioSpecificConfig announced by the ADTS header at the start of [data].
  factory fromAdts(Uint8List data) {
    final objectType = ((data[2] >> 6) & 0x03) + 1;
    final rateIndex = (data[2] >> 2) & 0x0f;
    final channels = ((data[2] & 0x01) << 2) | (data[3] >> 6);
    if (rateIndex >= _aacRates.length) throw FormatException('bad ADTS sampling frequency index $rateIndex');
    return AacConfig.parse(
      Uint8List.fromList([(objectType << 3) | (rateIndex >> 1), ((rateIndex & 1) << 7) | (channels << 3)]),
    );
  }

  /// The AudioSpecificConfig bytes, copied into `esds` unchanged.
  final Uint8List asc;

  /// Audio object type of the core coder (2 for AAC-LC).
  final int objectType;

  /// Core sampling rate: the MP4 track timescale.
  final int sampleRate;

  /// `channelConfiguration` (0: defined in the bitstream).
  final int channelConfig;

  /// Samples per frame at [sampleRate] (1024, or 960).
  final int frameSamples;

  /// Channel count for the `mp4a` sample entry.
  int get channelCount => switch (channelConfig) {
    >= 1 && <= 6 => channelConfig,
    7 || 12 || 14 => 8,
    11 => 7,
    13 => 24,
    _ => 2,
  };

  /// Whether [other] has the same AudioSpecificConfig bytes.
  bool sameAs(AacConfig other) => _bytesEqual(asc, other.asc);

  /// Length of the ADTS header in front of [data] when [data] is exactly one
  /// ADTS frame (sync word, layer 0, frame length equal to [data]'s length,
  /// one raw data block); 0 otherwise.
  static int adtsHeaderLength(Uint8List data) {
    if (data.length < 7 || data[0] != 0xff || (data[1] & 0xf6) != 0xf0) return 0;
    final frameLength = ((data[3] & 0x03) << 11) | (data[4] << 3) | (data[5] >> 5);
    if (frameLength != data.length || (data[6] & 0x03) != 0) return 0;
    final header = (data[1] & 0x01) == 1 ? 7 : 9;
    return frameLength > header ? header : 0;
  }
}
