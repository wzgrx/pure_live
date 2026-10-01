import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart' as kit;
import 'package:flutter/services.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_net/live_net.dart';
import 'package:live_record/live_record.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/recording.dart';

/// Whether this build carries the FFmpeg bundle (`ffmpeg_kit_extended_config`
/// in the workspace pubspec: Android, Windows and Linux, as in 3.x).
bool get platformHasFfmpeg => Platform.isAndroid || Platform.isWindows || Platform.isLinux;

/// FFmpeg through FFmpegKit (3.x `FFmpegService` and `VideoProcessorService`
/// used `ffmpeg_kit_extended_flutter` 0.6.2 the same way): a session from the
/// argument list, log, statistics and completion callbacks, `cancel`.
final class FfmpegKitRunner implements FfmpegRunner {
  Future<void>? _initialized;

  Future<void> _initialize() =>
      _initialized ??= kit.FFmpegKitExtended.initialize().catchError((Object error, StackTrace stack) {
        _initialized = null;
        Error.throwWithStackTrace(error, stack);
      });

  @override
  Future<FfmpegExecution> start(List<String> arguments) async {
    await _initialize();
    final execution = _KitExecution();
    final session = kit.FFmpegKit.createSessionFromArguments(arguments);
    execution.session = session;
    session
      ..setLogCallback((entry) => execution.log(entry.message))
      ..setStatisticsCallback(
        (stats) => execution.statistic(
          FfmpegStatistics(
            time: stats.time,
            size: stats.size,
            bitrate: stats.bitrate,
            speed: stats.speed,
            videoFps: stats.videoFps,
            videoFrame: stats.videoFrameNumber,
          ),
        ),
      )
      ..setCompleteCallback((completed) => execution.finish(completed.getReturnCode()));
    unawaited(
      session.executeAsync().then<void>((_) {}).catchError((Object error, StackTrace stack) {
        log('FFmpeg failed before completion', name: 'FfmpegKitRunner', error: error, stackTrace: stack);
        execution
          ..log('FFmpeg execution failed: $error')
          ..finish(-1);
      }),
    );
    return execution;
  }
}

final class _KitExecution implements FfmpegExecution {
  final _logs = StreamController<String>.broadcast(sync: true);
  final _statistics = StreamController<FfmpegStatistics>.broadcast(sync: true);
  final _exit = Completer<int>();
  kit.FFmpegSession? session;

  void log(String line) {
    if (!_logs.isClosed) _logs.add(line);
  }

  void statistic(FfmpegStatistics value) {
    if (!_statistics.isClosed) _statistics.add(value);
  }

  void finish(int code) {
    if (_exit.isCompleted) return;
    _exit.complete(code);
    unawaited(_logs.close());
    unawaited(_statistics.close());
  }

  @override
  Stream<String> get logs => _logs.stream;

  @override
  Stream<FfmpegStatistics> get statistics => _statistics.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void cancel() {
    if (_exit.isCompleted) return;
    try {
      session?.cancel();
    } on Object catch (error) {
      log('FFmpeg cancel failed: $error');
    }
  }
}

/// The CA bundle FFmpeg's OpenSSL needs on Android and Linux (3.x
/// `FFmpegTlsTrustStore`): the app's copy of Mozilla's bundle, written next
/// to the data. Windows uses Schannel and needs none.
final class RecordCaBundle {
  /// Creates the bundle written into [directory].
  new(this.directory);

  /// The asset (3.x's, 2026-08-13).
  static const asset = 'assets/certificates/mozilla-ca-bundle.pem';

  /// Where the file goes.
  final Directory directory;

  String? _path;

  /// The file's path once [prepare] finished, else null.
  String? get path => _path;

  /// Writes the bundle when it is missing or differs (Android and Linux).
  Future<void> prepare(AssetBundle bundle) async {
    if (!Platform.isAndroid && !Platform.isLinux) return;
    try {
      final data = await bundle.load(asset);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final target = File(p.join(directory.path, 'mozilla-ca-bundle.pem'));
      if (!target.existsSync() || !_same(await target.readAsBytes(), bytes)) {
        await directory.create(recursive: true);
        final temporary = File('${target.path}.tmp');
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(target.path);
      }
      _path = target.path;
    } on Object catch (error, stack) {
      log('CA bundle unavailable', name: 'RecordCaBundle', error: error, stackTrace: stack);
    }
  }

  static bool _same(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}

const MethodChannel _recorderChannel = MethodChannel('pure_live/recorder');

/// Android's foreground service of recordings (3.x
/// `RecorderBackgroundService` over `RecorderForegroundService.kt`): the
/// first holder starts it, the last release stops it. When Android stops it
/// (the Android 15 data-sync time limit, or the service dies) the
/// recorder's tasks stop with the reason, and later starts are refused until
/// the user starts a task again ([allowUserRetry]).
final class AndroidRecordKeepAlive implements RecordingKeepAlive {
  /// Creates the keep-alive; [title] and [text] give the notification's
  /// words, [onInterrupted] receives Android's reason (`timeout`,
  /// `service_stopped`).
  new({required this.title, required this.text, required this.onInterrupted, this._channel = _recorderChannel}) {
    _channel.setMethodCallHandler(_native);
  }

