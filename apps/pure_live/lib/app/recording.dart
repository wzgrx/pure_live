import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the recording centre's tasks are kept (3.x `recorder_tasks`; the
/// import left 3.x's list in `legacy_values`).
const String recorderTasksKey = 'recorder.tasks';

/// The task list of window [instanceId]: [recorderTasksKey] for the main
/// window; an extra desktop window shares the data (docs/ui/compare/U.13
/// c14) but records on its own, so its list is kept apart (each list is
/// written whole) and dropped when the window closes.
String recorderTasksKeyFor(String instanceId) => instanceId.isEmpty ? recorderTasksKey : '$recorderTasksKey.$instanceId';

/// How many of [tasks] hold a recording (preparing, writing, reconnecting
/// or joining the file).
int activeRecordings(Iterable<RecordTask> tasks) => tasks.where((task) => task.status.isActive).length;

/// The input openers of the recipe platforms (FC2, Bigo, niconico): without
/// them those rooms cannot be recorded (M8).
List<RecipeOpener> recipeOpeners(SiteRegistry sites) => [
  BigoRecipeOpener(sites.of(SiteIds.bigo) as BigoSite),
  Fc2RecipeOpener(sites.of(SiteIds.fc2Live) as Fc2LiveSite),
  NiconicoRecipeOpener(sites.of(SiteIds.niconico) as NiconicoSite),
];

/// Opens a room's chat for recording (M8.1, 3.x
/// `RecorderController._connectRecordingDanmaku`) over live_danmaku: the
/// platform's connection, the duplicate and backlog gate and the user's
/// block lists. The display-only filters (repeated text, similarity) stay
/// off: the file keeps what was said.
RecordChatConnector recordChatConnector({
  required SiteRegistry sites,
  required DanmakuRegistry danmaku,
  required LiveStore store,
  Duration timeout = const Duration(seconds: 20),
}) => (task, {required onMessage, required onEnded}) async {
  if (!danmaku.supports(task.platform)) return null;
  final site = sites.maybeOf(task.platform);
  if (site == null) return null;
  final room = await site.getRoomDetail(roomId: task.roomId).timeout(timeout);
  final filter = DanmakuMessageFilter(
    settings: DanmakuFilterSettings(
      blockedUsers: await store.blockLists.list(BlockKind.user),
      blockedKeywords: await store.blockLists.list(BlockKind.keyword),
    ),
  );
  final connection = danmaku.connectionFor(task.platform);
  var joined = false;
  final events = connection.events.listen((event) {
    switch (event) {
      case DanmakuReceived(:final message) when message.type == LiveMessageType.chat && filter.accepts(message):
        onMessage(message);
      case DanmakuClosed() when joined:
        onEnded();
      case _:
    }
  });
  Future<void> stop() async {
    await events.cancel();
    await connection.close();
  }

  try {
    await connection.connect(room.danmakuData).timeout(timeout);
  } on Object {
    await stop();
    rethrow;
  }
  if (connection.status == DanmakuStatus.closed) {
    await stop();
    return null;
  }
  joined = true;
  return RecordChatConnection(stop: stop);
};

/// The default recording folder: Android's app folder on external storage
/// (no permission needed), else `Records` in the data folder.
Future<String> defaultRecordDirectory(Directory dataRoot) async {
  if (Platform.isAndroid) {
    final external = await getExternalStorageDirectory();
    if (external != null) return p.join(external.path, 'Records');
  }
  return p.join(dataRoot.path, 'Records');
}

/// The recording settings: live_store's `Settings.recorder` (3.x's Hive
/// keys, carried by backups since M8.1) read as live_record's
/// [RecordSettings].
///
/// Reads are synchronous (the recorder asks on every decision). [load] moves
/// the values the app kept before M8.1 into the store once: the user's v4
/// values from `meta[recorder.settings]` first, then 3.x's values that the
/// import parked in `legacy_values` (where the store has none yet).
final class RecordSettingsStore {
  /// Creates the store over the app's [LiveStore].
  new(this._store);

  /// The meta key where M13.15 kept the values (one JSON object, 3.x keys);
  /// [load] empties it.
  static const legacyStorageKey = 'recorder.settings';

  final LiveStore _store;
  Future<void>? _loading;

  SettingsStore get _settings => _store.settings;

  /// The settings now.
  RecordSettings get current => of(_settings);

  /// The settings after every change of a recorder setting (a restore or a
  /// reset included).
  Stream<RecordSettings> get changes => _settings.changes.where(Settings.recorder.contains).map((_) => current);

  /// Moves the values kept before M8.1 into the store (once).
  Future<void> load() => _loading ??= _migrate();

