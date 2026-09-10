import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/niconico/niconico_api.dart';
import 'package:pure_live/core/site/niconico/niconico_watch.dart';
import 'package:pure_live/player/core/niconico_playback_input.dart';
import 'package:pure_live/player/core/playback_source_transport.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/services/niconico_hls_input.dart';

import 'niconico_hls_input_test.dart' as fixture;

Matcher kind(NiconicoFailure value) => throwsA(isA<NiconicoException>().having((e) => e.kind, 'kind', value));

class Harness {
  int requests = 0;
  final requesting = Completer<void>();
  final binding = Completer<void>();
  final seats = <fixture.Seat>[];
  final relays = <fixture.Relay>[];
  final inputs = <NiconicoHlsInput>[];
  final bootstraps = <String?>[];
  Completer<void>? metadataGate;
  Completer<FFmpegHlsInputRelay>? relayGate;
  bool badCleanup = false;
  late final source = NiconicoPlaybackInput(
    programId: 'lv100',
    resolution: '1280x720',
    bandwidth: 3000000,
    api: NiconicoApi(
      request: (uri, cancel) async {
        requests++;
        if (!requesting.isCompleted) requesting.complete();
        final data = fixture.fixture('live');
        data['site']['relive']['webSocketUrl'] =
            'wss://a.live2.nicovideo.jp/unama/wsapi/v2/watch/123?audience_token=fixture-$requests';
        await metadataGate?.future;
        return (
          status: 200,
          body: '<script id="embedded-data" data-props="${const HtmlEscape().convert(jsonEncode(data))}"></script>',
        );
      },
    ),
    findProxy: (_) => 'PROXY localhost:7897',
    openInput: (watch, {required resolution, bandwidth, required recording, required findProxy, cancel}) async {
      expect(resolution, '1280x720');
      expect(bandwidth, 3000000);
      expect(recording, false);
      expect(findProxy(Uri.parse('https://example.test')), 'PROXY localhost:7897');
      bootstraps.add(watch.webSocketUri!.queryParameters['audience_token']);
      final seat = fixture.Seat()..badCleanup = badCleanup;
      final relay = fixture.Relay();
      seats.add(seat);
      relays.add(relay);
      final input = await NiconicoHlsInput.open(
        watch,
        resolution: resolution,
        bandwidth: bandwidth,
        recording: recording,
        findProxy: findProxy,
        cancel: cancel,
        openSeat: (_, _, _) async => seat,
        readMaster: (_, _, _, _) async => fixture.master,
        createRelay: (_, _, _) async {
          if (!binding.isCompleted) binding.complete();
          return relayGate == null ? relay : await relayGate!.future;
        },
      );
      inputs.add(input);
      return input;
    },
  );
  Future<void> open(PlaybackSourceTransport transport, {PlaybackNativeOpen? native}) => transport.openOwned(
    createInput: source.open,
    nativeOpen:
        native ??
        (url, choices, headers, private) async {
          expect(url, 'http://127.0.0.1:18000/private/root.m3u8');
          expect(choices, [url]);
          expect(headers, isEmpty);
          expect(private, true);
          expect(url, isNot(contains('audience_token')));
        },
  );
}

