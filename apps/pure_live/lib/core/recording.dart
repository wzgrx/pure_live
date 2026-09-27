import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live_app/core/proxy.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';

/// Recorder settings from the registry (spec/modules/record.md §20).
RecordSettings recordSettingsFrom(SettingsStore s) => RecordSettings(
  defaultQuality: switch (s.get(Settings.recordDefaultQuality)) {
    QualityPreference.original => RecordQuality.original,
    QualityPreference.bluRay8M => RecordQuality.bluRay8M,
    QualityPreference.bluRay4M => RecordQuality.bluRay4M,
    QualityPreference.superHigh => RecordQuality.superHd,
    QualityPreference.smooth => RecordQuality.smooth,
  },
  maxConcurrent: s.get(Settings.recordMaxConcurrent),
  autoReconnect: s.get(Settings.recordAutoReconnect),
  maxRetries: s.get(Settings.recordMaxRetries),
  retryDelay: Duration(seconds: s.get(Settings.recordRetryDelay)),
  polling: s.get(Settings.recordPolling),
  liveCheckInterval: Duration(seconds: s.get(Settings.recordLiveCheckInterval)),
  backoff: s.get(Settings.recordBackoff),
  maxCheckInterval: Duration(seconds: s.get(Settings.recordMaxCheckInterval)),
  resumeOnLaunch: s.get(Settings.recordResumeOnLaunch),
  readTimeout: Duration(seconds: s.get(Settings.recordReadTimeout)),
  danmaku: s.get(Settings.recordDanmaku),
  splitMinutes: s.get(Settings.recordSplitMinutes),
  splitMegabytes: s.get(Settings.recordSplitMegabytes),
  remuxToMp4: s.get(Settings.recordRemuxToMp4),
  keepSourceAfterRemux: s.get(Settings.recordKeepSourceAfterRemux),
  // The "cache limit" caps the recording folder (§15).
  storageLimitMegabytes: s.get(Settings.recordCacheLimitEnabled) ? s.get(Settings.recordCacheLimitMb) : 0,
);

/// Chat for recordings through live_danmaku's connectors (§17): plain chats only.
final class DanmakuRecordChat implements RecordChatSource {
  const new(this._sites, this._cookies, [this._proxy = const FixedProxyPolicy()]);

  final Map<String, PlatformSite> _sites;
  final CookieVault _cookies;
  final ProxyPolicy _proxy;

  @override
  Stream<RecordChatMessage> connect(RoomDetail room) {
    final raw = _sites[room.ref.platform]?.raw;
    final connector = danmakuConnectorFor(
      room,
      transport: IoDanmakuTransport(proxy: _proxy),
      credentials: SiteDanmakuCredentials(
        bilibiliSite: raw is BilibiliSite ? raw : null,
        douyinSite: raw is DouyinSite ? raw : null,
        cookies: _cookies,
      ),
    );
    if (connector == null) return const Stream.empty();
    late final StreamController<RecordChatMessage> controller;
    controller = StreamController<RecordChatMessage>(
      onListen: () async {
        controller
            .addStream(
              connector.events
                  .where((e) => e is DanmakuChat)
                  .cast<DanmakuChat>()
                  .map(
                    (chat) => RecordChatMessage(
                      text: chat.text,
                      id: chat.id,
                      userId: chat.userId,
                      userName: chat.userName,
                      color: chat.color,
                      sentAt: chat.sentAt,
                    ),
                  ),
            )
            .ignore();
        if (!await connector.connect()) await controller.close();
      },
      onCancel: connector.close,
    );
    return controller.stream;
  }
}

/// Folders the recorder uses, resolved in main() before the first frame.
final class RecordPaths {
  const new({required this.dataRoot, required this.defaultRecordRoot});

  /// The app's data folder (`DB/record_tasks.json` lives under it).
  final String dataRoot;

  /// Where recordings go unless the user chose a folder: on Android the
  /// app-specific external folder, reachable from a file manager.
  final String defaultRecordRoot;