  Future<void> _migrate() async {
    final text = await _store.meta.get(legacyStorageKey);
    if (text != null) {
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
      if (decoded is Map) {
        final values = Map<String, Object?>.from(decoded);
        final normalized = toValues(fromValues(values));
        await _settings.setAll({
          for (final setting in Settings.recorder)
            if (values.containsKey(setting.key)) setting: normalized[setting.key]!,
        });
      }
      await _store.meta.set(legacyStorageKey, null);
    }
    await LegacyMigration.adoptLegacyValues(_store);
  }

  /// Stores [value] for one of `Settings.recorder`.
  Future<void> set<T extends Object>(Setting<T> setting, T value) => _settings.set(setting, value);

  /// The recorder's settings from [settings].
  static RecordSettings of(SettingsStore settings) => RecordSettings(
    segmentTime: settings.get(Settings.recordSegmentTime),
    maxTaskCount: settings.get(Settings.recordMaxTaskCount),
    autoReconnect: settings.get(Settings.recordAutoReconnect),
    maxCacheMB: settings.get(Settings.recordMaxCacheMB),
    enableCacheLimit: settings.get(Settings.recordEnableCacheLimit),
    savePath: settings.get(Settings.recordSavePath).trim(),
    defaultQuality: settings.get(Settings.recordDefaultQuality),
    maxRetryCount: settings.get(Settings.recordMaxRetryCount),
    retryDelay: settings.get(Settings.recordRetryDelay),
    enablePolling: settings.get(Settings.recordEnablePolling),
    liveCheckInterval: settings.get(Settings.recordLiveCheckInterval),
    enableBackoff: settings.get(Settings.recordEnableBackoff),
    maxCheckInterval: settings.get(Settings.recordMaxCheckInterval),
    autoStartOnBoot: settings.get(Settings.recordAutoStartOnBoot),
    preferBestStream: settings.get(Settings.recordPreferBestStream),
    rwTimeout: settings.get(Settings.recordRwTimeout),
    threadQueueSize: settings.get(Settings.recordThreadQueueSize),
    usePinyinForFolder: settings.get(Settings.recordPinyinFolders),
    recordDanmaku: settings.get(Settings.recordDanmaku),
  );

  /// Settings from values under 3.x's Hive keys (the pre-M8.1 meta object;
  /// lenient about types like 3.x's `HivePrefUtil`).
  static RecordSettings fromValues(Map<String, Object?> values) {
    final defaults = RecordSettings();
    int integer(Setting<Object> setting, int fallback) => switch (values[setting.key]) {
      final num value => value.toInt(),
      final String value => int.tryParse(value.trim()) ?? fallback,
      _ => fallback,
    };
    bool flag(Setting<Object> setting, {required bool fallback}) => switch (values[setting.key]) {
      final bool value => value,
      final num value => value != 0,
      final String value => switch (value.trim().toLowerCase()) {
        'true' || '1' => true,
        'false' || '0' => false,
        _ => fallback,
      },
      _ => fallback,
    };
    String text(Setting<Object> setting, String fallback) => switch (values[setting.key]) {
      final String value => value,
      _ => fallback,
    };
    return RecordSettings(
      segmentTime: integer(Settings.recordSegmentTime, defaults.segmentTime),
      maxTaskCount: integer(Settings.recordMaxTaskCount, defaults.maxTaskCount),
      autoReconnect: flag(Settings.recordAutoReconnect, fallback: defaults.autoReconnect),
      maxCacheMB: integer(Settings.recordMaxCacheMB, defaults.maxCacheMB),
      enableCacheLimit: flag(Settings.recordEnableCacheLimit, fallback: defaults.enableCacheLimit),
      savePath: text(Settings.recordSavePath, defaults.savePath).trim(),
      defaultQuality: text(Settings.recordDefaultQuality, defaults.defaultQuality),
      maxRetryCount: integer(Settings.recordMaxRetryCount, defaults.maxRetryCount),
      retryDelay: integer(Settings.recordRetryDelay, defaults.retryDelay),
      enablePolling: flag(Settings.recordEnablePolling, fallback: defaults.enablePolling),
      liveCheckInterval: integer(Settings.recordLiveCheckInterval, defaults.liveCheckInterval),
      enableBackoff: flag(Settings.recordEnableBackoff, fallback: defaults.enableBackoff),
      maxCheckInterval: integer(Settings.recordMaxCheckInterval, defaults.maxCheckInterval),
      autoStartOnBoot: flag(Settings.recordAutoStartOnBoot, fallback: defaults.autoStartOnBoot),
      preferBestStream: flag(Settings.recordPreferBestStream, fallback: defaults.preferBestStream),
      rwTimeout: integer(Settings.recordRwTimeout, defaults.rwTimeout),
      threadQueueSize: integer(Settings.recordThreadQueueSize, defaults.threadQueueSize),
      usePinyinForFolder: flag(Settings.recordPinyinFolders, fallback: defaults.usePinyinForFolder),
      recordDanmaku: flag(Settings.recordDanmaku, fallback: defaults.recordDanmaku),
    );
  }

