import 'dart:typed_data';

import 'package:live_record/src/files.dart';
import 'package:live_record/src/remux.dart';
import 'package:live_record/src/remux/codec_config.dart';
import 'package:live_record/src/remux/sample_table.dart';

/// Movie timescale (`mvhd`, `tkhd`, `elst` durations): milliseconds.
const movieTimescale = 1000;

/// Buffered sequential writer over a [RecordSink] with big-endian helpers.
/// The fixed-size helpers assume room: callers check [full] and [flush].
final class Mp4Output {
  /// Writes to [_sink] through a buffer of [bufferSize] bytes.
  new(this._sink, {int bufferSize = 1 << 20}) : _buffer = Uint8List(bufferSize), _data = ByteData(0) {
    _data = ByteData.sublistView(_buffer);
  }

  final RecordSink _sink;
  final Uint8List _buffer;
  ByteData _data;
  var _position = 0;
  var _flushed = 0;

  /// Bytes written so far (flushed or buffered).
  int get length => _flushed + _position;

  /// Whether the buffer has less than 16 bytes left.
  bool get full => _position > _buffer.length - 16;

  /// Writes one byte.
  void u8(int value) => _buffer[_position++] = value;

  /// Writes a 32-bit big-endian value.
  void u32(int value) {
    _data.setUint32(_position, value & 0xffffffff);
    _position += 4;
  }

  /// Writes a 64-bit big-endian value.
  void u64(int value) {
    _data
      ..setUint32(_position, (value >> 32) & 0xffffffff)
      ..setUint32(_position + 4, value & 0xffffffff);
    _position += 8;
  }

  /// Writes a four-character code.
  void fourCc(String code) {
    for (var i = 0; i < 4; i++) {
      _buffer[_position++] = code.codeUnitAt(i);
    }
  }

  /// Writes [bytes] of any length.
  Future<void> add(Uint8List bytes) async {
    if (bytes.length <= _buffer.length - _position) {
      _buffer.setRange(_position, _position + bytes.length, bytes);
      _position += bytes.length;
      return;
    }
    await flush();
    if (bytes.length >= _buffer.length ~/ 2) {
      await _sink.write(bytes);
      _flushed += bytes.length;
    } else {
      _buffer.setRange(0, bytes.length, bytes);
      _position = bytes.length;
    }
  }

  /// Hands the buffered bytes to the sink.
  Future<void> flush() async {
    if (_position == 0) return;
    // The sink may keep the list until the write completes: give it a copy.
    await _sink.write(Uint8List.fromList(Uint8List.sublistView(_buffer, 0, _position)));
    _flushed += _position;
    _position = 0;
  }
}

/// Builds a small box tree in memory (everything but the large sample tables).
final class _Bytes {
  var _buffer = Uint8List(256);
  late var _data = ByteData.sublistView(_buffer);
  var _length = 0;

  int get length => _length;

  void _ensure(int extra) {
    if (_length + extra <= _buffer.length) return;
    var capacity = _buffer.length * 2;
    while (capacity < _length + extra) {
      capacity *= 2;
    }
    _buffer = Uint8List(capacity)..setRange(0, _length, _buffer);
    _data = ByteData.sublistView(_buffer);
  }

  void u8(int value) {
    _ensure(1);
    _buffer[_length++] = value;
  }

  void u16(int value) {
    _ensure(2);
    _data.setUint16(_length, value & 0xffff);
    _length += 2;
  }

  void u32(int value) {
    _ensure(4);
    _data.setUint32(_length, value & 0xffffffff);
    _length += 4;
  }

  void u64(int value) {
    u32(value >> 32);
    u32(value);
  }

  void fourCc(String code) {
    for (var i = 0; i < 4; i++) {
      u8(code.codeUnitAt(i));
    }
  }

  void bytes(List<int> values) {
    _ensure(values.length);
    _buffer.setRange(_length, _length + values.length, values);
    _length += values.length;
  }

  void zeros(int count) {
    _ensure(count);
    _buffer.fillRange(_length, _length + count, 0);
    _length += count;
  }

  void box(String type, void Function() body) {
    final start = _length;
    u32(0);
    fourCc(type);
    body();
    _data.setUint32(start, _length - start);
  }

  void fullBox(String type, int version, int flags, void Function() body) => box(type, () {
    u32((version << 24) | flags);
    body();
  });