  /// Resolves the folders for this platform.
  static Future<RecordPaths> resolve(String dataRoot) async {
    final external = Platform.isAndroid ? await getExternalStorageDirectory() : null;
    return RecordPaths(
      dataRoot: dataRoot,
      defaultRecordRoot: '${external?.path ?? dataRoot}${Platform.pathSeparator}RECORDS',
    );
  }
}

/// Paths; main() overrides it.
final Provider<RecordPaths> recordPathsProvider = Provider<RecordPaths>(
  (ref) => throw StateError('RecordPaths are resolved in main()'),
);

/// The recorder. The app watches it at startup so crash recovery runs in the
/// background (§14.1); record.* setting changes apply immediately.
final Provider<RecordManager> recordManagerProvider = Provider<RecordManager>((ref) {
  final paths = ref.watch(recordPathsProvider);
  final settings = ref.watch(storeProvider).settings;
  final sites = ref.watch(sitesProvider);
  final chosen = settings.get(Settings.recordDirectory);
  final manager = RecordManager(
    rooms: SiteRecordRooms((platform) => sites[platform]?.raw),
    store: JsonFileRecordTaskStore(
      '${paths.dataRoot}${Platform.pathSeparator}DB${Platform.pathSeparator}record_tasks.json',
    ),
    root: RecordRoot.resolve(defaultRoot: paths.defaultRecordRoot, chosen: chosen.isEmpty ? null : chosen),
    settings: recordSettingsFrom(settings),
    opener: httpRecordOpener(proxy: ref.watch(proxyPolicyProvider)),
    // Finished segments to MP4 in a background isolate (ADR 0021).
    remuxer: const IsolateRemuxer(FlvToMp4Remuxer()),
    // Read per session, so switching the setting applies to the next one.
    transliterate: (text) => settings.get(Settings.recordPinyinFolders) ? pinyinFolderName(text) : text,
    chat: DanmakuRecordChat(sites, ref.watch(cookieVaultProvider), ref.watch(proxyPolicyProvider)),
  );
  unawaited(manager.init());
  final changes = settings.changes.where((id) => id.startsWith('record.')).listen((_) {
    unawaited(manager.updateSettings(recordSettingsFrom(settings)));
  });
  // Android: a foreground service keeps recordings going in the background
  // (F-REC-06, spec/modules/record.md §16.1).
  final keepAlive = Platform.isAndroid ? RecordKeepAlive(manager, MethodRecordServiceChannel()) : null;
  final lifecycle = keepAlive == null ? null : AppLifecycleListener(onResume: keepAlive.resumed);
  ref.onDispose(() {
    unawaited(changes.cancel());
    lifecycle?.dispose();
    unawaited(keepAlive?.dispose());
    unawaited(manager.dispose());
  });
  return manager;
});

/// The notification of the Android recording service: title and text.
typedef RecordNotice = ({String title, String text});

/// What the Android recording service shows for [tasks] (spec/modules/record.md
/// §16.1): "正在录制 N 个直播间" with the streamers' names, or
/// "正在处理录制文件" while only finalizing tasks are left; null when no task
/// holds a session, which stops the service.
RecordNotice? recordServiceNotice(Iterable<RecordTask> tasks) {
  final recording = [
    for (final task in tasks)
      if (task.state.active && task.state != RecordState.finalizing) task,
  ];
  final finishing = tasks.where((task) => task.state == RecordState.finalizing).length;
  if (recording.isEmpty) {
    return finishing == 0 ? null : (title: '正在处理录制文件', text: '$finishing 个录制正在收尾，完成后通知会消失');
  }
  final names = [for (final task in recording) _taskName(task)];
  final shown = names.length > 3 ? '${names.take(3).join('、')} 等' : names.join('、');
  return (title: '正在录制 ${recording.length} 个直播间', text: finishing == 0 ? shown : '$shown；$finishing 个正在收尾');
}

String _taskName(RecordTask task) => task.snapshot.anchorName.isEmpty ? task.room.roomId : task.snapshot.anchorName;

/// The native side of background recording (Android `RecordService.kt`).
abstract interface class RecordServiceChannel {
  /// Starts or refreshes the service with [notice]; false when Android
  /// refused to start it (for example from the background).
  Future<bool> update(RecordNotice notice);

  /// Stops the service and releases the locks.
  Future<void> stop();

