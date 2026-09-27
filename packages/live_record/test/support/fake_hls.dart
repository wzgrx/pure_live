import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/live_record.dart';
import 'package:live_record/src/hls/aes.dart';

import 'ts_build.dart';

/// The fMP4 fixture (ffmpeg HLS muxer): initialisation section and two fragments.
final Uint8List fmp4Init = File('test/fixtures/hls/fmp4/init.mp4').readAsBytesSync();
final List<Uint8List> fmp4Fragments = [
  File('test/fixtures/hls/fmp4/seg0.m4s').readAsBytesSync(),
  File('test/fixtures/hls/fmp4/seg1.m4s').readAsBytesSync(),
];

/// A small MPEG-TS segment for sequence [sequence]: a keyframe and two more
/// frames, two AAC frames; timestamps follow the sequence number.
Uint8List tsSegment(int sequence, {int targetMs = 2000, Uint8List? sps}) {
  final base = 90000 + sequence * targetMs * 90;
  return buildTs([
    TsUnit.video(pts: base, key: true, sps: sps),
    TsUnit.audio(pts: base),
    TsUnit.video(pts: base + targetMs * 30),
    TsUnit.audio(pts: base + targetMs * 45),
    TsUnit.video(pts: base + targetMs * 60),
  ]);
}

/// A fake live HLS stream over fake time (spec §7): a new segment every
/// target duration; the media playlist lists the last [window] segments.
/// [window] segments exist before [epoch] (half a second after creation);
/// one more appears at the epoch and every target duration after it.
/// Everything is served through [get], like an [HlsClient].
final class FakeHlsServer implements HlsClient {
  new({
    this.target = const Duration(seconds: 2),
    this.window = 5,
    this.firstSequence = 100,
    DateTime? epoch,
    this.fmp4 = false,
    this.key,
    this.explicitIv = false,
    this.byteRange = false,
    this.lowLatency = false,
    this.master = false,
    this.separateAudio = false,
  }) : epoch = epoch ?? clock.now().add(const Duration(milliseconds: 500));

  final Duration target;
  final int window;
  int firstSequence;
  final DateTime epoch;
  final bool fmp4;

  /// AES-128 key of the segments, if encrypted.
  final Uint8List? key;
  final bool explicitIv;
  final bool byteRange;
  final bool lowLatency;
  final bool master;
  final bool separateAudio;

  /// The playlist stops changing while set.
  bool get frozen => _frozenAt != null;

  set frozen(bool value) => _frozenAt = value ? _produced : null;
  int? _frozenAt;

  /// `EXT-X-ENDLIST` after the current segments.
  bool ended = false;

  /// Numbering restarts: every sequence number is shifted by this.
  int shift = 0;

  /// `EXT-X-KEY` method for the playlist, overriding AES-128 (`SAMPLE-AES`).
  String? keyMethod;

  /// Answers for the next requests of a path suffix: a status code, or an exception.
  final Map<String, List<Object>> failures = {};

  /// Status for every request of a path suffix while set.
  final Map<String, int> statusAll = {};

  /// Sequence numbers that answer 404 (every attempt).
  final Set<int> missing = {};

  /// Sequence numbers marked `EXT-X-GAP`.
  final Set<int> gaps = {};

  /// Response time of each request.
  Duration latency = Duration.zero;

  /// Every request, in order.
  final List<({Uri url, DateTime at, String? range})> requests = [];

  var _inFlight = 0;

  /// Largest number of requests in flight at once, per kind.
  int maxPlaylistInFlight = 0;
  int maxSegmentInFlight = 0;
  var _segmentsInFlight = 0;
  var _playlistsInFlight = 0;

  /// Whether [close] was called.
  bool closed = false;

  /// The URL a line points to.
  Uri get url => Uri.parse(master ? 'https://cdn.test/live/master.m3u8' : 'https://cdn.test/live/index.m3u8');

  /// A stream line for [url] (FLV adapters give FLV lines; this one is HLS).
  StreamLine line({Uri? at, Lease? lease}) => StreamLine(
    url: at ?? url,
    format: StreamFormat.hls,
    lineId: 'cdn',
    requested: const Quality(id: 'src', label: '原画', rank: 1),
    headers: const {'user-agent': 'test', 'referer': 'https://example.test/'},
    lease: lease,
  );