  /// An MPEG-4 descriptor with a 4-byte size field (ISO/IEC 14496-1 8.3.3).
  void descriptor(int tag, void Function() body) {
    u8(tag);
    final start = _length;
    u32(0);
    body();
    final size = _length - start - 4;
    _buffer
      ..[start] = 0x80 | ((size >> 21) & 0x7f)
      ..[start + 1] = 0x80 | ((size >> 14) & 0x7f)
      ..[start + 2] = 0x80 | ((size >> 7) & 0x7f)
      ..[start + 3] = size & 0x7f;
  }

  Uint8List take() => Uint8List.sublistView(_buffer, 0, _length);
}

sealed class _Node {
  int get size;

  Future<void> write(Mp4Output out);
}

final class _Raw extends _Node {
  new(this.bytes);

  final Uint8List bytes;

  @override
  int get size => bytes.length;

  @override
  Future<void> write(Mp4Output out) => out.add(bytes);
}

final class _Container extends _Node {
  new(this.type, this.children);

  final String type;
  final List<_Node> children;

  @override
  int get size => children.fold(8, (sum, child) => sum + child.size);

  @override
  Future<void> write(Mp4Output out) async {
    if (out.full) await out.flush();
    out
      ..u32(size)
      ..fourCc(type);
    for (final child in children) {
      await child.write(out);
    }
  }
}

/// A full box holding a large table, written entry by entry.
final class _Table extends _Node {
  new(this.type, {required this.fields, required this.entries, required this.entrySize, required this.writeEntry});

  final String type;

  /// Version/flags word and the 32-bit fields before the entries.
  final List<int> fields;
  final int entries;
  final int entrySize;
  final void Function(Mp4Output out, int index) writeEntry;

  @override
  int get size => 8 + fields.length * 4 + entries * entrySize;

  @override
  Future<void> write(Mp4Output out) async {
    if (out.full) await out.flush();
    out
      ..u32(size)
      ..fourCc(type);
    for (final field in fields) {
      if (out.full) await out.flush();
      out.u32(field);
    }
    for (var i = 0; i < entries; i++) {
      if (out.full) await out.flush();
      writeEntry(out, i);
    }
  }
}

/// Codec description of a track for its sample entry.
sealed class Mp4Codec {
  const new();

  /// Whether the track is video.
  bool get isVideo;

  /// Four-character type of the sample entry (`avc1`, `hvc1`, `mp4a`…).
  String get entryType;
}

/// H.264 or H.265 video.
final class Mp4VideoCodec extends Mp4Codec {
  /// Creates the description.
  const new(this.config);

  /// Decoder configuration (record, size, aspect ratio).
  final VideoConfig config;

  @override
  bool get isVideo => true;

  @override
  String get entryType => config.codec == VideoCodec.avc ? 'avc1' : 'hvc1';
}

/// AAC audio.
final class Mp4AacCodec extends Mp4Codec {
  /// Creates the description.
  const new(this.config);

  /// AudioSpecificConfig.
  final AacConfig config;

  @override
  bool get isVideo => false;

  @override
  String get entryType => 'mp4a';
}

/// A sample entry copied as it is from another MP4 (fragmented MP4
/// recordings keep their initialisation section's entry).
final class Mp4RawCodec extends Mp4Codec {
  /// Creates the description from a whole sample entry box ([entry]).
  const new(this.entry, {required this.isVideo, this.width = 0, this.height = 0});

  /// The sample entry box, header included.
  final Uint8List entry;

  @override
  final bool isVideo;

  /// Track width for `tkhd` (display size).
  final int width;

  /// Track height for `tkhd`.
  final int height;

  @override
  String get entryType => String.fromCharCodes(entry, 4, 8);
}

/// One track of the MP4: its tables, codec and placement on the movie timeline.
final class Mp4Track {
  /// Creates a track.
  const new({
    required this.table,
    required this.codec,
    required this.startMs,
    this.fallbackWidth = 0,
    this.fallbackHeight = 0,
  });

  /// Sample tables (finished).
  final TrackTable table;

  /// Codec.
  final Mp4Codec codec;

  /// Where the first sample's decode time lies on the movie timeline (ms).
  final int startMs;

  /// Width when the SPS gave none (`onMetaData`).
  final int fallbackWidth;

  /// Height when the SPS gave none (`onMetaData`).
  final int fallbackHeight;

  /// Whether this is a video track.
  bool get isVideo => codec.isVideo;

  /// Where the first sample is presented on the FLV timeline (ms).
  int get presentationStartMs => startMs + (table.firstOffset * movieTimescale / table.timescale).floor();
}

int _toMovie(int ticks, int timescale) => (ticks * movieTimescale + timescale - 1) ~/ timescale;

