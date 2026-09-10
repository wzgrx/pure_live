import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/web_socket_util.dart';
import 'package:pure_live/core/site/niconico/niconico_session.dart';
import 'package:pure_live/core/site/niconico/niconico_watch.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/niconico/$name.json').readAsStringSync()) as Map<String, dynamic>;
NiconicoWatch watch([String name = 'live']) => NiconicoWatch.parseData(fixture(name), programId: 'lv100');
Matcher failure(NiconicoFailure kind) => throwsA(isA<NiconicoException>().having((e) => e.kind, 'kind', kind));

class Harness {
  final channel = FakeChannel();
  int connections = 0;
  HttpClient? client;
  WebSocketConnector get connector => (endpoint, {connectTimeout, protocols, headers, customClient}) {
    connections++;
    client = customClient;
    expect(Uri.parse(endpoint).host, 'a.live2.nicovideo.jp');
    expect(headers, {'Origin': 'https://live.nicovideo.jp'});
    return channel;
  };
  void send(String type, [Object? data]) => channel.incoming.add(jsonEncode({'type': type, 'data': ?data}));
  void grant({int seconds = 1}) {
    send('seat', {'keepIntervalSec': seconds});
    send('stream', fixture('stream'));
  }

  Future<NiconicoSession> start(SessionTester tester, {CancelToken? cancel, Duration? silence}) async {
    final result = NiconicoSession.open(
      watch(),
      cancel: cancel,
      connector: connector,
      silenceTimeout: silence ?? const Duration(seconds: 90),
    );
    await tester.pump();
    grant();
    await tester.pump();
    return result;
  }

  Future<void> finish() => channel.incoming.close();
}

