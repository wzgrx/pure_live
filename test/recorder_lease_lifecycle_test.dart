import 'package:pure_live/core/site/niconico/niconico_input_recipe.dart';
import 'package:pure_live/recorder/services/owned_record_input.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/hls_source_query_policy.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_scheduler.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/models/live_record_task.dart';
import 'package:pure_live/recorder/models/record_status.dart';
import 'package:pure_live/recorder/pages/record_settings/record_settings_controller.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_controller.dart';
import 'package:pure_live/recorder/services/cache_service.dart';
import 'package:pure_live/recorder/services/ffmpeg_service.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';

const _nativeUrl = 'https://al.flv.huya.com/fixture.flv?ctype=huya_pc_exe&t=100';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Native native;
  late _Resolver resolver;
  late RecorderController recorder;
  late LiveRecordTask task;

  setUp(() async {
    Get.testMode = true;
    root = await Directory.systemTemp.createTemp('pure-live-record-lease-');
    Hive.init(root.path);
    await HivePrefUtil.init();
    Get.put(CacheService(defaultDirectoryResolver: () async => root));
    native = _Native();
    resolver = Get.put<StreamResolverService>(_Resolver()) as _Resolver;
    recorder = Get.put(
      RecorderController.forTesting(settings: _Settings(), ffmpeg: native, scheduler: FFmpegScheduler.forTesting()),
    );
    task = LiveRecordTask(
      taskId: 'huya_fixture',
      roomId: 'fixture',
      platform: 'huya',
      title: 'fixture',
      nick: 'fixture',
      avatar: '',
      cover: '',
      createTime: DateTime(2026, 9, 5),
      autoReconnect: true,
    );
    recorder.tasks.add(task);
  });

  tearDown(() async {
    Get.delete<RecorderController>(force: true);
    if (resolver.pending?.isCompleted == false) resolver.pending!.complete(resolver.stream(1));
    await until(() => recorder.scheduler.runningCount == 0);
    await native.events.close();
    Get.reset();
    await Hive.close();
    await root.delete(recursive: true);
  });

  Future<void> start() async {
    expect(await recorder.startTask(task), isTrue);
    await until(() => native.starts == 1 && resolver.calls == 2);
  }

  for (final source in [
    (url: 'https://cdn.example/live/master.m3u8?token=fixture', policy: true),
    (url: 'https://cdn.example/live/media.m3u8', policy: false),
    (url: _nativeUrl, policy: false),
  ]) {
    test('ordinary recording requests selected HLS retention on start and user restart: $source', () async {
      resolver.url = source.url;
      resolver.withPolicy = source.policy;
      await start();
      expect(native.prefetchOptions, [true]);
      await recorder.stopTask(task);
      expect(task.wasStoppedByUser, isTrue);
      await until(() => recorder.scheduler.runningCount == 0);
      expect(await recorder.startTask(task), isTrue);
      await until(() => native.starts == 2);
      expect(native.prefetchOptions, [true, true]);
      expect(native.liveOptions, [true, true]);
      expect(native.urls, everyElement(startsWith(source.url)));
    });
  }

  test('owned recording reaches typed manager entry and keeps private input out of persisted task', () async {
    resolver.owned = true;
    expect(await recorder.startTask(task), isTrue);
    await until(() => native.starts == 1);
    expect(native.ownedIdentities, ['niconico:lv100:800x450:1080800']);
    expect(native.urls, ['http://127.0.0.1:19001/owned/root.m3u8']);
    expect(native.policies, [null]);
    expect(task.currentUrl, isNull);
    expect(task.selectedLineIndex, 0);
    expect(task.selectedQualityId, 'fixture');
    expect(task.toJson().toString(), isNot(contains('19001')));
    expect(task.toJson().keys, isNot(contains('inputRecipe')));
    await recorder.stopTask(task);
    await until(() => recorder.scheduler.runningCount == 0);
    expect(resolver.calls, 1, reason: 'owned inputs must not schedule signed-URL prefetch');
    expect(task.wasStoppedByUser, true);
  });

  test('healthy native WUP FLV prefetches without cancelling the current capture', () async {
    await start();
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(native.rotations, 0);
    expect(native.stops, 0);
    expect(native.starts, 1);
    expect(task.status, RecordStatus.running);
    expect(resolver.calls, 2, reason: 'credential maintenance must not poll or spin');
  });

  test('recorder passes the exact selected source policy to each native attempt', () async {
    resolver.url = 'https://cdn.example/live/master.m3u8?token=fixture';
    resolver.withPolicy = true;
    await start();
    expect(native.policies.single?.matchesSource(Uri.parse(native.urls.single)), isTrue);
    native.finish(task.taskId, eof: true);
    await until(() => native.starts == 2, timeout: const Duration(seconds: 4));
    expect(native.policies.last?.matchesSource(Uri.parse(native.urls.last)), isTrue);
    expect(native.prefetchOptions, [true, true]);
    expect(native.policies.first?.matchesSource(Uri.parse(native.urls.last)), isFalse);
    expect(task.toJson().keys, isNot(contains('sourceQueryPolicy')));
  });

  test('native credential prefetch failure leaves healthy media running', () async {
    resolver.failPrefetch = true;
    await start();
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(native.rotations, 0);
    expect(native.starts, 1);
    expect(resolver.calls, 2, reason: 'failed prefetch must use bounded scheduling');
  });

  for (final url in [
    'https://al.flv.huya.com/fixture.flv?ctype=tars_mobile&t=103',
    'https://al.hls.huya.com/fixture.m3u8?ctype=huya_pc_exe&t=100',
    'https://cdn.example/live.flv?ctype=huya_pc_exe&t=100',
  ]) {
    test('non-native or other-platform lease retains rotation: $url', () async {
      resolver.url = url;
      await start();
      await until(() => native.rotations == 1);
      expect(resolver.calls, 2);
    });
  }

  test('actual native EOF consumes a still-valid prefetched credential', () async {
    await start();
    native.finish(task.taskId, eof: true);
    await until(() => native.starts == 2, timeout: const Duration(seconds: 4));
    expect(resolver.calls, 2, reason: 'terminal EOF must not discard the ready replacement');
    expect(native.urls.last, contains('lease=1'));
  });

  test('expired prefetch is resolved again on actual EOF', () async {
    resolver.expiredPrefetch = true;
    await start();
    native.finish(task.taskId, eof: true);
    await until(() => native.starts == 2, timeout: const Duration(seconds: 4));
    expect(resolver.calls, 3);
    expect(native.urls.last, contains('lease=2'));
  });

  test('user stop invalidates a pending prefetch and its timers', () async {
    resolver.pending = Completer<ResolvedRecordStream>();
    await start();
    await recorder.stopTask(task);
    resolver.pending!.complete(resolver.stream(1));
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(native.rotations, 0);
    expect(native.starts, 1);
    expect(task.wasStoppedByUser, isTrue);
    expect(task.status, RecordStatus.stopped);
  });

  test('old pending prefetch cannot rearm maintenance after a new native session', () async {
    resolver.pending = Completer<ResolvedRecordStream>();
    await start();
    task.currentUrl = 'https://al.flv.huya.com/new.flv?ctype=huya_pc_exe&t=100';
    native.session = _Counters(99);
    native.events.add(FFmpegEvent(taskId: task.taskId, type: FFmpegEventType.startAck, data: {'sessionId': 99}));
    resolver.pending!.complete(resolver.stream(1));
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(resolver.calls, 2);
    expect(native.rotations, 0);
    expect(task.currentUrl, contains('/new.flv'));
  });

  test('replacing a task with the same ID invalidates old lease callbacks', () async {
    resolver.url = 'https://al.hls.huya.com/fixture.m3u8';
    resolver.pending = Completer<ResolvedRecordStream>();
    await start();
    recorder.tasks.assignAll([LiveRecordTask.fromJson(task.toJson())]);
    resolver.pending!.complete(resolver.stream(1));
    await Future<void>.delayed(const Duration(milliseconds: 650));
    expect(native.rotations, 0, reason: 'the removed card no longer owns this recording action');
  });
}

