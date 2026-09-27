import 'dart:async';
import 'dart:typed_data';

import 'package:live_record/src/files.dart';
import 'package:live_record/src/remux.dart';
import 'package:live_record/src/remux/codec_config.dart';
import 'package:live_record/src/remux/mp4_remux.dart';
import 'package:live_record/src/remux/mp4_writer.dart';
import 'package:live_record/src/remux/sample_table.dart';
import 'package:live_record/src/remux/ts_demux.dart';

const int _ticks = 90000;

/// Copies the H.264/H.265 and AAC streams of the MPEG-TS file at [input]
/// (the HLS writer's `.ts`) into a faststart MP4 at [output] without
/// decoding (spec §10). Access units become length-prefixed samples;
/// parameter sets that repeat the track's configuration are left out of the
/// samples (they live in `avcC`/`hvcC`); ADTS headers are removed. The
/// stretches of the recording (HLS discontinuities, a restarted stream) are
/// joined into one timeline ([TimelineJoiner]). Any damage — lost packets
/// inside a unit, a PES shorter or longer than declared, a codec
/// configuration change, an unsupported codec — throws [RemuxException].
Future<RemuxResult> remuxTsToMp4({
  required String input,
  required String output,
  RecordFiles files = const IoRecordFiles(),
  void Function(int bytesRead)? onProgress,
  bool Function()? isCancelled,
  int blockSize = 1 << 20,
}) => remuxToMp4(
  source: TsMp4Source.new,
  input: input,
  output: output,
  files: files,
  onProgress: onProgress,
  isCancelled: isCancelled,
  blockSize: blockSize,
);

/// [Mp4Source] over an MPEG-TS recording.
final class TsMp4Source implements Mp4Source {
  /// Creates a source for one pass.
  new();

  final _demuxer = TsDemuxer();
  final _joiner = TimelineJoiner(window: 60 * _ticks, back: _ticks);

  VideoConfig? _video;
  late List<Uint8List> _videoSets;
  int? _videoFirst;
  int? _videoLast;
  int? _videoStartMs;
  int _videoStep = 3000;
  var _videoDropped = 0;

  AacConfig? _audio;
  late Uint8List _asc;
  int? _audioFirst;
  int? _audioLast;
  int? _audioStartMs;

  @override
  int dropped = 0;

  @override
  Future<void> read(
    RecordReader reader, {
    required int blockSize,
    required void Function(Mp4Sample sample) onSample,
    required void Function(int read) onBlock,
    bool Function()? isCancelled,
    Future<void> Function()? afterBlock,
  }) async {
    void onUnit(TsSample unit) {
      if (isCancelled?.call() ?? false) throw const RemuxException('cancelled');
      final sample = unit.video ? _onVideo(unit) : _onAudio(unit);
      if (sample != null) onSample(sample);
    }

    final length = reader.length;
    final size = blockSize < tsPacketSize ? tsPacketSize : blockSize - blockSize % tsPacketSize;
    var read = 0;
    var carry = Uint8List(0);
    while (read < length) {
      if (isCancelled?.call() ?? false) throw const RemuxException('cancelled');
      final wanted = length - read < size ? length - read : size;
      final block = await reader.read(read, wanted);
      if (block.isEmpty) throw RemuxException('input ended at $read of $length bytes');
      final start = read - carry.length;
      read += block.length;
      final data = carry.isEmpty
          ? block
          : (Uint8List(carry.length + block.length)
              ..setRange(0, carry.length, carry)
              ..setRange(carry.length, carry.length + block.length, block));
      var at = 0;
      for (; at + tsPacketSize <= data.length; at += tsPacketSize) {
        _demuxer.add(Uint8List.sublistView(data, at, at + tsPacketSize), start + at, onUnit);
      }
      carry = Uint8List.fromList(Uint8List.sublistView(data, at));
      await afterBlock?.call();
      onBlock(read);
    }
    if (carry.isNotEmpty) throw RemuxException('truncated MPEG-TS packet at offset ${length - carry.length}');
    _demuxer.finish(onUnit);
    if (_video == null && _videoDropped > 0) throw const RemuxException('video without SPS/PPS or keyframe');
    await afterBlock?.call();
  }