void main() {
  sessionTest('startup owns one seat; periodic keepSeat and ping have no comment side effect', (tester) async {
    final h = Harness();
    final session = await h.start(tester);
    try {
      final start = h.channel.outgoing.sent.first;
      expect(start['type'], 'startWatching');
      expect(start['data']['room']['commentable'], isFalse);
      expect(h.channel.outgoing.sent[1]['type'], 'getAkashic');
      expect(session.current.retainedCookieCount, 13);
      await tester.pump(const Duration(seconds: 2));
      expect(session.seatKeepAlivesSent, 2);
      h.send('ping');
      await tester.pump();
      expect(session.pongsSent, 1);
      expect(session.seatKeepAlivesSent, 3);
      expect(h.connections, 1);
      final old = session.current;
      await tester.close(session);
      expect(await session.done, isNull);
      expect(session.cleanupSucceeded, isTrue);
      expect(old.isActive, isFalse);
      expect(old.retainedCookieCount, 0);
      final count = h.channel.outgoing.sent.length;
      await tester.pump(const Duration(seconds: 100));
      expect(h.channel.outgoing.sent.length, count);
    } finally {
      await tester.close(session);
      await h.finish();
    }
  });
  sessionTest('stream before seat is retained but does not complete startup', (tester) async {
    final h = Harness();
    var completed = false;
    final future = NiconicoSession.open(watch(), connector: h.connector).then((s) {
      completed = true;
      return s;
    });
    await tester.pump();
    h.send('stream', fixture('stream'));
    await tester.pump();
    expect(completed, isFalse);
    h.send('seat', {'keepIntervalSec': 30});
    await tester.pump();
    final session = await future;
    expect(session.seatIntervalSeconds, 30);
    await tester.close(session);
    await h.finish();
  });
  sessionTest('seat changes replace the timer instead of multiplying it', (tester) async {
    final h = Harness();
    final session = await h.start(tester);
    try {
      h.send('seat', {'keepIntervalSec': 3});
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(session.seatKeepAlivesSent, 0);
      await tester.pump(const Duration(seconds: 1));
      expect(session.seatKeepAlivesSent, 1);
    } finally {
      await tester.close(session);
      await h.finish();
    }
  });
  sessionTest('new stream event atomically replaces cookies and revokes the old grant', (tester) async {
    final h = Harness();
    final session = await h.start(tester);
    final previous = session.current;
    final updates = <Object>[];
    final listener = session.changes.listen(updates.add);
    try {
      final next = fixture('stream');
      next['cookies'][1]['value'] = 'rotated';
      h.send('stream', next);
      await tester.pump();
      expect(updates, hasLength(1));
      expect(previous.isActive, isFalse);
      expect(session.current.cookieHeaderFor(session.current.uri), contains('rotated'));
      expect(previous.retainedCookieCount, 0);
    } finally {
      await tester.settle(listener.cancel());
      await tester.close(session);
      await h.finish();
    }
  });
  sessionTest('independent consumers sharing a caller token do not close each other', (tester) async {
    final caller = CancelToken();
    final a = Harness();
    final b = Harness();
    final first = await a.start(tester, cancel: caller);
    final second = await b.start(tester, cancel: caller);
    try {
      await tester.close(first);
      expect(caller.isCancelled, isFalse);
      expect(second.isClosed, isFalse);
      caller.cancel();
      await tester.pump();
      await second.done;
      expect(second.isClosed, isTrue);
      expect(second.cleanupSucceeded, isTrue);
    } finally {
      await tester.close(first);
      await tester.close(second);
      await a.finish();
      await b.finish();
    }
  });
  for (final kind in ['disconnect', 'error', 'malformed', 'invalid-stream', 'socket-error', 'socket-done']) {
    sessionTest('$kind ends the owned session without hidden reconnect', (tester) async {
      final h = Harness();
      final session = await h.start(tester);
      final previous = session.current;
      try {
        switch (kind) {
          case 'disconnect':
            h.send('disconnect', {'reason': 'server condition'});
          case 'error':
            h.send('error', {'code': 'unknown'});
          case 'malformed':
            h.channel.incoming.add('invalid-json');
          case 'invalid-stream':
            h.send('stream', {'protocol': 'dash'});
          case 'socket-error':
            h.channel.incoming.addError(StateError('private details'));
          case 'socket-done':
            await tester.settle(h.channel.incoming.close());
        }
        await tester.pump();
        expect(await session.done, isNotNull);
        expect(session.cleanupSucceeded, isTrue);
        expect(previous.isActive, isFalse);
        await tester.pump(const Duration(seconds: 100));
        expect(h.connections, 1);
      } finally {
        await tester.close(session);
        await h.finish();
      }
    });
  }
  sessionTest('silence watchdog closes a half-open session and clears cookies', (tester) async {
    final h = Harness();
    final session = await h.start(tester, silence: const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    expect(await session.done, NiconicoFailure.transport);
    expect(session.cleanupSucceeded, isTrue);
    await h.finish();
  });
  for (final message in [0, -1, 301, '30', null]) {
    sessionTest('invalid seat interval $message terminates startup', (tester) async {
      final h = Harness();
      final result = expectLater(
        NiconicoSession.open(watch(), connector: h.connector),
        failure(NiconicoFailure.schema),
      );
      await tester.pump();
      h.send('seat', {'keepIntervalSec': message});
      await tester.pump();
      await result;
      expect(h.channel.outgoing.closed, isTrue);
      await h.finish();
    });
  }
  sessionTest('startup timeout consumes late handshake errors and never sends after close', (tester) async {
    final h = Harness();
    final ready = Completer<void>();
    h.channel.readyOverride = ready.future;
    final result = expectLater(
      NiconicoSession.open(watch(), connector: h.connector, startupTimeout: const Duration(milliseconds: 20)),
      failure(NiconicoFailure.transport),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    await result;
    expect(h.channel.outgoing.closed, isTrue);
    ready.completeError(StateError('late upgrade'));
    await tester.pump();
    expect(h.channel.outgoing.sent, isEmpty);
    await h.finish();
  });
  sessionTest('cancellation during handshake removes all owned timers immediately', (tester) async {
    final h = Harness();
    final ready = Completer<void>();
    h.channel.readyOverride = ready.future;
    final caller = CancelToken();
    final result = expectLater(
      NiconicoSession.open(watch(), connector: h.connector, cancel: caller),
      failure(NiconicoFailure.cancelled),
    );
    await tester.pump();
    caller.cancel();
    await tester.pump();
    await result;
    ready.complete();
    await tester.pump();
    expect(h.channel.outgoing.sent, isEmpty);
    await h.finish();
  });
  sessionTest('stream without seat remains bounded by startup deadline', (tester) async {
    final h = Harness();
    final result = expectLater(
      NiconicoSession.open(watch(), connector: h.connector, startupTimeout: const Duration(milliseconds: 20)),
      failure(NiconicoFailure.transport),
    );
    await tester.pump();
    h.send('stream', fixture('stream'));
    await tester.pump(const Duration(milliseconds: 25));
    await result;
    await h.finish();
  });
  sessionTest('send failure closes rather than reporting a successful keepalive', (tester) async {
    final h = Harness();
    final session = await h.start(tester);
    h.channel.outgoing.throwOnAdd = true;
    h.send('ping');
    await tester.pump();
    expect(await session.done, NiconicoFailure.transport);
    expect(session.pongsSent, 0);
    await h.finish();
  });
  sessionTest('close deadline is reported as unverified cleanup, not a successful close', (tester) async {
    final h = Harness();
    final session = await h.start(tester);
    h.channel.outgoing.hangClose = true;
    final close = session.close();
    expect(identical(close, session.close()), isTrue);
    await tester.pump(const Duration(seconds: 3));
    await close;
    expect(session.cleanupSucceeded, isFalse);
    expect(await session.done, NiconicoFailure.cleanup);
    h.channel.outgoing.release();
    await h.finish();
  });
  sessionTest('proxy handshake uses its own client and preserves direct behavior', (tester) async {
    configureWebSocketProxyRouting((_) => 'PROXY localhost:7897');
    final h = Harness();
    NiconicoSession? session;
    try {
      session = await h.start(tester);
      expect(h.client, isNotNull);
    } finally {
      if (session != null) await tester.close(session);
      configureWebSocketProxyRouting(null);
      await h.finish();
    }
  });
  test('access/status/pre-cancellation gates prevent a connection', () async {
    final h = Harness();
    await expectLater(NiconicoSession.open(watch('region'), connector: h.connector), failure(NiconicoFailure.access));
    await expectLater(NiconicoSession.open(watch('ended'), connector: h.connector), failure(NiconicoFailure.notLive));
    await expectLater(
      NiconicoSession.open(watch(), cancel: CancelToken()..cancel(), connector: h.connector),
      failure(NiconicoFailure.cancelled),
    );
    expect(h.connections, 0);
    await h.finish();
  });
}

class FakeChannel implements WebSocketChannel {
  final incoming = StreamController<dynamic>.broadcast();
  final outgoing = FakeSink();
  Future<void>? readyOverride;
  @override
  Future<void> get ready => readyOverride ?? Future<void>.value();
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  WebSocketSink get sink => outgoing;
  @override
  String? get protocol => null;
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSink implements WebSocketSink {
  final sent = <Map<String, dynamic>>[];
  final _done = Completer<void>();
  bool closed = false;
  bool throwOnAdd = false;
  bool hangClose = false;
  @override
  void add(dynamic data) {
    if (closed || throwOnAdd) throw StateError('send failed');
    sent.add(jsonDecode(data as String) as Map<String, dynamic>);
  }

  void release() {
    if (!_done.isCompleted) _done.complete();
  }

  @override
  Future<void> close([int? code, String? reason]) {
    closed = true;
    if (!hangClose) release();
    return _done.future;
  }

  @override
  Future<void> get done => _done.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// SDK stream cancellation can complete in the root zone. Yield that zone
// without advancing the fake clock, so cleanup is not mistaken for a timeout.
class SessionTester {
  SessionTester(this.delegate);
  final WidgetTester delegate;
  Future<void> pump([Duration duration = Duration.zero]) async {
    await delegate.pump(duration);
    await delegate.runAsync(() => Future<void>.delayed(Duration.zero));
    await delegate.pump();
  }

  Future<void> close(NiconicoSession session) async {
    final closing = session.close();
    await pump();
    await closing;
  }

  Future<T> settle<T>(Future<T> future) async {
    await pump();
    return future;
  }
}

void sessionTest(String name, Future<void> Function(SessionTester) body) {
  testWidgets(name, (tester) => body(SessionTester(tester)), timeout: const Timeout(Duration(seconds: 20)));
}
