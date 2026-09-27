import 'dart:async';
import 'dart:typed_data';

import 'package:live_record/src/files.dart';
import 'package:live_record/src/remux.dart';
import 'package:live_record/src/remux/mp4_remux.dart';
import 'package:live_record/src/remux/mp4_writer.dart';
import 'package:live_record/src/remux/sample_table.dart';

const int _ticks = 90000;

/// Copies the video and audio tracks of the fragmented MP4 at [input] (the
/// HLS writer's `.m4s`: an initialisation section, then `moof` + `mdat`
/// fragments) into a faststart MP4 at [output] (spec §10). Sample entries
/// (`avc1`, `hvc1`, `mp4a`… with their configuration boxes) are copied as
/// they are; sample tables are rebuilt from the `trun` boxes; the stretches
/// of the recording are joined into one timeline ([TimelineJoiner]).
/// Encrypted tracks, a second initialisation section, sample data outside
/// the file and cut boxes throw [RemuxException].
Future<RemuxResult> remuxFmp4ToMp4({
  required String input,
  required String output,
  RecordFiles files = const IoRecordFiles(),
  void Function(int bytesRead)? onProgress,
  bool Function()? isCancelled,
}) => remuxToMp4(
  source: Fmp4Source.new,
  input: input,
  output: output,
  files: files,
  onProgress: onProgress,
  isCancelled: isCancelled,
);

final class _Track {
  new({
    required this.id,
    required this.video,
    required this.timescale,
    required this.entry,
    required this.width,
    required this.height,
  });

  final int id;
  final bool video;
  final int timescale;
  final Uint8List entry;
  final int width;
  final int height;
  int defaultDuration = 0;
  int defaultSize = 0;
  int defaultFlags = 0;

  /// Decode time after the last sample, for fragments without `tfdt`.
  int next = 0;
  int? first;
  int? last;
  int? startMs;
  int step = 0;
}

/// Box header: type, size (whole box) and header length.
({String type, int size, int header}) _box(Uint8List bytes, int at, int limit) {
  if (at + 8 > limit) throw const RemuxException('truncated box header');
  final data = ByteData.sublistView(bytes);
  var size = data.getUint32(at);
  final type = String.fromCharCodes(bytes, at + 4, at + 8);
  var header = 8;
  if (size == 1) {
    if (at + 16 > limit) throw const RemuxException('truncated box header');
    size = data.getUint32(at + 8) * 0x100000000 + data.getUint32(at + 12);
    header = 16;
  } else if (size == 0) {
    size = limit - at;
  }
  if (size < header || at + size > limit) throw RemuxException('box $type overruns its parent');
  return (type: type, size: size, header: header);
}

/// Child boxes of the box body [from, to) of [bytes].
Iterable<({String type, int start, int body, int end})> _children(Uint8List bytes, int from, int to) sync* {
  var at = from;
  while (at + 8 <= to) {
    final box = _box(bytes, at, to);
    yield (type: box.type, start: at, body: at + box.header, end: at + box.size);
    at += box.size;
  }
}

/// [Mp4Source] over a fragmented MP4 recording.
final class Fmp4Source implements Mp4Source {
  /// Creates a source for one pass.
  new();

