import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the recording centre's tasks are kept (3.x `recorder_tasks`; the
/// import left 3.x's list in `legacy_values`).
const String recorderTasksKey = 'recorder.tasks';

/// The input openers of the recipe platforms (FC2, Bigo, niconico): without
/// them those rooms cannot be recorded (M8).
List<RecipeOpener> recipeOpeners(SiteRegistry sites) => [
  BigoRecipeOpener(sites.of(SiteIds.bigo) as BigoSite),
  Fc2RecipeOpener(sites.of(SiteIds.fc2Live) as Fc2LiveSite),
  NiconicoRecipeOpener(sites.of(SiteIds.niconico) as NiconicoSite),
];

/// The default recording folder: Android's app folder on external storage
/// (no permission needed), else `Records` in the data folder.
Future<String> defaultRecordDirectory(Directory dataRoot) async {
  if (Platform.isAndroid) {
    final external = await getExternalStorageDirectory();
    if (external != null) return p.join(external.path, 'Records');
  }
  return p.join(dataRoot.path, 'Records');
}

/// The recording settings (3.x `RecorderConfig` over its Hive keys).
///
/// live_store's settings registry has no recorder settings (M9 kept 3.x's
/// values in `legacy_values`), so they live as one JSON object in
/// `meta[recorder.settings]`, keyed by 3.x's Hive keys. Until the user
/// changes one, 3.x's imported values are read. Reads are synchronous (the
/// recorder asks on every decision); writes go to the store in order.
final class RecordSettingsStore {
  /// Creates the store over `meta`; [load] reads the saved values.
  new(this._meta);

  /// The meta key of the saved values.
  static const storageKey = 'recorder.settings';

  /// 3.x's Hive keys (`RecorderKeys`).
  static const segmentTime = 'segmentTime';

  /// See [segmentTime].
  static const maxTaskCount = 'maxTaskCount';

  /// See [segmentTime].
  static const autoReconnect = 'autoReconnect';

  /// See [segmentTime].
  static const maxCacheMB = 'maxCacheMB';

  /// See [segmentTime].
  static const enableCacheLimit = 'enableCacheLimit';

  /// See [segmentTime].
  static const savePath = 'recordSavePath';

  /// See [segmentTime].
  static const defaultQuality = 'default_quality';

  /// See [segmentTime].
  static const maxRetryCount = 'max_retry_count';

  /// See [segmentTime].
  static const retryDelay = 'retry_delay';

  /// See [segmentTime].
  static const enablePolling = 'enable_polling';

  /// See [segmentTime].
  static const liveCheckInterval = 'live_check_interval';

  /// See [segmentTime].
  static const enableBackoff = 'enable_backoff';

  /// See [segmentTime].
  static const maxCheckInterval = 'max_check_interval';

  /// See [segmentTime].
  static const autoStartOnBoot = 'auto_start_on_boot';

  /// See [segmentTime].
  static const preferBestStream = 'recorder_prefer_best_stream';

  /// See [segmentTime].
  static const rwTimeout = 'recorder_rw_timeout';

  /// See [segmentTime].
  static const threadQueueSize = 'recorder_thread_queue_size';

  /// See [segmentTime].
  static const usePinyinForFolder = 'recorder_folder_naming_strategy';

  /// See [segmentTime].
  static const recordDanmaku = 'recorder_record_danmaku';

  /// Every key, in 3.x's order.
  static const List<String> keys = [
    segmentTime,
    maxTaskCount,
    autoReconnect,
    maxCacheMB,
    enableCacheLimit,
    savePath,
    defaultQuality,
    maxRetryCount,
    retryDelay,
    enablePolling,
    liveCheckInterval,
    enableBackoff,
    maxCheckInterval,
    autoStartOnBoot,
    preferBestStream,
    rwTimeout,
    threadQueueSize,
    usePinyinForFolder,
    recordDanmaku,
  ];

  final MetaStore _meta;
  final _changes = StreamController<RecordSettings>.broadcast();
  var _values = <String, Object?>{};
  var _current = RecordSettings();
  var _dirty = false;
  Future<void>? _writing;

  /// The settings now.
  RecordSettings get current => _current;

  /// The settings after every change.
  Stream<RecordSettings> get changes => _changes.stream;

  /// Reads the saved values, else 3.x's imported ones.
  Future<void> load() async {
    Map<String, Object?>? saved;
    try {
      final text = await _meta.get(storageKey);
      final decoded = text == null ? null : jsonDecode(text);
      if (decoded is Map) saved = Map<String, Object?>.from(decoded);
    } on FormatException {
      saved = null;
    }
    if (saved == null) {
      saved = {};
      for (final key in keys) {
        final value = await _meta.legacyValue(key);
        if (value != null) saved[key] = value;
      }
    }
    _values = saved;
    _current = fromValues(_values);
    if (!_changes.isClosed) _changes.add(_current);
  }

  /// Sets [key] (one of [keys]) to [value]; the stored value is the
  /// normalized one.
  Future<void> set(String key, Object value) {
    _values[key] = value;
    _current = fromValues(_values);
    _values = toValues(_current);
    if (!_changes.isClosed) _changes.add(_current);
    _dirty = true;
    return flush();
  }

  /// Writes pending changes and waits for the write in flight.
  Future<void> flush() async {
    while (true) {
      final inFlight = _writing;
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      if (!_dirty) return;
      _dirty = false;
      final write = _meta.set(storageKey, jsonEncode(_values));
      _writing = write;
      try {
        await write;
      } finally {
        if (identical(_writing, write)) _writing = null;
      }
    }
  }

  /// Writes pending changes and closes [changes].
  Future<void> close() async {
    await flush();
    await _changes.close();
  }

