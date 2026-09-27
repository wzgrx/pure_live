import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/transport.dart';
import 'package:meta/meta.dart';

/// Shared lifecycle of the connectors: one run at a time, a generation that
/// makes every callback of an old run stale, status notices, bounded close.
abstract base class ConnectorBase implements DanmakuConnector {
  /// Creates the base.
  new({required this.detail, required this.transport, this.session = 0, DanmakuClock? clock})
    : clock = clock ?? const SystemDanmakuClock();

  /// The room as the adapter returned it.
  final RoomDetail detail;

  /// Network access.
  final DanmakuTransport transport;

  /// Time source.
  final DanmakuClock clock;

  @override
  final int session;

  @override
  RoomRef get room => detail.ref;

  final StreamController<DanmakuEvent> _events = StreamController<DanmakuEvent>();
  var _generation = 0;
  var _closed = false;
  Future<void>? _run;
  Completer<bool>? _ready;
  final Set<void Function()> _stopHooks = {};

  @override
  Stream<DanmakuEvent> get events => _events.stream;

  /// Whether the run started in [generation] was superseded or closed.
  @protected
  bool isStale(int generation) => _closed || generation != _generation;

  /// Runs [hook] when [close] is called (at once when already closed);
  /// the returned function unregisters it. Hooks are removed after use, so
  /// long polling does not pile up listeners.
  @protected
  void Function() onStop(void Function() hook) {
    if (_closed) {
      hook();
      return () {};
    }
    _stopHooks.add(hook);
    return () => _stopHooks.remove(hook);
  }

  /// A decode context stamped now.
  @protected
  DecodeContext context() =>
      DecodeContext(room: room.key, session: session, receivedAt: clock.micros(), now: clock.now());

  /// Emits [event] unless [generation] is stale.
  @protected
  void emit(int generation, DanmakuEvent event) {
    if (!isStale(generation)) _events.add(event);
  }

  /// Emits a status notice.
  @protected
  void status(int generation, DanmakuStatus status, [List<String> args = const []]) => emit(
    generation,
    DanmakuSystem(room: room.key, session: session, receivedAt: clock.micros(), status: status, args: args),
  );

  /// Marks the run as joined (completes [connect]).
  @protected
  void joined(int generation) {
    if (isStale(generation)) return;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.complete(true);
  }

  /// Ends the run in the terminal state with [reason].
  @protected
  void terminal(int generation, String reason, [String? detail]) {
    if (isStale(generation)) return;
    status(generation, DanmakuStatus.closed, [reason, ?detail]);
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.complete(false);
  }

  /// Waits [delay] unless [close] comes first; true when still current.
  @protected
  Future<bool> pause(int generation, Duration delay) async {
    if (isStale(generation)) return false;
    if (delay > Duration.zero) {
      final wake = Completer<void>();
      void done() {
        if (!wake.isCompleted) wake.complete();
      }

      final timer = Timer(delay, done);
      final remove = onStop(done);
      await wake.future;
      timer.cancel();
      remove();
    }
    return !isStale(generation);
  }

  /// The platform loop for one run; returns when the run ends (terminal or
  /// stale).
  @protected
  Future<void> run(int generation);

  @override
  Future<bool> connect() {
    if (_closed) throw StateError('Connector for ${room.key} is closed');
    final ready = _ready;
    if (_run != null && ready != null) return ready.future;
    final generation = ++_generation;
    final next = Completer<bool>();
    _ready = next;
    _run = () async {
      try {
        await run(generation);
      } on Object catch (error) {
        terminal(generation, 'failed', '$error');
      } finally {
        if (!next.isCompleted) next.complete(false);
        if (generation == _generation) _run = null;
      }
    }();
    return next.future;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _generation++;
    for (final hook in [..._stopHooks]) {
      hook();
    }
    _stopHooks.clear();
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.complete(false);
    final run = _run;
    if (run != null) {
      await run.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
    // A single-subscription stream nobody listens to never delivers its
    // done event, so the close future is not awaited.
    unawaited(_events.close());
  }
}
