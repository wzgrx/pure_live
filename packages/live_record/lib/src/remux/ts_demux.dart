import 'dart:typed_data';

import 'package:live_record/src/remux.dart';
import 'package:live_record/src/remux/codec_config.dart';

/// Size of an MPEG-TS packet.
const tsPacketSize = 188;

/// MPEG-TS sync byte.
const tsSync = 0x47;

/// 2^33: the wrap of 90 kHz PES timestamps.
const int _wrap = 1 << 33;

/// Whether [data] looks like MPEG-TS: sync bytes at the first packets.
bool looksLikeTs(Uint8List data) {
  if (data.isEmpty || data[0] != tsSync) return false;
  for (var at = tsPacketSize; at < data.length && at < 4 * tsPacketSize; at += tsPacketSize) {
    if (data[at] != tsSync) return false;
  }
  return true;
}

/// One access unit from an MPEG-TS elementary stream.
final class TsSample {
  /// Creates a sample.
  const new({
    required this.video,
    required this.dts,
    required this.pts,
    required this.keyframe,
    required this.data,
    required this.offset,
    this.aligned = true,
  });

  /// Video (true) or audio.
  final bool video;

  /// Decode time, 90 kHz, unwrapped across the 33-bit wrap.
  final int dts;

  /// Presentation time, 90 kHz, unwrapped.
  final int pts;

  /// Whether the unit can start decoding (IDR / IRAP / recovery point); always true for audio.
  final bool keyframe;

  /// Video: the access unit in Annex B; audio: one ADTS frame, header
  /// included ([adtsPayload] is the raw AAC frame).
  final Uint8List data;

  /// File offset of the packet that started the PES (for errors).
  final int offset;

  /// Whether the unit's PES starts with it (no tail of the previous unit in front).
  final bool aligned;
}

/// A video stream's codec as the PMT announces it.
VideoCodec? _videoCodecOf(int streamType) => switch (streamType) {
  0x1B => VideoCodec.avc,
  0x24 => VideoCodec.hevc,
  _ => null,
};

bool _isVideoType(int streamType) => const {0x01, 0x02, 0x10, 0x1B, 0x24, 0x42, 0xD1, 0xEA}.contains(streamType);

bool _isAudioType(int streamType) => const {0x03, 0x04, 0x0F, 0x11, 0x1C, 0x81, 0x87}.contains(streamType);

/// Whether the PMT stream type [streamType] is a video stream (MPEG-1/2,
/// MPEG-4, H.264, H.265, CAVS, Dirac, VC-1).
bool isTsVideoType(int streamType) => _isVideoType(streamType);

/// Whether the PMT stream type [streamType] is an audio stream (MPEG audio,
/// AAC, LATM, AC-3, E-AC-3).
bool isTsAudioType(int streamType) => _isAudioType(streamType);

/// The codec the remux copies for video stream type [streamType] (H.264,
/// H.265), or null.
VideoCodec? tsVideoCodecOf(int streamType) => _videoCodecOf(streamType);

final class _Pes {
  new(this.pid, this.offset);

  final int pid;
  final int offset;
  final builder = BytesBuilder(copy: false);
}

final class _Section {
  final builder = BytesBuilder(copy: false);
  int? length;
}

final class _Clock {
  int? _last;
  var _base = 0;

  /// [raw] (33 bits) extended to a continuous value.
  int unwrap(int raw) {
    final last = _last;
    var value = raw + _base;
    if (last != null) {
      if (value - last < -(_wrap >> 1)) {
        _base += _wrap;
        value += _wrap;
      } else if (value - last > (_wrap >> 1) && _base >= _wrap) {
        _base -= _wrap;
        value -= _wrap;
      }
    }
    _last = value;
    return value;
  }
}

/// Demultiplexes MPEG-TS packets into video access units (H.264, H.265, one
/// per PES) and AAC frames (ADTS), following PAT/PMT changes. [strict]
/// reports damage as [RemuxException] (the remuxer: any demux error fails
/// the remux, REG-RECORD-008); otherwise damaged units are dropped and
/// counted in [damaged] (the recorder's probe).
final class TsDemuxer {
  /// Creates a demuxer.
  new({this.strict = true});

  /// Report damage as errors.
  final bool strict;