  /// [settings] under 3.x's Hive keys.
  static Map<String, Object> toValues(RecordSettings settings) => {
    Settings.recordSegmentTime.key: settings.segmentTime,
    Settings.recordMaxTaskCount.key: settings.maxTaskCount,
    Settings.recordAutoReconnect.key: settings.autoReconnect,
    Settings.recordMaxCacheMB.key: settings.maxCacheMB,
    Settings.recordEnableCacheLimit.key: settings.enableCacheLimit,
    Settings.recordSavePath.key: settings.savePath,
    Settings.recordDefaultQuality.key: settings.defaultQuality,
    Settings.recordMaxRetryCount.key: settings.maxRetryCount,
    Settings.recordRetryDelay.key: settings.retryDelay,
    Settings.recordEnablePolling.key: settings.enablePolling,
    Settings.recordLiveCheckInterval.key: settings.liveCheckInterval,
    Settings.recordEnableBackoff.key: settings.enableBackoff,
    Settings.recordMaxCheckInterval.key: settings.maxCheckInterval,
    Settings.recordAutoStartOnBoot.key: settings.autoStartOnBoot,
    Settings.recordPreferBestStream.key: settings.preferBestStream,
    Settings.recordRwTimeout.key: settings.rwTimeout,
    Settings.recordThreadQueueSize.key: settings.threadQueueSize,
    Settings.recordPinyinFolders.key: settings.usePinyinForFolder,
    Settings.recordDanmaku.key: settings.recordDanmaku,
  };
}

/// The keep-alive of the platform, with 3.x's rule that a refused or
/// interrupted keep-alive is retried only after a user's start
/// (`RecorderBackgroundService.allowUserRetry`).
abstract interface class RecordingKeepAlive implements RecordKeepAlive {
  /// Lets the next acquire try the platform again (a user's start).
  void allowUserRetry();
}

/// Recording in the app (3.x `RecorderController`, `RecordSettingsController`
/// and `CacheService` as the pages used them): the settings, the managed
/// directory and the recorder.
///
/// [recorder] is null where this build has no FFmpeg; the settings and the
/// directory still work. The live room's "record" button (M13.3b) calls
/// [addTask], [taskFor], [startTask] and the recorder's `stopTask` and
/// `removeTask`.
final class AppRecording {
  /// Creates recording over its parts; [start] loads and restores.
  new({
    required this.settings,
    required this.storage,
    this.recorder,
    this.keepAlive,
    this.chat,
    this._store,
    this._storageAccess,
    this.tasksKey = recorderTasksKey,
  });

  /// Where the tasks are kept ([recorderTasksKeyFor]).
  final String tasksKey;

  /// Settings.
  final RecordSettingsStore settings;

  /// The managed directory (the recorder's own instance, so folders in use
  /// stay protected from cleanup).
  final RecordStorage storage;

  /// The recorder; null without FFmpeg.
  final Recorder? recorder;

  /// The platform keep-alive (Android's foreground service).
  final RecordingKeepAlive? keepAlive;

  /// Saves the chat beside recordings when the setting is on (M8.1); null
  /// without a recorder or without danmaku.
  final RecordChatRecorder? chat;

  final LiveStore? _store;
  final Future<bool> Function({required bool interactive})? _storageAccess;
  StreamSubscription<RecordSettings>? _settingsChanges;
  StreamSubscription<List<RecordTask>>? _taskChanges;
  Future<void>? _loaded;
  Future<void>? _started;

  /// Whether this build can record.
  bool get available => recorder != null;

  /// Loads the settings (once; pages wait for it).
  Future<void> loadSettings() => _loaded ??= settings.load();

  /// Loads the settings, then restores the saved tasks (once; the app does
  /// this at start).
  Future<void> start() => _started ??= _start();

  Future<void> _start() async {
    await loadSettings();
    final recorder = this.recorder;
    if (recorder == null) return;
    final chat = this.chat;
    _settingsChanges = settings.changes.listen((_) {
      recorder.settingsChanged();
      chat?.sync(recorder.tasks);
    });
    if (chat != null) _taskChanges = recorder.changes.listen(chat.sync);
    final store = _store;
    if (store != null) await recorder.restore(await savedRecorderTasks(store, key: tasksKey));
  }

