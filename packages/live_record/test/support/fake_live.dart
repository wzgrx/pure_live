import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/testing.dart';

/// Builders for a synthetic live FLV: AVC video every [frameMs] with a
/// keyframe every [gopMs], AAC audio every [audioMs].
final class SyntheticFlv {
  const new({this.gopMs = 1000, this.frameMs = 40, this.audioMs = 23, this.videoConfigPayload = const [1, 2, 3]});

  final int gopMs;
  final int frameMs;
  final int audioMs;
  final List<int> videoConfigPayload;

  static Uint8List script(int ts) =>
      FlvTag.build(type: FlvTag.script, timestamp: ts, data: [2, 0, 10, ...'onMetaData'.codeUnits]);

  /// AVC decoder configuration (4-byte NALU lengths).
  Uint8List videoConfig(int ts) => FlvTag.build(
    type: FlvTag.video,
    timestamp: ts,
    data: [0x17, 0, 0, 0, 0, 1, 0x64, 0, 0x1f, 0xff, ...videoConfigPayload],
  );

  static Uint8List audioConfig(int ts) => FlvTag.build(type: FlvTag.audio, timestamp: ts, data: [0xAF, 0, 0x12, 0x10]);

  /// An AVC frame with one slice NAL (IDR for keyframes).
  static Uint8List video(int ts, {required bool key}) => FlvTag.build(
    type: FlvTag.video,
    timestamp: ts,
    data: [if (key) 0x17 else 0x27, 1, 0, 0, 0, 0, 0, 0, 3, if (key) 0x65 else 0x41, 0xAA, ts & 0xff],
  );

  /// An AVC tag holding only an SEI NAL.
  static Uint8List sei(int ts) =>
      FlvTag.build(type: FlvTag.video, timestamp: ts, data: [0x27, 1, 0, 0, 0, 0, 0, 0, 3, 0x06, 0x05, 0x01]);

  static Uint8List audio(int ts) => FlvTag.build(type: FlvTag.audio, timestamp: ts, data: [0xAF, 1, 0x21, ts & 0xff]);

  /// Media tags with timestamps in [from, to), ordered by timestamp (video first on ties).
  List<Uint8List> tags(int from, int to) {
    final out = <({int ts, int order, Uint8List tag})>[];
    for (var ts = (from + frameMs - 1) ~/ frameMs * frameMs; ts < to; ts += frameMs) {
      out.add((ts: ts, order: 0, tag: video(ts, key: ts % gopMs == 0)));
    }
    for (var ts = (from + audioMs - 1) ~/ audioMs * audioMs; ts < to; ts += audioMs) {
      out.add((ts: ts, order: 1, tag: audio(ts)));
    }
    out.sort((a, b) => a.ts != b.ts ? a.ts.compareTo(b.ts) : a.order.compareTo(b.order));
    return [for (final entry in out) entry.tag];
  }

  /// A whole connection's packets: header, script, configurations, then [from, to).
  List<Uint8List> connection(int from, int to) => [
    FlvTag.fileHeader(),
    script(0),
    videoConfig(from),
    audioConfig(from),
    ...tags(from, to),
  ];
}

/// A fake CDN for one live stream whose stream time is [base] plus the time
/// since [epoch]. Each connection starts with the header, script and codec
/// configurations, bursts the GOP cache, then delivers tags in real time
/// until [cutAfter] from the connect (Douyu `expire`) or until [cutAll].
final class FakeCdn {
  new({this.flv = const SyntheticFlv(), this.base = 100000, this.cutAfter, DateTime? epoch})
    : epoch = epoch ?? clock.now();

  SyntheticFlv flv;
  final int base;
  final Duration? cutAfter;
  final DateTime epoch;
  final List<FakeFlvSource> connections = [];
  final List<Uri> opened = [];

  /// Status to answer for the connection attempt with this index.
  final Map<int, int> statusFor = {};

  /// Answer every new attempt with this status while set.
  int? statusAll;

  /// Every new connection gets its timestamps shifted by this.
  int shiftNew = 0;

  /// The stream is over: open connections end, new ones deliver only a header.
  bool ended = false;

  /// The network is down: connecting fails.
  bool down = false;