  /// Video codec of the selected video stream, once a PMT announced one.
  VideoCodec? videoCodec;

  /// Stream types of the current PMT, in PMT order.
  List<int> streamTypes = const [];

  /// PES packets dropped as damaged (only when not [strict]).
  int damaged = 0;

  /// Units of streams the recorder does not copy were seen (MP3, AC-3, MPEG-2 video…).
  int? unsupportedType;

  int? _pmtPid;
  int? _videoPid;
  int? _audioPid;
  final _sections = <int, _Section>{};
  final _pes = <int, _Pes>{};
  final _continuity = <int, int>{};
  final _lastPacket = <int, Uint8List>{};
  final _clocks = <int, _Clock>{};

  // A video access unit waiting for the next PES (see [_video]).
  ({Uint8List data, int dts, int pts, int offset, bool aligned})? _pendingVideo;

  // An audio frame split across PES packets.
  Uint8List? _audioCarry;
  int _audioCarryPts = 0;
  int _audioRate = 0;

  // No ADTS frame yet, or the carried frame was cut by a gap: the next PES
  // may start with the rest of a frame whose start is not in the file.
  var _audioResync = true;

  /// PID of the video stream, if any.
  int? get videoPid => _videoPid;

  /// PID of the AAC stream, if any.
  int? get audioPid => _audioPid;

  /// Takes one 188-byte packet at file offset [offset]; completed units go to [emit].
  void add(Uint8List packet, int offset, void Function(TsSample sample) emit) {
    if (packet.length != tsPacketSize || packet[0] != tsSync) {
      throw RemuxException('lost MPEG-TS sync at offset $offset');
    }
    final transportError = (packet[1] & 0x80) != 0;
    final unitStart = (packet[1] & 0x40) != 0;
    final pid = ((packet[1] & 0x1F) << 8) | packet[2];
    final control = (packet[3] >> 4) & 0x03;
    final counter = packet[3] & 0x0F;
    if (pid == 0x1FFF) return;
    var at = 4;
    var discontinuity = false;
    if (control == 2 || control == 3) {
      final length = packet[4];
      if (length > 183) throw RemuxException('bad adaptation field length $length at offset $offset');
      if (length > 0) discontinuity = (packet[5] & 0x80) != 0;
      at = 5 + length;
    }
    final hasPayload = control == 1 || control == 3;
    if (!hasPayload) return;
    final tracked = pid == 0 || pid == _pmtPid || pid == _videoPid || pid == _audioPid;
    if (transportError && tracked) {
      _damage(pid, 'transport error indicator at offset $offset');
      return;
    }
    // Continuity (ISO/IEC 13818-1 2.4.3.3): a packet repeated as it was is
    // a duplicate. HLS segments written one after the other restart their
    // counters, so an equal counter alone is not one.
    final last = _continuity[pid];
    final previous = _lastPacket[pid];
    _continuity[pid] = counter;
    _lastPacket[pid] = packet;
    if (last != null && !discontinuity) {
      if (counter == last && previous != null && _samePacket(previous, packet)) return;
      if (counter != (last + 1) & 0x0F && !unitStart && tracked) {
        _damage(pid, 'packets lost before offset $offset (continuity $last → $counter)');
        return;
      }
    }
    final payload = Uint8List.sublistView(packet, at);
    if (pid == 0 || pid == _pmtPid) {
      _section(pid, payload, unitStart, offset, emit);
      return;
    }
    if (pid != _videoPid && pid != _audioPid) return;
    if (unitStart) {
      final previous = _pes.remove(pid);
      if (previous != null) _finishPes(previous, emit, atEnd: false);
      _pes[pid] = _Pes(pid, offset)..builder.add(payload);
    } else {
      _pes[pid]?.builder.add(payload);
    }
  }

  /// Ends the stream: emits the last unit of each stream. A PES shorter than
  /// its declared length at the very end (a file cut by a crash) is dropped.
  void finish(void Function(TsSample sample) emit) {
    for (final pes in _pes.values.toList()) {
      _finishPes(pes, emit, atEnd: true);
    }
    _pes.clear();
    _flushVideo(emit);
  }

  void _damage(int pid, String message) {
    if (strict) throw RemuxException(message);
    damaged++;
    _pes.remove(pid);
    _sections.remove(pid);
  }