void main() {
  test('each transport open reacquires watch metadata and a distinct owned seat', () async {
    final h = Harness();
    final transport = PlaybackSourceTransport();
    await h.open(transport);
    await h.open(transport);
    expect(h.requests, 2);
    expect(h.bootstraps, ['fixture-1', 'fixture-2']);
    expect(h.seats.map((e) => e.closes), [1, 0]);
    expect(h.inputs.map((e) => e.cleanupSucceeded), [true, false]);
    await transport.close();
    expect(h.seats.map((e) => e.closes), [1, 1]);
    expect(h.inputs.map((e) => e.retainedCookieCount), [0, 0]);
  });
  test('pre-cancel invokes neither metadata nor input creation', () async {
    final h = Harness();
    final cancel = CancelToken()..cancel();
    await expectLater(h.source.open(cancel), throwsA(same(cancel.cancelError)));
    expect(h.requests, 0);
    expect(h.seats, isEmpty);
  });
  test('cancel while metadata is pending never starts a seat from its late response', () async {
    final h = Harness()..metadataGate = Completer<void>();
    final transport = PlaybackSourceTransport();
    final result = expectLater(
      h.open(transport),
      throwsA(isA<DioException>().having((e) => e.type, 'kind', DioExceptionType.cancel)),
    );
    await h.requesting.future;
    await transport.close();
    await result;
    h.metadataGate!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(h.seats, isEmpty);
  });
  test('cancel during input bind closes live seat and joins late relay before teardown completes', () async {
    final h = Harness()..relayGate = Completer<FFmpegHlsInputRelay>();
    final transport = PlaybackSourceTransport();
    var nativeCalls = 0;
    final result = expectLater(
      h.open(
        transport,
        native: (_, _, _, _) async {
          nativeCalls++;
        },
      ),
      throwsA(isA<DioException>()),
    );
    await h.binding.future;
    var closed = false;
    final closing = transport.close().then((_) => closed = true);
    await h.seats.single.closeStarted.future;
    expect(closed, false);
    h.relayGate!.complete(h.relays.single);
    await result;
    await closing;
    expect(h.relays.single.closes, 1);
    expect(h.seats.single.closes, 1);
    expect(nativeCalls, 0);
  });
  test('root change during native opening fences candidate commit and preserves previous input', () async {
    final h = Harness();
    final transport = PlaybackSourceTransport();
    await h.open(transport);
    final entered = Completer<void>();
    final native = Completer<void>();
    final candidate = expectLater(
      h.open(
        transport,
        native: (_, _, _, _) async {
          entered.complete();
          await native.future;
        },
      ),
      throwsStateError,
    );
    await entered.future;
    h.seats.last.refresh(newRoot: true);
    expect(await h.inputs.last.done, NiconicoFailure.sessionClosed);
    native.complete();
    await candidate;
    expect(h.seats.map((e) => e.closes), [0, 1]);
    await transport.close();
    expect(h.seats.map((e) => e.closes), [1, 1]);
  });
  test('cleanup failure during cancellation stays a failure, not an expected cancellation', () async {
    final h = Harness()
      ..badCleanup = true
      ..relayGate = Completer<FFmpegHlsInputRelay>();
    final transport = PlaybackSourceTransport();
    final result = expectLater(h.open(transport), kind(NiconicoFailure.cleanup));
    await h.binding.future;
    final closing = expectLater(transport.close(), kind(NiconicoFailure.cleanup));
    await h.seats.single.closeStarted.future;
    h.relayGate!.complete(h.relays.single);
    await result;
    await closing;
    expect(h.relays.single.closes, 1);
    expect(h.seats.single.grant.retainedCookieCount, 0);
  });
  test('independent native transports never share a seat through the same recreation recipe', () async {
    final h = Harness();
    final a = PlaybackSourceTransport();
    final b = PlaybackSourceTransport();
    await h.open(a);
    await h.open(b);
    await a.close();
    expect(h.inputs.first.isClosed, true);
    expect(h.inputs.last.isClosed, false);
    expect(h.inputs.last.retainedCookieCount, 13);
    await b.close();
  });
  test('invalid recipe arguments fail before metadata acquisition', () {
    expect(() => NiconicoPlaybackInput(programId: 'other', resolution: null), kind(NiconicoFailure.identity));
    expect(() => NiconicoPlaybackInput(programId: 'lv100', resolution: null, bandwidth: 3000000), throwsArgumentError);
    expect(() => NiconicoPlaybackInput(programId: 'lv100', resolution: '1280x720', bandwidth: 0), throwsArgumentError);
  });
}
