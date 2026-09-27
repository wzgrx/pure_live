import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/live_record.dart';

import 'ts_build.dart';

/// PIDs of the synthetic live program.
abstract final class TsLivePids {
  static const pmt = 0x1000;
  static const video = 0x100;
  static const audio = 0x101;
  static const subtitles = 0x102;
}

/// One packet of a [TsLive] stream.
final class TsLivePacket {
  new(this.us, this.pid, this.bytes, {this.videoStart = false, this.key = false});

  /// Stream time in microseconds.
  final int us;
  final int pid;
  final Uint8List bytes;

  /// Starts a video PES.
  final bool videoStart;

  /// Starts a keyframe's PES.
  final bool key;
}

/// A synthetic live MPEG-TS program as broadcast muxers (and udpxy) send it:
/// H.264 frames every [frameMs] (a keyframe with SPS/PPS every [gop]
/// frames), AAC every [audioMs] (three frames per PES, declared length),
/// PAT and PMT every [psiMs]; the packets of the streams are interleaved,
/// so PES of one stream span the start of another's and PSI sits inside
/// frames; continuity counters run across the whole stream. Timestamps are
/// [base] + stream time.
final class TsLive {
  new({
    this.durationMs = 120000,
    this.frameMs = 40,
    this.gop = 25,
    this.audioMs = 64,
    this.psiMs = 100,
    this.keySize = 2400,
    this.frameSize = 500,
    this.audioFrameSize = 200,
    this.base = 900000,
    this.videoType = 0x1B,
    this.video = true,
    this.audio = true,
    this.subtitles = false,
    this.rai = true,
    this.otherSpsFromMs,
    this.audioRateIndexFromMs,
    this.audioPidFromMs,
  }) {
    _generate();
  }

  final int durationMs;
  final int frameMs;
  final int gop;
  final int audioMs;
  final int psiMs;
  final int keySize;
  final int frameSize;
  final int audioFrameSize;
  final int base;
  final int videoType;
  final bool video;
  final bool audio;
  final bool subtitles;
  final bool rai;

  /// From this stream time on, keyframes carry another SPS.
  final int? otherSpsFromMs;

  /// From this stream time on, AAC frames announce 44.1 kHz.
  final int? audioRateIndexFromMs;

  /// From this stream time on, the audio moves to another PID (a new PMT).
  final int? audioPidFromMs;

  final List<TsLivePacket> packets = [];

  /// Video frames per keyframe interval, in ms.
  int get gopMs => gop * frameMs;