  // PSI (§2.4.4).

  void _section(int pid, Uint8List payload, bool unitStart, int offset, void Function(TsSample sample) emit) {
    var data = payload;
    if (unitStart) {
      if (data.isEmpty) return;
      final pointer = data[0];
      if (1 + pointer > data.length) return;
      data = Uint8List.sublistView(data, 1 + pointer);
      _sections[pid] = _Section();
    }
    final section = _sections[pid];
    if (section == null) return;
    section.builder.add(data);
    if (section.length == null && section.builder.length >= 3) {
      final head = section.builder.toBytes();
      section.length = 3 + (((head[1] & 0x0F) << 8) | head[2]);
    }
    final length = section.length;
    if (length == null || section.builder.length < length) return;
    _sections.remove(pid);
    final bytes = Uint8List.sublistView(section.builder.toBytes(), 0, length);
    if (bytes[0] == 0xFF) return;
    if (pid == 0) {
      _pat(bytes);
    } else {
      _pmt(bytes, offset, emit);
    }
  }

  void _pat(Uint8List section) {
    if (section[0] != 0x00 || section.length < 12) return;
    for (var at = 8; at + 4 <= section.length - 4; at += 4) {
      final program = (section[at] << 8) | section[at + 1];
      final pid = ((section[at + 2] & 0x1F) << 8) | section[at + 3];
      if (program == 0) continue;
      _pmtPid = pid;
      return;
    }
  }

  void _pmt(Uint8List section, int offset, void Function(TsSample sample) emit) {
    if (section[0] != 0x02 || section.length < 16) return;
    final programInfo = ((section[10] & 0x0F) << 8) | section[11];
    var at = 12 + programInfo;
    final end = section.length - 4;
    final types = <int>[];
    int? video;
    int? audio;
    VideoCodec? codec;
    int? unsupportedVideo;
    int? unsupportedAudio;
    while (at + 5 <= end) {
      final type = section[at];
      final pid = ((section[at + 1] & 0x1F) << 8) | section[at + 2];
      final info = ((section[at + 3] & 0x0F) << 8) | section[at + 4];
      at += 5 + info;
      types.add(type);
      final videoCodec = _videoCodecOf(type);
      if (videoCodec != null) {
        if (video == null) {
          video = pid;
          codec = videoCodec;
        }
      } else if (_isVideoType(type)) {
        unsupportedVideo ??= type;
      } else if (type == 0x0F) {
        audio ??= pid;
      } else if (_isAudioType(type)) {
        unsupportedAudio ??= type;
      }
    }
    streamTypes = types;
    if (video == null && unsupportedVideo != null) unsupportedType ??= unsupportedVideo;
    if (audio == null && unsupportedAudio != null) unsupportedType ??= unsupportedAudio;
    if (strict && unsupportedType != null) {
      throw RemuxException(
        'unsupported MPEG-TS stream type 0x${unsupportedType!.toRadixString(16)} at offset $offset',
        unsupportedCodec: true,
      );
    }
    // A stream that moved to another PID ends its last unit on the old one.
    if (video != _videoPid) {
      final pes = _pes.remove(_videoPid);
      if (pes != null) _finishPes(pes, emit, atEnd: false);
      _flushVideo(emit);
      _videoPid = video;
    }
    if (audio != _audioPid) {
      final pes = _pes.remove(_audioPid);
      if (pes != null) _finishPes(pes, emit, atEnd: false);
      _audioCarry = null;
      _audioResync = true;
      _audioPid = audio;
    }
    if (codec != null) videoCodec = codec;
  }

  // PES (§2.4.3.6).

