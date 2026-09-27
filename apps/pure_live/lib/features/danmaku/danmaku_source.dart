import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live_app/core/proxy.dart';
import 'package:pure_live_app/core/sites.dart';

/// One room's chat connection as the room page sees it: batches in, filter
/// and budget updates out (spec/modules/danmaku.md CONN-2, FLT-6, SMP-3).
abstract interface class DanmakuFeed {
  /// Batches of this connection only (CONN-4: token and room key checked).
  Stream<DanmakuBatch> get batches;

  /// New filter settings or screen budget, applied to the next message.
  void update({DanmakuFilterSettings? settings, DanmakuScreenBudget? budget});

  /// Stops the connection; completes within 5 s (CONN-3).
  Future<void> close();
}

/// Opens chat connections: the app's one background worker, a fake in tests.
abstract interface class DanmakuSource {
  /// Connects to [room]'s chat.
  Future<DanmakuFeed> open(
    RoomDetail room, {
    required DanmakuFilterSettings settings,
    required DanmakuScreenBudget budget,
  });
}

/// The app's chat worker (ADR 0019: one isolate for every session), spawned
/// on the first room that needs it and stopped with the app.
final class WorkerDanmakuSource implements DanmakuSource {
  new(this._spawn);

  final Future<DanmakuWorker> Function() _spawn;
  Future<DanmakuWorker>? _worker;
  var _disposed = false;

  @override
  Future<DanmakuFeed> open(
    RoomDetail room, {
    required DanmakuFilterSettings settings,
    required DanmakuScreenBudget budget,
  }) async {
    if (_disposed) throw StateError('The danmaku worker is stopped');
    final worker = await (_worker ??= _spawn());
    return _WorkerFeed(worker.open(room, settings: settings, budget: budget));
  }

  /// Stops the worker and every session in it.
  Future<void> dispose() async {
    _disposed = true;
    final worker = _worker;
    _worker = null;
    if (worker != null) await (await worker).dispose();
  }
}

final class _WorkerFeed implements DanmakuFeed {
  new(this._session);

  final DanmakuSession _session;

  @override
  Stream<DanmakuBatch> get batches => _session.batches;

  @override
  void update({DanmakuFilterSettings? settings, DanmakuScreenBudget? budget}) =>
      _session.update(settings: settings, budget: budget);

  @override
  Future<void> close() => _session.close();
}

/// The chat source of the app. Credentials stay on this isolate: Bilibili
/// tokens and the Douyin session cookie come from the site adapters, other
/// cookies from the vault (ADR 0019 decision 2).
final Provider<DanmakuSource> danmakuSourceProvider = Provider<DanmakuSource>((ref) {
  final sites = ref.watch(sitesProvider);
  final cookies = ref.watch(cookieVaultProvider);
  final bilibili = sites['bilibili']?.info;
  final douyin = sites['douyin']?.info;
  // Chat goes through the same proxy as the adapters (F-SET-07).
  final proxy = ref.watch(proxyPolicyProvider);
  final source = WorkerDanmakuSource(
    () => DanmakuWorker.spawn(
      proxy: proxy,
      credentials: SiteDanmakuCredentials(
        bilibiliSite: bilibili is BilibiliSite ? bilibili : null,
        douyinSite: douyin is DouyinSite ? douyin : null,
        cookies: cookies,
      ),
    ),
  );
  ref.onDispose(() => unawaited(source.dispose()));
  return source;
});