  final _joiner = TimelineJoiner(window: 60 * _ticks, back: _ticks);
  _Track? _video;
  _Track? _audio;
  var _init = false;
  var _sawKeyframe = false;

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
    final length = reader.length;
    var offset = 0;
    while (offset < length) {
      if (isCancelled?.call() ?? false) throw const RemuxException('cancelled');
      final head = await reader.read(offset, length - offset < 16 ? length - offset : 16);
      if (head.length < 8) throw RemuxException('truncated box header at offset $offset');
      final type = String.fromCharCodes(head, 4, 8);
      var size = ByteData.sublistView(head).getUint32(0);
      if (size == 1) {
        if (head.length < 16) throw RemuxException('truncated box header at offset $offset');
        size = ByteData.sublistView(head).getUint32(8) * 0x100000000 + ByteData.sublistView(head).getUint32(12);
      } else if (size == 0) {
        size = length - offset;
      }
      if (size < 8) throw RemuxException('bad box size $size at offset $offset');
      if (offset + size > length) throw RemuxException('box $type at offset $offset is cut off');
      switch (type) {
        case 'moov':
          if (_init) throw RemuxException('a second initialisation section at offset $offset');
          if (size > 16 << 20) throw RemuxException('moov of $size bytes');
          _parseMoov(await reader.read(offset, size), offset);
          _init = true;
        case 'moof':
          if (!_init) throw RemuxException('fragment before the initialisation section at offset $offset');
          if (size > 16 << 20) throw RemuxException('moof of $size bytes');
          await _fragment(reader, await reader.read(offset, size), offset, length, onSample, isCancelled);
          await afterBlock?.call();
        default:
          // ftyp, styp, mdat (read through the fragments), sidx, prft, emsg, free…
          break;
      }
      offset += size;
      onBlock(offset);
    }
    if (!_init) throw const RemuxException('no initialisation section (moov)');
    await afterBlock?.call();
  }

  void _parseMoov(Uint8List moov, int offset) {
    final top = _box(moov, 0, moov.length);
    final trex = <int, ({int duration, int size, int flags})>{};
    for (final child in _children(moov, top.header, moov.length)) {
      if (child.type == 'mvex') {
        for (final entry in _children(moov, child.body, child.end)) {
          if (entry.type != 'trex') continue;
          final data = ByteData.sublistView(moov, entry.body);
          trex[data.getUint32(4)] = (duration: data.getUint32(12), size: data.getUint32(16), flags: data.getUint32(20));
        }
      }
    }
    for (final trak in _children(moov, top.header, moov.length)) {
      if (trak.type != 'trak') continue;
      final track = _parseTrak(moov, trak.body, trak.end, offset);
      if (track == null) continue;
      final defaults = trex[track.id];
      if (defaults != null) {
        track
          ..defaultDuration = defaults.duration
          ..defaultSize = defaults.size
          ..defaultFlags = defaults.flags;
      }
      if (track.video) {
        _video ??= track;
      } else {
        _audio ??= track;
      }
    }
    if (_video == null && _audio == null) throw const RemuxException('no audio or video track in the moov');
  }

  _Track? _parseTrak(Uint8List moov, int from, int to, int offset) {
    int? id;
    var width = 0;
    var height = 0;
    int? timescale;
    String? handler;
    Uint8List? entry;
    var entries = 0;
    for (final box in _children(moov, from, to)) {
      final data = ByteData.sublistView(moov);
      switch (box.type) {
        case 'tkhd':
          final v1 = moov[box.body] == 1;
          id = data.getUint32(box.body + (v1 ? 20 : 12));
          width = data.getUint32(box.end - 8) >> 16;
          height = data.getUint32(box.end - 4) >> 16;
        case 'mdia':
          for (final mdia in _children(moov, box.body, box.end)) {
            switch (mdia.type) {
              case 'mdhd':
                final v1 = moov[mdia.body] == 1;
                timescale = data.getUint32(mdia.body + (v1 ? 20 : 12));
              case 'hdlr':
                handler = String.fromCharCodes(moov, mdia.body + 8, mdia.body + 12);
              case 'minf':
                final stbl = _children(moov, mdia.body, mdia.end).where((b) => b.type == 'stbl').firstOrNull;
                final stsd = stbl == null
                    ? null
                    : _children(moov, stbl.body, stbl.end).where((b) => b.type == 'stsd').firstOrNull;
                if (stsd != null) {
                  entries = data.getUint32(stsd.body + 4);
                  final first = _box(moov, stsd.body + 8, stsd.end);
                  entry = Uint8List.fromList(Uint8List.sublistView(moov, stsd.body + 8, stsd.body + 8 + first.size));
                }
            }
          }
      }
    }
    if (handler != 'vide' && handler != 'soun') return null;
    if (id == null || timescale == null || timescale <= 0 || entry == null) {
      throw RemuxException('incomplete $handler track in the moov at offset $offset');
    }
    if (entries != 1) throw RemuxException('$entries sample descriptions in one track at offset $offset');
    final type = String.fromCharCodes(entry, 4, 8);
    if (type == 'encv' || type == 'enca') throw const RemuxException('encrypted fragmented MP4');
    return _Track(id: id, video: handler == 'vide', timescale: timescale, entry: entry, width: width, height: height);
  }

  Future<void> _fragment(
    RecordReader reader,
    Uint8List moof,
    int moofOffset,
    int fileLength,
    void Function(Mp4Sample sample) onSample,
    bool Function()? isCancelled,
  ) async {
    final top = _box(moof, 0, moof.length);
    final data = ByteData.sublistView(moof);
    final samples = <({_Track track, int dts, int cts, int size, bool sync, int at})>[];
    var previousEnd = moofOffset;
    for (final traf in _children(moof, top.header, moof.length)) {
      if (traf.type != 'traf') continue;
      _Track? track;
      var base = moofOffset;
      var duration = 0;
      var size = 0;
      var flags = 0;
      int? decode;
      int? runEnd;
      for (final box in _children(moof, traf.body, traf.end)) {
        switch (box.type) {
          case 'tfhd':
            final tfhd = data.getUint32(box.body) & 0xFFFFFF;
            final id = data.getUint32(box.body + 4);
            track = _video?.id == id ? _video : (_audio?.id == id ? _audio : null);
            duration = track?.defaultDuration ?? 0;
            size = track?.defaultSize ?? 0;
            flags = track?.defaultFlags ?? 0;
            var at = box.body + 8;
            if (tfhd & 0x01 != 0) {
              base = data.getUint32(at) * 0x100000000 + data.getUint32(at + 4);
              at += 8;
            } else if (tfhd & 0x020000 == 0) {
              // Neither an explicit base nor default-base-is-moof: after the previous track's data.
              base = previousEnd;
            }
            if (tfhd & 0x02 != 0) {
              if (data.getUint32(at) != 1) throw RemuxException('sample description change at offset $moofOffset');
              at += 4;
            }
            if (tfhd & 0x08 != 0) {
              duration = data.getUint32(at);
              at += 4;
            }
            if (tfhd & 0x10 != 0) {
              size = data.getUint32(at);
              at += 4;
            }
            if (tfhd & 0x20 != 0) flags = data.getUint32(at);
          case 'tfdt':
            final v1 = moof[box.body] == 1;
            decode = v1
                ? data.getUint32(box.body + 4) * 0x100000000 + data.getUint32(box.body + 8)
                : data.getUint32(box.body + 4);
          case 'trun':
            if (track == null) continue;
            final version = moof[box.body];
            final trun = data.getUint32(box.body) & 0xFFFFFF;
            final count = data.getUint32(box.body + 4);
            var at = box.body + 8;
            // Without a data offset a run continues after the previous one.
            var position = runEnd ?? base;
            if (trun & 0x01 != 0) {
              position = base + data.getInt32(at);
              at += 4;
            }
            int? firstFlags;
            if (trun & 0x04 != 0) {
              firstFlags = data.getUint32(at);
              at += 4;
            }
            var time = decode ?? track.next;
            decode = null;
            for (var i = 0; i < count; i++) {
              var sampleDuration = duration;
              var sampleSize = size;
              var sampleFlags = i == 0 && firstFlags != null ? firstFlags : flags;
              var cts = 0;
              if (trun & 0x100 != 0) {
                sampleDuration = data.getUint32(at);
                at += 4;
              }
              if (trun & 0x200 != 0) {
                sampleSize = data.getUint32(at);
                at += 4;
              }
              if (trun & 0x400 != 0) {
                final value = data.getUint32(at);
                if (!(i == 0 && firstFlags != null)) sampleFlags = value;
                at += 4;
              }
              if (trun & 0x800 != 0) {
                cts = version == 0 ? data.getUint32(at) : data.getInt32(at);
                at += 4;
              }
              if (at > box.end) throw RemuxException('truncated trun at offset $moofOffset');
              samples.add((
                track: track,
                dts: time,
                cts: cts,
                size: sampleSize,
                sync: (sampleFlags & 0x10000) == 0,
                at: position,
              ));
              position += sampleSize;
              time += sampleDuration;
            }
            track.next = time;
            runEnd = position;
        }
      }
      if (runEnd != null) previousEnd = runEnd;
    }
    if (samples.isEmpty) return;
    var from = samples.first.at;
    var to = from;
    for (final sample in samples) {
      if (sample.at < from) from = sample.at;
      if (sample.at + sample.size > to) to = sample.at + sample.size;
    }
    if (from < 0 || to > fileLength) throw RemuxException('fragment data outside the file at offset $moofOffset');
    if (to - from > 256 << 20) throw RemuxException('fragment of ${to - from} bytes at offset $moofOffset');
    final payload = await reader.read(from, to - from);
    if (payload.length != to - from) throw RemuxException('fragment data cut off at offset $moofOffset');
    for (final sample in samples) {
      if (isCancelled?.call() ?? false) throw const RemuxException('cancelled');
      final bytes = Uint8List.sublistView(payload, sample.at - from, sample.at - from + sample.size);
      final out = _sample(sample.track, sample.dts, sample.cts, sample.sync, bytes, moofOffset);
      if (out != null) onSample(out);
    }
  }

  Mp4Sample? _sample(_Track track, int decode, int composition, bool sync, Uint8List data, int offset) {
    var cts = composition;
    if (track.video && !_sawKeyframe) {
      if (!sync) {
        dropped++;
        return null;
      }
      _sawKeyframe = true;
    }
    final scale = track.timescale;
    final raw90 = (decode * _ticks / scale).round();
    final stepTicks = (track.step * _ticks / scale).round();
    final adjusted90 = _joiner.adjust(
      track.video ? videoTrack : audioTrack,
      raw90,
      duration: stepTicks > 0 ? stepTicks : _ticks ~/ 30,
    );
    final adjusted = decode + ((adjusted90 - raw90) * scale / _ticks).round();
    final first = track.first ??= adjusted;
    track.startMs ??= (adjusted90 / 90).floor();
    var dts = adjusted - first;
    final last = track.last;
    if (last != null) {
      if (dts <= last) {
        if (last - dts > scale) throw RemuxException('timestamps go back in the fragment at offset $offset');
        final bump = last + 1 - dts;
        dts = last + 1;
        cts -= bump;
      } else {
        track.step = dts - last;
      }
    }
    track.last = dts;
    return Mp4Sample(
      track: track.video ? videoTrack : audioTrack,
      ms: (adjusted90 / 90).floor(),
      dts: dts,
      offset: cts,
      sync: sync,
      data: data,
    );
  }

  @override
  int timescale(int track) => (track == videoTrack ? _video : _audio)!.timescale;

  @override
  int fallbackDuration(int track) {
    final t = (track == videoTrack ? _video : _audio)!;
    return t.video ? t.timescale ~/ 30 : 1024;
  }

  @override
  List<Mp4Track> tracks(Map<int, TrackTable> tables) => [
    for (final (index, track) in [(videoTrack, _video), (audioTrack, _audio)])
      if (track != null && (tables[index]?.sampleCount ?? 0) > 0)
        Mp4Track(
          table: tables[index]!,
          codec: Mp4RawCodec(track.entry, isVideo: track.video, width: track.width, height: track.height),
          startMs: track.startMs!,
        ),
  ];
}