  void _finishPes(_Pes pes, void Function(TsSample sample) emit, {required bool atEnd}) {
    final data = pes.builder.takeBytes();
    if (data.length < 9 || data[0] != 0 || data[1] != 0 || data[2] != 1) {
      if (data.isEmpty) return;
      _damage(pes.pid, 'bad PES start at offset ${pes.offset}');
      return;
    }
    final declared = (data[4] << 8) | data[5];
    if (declared != 0 && data.length != 6 + declared) {
      if (atEnd && data.length < 6 + declared) return;
      // Stuffing after a complete PES in the last packet is allowed.
      if (data.length < 6 + declared || !_onlyStuffing(data, 6 + declared)) {
        _damage(pes.pid, 'PES of ${data.length - 6} bytes, declared $declared, at offset ${pes.offset}');
        return;
      }
    }
    final flags = data[7] >> 6;
    final headerLength = data[8];
    final payloadStart = 9 + headerLength;
    final payloadEnd = declared == 0 ? data.length : 6 + declared;
    if (payloadStart > payloadEnd) {
      _damage(pes.pid, 'bad PES header at offset ${pes.offset}');
      return;
    }
    if (flags == 0 || flags == 1) {
      _damage(pes.pid, 'PES without a timestamp at offset ${pes.offset}');
      return;
    }
    final clock = _clocks.putIfAbsent(pes.pid, _Clock.new);
    final rawPts = _timestamp(data, 9);
    final rawDts = flags == 3 ? _timestamp(data, 14) : rawPts;
    final dts = clock.unwrap(rawDts);
    var delta = (rawPts - rawDts) % _wrap;
    if (delta > _wrap >> 1) delta -= _wrap;
    final pts = dts + delta;
    final payload = Uint8List.sublistView(data, payloadStart, payloadEnd);
    if (pes.pid == _videoPid) {
      _video(payload, dts, pts, pes, emit);
    } else if (pes.pid == _audioPid) {
      _adts(payload, pts, pes, emit);
    }
  }

  /// An access unit waits for the next PES: some muxers (Twitch / Amazon
  /// IVS) start a PES with the tail of the previous unit before its first
  /// start code; those bytes belong to the waiting unit (ffmpeg's parser
  /// joins them the same way).
  void _video(Uint8List payload, int dts, int pts, _Pes pes, void Function(TsSample sample) emit) {
    if (payload.isEmpty) return;
    var start = _firstStartCode(payload);
    if (start < 0) start = payload.length;
    final pending = _pendingVideo;
    if (start > 0) {
      if (pending != null) {
        final joined = Uint8List(pending.data.length + start)
          ..setRange(0, pending.data.length, pending.data)
          ..setRange(pending.data.length, pending.data.length + start, payload);
        _pendingVideo = (
          data: joined,
          dts: pending.dts,
          pts: pending.pts,
          offset: pending.offset,
          aligned: pending.aligned,
        );
      } else {
        // The tail of a unit from before the file began.
        damaged++;
      }
    }
    if (start >= payload.length) return;
    _flushVideo(emit);
    _pendingVideo = (
      data: Uint8List.sublistView(payload, start),
      dts: dts,
      pts: pts,
      offset: pes.offset,
      aligned: start == 0,
    );
  }

  void _flushVideo(void Function(TsSample sample) emit) {
    final unit = _pendingVideo;
    _pendingVideo = null;
    if (unit == null) return;
    final codec = videoCodec ?? VideoCodec.avc;
    if (strict && _accessUnitDelimiters(codec, unit.data) > 1) {
      throw RemuxException('several access units in one PES at offset ${unit.offset}');
    }
    emit(
      TsSample(
        video: true,
        dts: unit.dts,
        pts: unit.pts,
        keyframe: isKeyframe(codec, unit.data),
        data: unit.data,
        offset: unit.offset,
        aligned: unit.aligned,
      ),
    );
  }

