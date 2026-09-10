import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/hls_master_selection.dart';
import 'package:pure_live/core/site/niconico/niconico_session.dart';
import 'package:pure_live/core/site/niconico/niconico_stream.dart';
import 'package:pure_live/core/site/niconico/niconico_watch.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/services/niconico_hls_input.dart';

Map<String, dynamic> fixture(String name) => jsonDecode(File('test/fixtures/niconico/$name.json').readAsStringSync());
final watch = NiconicoWatch.parseData(fixture('live'), programId: 'lv100');
const master = '''#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="main",URI="audio.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1280x720,AUDIO="a"
720.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=854x480,AUDIO="a"
480.m3u8
''';
// Observed official-program attributes, with synthetic media paths.
const officialMaster = '''#EXTM3U
#EXT-X-VERSION:6
#EXT-X-INDEPENDENT-SEGMENTS
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="trial-audio-192Kbps",NAME="Main Audio",DEFAULT=YES,URI="audio192.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="trial-audio-96Kbps",NAME="Main Audio",DEFAULT=YES,URI="audio96.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=1080800,AVERAGE-BANDWIDTH=1000000,CODECS="avc1.4D401F,mp4a.40.2",RESOLUTION=800x450,FRAME-RATE=30.000,AUDIO="trial-audio-192Kbps"
normal.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=412800,AVERAGE-BANDWIDTH=384000,CODECS="avc1.4D4015,mp4a.40.2",RESOLUTION=512x288,FRAME-RATE=30.000,AUDIO="trial-audio-96Kbps"
low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=201600,AVERAGE-BANDWIDTH=192000,CODECS="avc1.4D4015,mp4a.40.2",RESOLUTION=512x288,FRAME-RATE=30.000,AUDIO="trial-audio-96Kbps"
super-low.m3u8
''';
String direct(Uri _) => 'DIRECT';
Matcher failure(NiconicoFailure kind) => throwsA(isA<NiconicoException>().having((e) => e.kind, 'kind', kind));

class Seat implements NiconicoSession {
  NiconicoStream grant = NiconicoStream.parse(fixture('stream'));
  final events = StreamController<NiconicoStream>.broadcast();
  final ended = Completer<NiconicoFailure?>();
  final closeStarted = Completer<void>();
  Completer<void>? closeGate;
  int closes = 0;
  bool badCleanup = false;
  bool throwCleanup = false;
  @override
  bool isClosed = false;
  @override
  bool cleanupSucceeded = false;
  @override
  int get seatKeepAlivesSent => 0;
  @override
  NiconicoStream get current {
    if (isClosed) throw const NiconicoException(NiconicoFailure.sessionClosed);
    return grant;
  }

  @override
  Stream<NiconicoStream> get changes => events.stream;
  @override
  Future<NiconicoFailure?> get done => ended.future;
  void refresh({bool newRoot = false}) {
    final data = fixture('stream');
    if (newRoot) data['uri'] = (data['uri'] as String).replaceFirst('master.m3u8', 'new.m3u8');
    for (final cookie in data['cookies'] as List) {
      cookie['value'] = 'refreshed';
    }
    grant.close();
    grant = NiconicoStream.parse(data);
    events.add(grant);
  }

  void disconnect() {
    isClosed = true;
    grant.close();
    ended.complete(NiconicoFailure.sessionError);
  }