  int get streamNow => base + clock.now().difference(epoch).inMilliseconds;

  Future<FlvPacketSource> open(StreamLine line) async {
    final index = opened.length;
    opened.add(line.url);
    if (down) throw const SocketException('Network is unreachable');
    final status = statusFor[index] ?? statusAll;
    if (status != null) throw UpstreamStatusException(status, line.url);
    final source = FakeFlvSource._(this, flv, shiftNew, streamNow);
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

/// One fake upstream connection.
final class FakeFlvSource implements FlvPacketSource {
  new _(this._cdn, this._flv, this._shift, int joinedAt)
    : _cutAt = _cdn.cutAfter == null ? null : joinedAt + _cdn.cutAfter!.inMilliseconds {
    final gop = _flv.gopMs;
    final lastKey = joinedAt ~/ gop * gop;
    _queue.add(FlvTag.fileHeader());
    if (!_cdn.ended) {
      _queue
        ..add(SyntheticFlv.script(0))
        ..add(_flv.videoConfig(lastKey))
        ..add(SyntheticFlv.audioConfig(lastKey))
        ..addAll(_flv.tags(lastKey, joinedAt));
    }
    _nextTs = joinedAt;
  }

  static const _chunkMs = 100;

  final FakeCdn _cdn;
  final SyntheticFlv _flv;
  final int _shift;
  final int? _cutAt;
  final _queue = ListQueue<Uint8List>();
  var _nextTs = 0;
  bool cancelled = false;
  bool cut = false;

  @override
  Future<Uint8List?> next() async {
    while (_queue.isEmpty) {
      if (cancelled || cut || _cdn.ended) return null;
      final cutAt = _cutAt;
      if (cutAt != null && _nextTs >= cutAt) return null;
      final now = _cdn.streamNow;
      if (now <= _nextTs) {
        await Future<void>.delayed(Duration(milliseconds: _nextTs - now + _chunkMs));
        continue;
      }
      final until = cutAt == null || now < cutAt ? now : cutAt;
      _queue.addAll(_flv.tags(_nextTs, until));
      _nextTs = until;
    }
    if (cancelled) return null;
    final tag = _queue.removeFirst();
    if (_shift == 0 || tag.length < 11 || tag[0] == 0x46) return tag;
    return FlvTag.withTimestamp(tag, FlvTag.timestamp(tag) + _shift);
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

const quality = Quality(id: '4', label: '原画', rank: 4);
const lowQuality = Quality(id: '2', label: '超清', rank: 2);

RoomDetail roomDetail({String roomId = '9999', LiveState state = LiveState.live, String anchor = '主播'}) => RoomDetail(
  card: RoomCard(ref: RoomRef('douyu', roomId), title: '标题', anchorName: anchor, state: state),
  link: Uri.parse('https://www.douyu.com/$roomId'),
);

/// A fake platform: a room that is live or not, and lines per resolve.
final class FakeRooms implements RecordRooms {
  new({this.lines = const ['hw', 'ws'], this.cutsConnection = false, this.leaseSeconds});

  bool live = true;

  /// The network is down: every request fails.
  bool down = false;
  List<String> lines;
  final bool cutsConnection;

  /// Lease length of every URL (Douyu 300); null for no lease.
  int? leaseSeconds;

  /// Errors for the next detail calls (consumed in order), and one for every call while set.
  final List<Exception> detailErrors = [];
  Exception? detailErrorAll;
  final List<Exception> streamErrors = [];

  /// Formats per line id (FLV by default).
  final Map<String, StreamFormat> formats = {};

  /// While set, detail calls wait for it.
  Future<void>? detailGate;

  int detailCalls = 0;
  int streamCalls = 0;
  final List<DateTime> detailTimes = [];
  var _serial = 0;

  @override
  Future<RoomDetail> detail(RoomRef room) async {
    detailCalls++;
    detailTimes.add(clock.now());
    final gate = detailGate;
    if (gate != null) await gate;
    if (down) throw const NetworkFailure('douyu', 'down');
    if (detailErrors.isNotEmpty) throw detailErrors.removeAt(0);
    final error = detailErrorAll;
    if (error != null) throw error;
    return roomDetail(roomId: room.roomId, state: live ? LiveState.live : LiveState.offline);
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    streamCalls++;
    if (down) throw const NetworkFailure('douyu', 'down');
    if (streamErrors.isNotEmpty) throw streamErrors.removeAt(0);
    final requested = quality ?? _quality;
    final issued = clock.now();
    final serial = ++_serial;
    final seconds = leaseSeconds;
    return StreamSet(
      qualities: const [_quality, lowQuality],
      selected: requested,
      lines: [
        for (final id in lines)
          StreamLine(
            url: formats[id] == StreamFormat.hls
                ? Uri.parse('https://$id.cdn.test/live/index.m3u8?serial=$serial&token=secret')
                : Uri.parse('https://$id.cdn.test/live/${requested.id}.flv?serial=$serial&token=secret'),
            format: formats[id] ?? StreamFormat.flv,
            lineId: id,
            requested: requested,
            headers: const {'cookie': 'secret-cookie', 'referer': 'https://www.douyu.com/'},
            lease: seconds == null
                ? null
                : Lease(
                    refreshAt: issued.add(Duration(seconds: seconds - (seconds ~/ 4 < 45 ? seconds ~/ 4 : 45))),
                    expiresAt: issued.add(Duration(seconds: seconds)),
                    cutsConnection: cutsConnection,
                  ),
          ),
      ],
    );
  }
}

const Quality _quality = quality;

/// Parsed FLV file: timestamps per stream and structure checks.
final class FlvFile {
  factory(Uint8List bytes) {
    final framer = FlvFramer();
    final packets = framer.add(bytes);
    final file = FlvFile._()
      ..header = packets.first
      ..trailing = framer.pending;
    for (final packet in packets.skip(1)) {
      file.tags.add(packet);
      final type = FlvTag.type(packet);
      final ts = FlvTag.timestamp(packet);
      if (type == FlvTag.script) {
        file.scripts++;
      } else if (FlvTag.isVideoConfig(packet)) {
        file.videoConfigs.add(packet);
      } else if (FlvTag.isAudioConfig(packet)) {
        file.audioConfigs++;
      } else if (type == FlvTag.video) {
        file.video.add(ts);
        if (FlvTag.isKeyframe(packet)) file.keyframes.add(ts);
      } else if (type == FlvTag.audio) {
        file.audio.add(ts);
      }
    }
    return file;
  }

  new _();

  late Uint8List header;
  int trailing = 0;
  final List<Uint8List> tags = [];
  final List<int> video = [];
  final List<int> audio = [];
  final List<int> keyframes = [];
  final List<Uint8List> videoConfigs = [];
  int audioConfigs = 0;
  int scripts = 0;

  /// Type of the first tags in order (for structure checks).
  List<String> get head => [
    for (final tag in tags.take(5))
      switch (FlvTag.type(tag)) {
        FlvTag.script => 'script',
        FlvTag.video when FlvTag.isVideoConfig(tag) => 'vconf',
        FlvTag.audio when FlvTag.isAudioConfig(tag) => 'aconf',
        FlvTag.video when FlvTag.isKeyframe(tag) => 'key',
        FlvTag.video => 'video',
        _ => 'audio',
      },
  ];

  static int maxStep(List<int> values) {
    var step = 0;
    for (var i = 1; i < values.length; i++) {
      if (values[i] - values[i - 1] > step) step = values[i] - values[i - 1];
    }
    return step;
  }

  static bool monotonic(List<int> values, {bool strict = false}) {
    for (var i = 1; i < values.length; i++) {
      if (strict ? values[i] <= values[i - 1] : values[i] < values[i - 1]) return false;
    }
    return true;
  }
}

/// A remuxer that copies the input into the output, reporting progress in
/// two steps; [fail] makes it throw like a demux error.
final class FakeRemuxer implements Remuxer {
  new(this.files);

  final MemoryRecordFiles files;
  bool fail = false;
  final List<String> inputs = [];

  @override
  Future<void> remux(RemuxJob job) async {
    inputs.add(job.input);
    final bytes = await files.read(job.input);
    job.onProgress(bytes.length ~/ 2);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (fail) throw const RemuxException('Invalid data found when processing input');
    files.put(job.output, bytes);
    job.onProgress(bytes.length);
  }
}