/// The `ftyp` + `moov` + `mdat` header of a faststart MP4 whose `mdat`
/// payload holds [payloadBytes] bytes; chunk offsets in the tracks are
/// relative to that payload. Uses `co64` and a 64-bit `mdat` size only when
/// the file needs them.
final class Mp4Header {
  /// Lays out the header for [tracks]. [creationTime] is stored in `mvhd`,
  /// `tkhd` and `mdhd` (seconds since 1904-01-01 UTC).
  factory({required List<Mp4Track> tracks, required int payloadBytes, int creationTime = 0}) {
    if (tracks.isEmpty) throw const RemuxException('no audio or video samples');
    final largeMdat = payloadBytes + 8 > 0xffffffff;
    final mdatHeader = largeMdat ? 16 : 8;
    final ftyp = _fileType(tracks);
    var header = Mp4Header._(ftyp, _Moov(tracks, creationTime, co64: false), payloadBytes, mdatHeader);
    if (header.payloadStart + payloadBytes > 0xffffffff) {
      header = Mp4Header._(ftyp, _Moov(tracks, creationTime, co64: true), payloadBytes, mdatHeader);
    }
    header._moov.base = header.payloadStart;
    return header;
  }

  new _(this._ftyp, this._moov, this.payloadBytes, this._mdatHeader);

  final _Raw _ftyp;
  final _Moov _moov;
  final int _mdatHeader;

  /// Bytes of the `mdat` payload.
  final int payloadBytes;

  /// Offset of the first `mdat` payload byte in the file.
  int get payloadStart => _ftyp.size + _moov.node.size + _mdatHeader;

  /// Size of the `moov` box.
  int get moovSize => _moov.node.size;

  /// Whether chunk offsets are 64-bit (`co64`).
  bool get co64 => _moov.co64;

  /// Movie duration in milliseconds.
  int get durationMs => _moov.durationMs;

  /// Writes `ftyp`, `moov` and the `mdat` box header.
  Future<void> write(Mp4Output out) async {
    await _ftyp.write(out);
    await _moov.node.write(out);
    if (out.full) await out.flush();
    if (_mdatHeader == 16) {
      out
        ..u32(1)
        ..fourCc('mdat')
        ..u64(payloadBytes + 16);
    } else {
      out
        ..u32(payloadBytes + 8)
        ..fourCc('mdat');
    }
  }

  static _Raw _fileType(List<Mp4Track> tracks) {
    final codecs = [
      for (final track in tracks)
        if (track.codec case Mp4VideoCodec(:final config))
          config.codec
        else if (track.codec case Mp4RawCodec(isVideo: true, :final entryType))
          if (entryType == 'avc1' || entryType == 'avc3')
            VideoCodec.avc
          else if (entryType == 'hvc1' || entryType == 'hev1')
            VideoCodec.hevc,
    ];
    final b = _Bytes();
    b.box('ftyp', () {
      b
        ..fourCc('isom')
        ..u32(0x200)
        ..fourCc('isom')
        ..fourCc('iso2');
      if (codecs.contains(VideoCodec.avc)) b.fourCc('avc1');
      if (codecs.contains(VideoCodec.hevc)) b.fourCc('hvc1');
      b.fourCc('mp41');
    });
    return _Raw(b.take());
  }
}

final class _Moov {
  new(this.tracks, this.creationTime, {required this.co64}) {
    node = _build();
  }

  final List<Mp4Track> tracks;
  final int creationTime;
  final bool co64;
  late final _Node node;
  int durationMs = 0;

  /// File offset of the `mdat` payload, set once the layout is known.
  int base = 0;

  _Node _build() {
    final traks = <_Node>[];
    final durations = <int>[];
    for (var i = 0; i < tracks.length; i++) {
      final (trak, duration) = _trak(tracks[i], i + 1);
      traks.add(trak);
      durations.add(duration);
    }
    durationMs = durations.fold(0, (a, b) => a > b ? a : b);
    final mvhd = _Bytes();
    final v1 = durationMs > 0xffffffff;
    mvhd.fullBox('mvhd', v1 ? 1 : 0, 0, () {
      _times(mvhd, v1);
      mvhd.u32(movieTimescale);
      v1 ? mvhd.u64(durationMs) : mvhd.u32(durationMs);
      mvhd
        ..u32(0x00010000)
        ..u16(0x0100)
        ..zeros(10);
      _matrix(mvhd);
      mvhd
        ..zeros(24)
        ..u32(tracks.length + 1);
    });
    return _Container('moov', [_Raw(mvhd.take()), ...traks]);
  }