Future<void> until(bool Function() condition, {Duration timeout = const Duration(seconds: 2)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 3));
  }
  expect(condition(), isTrue, reason: 'recording fixture did not reach its async boundary');
}

class _Settings extends RecordSettingsController {
  @override
  Future<void> refreshCacheSize() async {}
}

class _Resolver extends StreamResolverService {
  bool owned = false;
  bool withPolicy = false;
  String url = _nativeUrl;
  int calls = 0;
  bool failPrefetch = false;
  bool expiredPrefetch = false;
  Completer<ResolvedRecordStream>? pending;
  ResolvedRecordStream stream(int index) => owned
      ? ResolvedRecordStream.owned(
          input: NiconicoInputRecipe(programId: 'lv100', resolution: '800x450', bandwidth: 1080800),
          quality: LivePlayQuality(quality: 'fixture', id: 'fixture'),
          qualityCursorId: 'fixture',
        )
      : ResolvedRecordStream(
          url: '$url${url.contains('?') ? '&' : '?'}lease=$index',
          quality: LivePlayQuality(quality: 'fixture', id: 'fixture'),
          qualityCursorId: 'fixture',
          lineIndex: 0,
          candidateUrls: [url],
          sourceQueryPolicy: withPolicy
              ? HlsSourceQueryPolicy.fromSource(Uri.parse('$url${url.contains('?') ? '&' : '?'}lease=$index'))
              : null,
          refreshAt: DateTime.now().toUtc().add(
            index == 0 ? const Duration(milliseconds: 400) : const Duration(minutes: 4),
          ),
          invalidAt: DateTime.now().toUtc().add(
            expiredPrefetch && index == 1 ? const Duration(seconds: -1) : const Duration(minutes: 5),
          ),
        );
  @override
  Future<ResolvedRecordStream> resolveStream({
    required String roomId,
    required String platform,
    required String preferredQuality,
    String? previousQualityId,
    int? previousLineIndex,
    bool renewCurrent = false,
  }) async {
    final index = calls++;
    if (index == 1 && failPrefetch) throw StateError('fixture network failure');
    if (index == 1 && pending != null) return pending!.future;
    return stream(index);
  }
}