  /// Index of the first packet at or after stream time [us].
  int indexAt(int us) {
    var low = 0;
    var high = packets.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (packets[mid].us < us) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// Bytes of packets [from, to).
  Uint8List bytes(int from, int to) {
    final out = BytesBuilder(copy: false);
    for (var i = from; i < to && i < packets.length; i++) {
      out.add(packets[i].bytes);
    }
    return out.takeBytes();
  }

  /// Video frames (keyframes) whose PES starts in [fromMs, toMs).
  int framesBetween(int fromMs, int toMs, {bool keysOnly = false}) =>
      packets.where((p) => p.videoStart && p.us >= fromMs * 1000 && p.us < toMs * 1000 && (!keysOnly || p.key)).length;

  void _generate() {
    final raw = <({int us, int order, int pid, Uint8List payload, bool start, bool key, bool videoStart})>[];
    void pes(int pid, int us, int span, Uint8List pes, {bool key = false, int order = 1}) {
      final chunks = _split(pes, key: key && rai);
      for (var i = 0; i < chunks.length; i++) {
        raw.add((
          us: us + span * i ~/ chunks.length,
          order: order,
          pid: pid,
          payload: chunks[i],
          start: i == 0,
          key: key && i == 0,
          videoStart: pid == TsLivePids.video && i == 0,
        ));
      }
    }

    var serial = 0;
    if (video) {
      for (var n = 0; n * frameMs < durationMs; n++) {
        final ms = n * frameMs;
        final key = n % gop == 0;
        if (videoType == 0x02) {
          // MPEG-2: a sequence header and a GOP header in front of each I picture.
          final es = BytesBuilder();
          if (key) {
            es.add(const [0, 0, 1, 0xB3, 0x0A, 0x00, 0x60, 0x13, 0xFF, 0xFF, 0xE0, 0x18, 0, 0, 1, 0xB8, 0, 8, 0, 0]);
          }
          es
            ..add(const [0, 0, 1, 0x00])
            ..add(
              Uint8List(key ? keySize : frameSize)..fillRange(0, key ? keySize : frameSize, 0x80 + (serial++ & 0x3F)),
            );
          pes(
            TsLivePids.video,
            ms * 1000,
            frameMs * 1000,
            _pes(0xE0, base + ms * 90, es.takeBytes(), bounded: false),
            key: key,
            order: 2,
          );
          continue;
        }
        final es = BytesBuilder()..add(const [0, 0, 0, 1, 0x09, 0xF0]);
        if (key) {
          final sps = otherSpsFromMs != null && ms >= otherSpsFromMs! ? TsBuild.otherSps : TsBuild.sps;
          es
            ..add(const [0, 0, 0, 1])
            ..add(sps)
            ..add(const [0, 0, 0, 1])
            ..add(TsBuild.pps);
        }
        final size = key ? keySize : frameSize;
        final slice = Uint8List(size)
          ..[0] = key ? 0x65 : 0x41
          ..fillRange(1, size, 0x80 + (serial++ & 0x3F));
        es
          ..add(const [0, 0, 0, 1])
          ..add(slice);
        pes(
          TsLivePids.video,
          ms * 1000,
          frameMs * 1000,
          _pes(0xE0, base + ms * 90, es.takeBytes(), bounded: false),
          key: key,
          order: 2,
        );
      }
    }
    if (audio) {
      for (var n = 0; n * audioMs < durationMs; n++) {
        final ms = n * audioMs;
        final rate = audioRateIndexFromMs != null && ms >= audioRateIndexFromMs! ? 4 : 3;
        final es = BytesBuilder();
        for (var i = 0; i < 3; i++) {
          es.add(_adts(audioFrameSize, rate, 0x20 + (serial++ & 0x3F)));
        }
        final pid = audioPidFromMs != null && ms >= audioPidFromMs! ? TsLivePids.audio + 0x10 : TsLivePids.audio;
        pes(pid, ms * 1000, audioMs * 1000, _pes(0xC0, base + ms * 90, es.takeBytes(), bounded: true), order: 3);
      }
    }
    if (subtitles) {
      for (var n = 0; n * 500 < durationMs; n++) {
        pes(
          TsLivePids.subtitles,
          n * 500000 + 7,
          1000,
          _pes(0xBD, base + n * 500 * 90, Uint8List(300), bounded: true),
          order: 4,
        );
      }
    }
    for (var n = 0; n * psiMs < durationMs; n++) {
      final ms = n * psiMs;
      final audioPid = audioPidFromMs != null && ms >= audioPidFromMs! ? TsLivePids.audio + 0x10 : TsLivePids.audio;
      raw
        ..add((us: ms * 1000, order: -1, pid: 0, payload: _psi(_pat()), start: true, key: false, videoStart: false))
        ..add((
          us: ms * 1000,
          order: 0,
          pid: TsLivePids.pmt,
          payload: _psi(_pmt(audioPid)),
          start: true,
          key: false,
          videoStart: false,
        ));
    }
    raw.sort((a, b) => a.us != b.us ? a.us.compareTo(b.us) : a.order.compareTo(b.order));
    final counters = <int, int>{};
    for (final entry in raw) {
      final counter = counters[entry.pid] ?? 0;
      counters[entry.pid] = (counter + 1) & 0x0F;
      final packet = Uint8List.fromList(entry.payload)
        ..[1] = (entry.start ? 0x40 : 0) | (entry.pid >> 8)
        ..[2] = entry.pid & 0xFF
        ..[3] = (entry.payload[3] & 0xF0) | counter;
      packets.add(TsLivePacket(entry.us, entry.pid, packet, videoStart: entry.videoStart, key: entry.key));
    }
  }

  /// [pes] as 188-byte packets without PID and counter (set later); the
  /// last one padded with adaptation stuffing; a keyframe's first packet
  /// carries `random_access_indicator`.
  static List<Uint8List> _split(Uint8List pes, {required bool key}) {
    final out = <Uint8List>[];
    var at = 0;
    var first = true;
    while (at < pes.length) {
      final packet = Uint8List(188)..[0] = 0x47;
      final header = first && key ? 2 : 0;
      final room = 184 - header;
      final left = pes.length - at;
      if (left >= room && header == 0) {
        packet[3] = 0x10;
        packet.setRange(4, 188, pes, at);
        at += 184;
      } else {
        final take = left < room ? left : room;
        final stuffing = 184 - take;
        packet
          ..[3] = 0x30
          ..[4] = stuffing - 1;
        if (stuffing > 1) {
          packet[5] = first && key ? 0x40 : 0;
          packet.fillRange(6, 4 + stuffing, 0xFF);
        }
        packet.setRange(4 + stuffing, 188, pes, at);
        at += take;
      }
      first = false;
      out.add(packet);
    }
    return out;
  }

  static Uint8List _pes(int streamId, int pts, Uint8List es, {required bool bounded}) {
    final header = [0x80, 0x80, 5, ..._timestamp(2, pts)];
    final length = bounded ? header.length + es.length : 0;
    return Uint8List.fromList([0, 0, 1, streamId, length >> 8, length & 0xFF, ...header, ...es]);
  }

  static List<int> _timestamp(int prefix, int value) {
    final v = value % (1 << 33);
    return [
      (prefix << 4) | (((v >> 30) & 0x07) << 1) | 1,
      (v >> 22) & 0xFF,
      (((v >> 15) & 0x7F) << 1) | 1,
      (v >> 7) & 0xFF,
      ((v & 0x7F) << 1) | 1,
    ];
  }

  /// One ADTS frame: AAC-LC mono at sampling index [rate] (3: 48 kHz, 4: 44.1 kHz).
  static Uint8List _adts(int length, int rate, int fill) => Uint8List(length)
    ..fillRange(7, length, fill)
    ..[0] = 0xFF
    ..[1] = 0xF1
    ..[2] = (1 << 6) | (rate << 2)
    ..[3] = (1 << 6) | ((length >> 11) & 0x03)
    ..[4] = (length >> 3) & 0xFF
    ..[5] = ((length & 0x07) << 5) | 0x1F
    ..[6] = 0xFC;

  static Uint8List _psi(List<int> section) {
    final packet = Uint8List(188)
      ..[0] = 0x47
      ..[3] = 0x10
      ..[4] = 0
      ..setRange(5, 5 + section.length, section)
      ..fillRange(5 + section.length, 188, 0xFF);
    return packet;
  }

  List<int> _pat() => _section([0x00, 0xB0, 13, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, 0xE0 | 0x10, 0x00]);

  List<int> _pmt(int audioPid) {
    final streams = [
      if (video) ...[videoType, 0xE0 | (TsLivePids.video >> 8), TsLivePids.video & 0xFF, 0xF0, 0x00],
      if (audio) ...[0x0F, 0xE0 | (audioPid >> 8), audioPid & 0xFF, 0xF0, 0x00],
      if (subtitles) ...[0x06, 0xE0 | (TsLivePids.subtitles >> 8), TsLivePids.subtitles & 0xFF, 0xF0, 0x00],
    ];
    final pcr = video ? TsLivePids.video : audioPid;
    return _section([
      0x02,
      0xB0,
      13 + streams.length,
      0x00,
      0x01,
      0xC1,
      0x00,
      0x00,
      0xE0 | (pcr >> 8),
      pcr & 0xFF,
      0xF0,
      0x00,
      ...streams,
    ]);
  }

  static List<int> _section(List<int> body) {
    var crc = 0xFFFFFFFF;
    for (final byte in body) {
      crc ^= byte << 24;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x80000000) != 0 ? ((crc << 1) ^ 0x04C11DB7) : crc << 1;
        crc &= 0xFFFFFFFF;
      }
    }
    return [...body, crc >> 24, (crc >> 16) & 0xFF, (crc >> 8) & 0xFF, crc & 0xFF];
  }
}