  void _times(_Bytes b, bool v1) {
    if (v1) {
      b
        ..u64(creationTime)
        ..u64(creationTime);
    } else {
      b
        ..u32(creationTime)
        ..u32(creationTime);
    }
  }

  static void _matrix(_Bytes b) {
    const [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000].forEach(b.u32);
  }

  (_Node, int) _trak(Mp4Track track, int id) {
    final table = track.table;
    final timescale = table.timescale;
    // The earliest presented sample of any track starts the movie (as ffmpeg's `-c copy` does).
    final globalStart = tracks.fold(track.presentationStartMs, (min, t) {
      final start = t.presentationStartMs;
      return start < min ? start : min;
    });
    final mediaTime = table.firstOffset > 0 ? table.firstOffset : 0;
    final delay = track.startMs - globalStart + (mediaTime * movieTimescale) ~/ timescale;
    final segment = _toMovie(table.presentationEnd - mediaTime, timescale);
    final edit = delay > 0 || mediaTime > 0;
    final duration = (delay > 0 ? delay : 0) + segment;

    var width = 0;
    var height = 0;
    if (track.codec case Mp4VideoCodec(:final config)) {
      width = config.width > 0 ? config.width : track.fallbackWidth;
      height = config.height > 0 ? config.height : track.fallbackHeight;
      if (config.sarWidth != config.sarHeight) width = (width * config.sarWidth / config.sarHeight).round();
    } else if (track.codec case Mp4RawCodec(isVideo: true, width: final w, height: final h)) {
      width = w;
      height = h;
    }

    final head = _Bytes();
    final v1 = duration > 0xffffffff;
    head.fullBox('tkhd', v1 ? 1 : 0, 3, () {
      _times(head, v1);
      head
        ..u32(id)
        ..u32(0);
      v1 ? head.u64(duration) : head.u32(duration);
      head
        ..zeros(8)
        ..u16(0)
        ..u16(0)
        ..u16(track.isVideo ? 0 : 0x0100)
        ..u16(0);
      _matrix(head);
      head
        ..u32(width << 16)
        ..u32(height << 16);
    });
    if (edit) {
      final elstV1 = segment > 0xffffffff || delay > 0xffffffff || mediaTime > 0x7fffffff;
      head.box('edts', () {
        head.fullBox('elst', elstV1 ? 1 : 0, 0, () {
          head.u32(delay > 0 ? 2 : 1);
          void entry(int duration, int time) {
            if (elstV1) {
              head
                ..u64(duration)
                ..u64(time);
            } else {
              head
                ..u32(duration)
                ..u32(time);
            }
            head.u32(0x00010000);
          }

          if (delay > 0) entry(delay, -1);
          entry(segment, mediaTime);
        });
      });
    }

    final mdia = _Bytes();
    final mdhdV1 = table.duration > 0xffffffff;
    mdia.fullBox('mdhd', mdhdV1 ? 1 : 0, 0, () {
      _times(mdia, mdhdV1);
      mdia.u32(timescale);
      mdhdV1 ? mdia.u64(table.duration) : mdia.u32(table.duration);
      mdia
        ..u16(0x55c4) // 'und'
        ..u16(0);
    });
    mdia.fullBox('hdlr', 0, 0, () {
      mdia
        ..u32(0)
        ..fourCc(track.isVideo ? 'vide' : 'soun')
        ..zeros(12)
        ..bytes((track.isVideo ? 'VideoHandler' : 'SoundHandler').codeUnits)
        ..u8(0);
    });

    final minfHead = _Bytes();
    if (track.isVideo) {
      minfHead.fullBox('vmhd', 0, 1, () => minfHead.zeros(8));
    } else {
      minfHead.fullBox('smhd', 0, 0, () => minfHead.zeros(4));
    }
    minfHead.box('dinf', () {
      minfHead.fullBox('dref', 0, 0, () {
        minfHead
          ..u32(1)
          ..fullBox('url ', 0, 1, () {});
      });
    });

    final stbl = _Container('stbl', [_Raw(_stsd(track, width, height)), ..._tables(track)]);
    final minf = _Container('minf', [_Raw(minfHead.take()), stbl]);
    final mdiaNode = _Container('mdia', [_Raw(mdia.take()), minf]);
    return (_Container('trak', [_Raw(head.take()), mdiaNode]), duration);
  }