  /// Sets what runs when the system timed the service out (Android 15+
  /// `onTimeout`); null removes it.
  void handleTimeout(Future<void> Function()? handler);
}

/// [RecordServiceChannel] over the method channel `purelive/record`.
final class MethodRecordServiceChannel implements RecordServiceChannel {
  /// Creates the channel.
  new([this._channel = const MethodChannel('purelive/record')]);

  final MethodChannel _channel;

  @override
  Future<bool> update(RecordNotice notice) async =>
      await _channel.invokeMethod<bool>('update', {'title': notice.title, 'text': notice.text}) ?? false;

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');

  @override
  void handleTimeout(Future<void> Function()? handler) => _channel.setMethodCallHandler(
    handler == null
        ? null
        : (call) async {
            if (call.method == 'onTimeout') await handler();
          },
  );
}

/// Keeps Android recordings alive in the background (F-REC-06,
/// spec/modules/record.md §16.1): the service runs while any task holds a
/// session (`RecordManager.activeCountChanges`), its notification follows the
/// tasks, and it stops once the last task's final state is stored. Driven by
/// the count, not by per-task leases, so an old session ending never stops a
/// new one.
///
/// If the system times the service out, every active task is finished as
/// "后台运行时间被系统用尽" (`interruptAll`) while the native side still holds
/// the wake lock, then the service stops; it starts again only after the app
/// has been in front (which also resets Android's timer).
final class RecordKeepAlive {
  /// Starts following the manager's tasks.
  new(this._manager, this._channel) {
    _channel.handleTimeout(_timedOut);
    _subscriptions = [_manager.activeCountChanges.listen((_) => _sync()), _manager.updates.listen((_) => _sync())];
    _sync();
  }

  final RecordManager _manager;
  final RecordServiceChannel _channel;
  late final List<StreamSubscription<Object?>> _subscriptions;
  RecordNotice? _shown;
  Future<void> _calls = Future.value();
  bool _blocked = false;
  bool _draining = false;

  /// Whether the system timed the service out and the app has not been in
  /// front since.
  bool get blocked => _blocked;

  void _sync() {
    if (_draining) return;
    final notice = _blocked ? null : recordServiceNotice(_manager.tasks);
    if (notice == _shown) return;
    _shown = notice;
    _calls = _calls
        .then((_) async {
          if (notice != null) {
            await _channel.update(notice);
          } else {
            // The final state is stored before the process may lose its keep-alive (§13).
            await _manager.flush();
            if (_shown == null) await _channel.stop();
          }
        })
        .catchError((Object _) {});
  }

  Future<void> _timedOut() async {
    _blocked = true;
    _draining = true;
    try {
      await _manager.interruptAll();
    } finally {
      _draining = false;
    }
    _sync();
    await _calls;
  }

  /// The app is in front again: the service may start again.
  void resumed() {
    if (!_blocked) return;
    _blocked = false;
    _sync();
  }

  /// Stops following the manager and the service.
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _channel.handleTimeout(null);
    if (_shown != null) {
      _shown = null;
      await _calls;
      await _channel.stop();
    }
  }
}

/// Watches the recording state of one room, for the room page's button.
final StreamProviderFamily<RecordTask?, String> recordTaskProvider = StreamProvider.autoDispose
    .family<RecordTask?, String>((ref, key) async* {
      final manager = ref.watch(recordManagerProvider);
      yield manager.tasks.where((t) => t.key == key).firstOrNull;
      yield* manager.watch(key);
    });

/// A streamer name as a pinyin folder name (F-REC-03, record.md §path): no
/// tones, no separators, lower case, ASCII letters, digits and `_` only
/// (3.x `PathHelper.toSafePinyin`); `unknown` when nothing is left.
String pinyinFolderName(String text) {
  final String pinyin;
  try {
    pinyin = PinyinHelper.getPinyinE(text, separator: '', defPinyin: '');
  } on Object {
    return 'unknown';
  }
  final ascii = pinyin
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp('[^a-zA-Z0-9_]'), '')
      .replaceAll(RegExp('_+'), '_')
      .toLowerCase();
  return ascii.replaceAll('_', '').isEmpty ? 'unknown' : ascii;
}