  Mp4Sample? _onVideo(TsSample unit) {
    final codec = _demuxer.videoCodec;
    if (codec == null) return null;
    final nals = splitAnnexB(unit.data);
    final sets = [
      for (final nal in nals)
        if (nal.isNotEmpty && _isParameterSet(codec, nal)) nal,
    ];
    var config = _video;
    if (config == null) {
      final hasSps = sets.any((nal) => _isSps(codec, nal));
      if (!unit.keyframe || !hasSps) {
        _videoDropped++;
        dropped++;
        return null;
      }
      try {
        config = _video = VideoConfig.fromAnnexB(codec, unit.data);
      } on FormatException catch (error) {
        throw RemuxException('${error.message} at offset ${unit.offset}');
      }
      _videoSets = [for (final nal in sets) Uint8List.fromList(nal)];
    } else {
      for (final nal in sets) {
        if (!_videoSets.any((known) => _same(known, nal))) {
          throw RemuxException('video configuration changes at offset ${unit.offset}');
        }
      }
    }
    final units = [
      for (final nal in nals)
        if (nal.isNotEmpty && !sets.contains(nal)) nal,
    ];
    if (units.isEmpty) return null;
    final Uint8List payload;
    try {
      payload = lengthPrefixed(units, config.lengthSize);
    } on FormatException catch (error) {
      throw RemuxException('${error.message} at offset ${unit.offset}');
    }
    final adjusted = _joiner.adjust(videoTrack, unit.dts, duration: _videoStep);
    final pts = adjusted + unit.pts - unit.dts;
    final first = _videoFirst ??= adjusted;
    _videoStartMs ??= _floorMs(adjusted);
    var dts = adjusted - first;
    final last = _videoLast;
    if (last != null) {
      if (dts <= last) {
        if (last - dts > _ticks) throw RemuxException('video timestamps go back at offset ${unit.offset}');
        dts = last + 1;
      } else {
        final step = dts - last;
        _videoStep = step < 1 ? 1 : (step > 9000 ? 9000 : step);
      }
    }
    _videoLast = dts;
    return Mp4Sample(
      track: videoTrack,
      ms: _floorMs(adjusted),
      dts: dts,
      offset: pts - first - dts,
      sync: unit.keyframe,
      data: payload,
    );
  }

  Mp4Sample? _onAudio(TsSample unit) {
    final frame = unit.data;
    final asc = ascOfAdts(frame);
    var config = _audio;
    if (config == null) {
      try {
        config = _audio = AacConfig.parse(asc);
      } on FormatException catch (error) {
        throw RemuxException('${error.message} at offset ${unit.offset}');
      }
      _asc = asc;
    } else if (!_same(asc, _asc)) {
      throw RemuxException('audio configuration changes at offset ${unit.offset}');
    }
    final rate = config.sampleRate;
    final frameSamples = config.frameSamples;
    final adjusted = _joiner.adjust(audioTrack, unit.pts, duration: (frameSamples * _ticks / rate).round());
    final first = _audioFirst ??= adjusted;
    _audioStartMs ??= _floorMs(adjusted);
    final last = _audioLast;
    int dts;
    if (last == null) {
      dts = 0;
    } else {
      // Nominal frame after frame; follow the timestamps only when they move
      // a frame or more away (a hole or a clock drift).
      final target = ((adjusted - first) * rate / _ticks).round();
      final nominal = last + frameSamples;
      dts = (target - nominal).abs() < frameSamples ? nominal : (target > last ? target : last + 1);
    }
    _audioLast = dts;
    return Mp4Sample(
      track: audioTrack,
      ms: _floorMs(adjusted),
      dts: dts,
      offset: 0,
      sync: true,
      data: adtsPayload(frame),
    );
  }

  static int _floorMs(int ticks) => (ticks / 90).floor();

  static bool _isParameterSet(VideoCodec codec, Uint8List nal) {
    if (codec == VideoCodec.avc) {
      final type = nal[0] & 0x1F;
      return type == 7 || type == 8;
    }
    final type = (nal[0] >> 1) & 0x3F;
    return type >= 32 && type <= 34;
  }

  static bool _isSps(VideoCodec codec, Uint8List nal) =>
      codec == VideoCodec.avc ? (nal[0] & 0x1F) == 7 : ((nal[0] >> 1) & 0x3F) == 33;

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int timescale(int track) => track == videoTrack ? _ticks : _audio!.sampleRate;

  @override
  int fallbackDuration(int track) => track == videoTrack ? _ticks ~/ 30 : (_audio?.frameSamples ?? 1024);

  @override
  List<Mp4Track> tracks(Map<int, TrackTable> tables) {
    final video = tables[videoTrack];
    final audio = tables[audioTrack];
    final config = _video;
    final aac = _audio;
    return [
      if (video != null && video.sampleCount > 0 && config != null)
        Mp4Track(table: video, codec: Mp4VideoCodec(config), startMs: _videoStartMs!),
      if (audio != null && audio.sampleCount > 0 && aac != null)
        Mp4Track(table: audio, codec: Mp4AacCodec(aac), startMs: _audioStartMs!),
    ];
  }
}