  /// Offset of the first Annex B start code in [data] (its leading zero
  /// byte included when it is a 4-byte one), or -1.
  static int _firstStartCode(Uint8List data) {
    for (var i = 0; i + 2 < data.length; i++) {
      if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) return i > 0 && data[i - 1] == 0 ? i - 1 : i;
    }
    return -1;
  }

  static int _accessUnitDelimiters(VideoCodec codec, Uint8List unit) {
    var count = 0;
    for (final nal in splitAnnexB(unit)) {
      if (nal.isEmpty) continue;
      final type = codec == VideoCodec.avc ? nal[0] & 0x1F : (nal[0] >> 1) & 0x3F;
      if (type == (codec == VideoCodec.avc ? 9 : 35)) count++;
    }
    return count;
  }

  static bool _samePacket(Uint8List a, Uint8List b) {
    for (var i = 4; i < tsPacketSize; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _onlyStuffing(Uint8List data, int from) {
    for (var i = from; i < data.length; i++) {
      if (data[i] != 0xFF) return false;
    }
    return true;
  }

  static int _timestamp(Uint8List data, int at) =>
      ((data[at] >> 1) & 0x07) * (1 << 30) +
      (data[at + 1] << 22) +
      ((data[at + 2] >> 1) << 15) +
      (data[at + 3] << 7) +
      (data[at + 4] >> 1);

  void _adts(Uint8List input, int pts, _Pes pes, void Function(TsSample sample) emit) {
    // A frame that began in the previous PES keeps its own time; the first
    // frame starting in this PES has this PES's time.
    var carry = _audioCarry;
    _audioCarry = null;
    var payload = input;
    if (carry != null && _audioRate > 0) {
      // Muxers may split a frame across PES. When this PES does not follow
      // the carried frame (a reconnection or a split of a continuous
      // recording in between, spec §8.2), the frame's end is not in the
      // file: drop it rather than join it to foreign bytes.
      final frame = (1024 * 90000 / _audioRate).round();
      if ((pts - _audioCarryPts - frame).abs() > 2 * frame) {
        carry = null;
        damaged++;
        _audioResync = true;
      }
    }
    if (carry == null && _audioResync) {
      // The rest of a frame begun before the file (or the gap) comes first.
      final sync = _adtsSync(payload);
      if (sync < 0) return;
      if (sync > 0) {
        damaged++;
        payload = Uint8List.sublistView(payload, sync);
      }
      _audioResync = false;
    }
    final boundary = carry?.length ?? 0;
    final data = carry == null ? payload : _join(carry, payload);
    var time = carry == null ? pts : _audioCarryPts;
    var at = 0;
    var inPayload = carry == null;
    while (at < data.length) {
      if (!inPayload && at >= boundary) {
        inPayload = true;
        time = pts;
      }
      final left = data.length - at;
      if (left < 9 || data[at] != 0xFF || (data[at + 1] & 0xF6) != 0xF0) {
        if (left < 9 && data[at] == 0xFF) {
          _carry(Uint8List.sublistView(data, at), time);
        } else if (!_onlyStuffing(data, at)) {
          _damage(pes.pid, 'no ADTS sync in AAC PES at offset ${pes.offset}');
        }
        return;
      }
      final frame = _frameLength(Uint8List.sublistView(data, at));
      final header = (data[at + 1] & 0x01) == 1 ? 7 : 9;
      if (frame <= header) {
        _damage(pes.pid, 'bad ADTS frame length $frame at offset ${pes.offset}');
        return;
      }
      if ((data[at + 6] & 0x03) != 0) {
        _damage(pes.pid, 'ADTS frame with several raw data blocks at offset ${pes.offset}');
        return;
      }
      if (frame > left) {
        _carry(Uint8List.sublistView(data, at), time);
        return;
      }
      final bytes = Uint8List.sublistView(data, at, at + frame);
      emit(TsSample(video: false, dts: time, pts: time, keyframe: true, data: bytes, offset: pes.offset));
      time += _frameTicks(bytes);
      at += frame;
    }
  }

  /// Offset of the first ADTS frame in [data]: a sync word whose frame ends
  /// at the end of [data], runs past it, or is followed by another sync word.
  static int _adtsSync(Uint8List data) {
    for (var at = 0; at + 7 <= data.length; at++) {
      if (data[at] != 0xFF || (data[at + 1] & 0xF6) != 0xF0) continue;
      final length = _frameLength(Uint8List.sublistView(data, at));
      if (length < 7) continue;
      final next = at + length;
      if (next >= data.length) return at;
      if (next + 1 < data.length && data[next] == 0xFF && (data[next + 1] & 0xF6) == 0xF0) return at;
    }
    return -1;
  }

  static Uint8List _join(Uint8List a, Uint8List b) => Uint8List(a.length + b.length)
    ..setRange(0, a.length, a)
    ..setRange(a.length, a.length + b.length, b);

  void _carry(Uint8List bytes, int pts) {
    _audioCarry = Uint8List.fromList(bytes);
    _audioCarryPts = pts;
  }

  static int _frameLength(Uint8List data) => ((data[3] & 0x03) << 11) | (data[4] << 3) | (data[5] >> 5);

  int _frameTicks(Uint8List header) {
    final index = (header[2] >> 2) & 0x0F;
    final rate = index < _adtsRates.length ? _adtsRates[index] : 0;
    if (rate > 0) _audioRate = rate;
    return _audioRate > 0 ? (1024 * 90000 / _audioRate).round() : 1920;
  }

  /// Whether the Annex B access unit [unit] starts a GOP: an IDR or a
  /// recovery point (H.264), an IRAP picture (H.265).
  static bool isKeyframe(VideoCodec codec, Uint8List unit) {
    for (final nal in splitAnnexB(unit)) {
      if (nal.isEmpty) continue;
      if (codec == VideoCodec.avc) {
        final type = nal[0] & 0x1F;
        if (type == 5) return true;
        if (type == 6 && _hasRecoveryPoint(nal)) return true;
      } else {
        final type = (nal[0] >> 1) & 0x3F;
        if (type >= 16 && type <= 23) return true;
      }
    }
    return false;
  }

  static bool _hasRecoveryPoint(Uint8List nal) {
    final rbsp = unescapeRbsp(nal, 1);
    var at = 0;
    while (at < rbsp.length && rbsp[at] != 0x80) {
      var type = 0;
      while (at < rbsp.length && rbsp[at] == 0xFF) {
        type += 255;
        at++;
      }
      if (at >= rbsp.length) return false;
      type += rbsp[at++];
      var size = 0;
      while (at < rbsp.length && rbsp[at] == 0xFF) {
        size += 255;
        at++;
      }
      if (at >= rbsp.length) return false;
      size += rbsp[at++];
      if (type == 6) return true;
      at += size;
    }
    return false;
  }
}

const _adtsRates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350];

