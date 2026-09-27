import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';

/// Builders for a synthetic live FLV: AVC video at 25 fps with a keyframe
/// every [gopMs], AAC audio every [audioMs].
final class SyntheticFlv {
  const new({this.gopMs = 1000, this.frameMs = 40, this.audioMs = 23, this.videoConfigPayload = const [1, 2, 3]});

  final int gopMs;
  final int frameMs;
  final int audioMs;
  final List<int> videoConfigPayload;

  static Uint8List script(int ts) =>
      FlvTag.build(type: FlvTag.script, timestamp: ts, data: [2, 0, 10, ...'onMetaData'.codeUnits]);

  Uint8List videoConfig(int ts) =>
      FlvTag.build(type: FlvTag.video, timestamp: ts, data: [0x17, 0, 0, 0, 0, ...videoConfigPayload]);

  static Uint8List audioConfig(int ts) => FlvTag.build(type: FlvTag.audio, timestamp: ts, data: [0xAF, 0, 0x12, 0x10]);

  static Uint8List video(int ts, {required bool key}) =>
      FlvTag.build(type: FlvTag.video, timestamp: ts, data: [if (key) 0x17 else 0x27, 1, 0, 0, 0, 0xAA, ts & 0xff]);

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
}

/// A fake CDN for one live stream whose stream time is [base] plus the time
/// since [epoch]. Each connection starts with the header, script and codec
/// configurations, bursts the GOP cache (from the last keyframe up to now),
/// then delivers tags in real time until [cutAfter] from the connect.
final class FakeCdn {
  new({required this.flv, this.base = 100000, this.cutAfter, this.timelineShift = 0, DateTime? epoch})
    : epoch = epoch ?? clock.now();

  /// Stream served to new connections (swap it to change codec configurations).
  SyntheticFlv flv;
  final int base;

  /// Connections end this long after they start (Douyu `expire`).
  final Duration? cutAfter;

  /// Added to every timestamp of connections opened after [shiftFrom].
  int timelineShift;

  /// Connections opened at or after this count get [timelineShift].
  int shiftFrom = 1 << 30;

  /// Connections after the first run this far behind the live edge.
  int lagMs = 0;
  final DateTime epoch;
  final List<FakeFlvSource> connections = [];

  /// Connection attempts that fail.
  final Set<int> failing = {};

  int get streamNow => base + clock.now().difference(epoch).inMilliseconds;

  Future<FlvPacketSource> open(StreamLine line) async {
    final index = connections.length;
    if (failing.contains(index)) {
      connections.add(FakeFlvSource._failed());
      throw UpstreamStatusException(403, line.url);
    }
    final source = FakeFlvSource._(
      this,
      flv,
      index >= shiftFrom ? timelineShift : 0,
      streamNow - (index > 0 ? lagMs : 0),
      lag: index > 0 ? lagMs : 0,
    );
    connections.add(source);
    return source;
  }
}

/// One fake upstream connection.
final class FakeFlvSource implements FlvPacketSource {
  new _(FakeCdn cdn, this._flv, this._shift, int joinedAt, {this._lag = 0})
    : _cdn = cdn,
      _cutAt = cdn.cutAfter == null ? null : joinedAt + cdn.cutAfter!.inMilliseconds {
    final gop = _flv.gopMs;
    final lastKey = joinedAt ~/ gop * gop;
    _queue
      ..add(FlvTag.fileHeader())
      ..add(SyntheticFlv.script(0))
      ..add(_flv.videoConfig(lastKey))
      ..add(SyntheticFlv.audioConfig(lastKey))
      ..addAll(_flv.tags(lastKey, joinedAt));
    _nextTs = joinedAt;
  }

  new _failed() : _cdn = null, _flv = const SyntheticFlv(), _shift = 0, _cutAt = 0, _lag = 0;

  /// Delivery granularity once caught up with the live edge.
  static const _chunkMs = 100;

  final FakeCdn? _cdn;
  final SyntheticFlv _flv;
  final int _shift;
  final int _lag;
  final int? _cutAt;
  final _queue = ListQueue<Uint8List>();
  var _nextTs = 0;
  bool cancelled = false;
  int delivered = 0;

  @override
  Future<Uint8List?> next() async {
    final cdn = _cdn;
    if (cdn == null) return null;
    while (_queue.isEmpty) {
      if (cancelled) return null;
      final cut = _cutAt;
      if (cut != null && _nextTs >= cut) return null;
      final now = cdn.streamNow - _lag;
      if (now <= _nextTs) {
        await Future<void>.delayed(Duration(milliseconds: _nextTs - now + _chunkMs));
        continue;
      }
      final until = cut == null || now < cut ? now : cut;
      _queue.addAll(_flv.tags(_nextTs, until));
      _nextTs = until;
    }
    if (cancelled) return null;
    delivered++;
    final tag = _queue.removeFirst();
    if (_shift == 0 || tag.length < 11 || tag[0] == 0x46) return tag;
    return FlvTag.withTimestamp(tag, FlvTag.timestamp(tag) + _shift);
  }

  @override
  Future<void> cancel() async => cancelled = true;
}

/// Checks an output FLV: header first, then tags whose video and audio
/// timestamps never go back, and returns the largest gaps.
final class OutputCheck {
  final List<Uint8List> packets = [];
  final List<int> video = [];
  final List<int> audio = [];
  int scripts = 0;
  int videoConfigs = 0;
  int audioConfigs = 0;
  int keyframes = 0;

  void add(Uint8List packet) {
    packets.add(packet);
    if (packets.length == 1) return;
    final type = FlvTag.type(packet);
    final ts = FlvTag.timestamp(packet);
    if (type == FlvTag.script) {
      scripts++;
    } else if (FlvTag.isVideoConfig(packet)) {
      videoConfigs++;
    } else if (FlvTag.isAudioConfig(packet)) {
      audioConfigs++;
    } else if (type == FlvTag.video) {
      if (FlvTag.isKeyframe(packet)) keyframes++;
      video.add(ts);
    } else if (type == FlvTag.audio) {
      audio.add(ts);
    }
  }

  static int _maxGap(List<int> values) {
    var gap = 0;
    for (var i = 1; i < values.length; i++) {
      final delta = values[i] - values[i - 1];
      if (delta > gap) gap = delta;
    }
    return gap;
  }

  static bool _monotonic(List<int> values, {required bool strict}) {
    for (var i = 1; i < values.length; i++) {
      if (strict ? values[i] <= values[i - 1] : values[i] < values[i - 1]) return false;
    }
    return true;
  }

  int get maxVideoGap => _maxGap(video);
  int get maxAudioGap => _maxGap(audio);
  bool get videoMonotonic => _monotonic(video, strict: false);
  bool get audioMonotonic => _monotonic(audio, strict: true);

  /// Video timestamps that appear more than once.
  int get repeatedVideo => video.length - video.toSet().length;
}