  @override
  Future<void> close() async {
    closes++;
    isClosed = true;
    grant.close();
    closeStarted.complete();
    await closeGate?.future;
    cleanupSucceeded = !badCleanup;
    if (!ended.isCompleted) ended.complete(null);
    await events.close();
    if (throwCleanup) throw StateError('fixture cleanup');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Relay implements FFmpegHlsInputRelay {
  int closes = 0;
  int finishes = 0;
  final closeStarted = Completer<void>();
  Completer<void>? closeGate;
  bool badCleanup = false;
  @override
  int get resourceCount => 0;
  @override
  int get prefetchFeedCount => 0;
  @override
  Uri get inputUri => Uri.parse('http://127.0.0.1:18000/private/root.m3u8');
  @override
  Duration get drainTimeout => const Duration(seconds: 5);
  @override
  Future<void> finish() async {
    finishes++;
  }

  @override
  List<String> replaceFirstInput(Iterable<String> source) => ['-i', inputUri.toString()];
  @override
  Future<void> close() async {
    closes++;
    closeStarted.complete();
    await closeGate?.future;
    if (badCleanup) throw StateError('fixture cleanup');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Harness {
  final seat = Seat();
  final relay = Relay();
  final reading = Completer<void>();
  final building = Completer<void>();
  Completer<NiconicoSession>? seatGate;
  Completer<String>? masterGate;
  Completer<FFmpegHlsInputRelay>? relayGate;
  String? Function(Uri)? cookies;
  HlsMasterSelection? selection;
  CancelToken? internalCancel;
  int seatCalls = 0;
  int masterCalls = 0;
  int relayCalls = 0;
  String masterText = master;
  bool badMaster = false;
  bool badRelay = false;
  Future<NiconicoHlsInput> open({CancelToken? cancel, String? resolution = '1280x720', int? bandwidth}) =>
      NiconicoHlsInput.open(
        watch,
        resolution: resolution,
        bandwidth: bandwidth,
        recording: true,
        findProxy: direct,
        cancel: cancel,
        openSeat: (_, token, proxy) async {
          seatCalls++;
          internalCancel = token;
          expect(proxy(Uri.parse('https://example.test')), 'DIRECT');
          return seatGate == null ? seat : await seatGate!.future;
        },
        readMaster: (source, provider, token, proxy) async {
          masterCalls++;
          cookies = provider;
          expect(identical(token, internalCancel), true);
          reading.complete();
          if (badMaster) throw StateError('fixture read');
          return masterGate == null ? masterText : await masterGate!.future;
        },
        createRelay: (source, provider, selected) async {
          relayCalls++;
          selection = selected;
          cookies = provider;
          building.complete();
          if (badRelay) throw StateError('fixture relay');
          return relayGate == null ? relay : await relayGate!.future;
        },
      );
}

void main() {
  for (final choice in [
    ('800x450', 1080800, 'normal.m3u8', 'audio192.m3u8'),
    ('512x288', 412800, 'low.m3u8', 'audio96.m3u8'),
    ('512x288', 201600, 'super-low.m3u8', 'audio96.m3u8'),
  ]) {
    test('official bitrate ${choice.$2} retains exactly its observed video/audio pair', () async {
      final h = Harness()..masterText = officialMaster;
      final input = await h.open(resolution: choice.$1, bandwidth: choice.$2);
      expect(h.selection!.video.path, endsWith('/${choice.$3}'));
      expect(h.selection!.audio!.path, endsWith('/${choice.$4}'));
      await input.close();
    });
  }
  test('bandwidth without explicit resolution fails before acquiring a seat', () async {
    final h = Harness();
    await expectLater(h.open(resolution: null, bandwidth: 412800), throwsArgumentError);
    expect(h.seatCalls, 0);
    await h.seat.close();
  });
  test('late relay closes while early seat cleanup is still pending', () async {
    final h = Harness()..relayGate = Completer<FFmpegHlsInputRelay>();
    h.seat.closeGate = Completer<void>();
    final cancel = CancelToken();
    final result = expectLater(h.open(cancel: cancel), failure(NiconicoFailure.cancelled));
    await h.building.future;
    cancel.cancel();
    await h.seat.closeStarted.future;
    h.relayGate!.complete(h.relay);
    try {
      await h.relay.closeStarted.future.timeout(const Duration(seconds: 2));
      expect(h.seat.cleanupSucceeded, false);
    } finally {
      h.seat.closeGate!.complete();
      await result;
    }
    expect(h.relay.closes, 1);
  });
  test('default relay binds a private local socket and owner teardown releases it', () async {
    final seat = Seat();
    final input = await NiconicoHlsInput.open(
      watch,
      resolution: '1280x720',
      recording: false,
      findProxy: direct,
      openSeat: (_, _, _) async => seat,
      readMaster: (_, _, _, _) async => master,
    );
    final uri = input.inputUri;
    expect(uri.host, '127.0.0.1');
    expect(input.resourceCount, greaterThan(0));
    final socket = await Socket.connect(uri.host, uri.port);
    socket.destroy();
    await input.close();
    expect(input.resourceCount, 0);
    expect(input.retainedCookieCount, 0);
    expect(input.cleanupSucceeded, true);
    await expectLater(Socket.connect(uri.host, uri.port), throwsA(isA<SocketException>()));
  });
  for (final resolution in ['1920x1080', '1280x720']) {
    test('absent or ambiguous resolution $resolution is not silently replaced', () async {
      final h = Harness();
      if (resolution == '1280x720') h.masterText = master.replaceFirst('854x480', '1280x720');
      await expectLater(h.open(resolution: resolution), failure(NiconicoFailure.schema));
      expect(h.relayCalls, 0);
      expect(h.seat.cleanupSucceeded, true);
    });
  }
  test('owns selected video plus audio; graceful drain keeps seat until idempotent close', () async {
    final h = Harness();
    final input = await h.open();
    expect(h.selection!.video.path, endsWith('/720.m3u8'));
    expect(h.selection!.audio!.path, endsWith('/audio.m3u8'));
    expect(input.inputUri, h.relay.inputUri);
    expect(input.replaceFirstInput(['-i', 'unused']), ['-i', h.relay.inputUri.toString()]);
    expect(input.drainTimeout, const Duration(seconds: 5));
    await input.finish();
    expect(h.relay.finishes, 1);
    expect(h.seat.isClosed, false);
    final first = input.close();
    expect(identical(first, input.close()), true);
    await first;
    expect(await input.done, isNull);
    expect(input.cleanupSucceeded, true);
    expect(input.retainedCookieCount, 0);
    expect(h.seat.closes, 1);
    expect(h.relay.closes, 1);
    expect(() => input.inputUri, failure(NiconicoFailure.sessionClosed));
    expect(() => h.cookies!(h.seat.grant.uri), failure(NiconicoFailure.sessionClosed));
  });
  test('explicit ABR keeps master unchanged without an unnecessary pre-read', () async {
    final h = Harness();
    final input = await h.open(resolution: null);
    expect(h.masterCalls, 0);
    expect(h.selection, isNull);
    await input.close();
  });
  test('pre-cancel allocates no seat', () async {
    final h = Harness();
    await expectLater(h.open(cancel: CancelToken()..cancel()), failure(NiconicoFailure.cancelled));
    expect(h.seatCalls, 0);
    // The harness fixture, unlike production, preallocates its fake grant.
    await h.seat.close();
  });
  test('cancel during late seat creation closes returned seat before open rejects', () async {
    final h = Harness()..seatGate = Completer<NiconicoSession>();
    final cancel = CancelToken();
    final result = expectLater(h.open(cancel: cancel), failure(NiconicoFailure.cancelled));
    cancel.cancel();
    await h.internalCancel!.whenCancel;
    h.seatGate!.complete(h.seat);
    await result;
    expect(h.seat.closes, 1);
    expect(h.masterCalls, 0);
    expect(h.relayCalls, 0);
  });
  test('cancel pre-read closes live seat immediately and observes late read', () async {
    final h = Harness()..masterGate = Completer<String>();
    final cancel = CancelToken();
    var settled = false;
    final result = expectLater(h.open(cancel: cancel), failure(NiconicoFailure.cancelled)).then((_) => settled = true);
    await h.reading.future;
    cancel.cancel();
    await h.seat.closeStarted.future;
    expect(settled, false);
    expect(h.internalCancel!.isCancelled, true);
    h.masterGate!.complete(master);
    await result;
    expect(h.relayCalls, 0);
  });
  test('cancel bind closes early seat and late relay, awaiting both cleanups', () async {
    final h = Harness()..relayGate = Completer<FFmpegHlsInputRelay>();
    h.relay.closeGate = Completer<void>();
    final cancel = CancelToken();
    var settled = false;
    final result = expectLater(h.open(cancel: cancel), failure(NiconicoFailure.cancelled)).then((_) => settled = true);
    await h.building.future;
    cancel.cancel();
    await h.seat.closeStarted.future;
    h.relayGate!.complete(h.relay);
    await h.relay.closeStarted.future;
    expect(settled, false);
    h.relay.closeGate!.complete();
    await result;
    expect(h.relay.closes, 1);
  });
  test('same-root refresh revokes old grant and serves only new cookies', () async {
    final h = Harness();
    final input = await h.open();
    final old = h.seat.current;
    expect(h.cookies!(old.uri), contains('fixture-'));
    h.seat.refresh();
    expect(h.cookies!(old.uri), contains('refreshed'));
    expect(old.retainedCookieCount, 0);
    expect(input.isClosed, false);
    await input.close();
    expect(h.seat.grant.retainedCookieCount, 0);
  });
  for (final stage in ['read', 'bind', 'active']) {
    test('root change during $stage terminates owner without stale master or cookies', () async {
      final h = Harness();
      if (stage == 'read') h.masterGate = Completer<String>();
      if (stage == 'bind') h.relayGate = Completer<FFmpegHlsInputRelay>();
      NiconicoHlsInput? input;
      Future<void>? rejected;
      if (stage == 'active') {
        input = await h.open();
      } else {
        rejected = expectLater(h.open(), failure(NiconicoFailure.sessionClosed));
        await (stage == 'read' ? h.reading.future : h.building.future);
      }
      h.seat.refresh(newRoot: true);
      await h.seat.closeStarted.future;
      if (stage == 'read') h.masterGate!.complete(master);
      if (stage == 'bind') h.relayGate!.complete(h.relay);
      if (input != null) {
        expect(await input.done, NiconicoFailure.sessionClosed);
        expect(input.cleanupSucceeded, true);
      } else {
        await rejected;
      }
      expect(h.seat.closes, 1);
      expect(h.relay.closes, stage == 'read' ? 0 : 1);
      expect(h.seat.grant.retainedCookieCount, 0);
    });
  }
  test('remote session end closes relay without native polling', () async {
    final h = Harness();
    final input = await h.open();
    h.seat.disconnect();
    expect(await input.done, NiconicoFailure.sessionError);
    expect(h.relay.closes, 1);
    expect(input.cleanupSucceeded, true);
  });
  for (final stage in ['read', 'relay', 'selection']) {
    test('$stage failure closes acquired resources before open rejects', () async {
      final h = Harness();
      h.badMaster = stage == 'read';
      h.badRelay = stage == 'relay';
      if (stage == 'selection') h.masterText = '#EXTM3U\n#EXTINF:3,\none.ts\n';
      await expectLater(h.open(), throwsA(isA<NiconicoException>()));
      expect(h.seat.closes, 1);
      expect(h.seat.grant.retainedCookieCount, 0);
    });
  }
  for (final stage in ['seat flag', 'seat throw', 'relay']) {
    test('$stage cleanup failure still joins other owner and reports cleanup failure', () async {
      final h = Harness();
      final input = await h.open();
      h.seat.badCleanup = stage == 'seat flag';
      h.seat.throwCleanup = stage == 'seat throw';
      h.relay.badCleanup = stage == 'relay';
      await expectLater(input.close(), failure(NiconicoFailure.cleanup));
      expect(await input.done, NiconicoFailure.cleanup);
      expect(input.cleanupSucceeded, false);
      expect(h.seat.closes, 1);
      expect(h.relay.closes, 1);
    });
  }
  test('playback and recording owners have independent seats and close lifetimes', () async {
    final a = Harness();
    final b = Harness();
    final first = await a.open();
    final second = await b.open();
    await first.close();
    expect(second.isClosed, false);
    expect(b.cookies!(b.seat.current.uri), isNotNull);
    await second.close();
  });
  test('parent cancellation after open closes both resources and reports cancellation', () async {
    final h = Harness();
    final cancel = CancelToken();
    final input = await h.open(cancel: cancel);
    cancel.cancel();
    expect(await input.done, NiconicoFailure.cancelled);
    expect(input.retainedCookieCount, 0);
    expect(h.relay.closes, 1);
  });
}
