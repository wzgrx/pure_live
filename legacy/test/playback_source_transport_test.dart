import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/hls_source_query_policy.dart';
import 'package:pure_live/player/core/playback_source_transport.dart';
import 'package:pure_live/player/core/playback_proxy_policy.dart';
import 'package:pure_live/recorder/services/recorder_proxy_routing.dart';

const source = 'https://cdn.example/live/master.m3u8?token=fixture';
final policy = HlsSourceQueryPolicy.fromSource(Uri.parse(source));

void main() {
  test('owner teardown joins cleanup already started by dispatch-time cancellation', () async {
    final cleanup = Completer<void>();
    final opening = Completer<void>();
    final ready = Completer<void>();
    final owner = PlaybackSourceTransport(
      createInput: (_, _, _) async =>
          PlaybackInputLease(Uri.parse('http://127.0.0.1:19000/private/root.m3u8'), () => cleanup.future),
    );
    final retired = expectLater(
      _open(
        owner,
        nativeOpen: (_, _, _, _) async {
          opening.complete();
          await ready.future;
        },
      ),
      throwsStateError,
    );
    await opening.future;
    final cancellation = owner.cancelPending();
    var closed = false;
    final closing = owner.close().then((_) {
      closed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    cleanup.complete();
    await cancellation;
    await closing;
    ready.complete();
    await retired;
  });
  test('legacy URL with token stays direct and preserves original native headers and choices', () async {
    final owner = PlaybackSourceTransport(createInput: (_, _, _) => throw StateError('unexpected relay'));
    final headers = {'cookie': 'fixture=yes'};
    final urls = [source, 'https://backup.example/live.m3u8'];
    await owner.open(
      url: source,
      urls: urls,
      headers: headers,
      policy: null,
      nativeOpen: (url, choices, fields, privateInput) async {
        expect(url, source);
        expect(choices, same(urls));
        expect(fields, same(headers));
        expect(privateInput, isFalse);
      },
    );
    await owner.close();
  });

  test('successful replacement retires the previous lease only after native open', () async {
    final leases = <_Lease>[];
    final owner = _owner(leases);
    await _open(owner);
    final ready = Completer<void>();
    final opening = Completer<void>();
    final next = _open(
      owner,
      nativeOpen: (_, _, _, _) async {
        opening.complete();
        await ready.future;
      },
    );
    await opening.future;
    expect(leases.map((e) => e.closes), [0, 0]);
    ready.complete();
    await next;
    expect(leases.map((e) => e.closes), [1, 0]);
    await owner.close();
    await owner.close();
    expect(leases.map((e) => e.closes), [1, 1]);
  });

  test('failed candidate is closed without retiring the previous native input', () async {
    final leases = <_Lease>[];
    final owner = _owner(leases);
    await _open(owner);
    await expectLater(
      _open(owner, nativeOpen: (_, _, _, _) async => throw StateError('native rejected')),
      throwsStateError,
    );
    expect(leases.map((e) => e.closes), [0, 1]);
    await owner.close();
    expect(leases.map((e) => e.closes), [1, 1]);
  });

  test('direct replacement releases previous relay and carries no private-input flag', () async {
    final leases = <_Lease>[];
    final owner = _owner(leases);
    await _open(owner);
    await owner.open(
      url: source,
      urls: [source],
      headers: const {},
      policy: null,
      nativeOpen: (url, _, _, privateInput) async {
        expect(url, source);
        expect(privateInput, isFalse);
        expect(leases.single.closes, 0);
      },
    );
    expect(leases.single.closes, 1);
    await owner.close();
  });

  test('closing while input creation is pending retires its late result without native open', () async {
    final creating = Completer<PlaybackInputLease>();
    final lease = _Lease(1);
    final owner = PlaybackSourceTransport(createInput: (_, _, _) => creating.future);
    var opens = 0;
    final result = expectLater(
      _open(
        owner,
        nativeOpen: (_, _, _, _) async {
          opens++;
        },
      ),
      throwsStateError,
    );
    await owner.close();
    creating.complete(lease.input);
    await result;
    expect(opens, 0);
    expect(lease.closes, 1);
    await expectLater(_open(owner), throwsStateError);
  });

  test('newer open wins over a late factory result from the old generation', () async {
    final creating = Completer<PlaybackInputLease>();
    final old = _Lease(1);
    final next = _Lease(2);
    var calls = 0;
    final owner = PlaybackSourceTransport(
      createInput: (_, _, _) => ++calls == 1 ? creating.future : Future.value(next.input),
    );
    final stale = expectLater(
      _open(owner, nativeOpen: (_, _, _, _) async => fail('stale native open')),
      throwsStateError,
    );
    await _open(owner);
    creating.complete(old.input);
    await stale;
    expect(old.closes, 1);
    expect(next.closes, 0);
    await owner.close();
    expect(next.closes, 1);
  });

  for (final dispose in [false, true]) {
    test(
      'pending native completion after ${dispose ? 'dispose' : 'timeout cancellation'} never revives its input',
      () async {
        final leases = <_Lease>[];
        final owner = _owner(leases);
        await _open(owner);
        final opening = Completer<void>();
        final ready = Completer<void>();
        final result = expectLater(
          _open(
            owner,
            nativeOpen: (_, _, _, _) async {
              opening.complete();
              await ready.future;
            },
          ),
          throwsStateError,
        );
        await opening.future;
        if (dispose) {
          await owner.close();
        } else {
          await owner.cancelPending();
        }
        expect(leases.map((e) => e.closes), [dispose ? 1 : 0, 1]);
        ready.complete();
        await result;
        await owner.close();
        expect(leases.map((e) => e.closes), [1, 1]);
      },
    );
  }

  test('mismatched source policy fails before allocating input', () async {
    final owner = PlaybackSourceTransport(createInput: (_, _, _) => throw StateError('unexpected allocation'));
    await expectLater(
      owner.open(
        url: '$source-new',
        urls: [],
        headers: const {},
        policy: policy,
        nativeOpen: (_, _, _, _) async => fail('unexpected open'),
      ),
      throwsFormatException,
    );
    await owner.close();
  });

  test('header framing characters fail before native open', () async {
    for (final headers in [
      {'bad:name': 'value'},
      {'Cookie': 'value\r\nInjected: bad'},
      {'Cookie': 'bad\x00value'},
    ]) {
      final owner = PlaybackSourceTransport();
      await expectLater(
        owner.open(
          url: source,
          urls: [source],
          headers: headers,
          policy: policy,
          nativeOpen: (_, _, _, _) async => fail('unexpected open'),
        ),
        throwsFormatException,
      );
      await owner.close();
    }
  });

  test('native proxy is cleared for private input and restored for the next remote source', () {
    expect(PlaybackProxyPolicy.nativeUrl('PROXY 127.0.0.1:7897', privateInput: false), 'http://127.0.0.1:7897');
    expect(PlaybackProxyPolicy.nativeUrl('PROXY 127.0.0.1:7897', privateInput: true), '');
    expect(PlaybackProxyPolicy.nativeUrl('PROXY [::1]:7897', privateInput: false), 'http://[::1]:7897');
    expect(PlaybackProxyPolicy.nativeUrl('DIRECT', privateInput: false), '');
  });

  test('real relay fetches scoped children and owns headers without using the recording proxy', () async {
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final observed = <Uri>[];
    final cookies = <String?>[];
    final subscription = upstream.listen((request) async {
      observed.add(request.uri);
      cookies.add(request.headers.value('cookie'));
      request.response.write(
        request.uri.path.endsWith('.m3u8') ? '#EXTM3U\n#EXT-X-TARGETDURATION:2\n#EXTINF:2,\nseg.ts\n' : 'DATA',
      );
      await request.response.close();
    });
    // No registered app settings means direct media. The independent recording
    // callback must never see this playback request.
    configureRecorderProxyRouting((_) => throw StateError('recording proxy used for playback'));
    final url = 'http://127.0.0.1:${upstream.port}/live/master.m3u8?token=fixture';
    final owner = PlaybackSourceTransport();
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    Uri? input;
    try {
      await owner.open(
        url: url,
        urls: [url],
        headers: const {'Cookie': 'fixture=yes'},
        policy: HlsSourceQueryPolicy.fromSource(Uri.parse(url)),
        nativeOpen: (local, choices, headers, privateInput) async {
          input = Uri.parse(local);
          expect(local, isNot(contains('token=')));
          expect(headers, isEmpty);
          expect(choices, [local]);
          expect(privateInput, isTrue);
          final manifest = await (await (await client.getUrl(input!)).close()).transform(utf8.decoder).join();
          final segment = Uri.parse(const LineSplitter().convert(manifest).firstWhere((line) => !line.startsWith('#')));
          final response = await (await client.getUrl(segment)).close();
          expect(response.statusCode, 200);
          expect(await response.transform(utf8.decoder).join(), 'DATA');
        },
      );
      expect(observed, hasLength(2));
      expect(observed.last.queryParameters['token'], 'fixture');
      expect(cookies, ['fixture=yes', 'fixture=yes']);
      await owner.close();
      final probe = HttpClient()..findProxy = (_) => 'DIRECT';
      try {
        await expectLater(
          (() async {
            await (await probe.getUrl(input!)).close();
          })(),
          throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
        );
      } finally {
        probe.close(force: true);
      }
    } finally {
      client.close(force: true);
      await owner.close();
      configureRecorderProxyRouting(null);
      await upstream.close(force: true);
      await subscription.cancel();
    }
  });
}

Future<void> _open(PlaybackSourceTransport owner, {PlaybackNativeOpen? nativeOpen}) => owner.open(
  url: source,
  urls: [source],
  headers: const {'Cookie': 'fixture=yes'},
  policy: policy,
  nativeOpen:
      nativeOpen ??
      (url, urls, headers, privateInput) async {
        expect(privateInput, isTrue);
        expect(headers, isEmpty);
        expect(urls, [url]);
      },
);

PlaybackSourceTransport _owner(List<_Lease> leases) => PlaybackSourceTransport(
  createInput: (_, _, _) async {
    final lease = _Lease(leases.length + 1);
    leases.add(lease);
    return lease.input;
  },
);

class _Lease {
  _Lease(int id) {
    input = PlaybackInputLease(Uri.parse('http://127.0.0.1:19000/$id/root.m3u8'), () async {
      closes++;
    });
  }
  int closes = 0;
  late final PlaybackInputLease input;
}