  /// Settings from stored [values] (3.x Hive keys; lenient about types like
  /// 3.x's `HivePrefUtil`).
  static RecordSettings fromValues(Map<String, Object?> values) {
    final defaults = RecordSettings();
    int integer(String key, int fallback) => switch (values[key]) {
      final num value => value.toInt(),
      final String value => int.tryParse(value.trim()) ?? fallback,
      _ => fallback,
    };
    bool flag(String key, {required bool fallback}) => switch (values[key]) {
      final bool value => value,
      final num value => value != 0,
      final String value => switch (value.trim().toLowerCase()) {
        'true' || '1' => true,
        'false' || '0' => false,
        _ => fallback,
      },
      _ => fallback,
    };
    String text(String key, String fallback) => switch (values[key]) {
      final String value => value,
      _ => fallback,
    };
    return RecordSettings(
      segmentTime: integer(segmentTime, defaults.segmentTime),
      maxTaskCount: integer(maxTaskCount, defaults.maxTaskCount),
      autoReconnect: flag(autoReconnect, fallback: defaults.autoReconnect),
      maxCacheMB: integer(maxCacheMB, defaults.maxCacheMB),
      enableCacheLimit: flag(enableCacheLimit, fallback: defaults.enableCacheLimit),
      savePath: text(savePath, defaults.savePath).trim(),
      defaultQuality: text(defaultQuality, defaults.defaultQuality),
      maxRetryCount: integer(maxRetryCount, defaults.maxRetryCount),
      retryDelay: integer(retryDelay, defaults.retryDelay),
      enablePolling: flag(enablePolling, fallback: defaults.enablePolling),
      liveCheckInterval: integer(liveCheckInterval, defaults.liveCheckInterval),
      enableBackoff: flag(enableBackoff, fallback: defaults.enableBackoff),
      maxCheckInterval: integer(maxCheckInterval, defaults.maxCheckInterval),
      autoStartOnBoot: flag(autoStartOnBoot, fallback: defaults.autoStartOnBoot),
      preferBestStream: flag(preferBestStream, fallback: defaults.preferBestStream),
      rwTimeout: integer(rwTimeout, defaults.rwTimeout),
      threadQueueSize: integer(threadQueueSize, defaults.threadQueueSize),
      usePinyinForFolder: flag(usePinyinForFolder, fallback: defaults.usePinyinForFolder),
      recordDanmaku: flag(recordDanmaku, fallback: defaults.recordDanmaku),
    );
  }

  /// The stored form of [settings].
  static Map<String, Object?> toValues(RecordSettings settings) => {
    segmentTime: settings.segmentTime,
    maxTaskCount: settings.maxTaskCount,
    autoReconnect: settings.autoReconnect,
    maxCacheMB: settings.maxCacheMB,
    enableCacheLimit: settings.enableCacheLimit,
    savePath: settings.savePath,
    defaultQuality: settings.defaultQuality,
    maxRetryCount: settings.maxRetryCount,
    retryDelay: settings.retryDelay,
    enablePolling: settings.enablePolling,
    liveCheckInterval: settings.liveCheckInterval,
    enableBackoff: settings.enableBackoff,
    maxCheckInterval: settings.maxCheckInterval,
    autoStartOnBoot: settings.autoStartOnBoot,
    preferBestStream: settings.preferBestStream,
    rwTimeout: settings.rwTimeout,
    threadQueueSize: settings.threadQueueSize,
    usePinyinForFolder: settings.usePinyinForFolder,
    recordDanmaku: settings.recordDanmaku,
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
  new({required this.settings, required this.storage, this.recorder, this.keepAlive, this._store, this._storageAccess});

  /// Settings.
  final RecordSettingsStore settings;

  /// The managed directory (the recorder's own instance, so folders in use
  /// stay protected from cleanup).
  final RecordStorage storage;

  /// The recorder; null without FFmpeg.
  final Recorder? recorder;

  /// The platform keep-alive (Android's foreground service).
  final RecordingKeepAlive? keepAlive;

  final LiveStore? _store;
  final Future<bool> Function({required bool interactive})? _storageAccess;
  StreamSubscription<RecordSettings>? _settingsChanges;
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
    _settingsChanges = settings.changes.listen((_) => recorder.settingsChanged());
    final store = _store;
    if (store != null) await recorder.restore(await savedRecorderTasks(store));
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
    await settings.close();
  }
}

/// Recording over the app's parts. Without [ffmpeg] there is no recorder
/// (tests, platforms without the FFmpeg bundle).
AppRecording buildAppRecording({
  required LiveStore store,
  required SiteRegistry sites,
  required ProxyPolicy proxy,
  required Directory dataRoot,
  FfmpegRunner? ffmpeg,
  RecordingKeepAlive? keepAlive,
  Future<bool> Function(RecordStorage storage, {required bool interactive})? storageAccess,
  String? Function()? caFile,
}) {
  final settings = RecordSettingsStore(store.meta);
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
          persist: (json) => store.meta.set(recorderTasksKey, json),
          keepAlive: keepAlive,
          storageAccess: access,
          caFile: caFile,
        );
  return AppRecording(
    settings: settings,
    storage: storage,
    recorder: recorder,
    keepAlive: keepAlive,
    store: store,
    storageAccess: access,
  );
}

/// The saved task list: v4's, else the one imported from 3.x.
Future<String?> savedRecorderTasks(LiveStore store) async {
  final saved = await store.meta.get(recorderTasksKey);
  if (saved != null) return saved;
  final legacy = await store.meta.legacyValue('recorder_tasks');
  return switch (legacy) {
    null => null,
    final String text => text,
    _ => jsonEncode(legacy),
  };
}