  /// Index of the newest segment produced by now.
  int get _produced {
    final elapsed = clock.now().difference(epoch).inMilliseconds;
    return window - 1 + (elapsed < 0 ? 0 : elapsed ~/ target.inMilliseconds + 1);
  }

  int get _newest => _frozenAt ?? _produced;

  /// Sequence numbers in the current playlist.
  List<int> get listed {
    final newest = _newest;
    final first = newest - window + 1 < 0 ? 0 : newest - window + 1;
    return [for (var k = first; k <= newest; k++) firstSequence + shift + k];
  }

  /// The plain bytes of segment [sequence].
  Uint8List segmentBytes(int sequence) =>
      fmp4 ? fmp4Fragments[sequence % 2] : tsSegment(sequence, targetMs: target.inMilliseconds);

  Uint8List _iv(int sequence) =>
      explicitIv ? Uint8List.fromList(List.generate(16, (i) => 0xA0 + i)) : HlsAes128.sequenceIv(sequence);

  Uint8List _served(int sequence) {
    final plain = segmentBytes(sequence);
    final k = key;
    return k == null ? plain : HlsAes128(k).encrypt(plain, _iv(sequence));
  }

  String playlist() {
    final seqs = listed;
    final b = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:7')
      ..writeln('#EXT-X-TARGETDURATION:${target.inSeconds}')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:${seqs.isEmpty ? 0 : seqs.first}');
    if (lowLatency) {
      b
        ..writeln('#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=1.5')
        ..writeln('#EXT-X-PART-INF:PART-TARGET=0.5');
    }
    final k = key;
    if (keyMethod != null) {
      b.writeln('#EXT-X-KEY:METHOD=$keyMethod,URI="https://keys.test/k1"');
    } else if (k != null) {
      b.writeln(
        '#EXT-X-KEY:METHOD=AES-128,URI="https://keys.test/k1"'
        '${explicitIv ? ',IV=0x${[for (var i = 0; i < 16; i++) (0xA0 + i).toRadixString(16)].join()}' : ''}',
      );
    }
    if (fmp4) b.writeln('#EXT-X-MAP:URI="init.mp4"');
    for (final seq in seqs) {
      if (gaps.contains(seq)) b.writeln('#EXT-X-GAP');
      if (lowLatency) {
        b
          ..writeln('#EXT-X-PART:DURATION=0.5,URI="part/$seq.0.ts",INDEPENDENT=YES')
          ..writeln('#EXT-X-PART:DURATION=0.5,URI="part/$seq.1.ts"');
      }
      b.writeln('#EXTINF:${target.inSeconds}.000,');
      if (byteRange) {
        final length = _served(seq).length;
        // Implicit offsets after the first, as servers write them.
        b
          ..writeln(seq == seqs.first ? '#EXT-X-BYTERANGE:$length@${_rangeOffset(seq)}' : '#EXT-X-BYTERANGE:$length')
          ..writeln('all.ts');
      } else {
        b.writeln('seg/$seq.${fmp4 ? 'm4s' : 'ts'}');
      }
    }
    if (lowLatency && seqs.isNotEmpty) {
      b
        ..writeln('#EXT-X-PART:DURATION=0.5,URI="part/${seqs.last + 1}.0.ts",INDEPENDENT=YES')
        ..writeln('#EXT-X-PRELOAD-HINT:TYPE=PART,URI="part/${seqs.last + 1}.1.ts"');
    }
    if (ended) b.writeln('#EXT-X-ENDLIST');
    return b.toString();
  }

  /// Byte ranges: every segment lives in the growing resource `all.ts`,
  /// sequence after sequence from the first ever produced.
  int _rangeOffset(int sequence) {
    var offset = 0;
    for (var seq = firstSequence + shift; seq < sequence; seq++) {
      offset += _served(seq).length;
    }
    return offset;
  }

  Uint8List _all() {
    final b = BytesBuilder();
    final last = listed.last;
    for (var seq = firstSequence + shift; seq <= last; seq++) {
      b.add(_served(seq));
    }
    return b.takeBytes();
  }

