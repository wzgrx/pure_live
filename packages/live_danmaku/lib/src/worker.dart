import 'dart:async';
import 'dart:isolate';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/factory.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/pipeline/pipeline.dart';
import 'package:live_danmaku/src/pipeline/settings.dart';
import 'package:live_danmaku/src/transport.dart';
import 'package:live_net/live_net.dart';

/// Builds the worker's transport inside the worker isolate.
typedef DanmakuTransportFactory = DanmakuTransport Function();

/// One background isolate that runs every chat session of the app (CONN-1;
/// docs/adr/0019-danmaku-layer.md: one worker for all sessions). Connections,
/// heartbeats, decompression, decoding, filtering and sampling happen there;
/// the calling isolate only receives [DanmakuBatch]es and answers credential
/// requests with its [DanmakuCredentials].
final class DanmakuWorker {
  new _(this._isolate, this._commands, this._inbox, this._credentials) {
    _subscription = _inbox.listen(_receive);
  }

  /// Starts the worker. [proxy] must be plain data (it is copied into the
  /// worker, which builds an [IoDanmakuTransport] on it); [transport]
  /// replaces that transport (tests). [credentials] answers the worker's
  /// Bilibili token and cookie requests on this isolate.
  static Future<DanmakuWorker> spawn({
    ProxyPolicy proxy = const FixedProxyPolicy(),
    DanmakuCredentials? credentials,
    DanmakuTransportFactory? transport,
    Duration startTimeout = const Duration(seconds: 20),
  }) async {
    final inbox = ReceivePort('danmaku worker replies');
    final isolate = await Isolate.spawn(
      _workerMain,
      _Boot(inbox.sendPort, proxy, transport, startTimeout),
      debugName: 'danmaku worker',
      errorsAreFatal: false,
    );
    final broadcast = inbox.asBroadcastStream();
    final commands = await broadcast.first as SendPort;
    return DanmakuWorker._(isolate, commands, broadcast, credentials);
  }

  final Isolate _isolate;
  final SendPort _commands;
  final Stream<Object?> _inbox;
  final DanmakuCredentials? _credentials;
  late final StreamSubscription<Object?> _subscription;
  final Map<int, DanmakuSession> _sessions = {};
  var _nextToken = 0;
  var _disposed = false;

  /// Opens a chat session for [room]. Every session gets a new token; a
  /// batch reaches [DanmakuSession.batches] only when its token and room
  /// key match (CONN-4). A platform without a connector yields one
  /// [DanmakuStatus.unsupported] notice.
  DanmakuSession open(
    RoomDetail room, {
    DanmakuFilterSettings settings = const DanmakuFilterSettings(),
    DanmakuScreenBudget? budget,
  }) {
    if (_disposed) throw StateError('DanmakuWorker is disposed');
    final token = ++_nextToken;
    final session = DanmakuSession._(this, room.ref, token);
    _sessions[token] = session;
    _commands.send(_Open(token, room, settings, (budget ?? DanmakuScreenBudget.room).perSecond));
    return session;
  }

  void _receive(Object? message) {
    switch (message) {
      case final DanmakuBatch batch:
        _sessions[batch.session]?._deliver(batch);
      case _Closed(:final token):
        _sessions.remove(token)?._finished();
      case final _CredentialRequest request:
        unawaited(_answer(request));
    }
  }

  Future<void> _answer(_CredentialRequest request) async {
    final credentials = _credentials;
    try {
      if (credentials == null) throw StateError('no credentials');
      final value = switch (request.kind) {
        _CredentialKind.bilibili => await credentials.bilibili(request.room!),
        _CredentialKind.cookie => await credentials.cookie(request.platform),
      };
      _commands.send(_CredentialReply(request.id, value, null));
    } on Object catch (error) {
      _commands.send(_CredentialReply(request.id, null, '$error'));
    }
  }

  /// Closes every session and stops the isolate.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait([
      for (final session in [..._sessions.values]) session.close(),
    ]);
    _commands.send(const _Shutdown());
    await _subscription.cancel();
    _isolate.kill();
  }
}

/// One room's chat, seen from the calling isolate.
final class DanmakuSession {
  new _(this._worker, this.room, this.token);

  final DanmakuWorker _worker;

  /// The room.
  final RoomRef room;

  /// This session's token.
  final int token;

  final StreamController<DanmakuBatch> _batches = StreamController<DanmakuBatch>();
  final Completer<void> _done = Completer<void>();
  var _closing = false;

  /// Batches of this session only.
  Stream<DanmakuBatch> get batches => _batches.stream;

  void _deliver(DanmakuBatch batch) {
    // Token, room key and liveness must all match (CONN-4).
    if (_closing || batch.session != token || batch.room != room.key) return;
    _batches.add(batch);
  }

  void _finished() {
    if (!_done.isCompleted) _done.complete();
    unawaited(_batches.close());
  }

  /// FLT-6 / SMP-3 new filter settings or screen budget, applied to the
  /// next message.
  void update({DanmakuFilterSettings? settings, DanmakuScreenBudget? budget}) {
    if (_closing) return;
    _worker._commands.send(_Update(token, settings, budget?.perSecond));
  }

  /// Stops the connection; completes within 5 s even when the worker does
  /// not answer (CONN-3).
  Future<void> close() async {
    if (!_closing) {
      _closing = true;
      _worker._commands.send(_Close(token));
    }
    await _done.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _worker._sessions.remove(token);
        _finished();
      },
    );
  }
}

