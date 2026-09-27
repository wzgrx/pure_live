import 'package:pure_live/common/services/settings/log_controller.dart';
import 'package:pure_live/get/get.dart';

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_extended_flutter/ffmpeg_kit_extended_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/niconico/niconico_api.dart';
import 'package:pure_live/core/site/niconico/niconico_input_recipe.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_event.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_types.dart';
import 'package:pure_live/recorder/ffmpeg/ffmpeg_manager.dart';
import 'package:pure_live/recorder/services/ffmpeg_service.dart';
import 'package:pure_live/recorder/services/live_input_recording_binding.dart';
import 'package:pure_live/recorder/services/owned_record_input.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';

import 'niconico_hls_input_test.dart' as fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    Get.put<LogController>(_QuietLog());
  });
  tearDown(Get.reset);
  for (final cursor in [false, true]) {
    test('owned recorder resolution rotates quality, renews and wraps one logical line cursor=$cursor', () async {
      final site = cursor ? _CursorSite() : _Site();
      final resolver = StreamResolverService(siteResolver: (_) => site);
      Future<ResolvedRecordStream> resolve({ResolvedRecordStream? previous, bool renew = false}) =>
          resolver.resolveStream(
            roomId: 'lv100',
            platform: 'bilibili',
            preferredQuality: 'high',
            previousQualityId: previous?.qualityCursorId,
            previousLineIndex: previous?.lineIndex,
            renewCurrent: renew,
          );
      final first = await resolve();
      expect(first.inputRecipe?.identity, 'niconico:lv100:800x450:1080800');
      expect(first.url, isEmpty);
      expect(first.candidateUrls, isEmpty);
      expect(first.sourceQueryPolicy, isNull);
      expect(first.refreshAt, isNull);
      expect(first.lineLabel, '线路1');
      expect(first.qualityCursorId, 'high');
      expect((await resolve(previous: first, renew: true)).qualityCursorId, 'high');
      final next = await resolve(previous: first);
      expect(next.qualityCursorId, 'low');
      expect(next.lineIndex, 0);
      expect((await resolve(previous: next)).qualityCursorId, 'high');
      expect(site.calls.length, lessThan(10));
    });
  }
  test('single owned cursor wraps only after exhausting line zero and retains quality confirmation', () async {
    final site = _CursorSite()
      ..oneQuality = true
      ..unconfirmed = true;
    final resolver = StreamResolverService(siteResolver: (_) => site);
    final result = await resolver.resolveStream(
      roomId: 'lv100',
      platform: 'bilibili',
      preferredQuality: 'high',
      previousQualityId: 'high',
      previousLineIndex: 0,
    );
    expect(site.calls, ['high:1', 'high:0']);
    expect(result.lineIndex, 0);
    expect(result.qualityCursorId, 'high');
    expect(result.quality.isPlaybackUnconfirmed, true);
  });
  test('recording binder is lazy, reacquires metadata, passes selected feeds and recorder proxy', () async {
    var requests = 0;
    final inputs = <_Input>[];
    final source = bindNiconicoRecording(
      NiconicoInputRecipe(programId: 'lv100', resolution: '800x450', bandwidth: 1080800),
      api: NiconicoApi(
        request: (_, _) async {
          requests++;
          final body = const HtmlEscape().convert(jsonEncode(fixture.fixture('live')));
          return (status: 200, body: '<script id="embedded-data" data-props="$body"></script>');
        },
      ),
      findProxy: (_) => 'PROXY localhost:7897',
      openInput: (watch, {required resolution, bandwidth, required recording, required findProxy, cancel}) async {
        expect(watch.programId, 'lv100');
        expect(resolution, '800x450');
        expect(bandwidth, 1080800);
        expect(recording, true);
        expect(findProxy(Uri.parse('https://example.test')), 'PROXY localhost:7897');
        final input = _Input();
        inputs.add(input);
        return input;
      },
    );
    expect(requests, 0);
    for (var n = 0; n < 2; n++) {
      await (await source.createInput(CancelToken())).close();
    }
    expect(requests, 2);
    expect(inputs.map((e) => e.closes), [1, 1]);
    final cancel = CancelToken()..cancel();
    await expectLater(source.createInput(cancel), throwsA(isA<DioException>()));
    expect(requests, 2);
  });

  for (final mode in ['graceful', 'forced', 'finish-error', 'eof']) {
    test('actual recording service owns input until native termination and cleanup: $mode', () async {
      final h = _Harness();
      h.input.closeGate = Completer<void>();
      h.input.onFinish = mode == 'graceful' ? () => h.native.complete() : null;
      h.input.finishError = mode == 'finish-error';
      final run = h.start();
      addTearDown(() async {
        if (!h.input.closeGate!.isCompleted) h.input.closeGate!.complete();
        if (h.native.started.isCompleted && !h.native.done.isCompleted) h.native.complete();
        await run;
      });
      await h.native.started.future;
      expect(h.arguments!.where((value) => value.contains('://')), [h.input.inputUri.toString()]);
      expect(h.events.map((e) => e.type), [FFmpegEventType.startAck]);
      expect(h.service.isRunning('test'), true);
      expect(h.input.closes, 0);
      Future<void>? stop;
      var stopEnded = false;
      if (mode == 'eof') {
        h.native.complete();
      } else {
        stop = h.service.stop('test').then((_) => stopEnded = true);
      }
      await h.input.closing.future;
      expect(h.service.isRunning('test'), true, reason: 'cleanup still owns the attempt');
      expect(stopEnded, false);
      expect(h.input.closes, 1);
      final terminal = h.events.last;
      expect(terminal.type, mode == 'eof' ? FFmpegEventType.error : FFmpegEventType.complete);
      expect(terminal.data['inputDrainKind'], 'hls');
      expect(terminal.data['inputDrained'], mode == 'graceful');
      expect(terminal.data['forcedCancel'], mode == 'forced' || mode == 'finish-error');
      expect(h.cancels, mode == 'forced' || mode == 'finish-error' ? 1 : 0);
      if (mode == 'eof') expect(terminal.data['failure_kind'], 'unexpectedEof');
      h.input.closeGate!.complete();
      await run;
      if (stop != null) await stop;
      expect(h.service.isRunning('test'), false);
      expect(h.input.closes, 1);
    });
  }
  test('stop during initialization reserves task and prevents input and native allocation', () async {
    final h = _Harness()..initializeGate = Completer<void>();
    final running = expectLater(h.start(), throwsA(isA<DioException>()));
    await h.initializing.future;
    expect(h.service.isRunning('test'), true);
    await expectLater(h.start(), throwsStateError);
    final stop = h.service.stop('test');
    h.initializeGate!.complete();
    await Future.wait([running, stop]);
    expect(h.creates, 0);
    expect(h.arguments, isNull);
    expect(h.events, isEmpty);
    expect(h.service.isRunning('test'), false);
  });
  test('stop during creation cancels and joins a late allocated input before allowing restart', () async {
    final h = _Harness()..inputGate = Completer<void>();
    final running = expectLater(h.start(), throwsA(isA<DioException>()));
    await h.creating.future;
    final stop = h.service.stop('test');
    expect(h.cancel!.isCancelled, true);
    h.inputGate!.complete();
    await Future.wait([running, stop]);
    expect(h.input.closes, 1);
    expect(h.arguments, isNull);
    expect(h.events, isEmpty);
    expect(h.service.isRunning('test'), false);
  });
  for (final stage in ['builder', 'native-create', 'native-execute', 'input-closed']) {
    test('recording failure releases the owned input: $stage', () async {
      final h = _Harness()..failureStage = stage;
      if (stage == 'input-closed') h.input.isClosed = true;
      if (stage == 'native-execute') {
        await h.start();
      } else {
        await expectLater(h.start(), throwsStateError);
      }
      expect(h.input.closes, 1);
      expect(h.service.isRunning('test'), false);
      if (stage == 'native-execute') expect(h.events.last.type, FFmpegEventType.error);
    });
  }
  test('owned coverage and tail evidence are retained without declaring full decoding', () async {
    final h = _Harness();
    h.input.onFinish = () => h.native.complete();
    final run = h.start();
    await h.native.started.future;
    h.input.onCoverageIncomplete?.call();
    h.input.onCoverageIncomplete?.call();
    expect(h.events.where((e) => e.type == FFmpegEventType.inputCoverage), hasLength(1));
    h.input.inputTailDiscarded = true;
    await h.service.stop('test');
    await run;
    expect(h.events.last.data['inputCoverageIncomplete'], true);
    expect(h.events.last.data['inputTailDiscarded'], true);
    expect(h.events.last.data['inputIntegrityError'], false);
    expect(h.events.last.data.toString(), isNot(contains('19001')));
  });
  for (final owned in [false, true]) {
    test('actual FFmpeg manager reserves initialization inside cancellation owner: owned=$owned', () async {
      final h = _Harness()..initializeGate = Completer<void>();
      final manager = FFmpegManager.forTesting(h.service);
      final run = expectLater(
        owned
            ? manager.startOwned(taskId: 'test', source: h.source, buildArguments: h.build)
            : manager.start(taskId: 'test', arguments: ['-i', 'input.ts', 'output.ts']),
        throwsA(isA<DioException>()),
      );
      await h.initializing.future;
      final stop = manager.stop('test');
      h.initializeGate!.complete();
      await Future.wait([run, stop]);
      expect(h.creates, 0);
      expect(h.arguments, isNull);
    });
  }
}