class _Native implements FFmpegManager {
  final ownedIdentities = <String>[];
  @override
  Future<void> startOwned({
    required String taskId,
    required OwnedRecordSource source,
    required RecordArgumentsBuilder buildArguments,
  }) {
    ownedIdentities.add(source.identity);
    final arguments = buildArguments(Uri.parse('http://127.0.0.1:19001/owned/root.m3u8'));
    expect(arguments, isNot(contains('-headers')));
    return start(taskId: taskId, arguments: arguments, liveRecording: true);
  }

  final policies = <HlsSourceQueryPolicy?>[];
  final prefetchOptions = <bool>[];
  final liveOptions = <bool>[];
  final events = StreamController<FFmpegEvent>.broadcast(sync: true);
  final urls = <String>[];
  Completer<void>? execution;
  _Counters? session;
  int starts = 0;
  int stops = 0;
  int rotations = 0;
  @override
  Stream<FFmpegEvent> get stream => events.stream;
  @override
  FFmpegRecordSession? getSession(String taskId) => session;
  @override
  bool isRunning(String taskId) => session != null;
  @override
  Future<void> start({
    required String taskId,
    required List<String> arguments,
    bool liveRecording = false,
    HlsSourceQueryPolicy? sourceQueryPolicy,
    HlsRelayDiagnostics? hlsDiagnostics,
    bool hlsPrefetch = false,
  }) async {
    policies.add(sourceQueryPolicy);
    prefetchOptions.add(hlsPrefetch);
    liveOptions.add(liveRecording);
    final done = Completer<void>();
    execution = done;
    final id = ++starts;
    session = _Counters(id);
    urls.add(arguments[arguments.indexOf('-i') + 1]);
    events.add(FFmpegEvent(taskId: taskId, type: FFmpegEventType.startAck, data: {'sessionId': id}));
    events.add(FFmpegEvent(taskId: taskId, type: FFmpegEventType.started, data: {'sessionId': id}));
    await done.future;
  }

  void finish(String taskId, {bool eof = false}) {
    final current = session;
    if (current == null) return;
    session = null;
    execution?.complete();
    events.add(
      FFmpegEvent(
        taskId: taskId,
        type: eof ? FFmpegEventType.error : FFmpegEventType.complete,
        data: {
          'sessionId': current.sessionId,
          'manualStop': !eof,
          if (eof) ...{'failure_kind': 'unexpectedEof', 'code': 0, 'retryable': true, 'silent': true},
        },
      ),
    );
  }

  @override
  Future<void> stop(String taskId) async {
    stops++;
    finish(taskId);
  }

  @override
  Future<void> refreshLease(String taskId) async {
    rotations++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Counters implements FFmpegRecordSession {
  _Counters(this.sessionId);
  @override
  final int sessionId;
  @override
  int get fileSize => 0;
  @override
  int get recordedSeconds => 0;
  @override
  bool get mediaStarted => true;
  @override
  double get bitrate => 0;
  @override
  double get speed => 1;
  @override
  double get fps => 60;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