/// Strips the ADTS header of [frame]; the raw AAC frame.
Uint8List adtsPayload(Uint8List frame) {
  final header = (frame[1] & 0x01) == 1 ? 7 : 9;
  return Uint8List.sublistView(frame, header);
}

/// What identifies the codec setup of an MPEG-TS stretch: stream types and
/// the video parameter sets and AAC configuration. Two HLS segments with the
/// same signature can share a file (spec §6.5).
final class TsSignature {
  /// Creates a signature.
  const new({required this.streamTypes, this.parameterSets, this.audioConfig, this.startsWithKeyframe = false});

  /// PMT stream types (only video and audio ones).
  final List<int> streamTypes;

  /// Video parameter sets (VPS, SPS, PPS in Annex B), when the segment has a keyframe.
  final Uint8List? parameterSets;

  /// AAC AudioSpecificConfig, when the segment has audio.
  final Uint8List? audioConfig;

  /// Whether the first video unit is a keyframe (a segment can start a file).
  final bool startsWithKeyframe;

  /// Whether a file with this signature can take a segment of [other]: same streams,
  /// and the same parameters where both know them.
  bool compatible(TsSignature other) {
    if (!_same(streamTypes, other.streamTypes)) return false;
    final sets = parameterSets;
    final otherSets = other.parameterSets;
    if (sets != null && otherSets != null && !_same(sets, otherSets)) return false;
    final audio = audioConfig;
    final otherAudio = other.audioConfig;
    return audio == null || otherAudio == null || _same(audio, otherAudio);
  }

  /// This signature with what [other] knows added where this one knows nothing.
  TsSignature merge(TsSignature other) => TsSignature(
    streamTypes: streamTypes,
    parameterSets: parameterSets ?? other.parameterSets,
    audioConfig: audioConfig ?? other.audioConfig,
    startsWithKeyframe: startsWithKeyframe,
  );

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Reads the signature of one MPEG-TS segment; null when it is not TS.
  static TsSignature? of(Uint8List segment) {
    if (!looksLikeTs(segment)) return null;
    final demuxer = TsDemuxer(strict: false);
    Uint8List? sets;
    Uint8List? audio;
    bool? firstKey;
    var done = false;
    void onSample(TsSample sample) {
      if (sample.video) {
        firstKey ??= sample.keyframe;
        if (sets == null && sample.keyframe) sets = parameterSetsOf(demuxer.videoCodec ?? VideoCodec.avc, sample.data);
      } else {
        audio ??= ascOfAdts(sample.data);
      }
      done = (sets != null || demuxer.videoPid == null) && (audio != null || demuxer.audioPid == null);
    }

    try {
      for (var at = 0; at + tsPacketSize <= segment.length && !done; at += tsPacketSize) {
        demuxer.add(Uint8List.sublistView(segment, at, at + tsPacketSize), at, onSample);
      }
      if (!done) demuxer.finish(onSample);
    } on Object {
      // A damaged segment still gets written; the remux judges the file.
    }
    return TsSignature(
      streamTypes: [
        for (final type in demuxer.streamTypes)
          if (_isVideoType(type) || _isAudioType(type)) type,
      ],
      parameterSets: sets,
      audioConfig: audio,
      startsWithKeyframe: firstKey ?? true,
    );
  }
}