class _Site extends LiveSite implements LivePlayUrlResolver {
  bool oneQuality = false, unconfirmed = false;
  final calls = <String>[];
  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) async =>
      LiveRoom(roomId: roomId, platform: platform, liveStatus: LiveStatus.live, status: true);
  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async => [
    LivePlayQuality(quality: 'high', id: 'high', sort: 1000),
    if (!oneQuality) LivePlayQuality(quality: 'low', id: 'low', sort: 100),
  ];
  LivePlayUrlResolution resolve(LivePlayQuality quality, int? line) {
    calls.add('${quality.selectionId}:${line ?? 0}');
    return LivePlayUrlResolution.owned(
      input: NiconicoInputRecipe(programId: 'lv100', resolution: '800x450', bandwidth: 1080800),
      appliedQualityData: quality.selectionId,
      qualityUnconfirmed: unconfirmed,
    );
  }

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => resolve(quality, null);
}

class _CursorSite extends _Site implements LivePlayUrlCursorResolver {
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlAtRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
    required int lineIndex,
  }) async => resolve(quality, lineIndex);
}

class _Input implements OwnedRecordInput {
  @override
  bool isClosed = false;
  @override
  bool finishRequested = false;
  @override
  bool inputTailDiscarded = false;
  @override
  void Function()? onCoverageIncomplete;
  void Function()? onFinish;
  bool finishError = false;
  Completer<void>? closeGate;
  final closing = Completer<void>();
  int closes = 0;
  @override
  Uri get inputUri => Uri.parse('http://127.0.0.1:19001/private/root.m3u8');
  @override
  Duration get drainTimeout => const Duration(milliseconds: 40);
  @override
  List<String> replaceFirstInput(Iterable<String> arguments) => arguments.toList();
  @override
  Future<void> finish() async {
    finishRequested = true;
    if (finishError) throw StateError('finish');
    onFinish?.call();
  }