  Uint8List _stsd(Mp4Track track, int displayWidth, int displayHeight) {
    final b = _Bytes();
    b.fullBox('stsd', 0, 0, () {
      b.u32(1);
      switch (track.codec) {
        case Mp4VideoCodec(:final config):
          final width = config.width > 0 ? config.width : track.fallbackWidth;
          final height = config.height > 0 ? config.height : track.fallbackHeight;
          b.box(config.codec == VideoCodec.avc ? 'avc1' : 'hvc1', () {
            b
              ..zeros(6)
              ..u16(1)
              ..zeros(16)
              ..u16(width)
              ..u16(height)
              ..u32(0x00480000)
              ..u32(0x00480000)
              ..u32(0)
              ..u16(1)
              ..zeros(32)
              ..u16(0x0018)
              ..u16(0xffff)
              ..box(config.codec == VideoCodec.avc ? 'avcC' : 'hvcC', () => b.bytes(config.record));
            if (config.sarWidth != config.sarHeight) {
              b.box('pasp', () {
                b
                  ..u32(config.sarWidth)
                  ..u32(config.sarHeight);
              });
            }
          });
        case Mp4RawCodec(:final entry):
          b.bytes(entry);
        case Mp4AacCodec(:final config):
          final table = track.table;
          final seconds = table.duration / table.timescale;
          final average = seconds > 0 ? (table.totalBytes * 8 / seconds).round() : 0;
          final peak = table.maxBytesPerSecond * 8;
          b.box('mp4a', () {
            b
              ..zeros(6)
              ..u16(1)
              ..zeros(8)
              ..u16(config.channelCount)
              ..u16(16)
              ..u16(0)
              ..u16(0)
              ..u32(config.sampleRate < 0x10000 ? config.sampleRate << 16 : 0)
              ..fullBox('esds', 0, 0, () {
                b.descriptor(0x03, () {
                  b
                    ..u16(0)
                    ..u8(0)
                    ..descriptor(0x04, () {
                      b
                        ..u8(0x40) // MPEG-4 Audio
                        ..u8(0x15) // audio stream
                        ..u8((table.maxSampleSize >> 16) & 0xff)
                        ..u16(table.maxSampleSize & 0xffff)
                        ..u32(peak > average ? peak : average)
                        ..u32(average)
                        ..descriptor(0x05, () => b.bytes(config.asc));
                    })
                    ..descriptor(0x06, () => b.u8(0x02));
                });
              });
          });
      }
    });
    return b.take();
  }

  List<_Node> _tables(Mp4Track track) {
    final table = track.table;
    final nodes = <_Node>[
      _Table(
        'stts',
        fields: [0, table.stts.length],
        entries: table.stts.length,
        entrySize: 8,
        writeEntry: (out, i) => out
          ..u32(table.stts.counts[i])
          ..u32(table.stts.values[i]),
      ),
    ];
    if (table.hasCompositionOffsets) {
      nodes.add(
        _Table(
          'ctts',
          fields: [if (table.hasNegativeOffsets) 1 << 24 else 0, table.ctts.length],
          entries: table.ctts.length,
          entrySize: 8,
          writeEntry: (out, i) => out
            ..u32(table.ctts.counts[i])
            ..u32(table.ctts.values[i]),
        ),
      );
    }
    if (track.isVideo && table.syncSamples.length < table.sampleCount) {
      nodes.add(
        _Table(
          'stss',
          fields: [0, table.syncSamples.length],
          entries: table.syncSamples.length,
          entrySize: 4,
          writeEntry: (out, i) => out.u32(table.syncSamples[i]),
        ),
      );
    }
    nodes
      ..add(
        _Table(
          'stsz',
          fields: [0, 0, table.sampleCount],
          entries: table.sampleCount,
          entrySize: 4,
          writeEntry: (out, i) => out.u32(table.sizes[i]),
        ),
      )
      ..add(
        _Table(
          'stsc',
          fields: [0, table.chunkRunFirst.length],
          entries: table.chunkRunFirst.length,
          entrySize: 12,
          writeEntry: (out, i) => out
            ..u32(table.chunkRunFirst[i])
            ..u32(table.chunkRunSamples[i])
            ..u32(1),
        ),
      )
      ..add(
        co64
            ? _Table(
                'co64',
                fields: [0, table.chunkOffsets.length],
                entries: table.chunkOffsets.length,
                entrySize: 8,
                writeEntry: (out, i) => out.u64(base + table.chunkOffsets[i]),
              )
            : _Table(
                'stco',
                fields: [0, table.chunkOffsets.length],
                entries: table.chunkOffsets.length,
                entrySize: 4,
                writeEntry: (out, i) => out.u32(base + table.chunkOffsets[i]),
              ),
      );
    return nodes;
  }
}