  /// Notification title.
  final String Function() title;

  /// Notification text.
  final String Function() text;

  /// Called when Android ended the service.
  final Future<void> Function(String reason) onInterrupted;

  final MethodChannel _channel;
  final _owners = <Object>{};
  bool? _applied;
  String? _interruption;
  Future<void>? _applying;

  @override
  void allowUserRetry() => _interruption = null;

  @override
  Future<void> acquire(Object owner) async {
    final interruption = _interruption;
    if (interruption != null) throw RecordKeepAliveException(interruption);
    _owners.add(owner);
    try {
      await _apply();
      if (_applied != true) throw RecordKeepAliveException(_interruption ?? 'start_failed');
    } on Object {
      _owners.remove(owner);
      if (_owners.isEmpty) unawaited(_apply().catchError((Object _) {}));
      rethrow;
    }
  }

  @override
  Future<void> release(Object owner) async {
    if (!_owners.remove(owner)) return;
    await _apply();
  }

  Future<void> _apply() async {
    while (true) {
      final inFlight = _applying;
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      final wanted = _owners.isNotEmpty && _interruption == null;
      if (_applied == wanted) return;
      final change = _set(wanted);
      _applying = change;
      try {
        await change;
      } finally {
        if (identical(_applying, change)) _applying = null;
      }
      if (wanted && _applied != true) return;
    }
  }

  Future<void> _set(bool active) async {
    try {
      await _channel.invokeMethod<void>('setActive', {
        'active': active,
        if (active) 'title': title(),
        if (active) 'text': text(),
      });
      _applied = active;
    } on PlatformException catch (error) {
      _applied = null;
      if (active) _interruption = 'start_failed';
      log('Recording service ${active ? 'start' : 'stop'} failed: ${error.message}', name: 'RecordKeepAlive');
      if (!active) _applied = false;
    }
  }

  Future<void> _native(MethodCall call) async {
    if (call.method != 'interrupted') return;
    final arguments = call.arguments;
    final reason = arguments is Map ? '${arguments['reason'] ?? 'service_stopped'}' : 'service_stopped';
    if (_interruption != null) return;
    _interruption = reason;
    // The service is gone; the next stop must still reach Android so the
    // locks are released.
    _applied = null;
    await onInterrupted(reason);
    await _apply();
  }
}

/// Storage access for recordings (3.x `requestStoragePermission`): the
/// managed directory is writable, else Android asks for all-files access
/// (API 30+) or the storage permission, but only for a user action.
Future<bool> androidStorageAccess(RecordStorage storage, {required bool interactive}) async {
  if (!Platform.isAndroid) return true;
  if (await storage.canWrite()) return true;
  if (!interactive) return false;
  try {
    await _recorderChannel.invokeMethod<bool>('requestStorage');
  } on PlatformException catch (error) {
    log('Storage permission request failed: ${error.message}', name: 'RecordStorage');
  } on MissingPluginException {
    return false;
  }
  return await storage.canWrite();
}

/// Recording with this platform's parts: FFmpegKit where the bundle exists,
/// Android's foreground service and storage access, the CA bundle on
/// Android and Linux (written in the background; FFmpeg gets it once
/// ready). [words] gives the notification's text.
AppRecording platformAppRecording({
  required LiveStore store,
  required SiteRegistry sites,
  required ProxyPolicy proxy,
  required Directory dataRoot,
  required String Function(String key) words,
  DanmakuRegistry? danmaku,
  String tasksKey = recorderTasksKey,
}) {
  final caBundle = RecordCaBundle(Directory(p.join(dataRoot.path, 'certificates')));
  unawaited(caBundle.prepare(rootBundle));
  late final AppRecording recording;
  final keepAlive = Platform.isAndroid
      ? AndroidRecordKeepAlive(
          title: () => words('recorder_background_notification_title'),
          text: () => words('recorder_background_notification_text'),
          onInterrupted: (reason) async => await recording.recorder?.keepAliveInterrupted(reason),
        )
      : null;
  return recording = buildAppRecording(
    store: store,
    sites: sites,
    proxy: proxy,
    dataRoot: dataRoot,
    ffmpeg: platformHasFfmpeg ? FfmpegKitRunner() : null,
    danmaku: danmaku,
    keepAlive: keepAlive,
    storageAccess: androidStorageAccess,
    caFile: () => caBundle.path,
    tasksKey: tasksKey,
  );
}