// ---------------------------------------------------------------- messages

final class _Boot {
  const new(this.replies, this.proxy, this.transport, this.startTimeout);

  final SendPort replies;
  final ProxyPolicy proxy;
  final DanmakuTransportFactory? transport;
  final Duration startTimeout;
}

final class _Open {
  const new(this.token, this.room, this.settings, this.budget);

  final int token;
  final RoomDetail room;
  final DanmakuFilterSettings settings;
  final double budget;
}

final class _Update {
  const new(this.token, this.settings, this.budget);

  final int token;
  final DanmakuFilterSettings? settings;
  final double? budget;
}

final class _Close {
  const new(this.token);

  final int token;
}

final class _Closed {
  const new(this.token);

  final int token;
}

final class _Shutdown {
  const new();
}

enum _CredentialKind { bilibili, cookie }

final class _CredentialRequest {
  const new(this.id, this.kind, this.platform, this.room);

  final int id;
  final _CredentialKind kind;
  final String platform;
  final RoomDetail? room;
}

final class _CredentialReply {
  const new(this.id, this.value, this.error);

  final int id;
  final Object? value;
  final String? error;
}

// ------------------------------------------------------------------ worker

void _workerMain(_Boot boot) {
  final inbox = ReceivePort('danmaku worker');
  boot.replies.send(inbox.sendPort);
  final transport = boot.transport?.call() ?? IoDanmakuTransport(proxy: boot.proxy);
  final credentials = _RemoteCredentials(boot.replies);
  final sessions = <int, _WorkerSession>{};
  inbox.listen((message) {
    switch (message) {
      case final _Open open:
        sessions[open.token] = _WorkerSession.start(
          open,
          transport: transport,
          credentials: credentials,
          replies: boot.replies,
          startTimeout: boot.startTimeout,
        );
      case final _Update update:
        sessions[update.token]?.update(update);
      case _Close(:final token):
        final session = sessions.remove(token);
        if (session == null) {
          boot.replies.send(_Closed(token));
        } else {
          unawaited(session.close().whenComplete(() => boot.replies.send(_Closed(token))));
        }
      case final _CredentialReply reply:
        credentials.complete(reply);
      case _Shutdown():
        unawaited(() async {
          await Future.wait([for (final session in sessions.values) session.close()]);
          transport.http.close();
          inbox.close();
        }());
    }
  });
}

final class _WorkerSession {
  new _(this.pipeline, this.connector);

  factory start(
    _Open open, {
    required DanmakuTransport transport,
    required DanmakuCredentials credentials,
    required SendPort replies,
    required Duration startTimeout,
  }) {
    const clock = SystemDanmakuClock();
    final pipeline = DanmakuPipeline(
      room: open.room.ref.key,
      session: open.token,
      onBatch: replies.send,
      settings: open.settings,
      budget: DanmakuScreenBudget(open.budget),
      clock: clock,
    );
    final connector = danmakuConnectorFor(
      open.room,
      transport: transport,
      credentials: credentials,
      session: open.token,
      clock: clock,
    );
    final session = _WorkerSession._(pipeline, connector);
    if (connector == null) {
      pipeline.add(
        DanmakuSystem(
          room: open.room.ref.key,
          session: open.token,
          receivedAt: clock.micros(),
          status: DanmakuStatus.unsupported,
        ),
      );
      return session;
    }
    session._subscription = connector.events.listen(pipeline.add);
    unawaited(
      connector.connect().timeout(
        startTimeout,
        onTimeout: () {
          // REG-DANMAKU-016: a start that hangs ends in the timeout state.
          pipeline.add(
            DanmakuSystem(
              room: open.room.ref.key,
              session: open.token,
              receivedAt: clock.micros(),
              status: DanmakuStatus.timeout,
            ),
          );
          unawaited(connector.close());
          return false;
        },
      ),
    );
    return session;
  }

  final DanmakuPipeline pipeline;
  final DanmakuConnector? connector;
  StreamSubscription<DanmakuEvent>? _subscription;

  void update(_Update update) {
    final settings = update.settings;
    if (settings != null) pipeline.settings = settings;
    final budget = update.budget;
    if (budget != null) pipeline.budget = DanmakuScreenBudget(budget);
  }

  Future<void> close() async {
    await connector?.close();
    await _subscription?.cancel();
    pipeline.close();
  }
}

/// Forwards credential requests to the calling isolate.
final class _RemoteCredentials implements DanmakuCredentials {
  new(this._replies);

  final SendPort _replies;
  final Map<int, Completer<Object?>> _pending = {};
  var _next = 0;

  Future<Object?> _ask(_CredentialKind kind, String platform, RoomDetail? room) {
    final id = ++_next;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _replies.send(_CredentialRequest(id, kind, platform, room));
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('credential request');
      },
    );
  }

  void complete(_CredentialReply reply) {
    final completer = _pending.remove(reply.id);
    if (completer == null) return;
    final error = reply.error;
    if (error != null) {
      completer.completeError(StateError(error));
    } else {
      completer.complete(reply.value);
    }
  }

  @override
  Future<BilibiliDanmakuInfo> bilibili(RoomDetail room) async =>
      (await _ask(_CredentialKind.bilibili, room.ref.platform, room))! as BilibiliDanmakuInfo;

  @override
  Future<String?> cookie(String platform) async => await _ask(_CredentialKind.cookie, platform, null) as String?;
}