  /// How many tasks hold a recording now (preparing, writing, reconnecting
  /// or joining the file): leaving the app stops them, so the close dialog
  /// and the tray say so (docs/ui/compare/U.13 c9).
  int get activeCount => activeRecordings(recorder?.tasks ?? const []);

  /// [activeCount] now and after every change of the tasks.
  Stream<int> get activeCounts {
    final recorder = this.recorder;
    if (recorder == null) return Stream.value(0);
    return Stream<int>.multi((controller) {
      controller.add(activeCount);
      final subscription = recorder.changes.map(activeRecordings).listen(controller.add);
      controller.onCancel = subscription.cancel;
    }).distinct();
  }

  /// The task of [room], if any.
  RecordTask? taskFor(LiveRoom room) =>
      recorder?.tasks.where((task) => task.platform == room.platform && task.roomId == room.roomId).firstOrNull;

  /// Adds (or returns) the task of [room] as the user asked (3.x
  /// `addTask`): starts it now, or waits for the room to go live.
  Future<RecordTask?> addTask(LiveRoom room, {bool startImmediately = true}) async {
    final recorder = this.recorder;
    if (recorder == null) return null;
    keepAlive?.allowUserRetry();
    return await recorder.addTask(room, startImmediately: startImmediately);
  }

  /// Starts [task] as the user asked (3.x `forceStartTask`).
  Future<bool> startTask(RecordTask task) async {
    final recorder = this.recorder;
    if (recorder == null) return false;
    keepAlive?.allowUserRetry();
    return await recorder.startTask(task);
  }

  /// Asks for storage access when the managed directory is not writable
  /// (Android; a user action may show the system screen).
  Future<bool> ensureStorageAccess({bool interactive = true}) async =>
      await _storageAccess?.call(interactive: interactive) ?? true;

  /// Stops the recorder's work (tasks resume after the next start) and
  /// writes the settings.
  Future<void> dispose() async {
    await _settingsChanges?.cancel();
    try {
      await recorder?.dispose();
    } on Object catch (error, stack) {
      log('Recorder shutdown failed', name: 'AppRecording', error: error, stackTrace: stack);
    }
    await _taskChanges?.cancel();
    await chat?.dispose();
  }
}

/// Recording over the app's parts. Without [ffmpeg] there is no recorder
/// (tests, platforms without the FFmpeg bundle); without [danmaku] no chat
/// is saved.
AppRecording buildAppRecording({
  required LiveStore store,
  required SiteRegistry sites,
  required ProxyPolicy proxy,
  required Directory dataRoot,
  FfmpegRunner? ffmpeg,
  DanmakuRegistry? danmaku,
  RecordChatConnector? chatConnector,
  RecordingKeepAlive? keepAlive,
  Future<bool> Function(RecordStorage storage, {required bool interactive})? storageAccess,
  String? Function()? caFile,
  String tasksKey = recorderTasksKey,
}) {
  final settings = RecordSettingsStore(store);
  final storage = RecordStorage(
    defaultDirectory: () => defaultRecordDirectory(dataRoot),
    configuredPath: () => settings.current.savePath,
    isAndroid: Platform.isAndroid,
  );
  Future<bool> access({required bool interactive}) =>
      storageAccess?.call(storage, interactive: interactive) ?? Future.value(true);
  final recorder = ffmpeg == null
      ? null
      : Recorder(
          sites: sites.maybeOf,
          ffmpeg: ffmpeg,
          storage: storage,
          settings: () => settings.current,
          inputs: RecordInputOpener(proxy: proxy, recipes: recipeOpeners(sites)),
          persist: (json) => store.meta.set(tasksKey, json),
          keepAlive: keepAlive,
          storageAccess: access,
          caFile: caFile,
        );
  final connect =
      chatConnector ?? (danmaku == null ? null : recordChatConnector(sites: sites, danmaku: danmaku, store: store));
  return AppRecording(
    settings: settings,
    storage: storage,
    recorder: recorder,
    keepAlive: keepAlive,
    chat: recorder == null || connect == null
        ? null
        : RecordChatRecorder(enabled: () => settings.current.recordDanmaku, connect: connect),
    store: store,
    storageAccess: access,
    tasksKey: tasksKey,
  );
}

/// The saved task list under [key]: v4's, else (the main window's list)
/// the one imported from 3.x.
Future<String?> savedRecorderTasks(LiveStore store, {String key = recorderTasksKey}) async {
  final saved = await store.meta.get(key);
  if (saved != null || key != recorderTasksKey) return saved;
  final legacy = await store.meta.legacyValue('recorder_tasks');
  return switch (legacy) {
    null => null,
    final String text => text,
    _ => jsonEncode(legacy),
  };
}