/// The VPS, SPS and PPS NAL units of [unit] in Annex B (start code + unit
/// each), in stream order; null when it has no SPS.
Uint8List? parameterSetsOf(VideoCodec codec, Uint8List unit) {
  final out = BytesBuilder(copy: false);
  var sps = false;
  for (final nal in splitAnnexB(unit)) {
    if (nal.isEmpty) continue;
    final type = codec == VideoCodec.avc ? nal[0] & 0x1F : (nal[0] >> 1) & 0x3F;
    final isSet = codec == VideoCodec.avc ? (type == 7 || type == 8) : (type >= 32 && type <= 34);
    if (!isSet) continue;
    if (codec == VideoCodec.avc ? type == 7 : type == 33) sps = true;
    out
      ..add(const [0, 0, 0, 1])
      ..add(nal);
  }
  return sps ? out.takeBytes() : null;
}

/// The AudioSpecificConfig announced by the ADTS header of [frame].
Uint8List ascOfAdts(Uint8List frame) {
  final objectType = ((frame[2] >> 6) & 0x03) + 1;
  final rateIndex = (frame[2] >> 2) & 0x0F;
  final channels = ((frame[2] & 0x01) << 2) | (frame[3] >> 6);
  return Uint8List.fromList([(objectType << 3) | (rateIndex >> 1), ((rateIndex & 1) << 7) | (channels << 3)]);
}

/// Splits the MPEG-TS [segment] at its first keyframe so the second part
/// can start a file (spec §6.5: files start with a keyframe): the first
/// part ends before the packet that starts the keyframe's PES; the second
/// part is the segment's PAT and PMT, then everything from that packet,
/// without the leftover packets of other streams' units begun before it.
/// Null when the segment has no keyframe whose PES starts with it.
({Uint8List head, Uint8List tail})? cutAtKeyframe(Uint8List segment) {
  final demuxer = TsDemuxer(strict: false);
  int? cut;
  void onSample(TsSample sample) {
    if (cut == null && sample.video && sample.keyframe && sample.aligned) cut = sample.offset;
  }

  final psi = BytesBuilder(copy: false);
  final seenPsi = <int>{};
  int? pmtPid;
  try {
    for (var at = 0; at + tsPacketSize <= segment.length && cut == null; at += tsPacketSize) {
      final packet = Uint8List.sublistView(segment, at, at + tsPacketSize);
      final pid = ((packet[1] & 0x1F) << 8) | packet[2];
      final unitStart = (packet[1] & 0x40) != 0;
      if ((pid == 0 || pid == pmtPid) && unitStart && seenPsi.add(pid)) psi.add(packet);
      demuxer.add(packet, at, onSample);
      pmtPid ??= demuxer._pmtPid;
    }
    if (cut == null) demuxer.finish(onSample);
  } on Object {
    return null;
  }
  final at = cut;
  if (at == null) return null;
  final tail = BytesBuilder(copy: false)..add(psi.takeBytes());
  final started = <int>{};
  for (var offset = at; offset + tsPacketSize <= segment.length; offset += tsPacketSize) {
    final packet = Uint8List.sublistView(segment, offset, offset + tsPacketSize);
    final pid = ((packet[1] & 0x1F) << 8) | packet[2];
    final unitStart = (packet[1] & 0x40) != 0;
    if (pid != 0 && pid != pmtPid && !started.contains(pid)) {
      if (!unitStart) continue;
      started.add(pid);
    }
    tail.add(packet);
  }
  return (head: Uint8List.sublistView(segment, 0, at), tail: tail.takeBytes());
}