/// A [ByteSource] from a list of chunks (sniff and unit tests).
final class ListByteSource implements ByteSource {
  new(List<Uint8List> chunks, {this.error}) : _chunks = [...chunks];

  final List<Uint8List> _chunks;

  /// Thrown after the chunks, instead of a clean end.
  final Object? error;
  bool cancelled = false;

  @override
  Future<Uint8List?> next() async {
    if (cancelled) return null;
    if (_chunks.isNotEmpty) return _chunks.removeAt(0);
    final error = this.error;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    return null;
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

/// A fake udpxy for one live program over fake time: a connection joins the
/// stream at the current stream time (any packet boundary) and gets its
/// packets in real time, [chunkPackets] at a time.
final class FakeTsCdn {
  new({TsLive? live, this.startMs = 10000, this.chunkPackets = 7, DateTime? epoch})
    : live = live ?? TsLive(),
      epoch = epoch ?? clock.now();

  /// The program; [restart] replaces it.
  TsLive live;

  /// Stream time at [epoch].
  int startMs;

  /// When the stream time was [startMs].
  DateTime epoch;

  final int chunkPackets;

  /// Delivers the bytes in pieces of this size instead (0: whole packets).
  int chunkBytes = 0;
  final List<FakeTsSource> connections = [];
  final List<Uri> opened = [];

  /// Status to answer for the connection attempt with this index.
  final Map<int, int> statusFor = {};

  /// Answer every new attempt with this status while set.
  int? statusAll;

  /// The network is down: connecting fails.
  bool down = false;

  /// Bytes every new connection sends before the stream (misaligned start).
  List<int> prefix = const [];

  /// Serves these bytes instead of the stream (an HTML page, an FLV file…).
  Uint8List? body;

  /// Packet indices every connection skips (lost upstream).
  final Set<int> lost = {};

  /// Bytes sent before the packet with this index (lost sync).
  final Map<int, List<int>> garbage = {};

  /// Current stream time in microseconds.
  int get nowUs => (startMs + clock.now().difference(epoch).inMilliseconds) * 1000;

  /// The source restarts: a new program from stream time 0 (timestamps from
  /// its own base, counters from 0); connections cut.
  void restart(TsLive next) {
    cutAll();
    live = next;
    startMs = 0;
    epoch = clock.now();
  }

  Future<ByteSource> open(StreamLine line) async {
    final index = opened.length;
    opened.add(line.url);
    if (down) throw const SocketException('Network is unreachable');
    final status = statusFor[index] ?? statusAll;
    if (status != null) throw UpstreamStatusException(status, line.url);
    final source = FakeTsSource._(this, live, live.indexAt(nowUs));
    connections.add(source);
    return source;
  }

  /// Ends every open connection now.
  void cutAll() {
    for (final connection in connections) {
      connection.cut = true;
    }
  }
}

/// One fake connection of a [FakeTsCdn].
final class FakeTsSource implements ByteSource {
  new _(this._cdn, this._live, int index)
    : _index = index,
      joined = index,
      _prefix = _cdn.prefix.isEmpty ? null : Uint8List.fromList(_cdn.prefix);

  final FakeTsCdn _cdn;
  final TsLive _live;
  int _index;
  Uint8List? _prefix;
  var _bodySent = false;
  var _carry = Uint8List(0);
  bool cancelled = false;
  bool cut = false;

  /// Index of the first packet this connection got.
  final int joined;

  /// Packet index it reached.
  int get position => _index;

  @override
  Future<Uint8List?> next() async {
    final size = _cdn.chunkBytes;
    if (size <= 0) return await _next();
    while (_carry.length < size) {
      final more = await _next();
      if (more == null) {
        if (_carry.isEmpty) return null;
        break;
      }
      _carry = Uint8List.fromList([..._carry, ...more]);
    }
    final take = _carry.length < size ? _carry.length : size;
    final out = Uint8List.sublistView(_carry, 0, take);
    _carry = Uint8List.sublistView(_carry, take);
    return out;
  }

  Future<Uint8List?> _next() async {
    final body = _cdn.body;
    if (body != null) {
      if (_bodySent || cancelled) return null;
      _bodySent = true;
      return body;
    }
    final prefix = _prefix;
    if (prefix != null) {
      _prefix = null;
      return prefix;
    }
    while (true) {
      if (cancelled || cut) return null;
      final packets = _live.packets;
      if (_index >= packets.length) return null;
      final now = _cdn.nowUs;
      if (packets[_index].us > now) {
        final wait = (packets[_index].us - now) ~/ 1000;
        await Future<void>.delayed(Duration(milliseconds: wait < 10 ? 10 : wait));
        continue;
      }
      final out = BytesBuilder(copy: false);
      var count = 0;
      while (_index < packets.length && packets[_index].us <= now && count < _cdn.chunkPackets) {
        final garbage = _cdn.garbage[_index];
        if (garbage != null) out.add(garbage);
        if (!_cdn.lost.contains(_index)) out.add(packets[_index].bytes);
        _index++;
        count++;
      }
      if (out.isEmpty) continue;
      return out.takeBytes();
    }
  }

  @override
  Future<void> cancel() async => cancelled = true;
}