  @override
  Future<void> close() async {
    closes++;
    isClosed = true;
    closing.complete();
    await closeGate?.future;
  }
}

class _Native implements FFmpegSession {
  final started = Completer<void>();
  final done = Completer<FFmpegSession>();
  @override
  FFmpegSessionCompleteCallback? completeCallback;
  bool executeError = false;
  @override
  int getSessionId() => 1;
  @override
  int getReturnCode() => 0;
  @override
  String? getLogs() => '';
  @override
  void setCompleteCallback(FFmpegSessionCompleteCallback? callback) => completeCallback = callback;
  @override
  Future<FFmpegSession> executeAsync({
    FFmpegSessionCompleteCallback? completeCallback,
    FFmpegLogCallback? logCallback,
    FFmpegStatisticsCallback? statisticsCallback,
  }) async {
    started.complete();
    if (executeError) throw StateError('execute');
    return done.future;
  }

  void complete() {
    try {
      completeCallback!(this);
    } finally {
      if (!done.isCompleted) done.complete(this);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #setLogCallback || invocation.memberName == #setStatisticsCallback) return null;
    return super.noSuchMethod(invocation);
  }
}

class _Harness {
  final input = _Input();
  final native = _Native();
  final events = <FFmpegEvent>[];
  final initializing = Completer<void>(), creating = Completer<void>();
  Completer<void>? initializeGate, inputGate;
  CancelToken? cancel;
  int creates = 0, cancels = 0;
  String? failureStage;
  List<String>? arguments;
  late final service = FFmpegService.forTesting(
    initialize: () async {
      initializing.complete();
      await initializeGate?.future;
    },
    createSession: (args) {
      if (failureStage == 'native-create') throw StateError('create');
      arguments = args;
      native.executeError = failureStage == 'native-execute';
      return native;
    },
    cancelSession: (_) {
      cancels++;
      native.complete();
    },
  );
  late final source = OwnedRecordSource(
    identity: 'fixture',
    createInput: (token) async {
      cancel = token;
      creates++;
      creating.complete();
      await inputGate?.future;
      return input;
    },
  );
  List<String> build(Uri uri) {
    if (failureStage == 'builder') throw StateError('builder');
    return ['-i', uri.toString(), 'output.ts'];
  }

  Future<void> start() =>
      service.startOwned(taskId: 'test', source: source, buildArguments: build, onEvent: events.add);
}

class _QuietLog extends GetxController implements LogController {
  @override
  Future<void> onInit() async {
    super.onInit();
  }

  @override
  bool get enableLog => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