  String masterPlaylist() => [
    '#EXTM3U',
    if (separateAudio) '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="en",DEFAULT=YES,URI="audio.m3u8"',
    '#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360${separateAudio ? ',AUDIO="aud"' : ''}',
    'low.m3u8',
    '#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720${separateAudio ? ',AUDIO="aud"' : ''}',
    'index.m3u8',
    '',
  ].join('\n');

  /// Requests whose path ends with [suffix].
  List<({Uri url, DateTime at, String? range})> requested(String suffix) => [
    for (final request in requests)
      if (request.url.path.endsWith(suffix)) request,
  ];

  /// Segment requests, as sequence numbers.
  List<int> get segmentRequests => [
    for (final request in requests)
      if (request.url.path.contains('/seg/')) int.parse(request.url.pathSegments.last.split('.').first),
  ];

  @override
  Future<HlsResponse> get(HlsRequest request) async {
    final url = request.url;
    requests.add((url: url, at: clock.now(), range: request.range?.header));
    final path = url.path;
    final isPlaylist = path.endsWith('.m3u8');
    _inFlight++;
    if (isPlaylist) {
      _playlistsInFlight++;
      if (_playlistsInFlight > maxPlaylistInFlight) maxPlaylistInFlight = _playlistsInFlight;
    } else if (path.contains('/seg/') || path.endsWith('all.ts')) {
      _segmentsInFlight++;
      if (_segmentsInFlight > maxSegmentInFlight) maxSegmentInFlight = _segmentsInFlight;
    }
    try {
      if (latency > Duration.zero) {
        var cancelled = false;
        final cancel = request.cancel?.then((_) => cancelled = true);
        await Future.any([Future<void>.delayed(latency), ?cancel]);
        if (cancelled) throw const HlsCancelled();
      }
      for (final MapEntry(key: suffix, value: answers) in failures.entries) {
        if (path.endsWith(suffix) && answers.isNotEmpty) {
          final answer = answers.removeAt(0);
          if (answer is int) throw UpstreamStatusException(answer, url);
          Error.throwWithStackTrace(answer, StackTrace.current);
        }
      }
      for (final MapEntry(key: suffix, value: status) in statusAll.entries) {
        if (path.endsWith(suffix)) throw UpstreamStatusException(status, url);
      }
      Uint8List body;
      if (path.endsWith('master.m3u8')) {
        body = Uint8List.fromList(masterPlaylist().codeUnits);
      } else if (isPlaylist) {
        body = Uint8List.fromList(playlist().codeUnits);
      } else if (url.host == 'keys.test') {
        body = key!;
      } else if (path.endsWith('init.mp4')) {
        body = fmp4Init;
      } else if (path.endsWith('all.ts')) {
        final all = _all();
        final range = request.range!;
        body = Uint8List.sublistView(all, range.offset, range.end);
      } else if (path.contains('/seg/')) {
        final sequence = int.parse(url.pathSegments.last.split('.').first);
        if (missing.contains(sequence)) throw UpstreamStatusException(404, url);
        body = _served(sequence);
      } else {
        throw UpstreamStatusException(404, url);
      }
      return HlsResponse(body: body, url: url);
    } finally {
      _inFlight--;
      if (isPlaylist) {
        _playlistsInFlight--;
      } else if (path.contains('/seg/') || path.endsWith('all.ts')) {
        _segmentsInFlight--;
      }
    }
  }

  /// Requests in flight.
  int get inFlight => _inFlight;

  @override
  void close() => closed = true;
}

/// An [HlsSink] that records what a feed delivers.
final class RecordingSink implements HlsSink {
  final List<HlsMedia> media = [];
  final List<HlsMissing> missing = [];

  /// While set, [ready] waits for it (a slow disk).
  Future<void>? gate;

  /// Sequence numbers written, in order.
  List<int> get sequences => [for (final item in media) item.sequence];

  @override
  Future<void> get ready => gate ?? Future.value();

  @override
  void addMedia(HlsMedia media) => this.media.add(media);

  @override
  void addMissing(HlsMissing missing) => this.missing.add(missing);
}
