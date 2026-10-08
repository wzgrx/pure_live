import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  group('resolver', () {
    test('quality order uses the platform rank and the preference, without duplicates', () {
      const qualities = [
        LivePlayQuality(quality: '流畅', id: 1, sort: 1),
        LivePlayQuality(quality: '原画', id: 4, sort: 4),
        LivePlayQuality(quality: '超清', id: 2, sort: 2),
        LivePlayQuality(quality: '超清', id: 2, sort: 2),
      ];
      expect(RecordStreamResolver.orderQualities(qualities, '原画').map((q) => q.id), [4, 2, 1]);
      expect(RecordStreamResolver.orderQualities(qualities, '超清').map((q) => q.id), [2, 4, 1]);
      expect(RecordStreamResolver.orderQualities(qualities, '流畅').map((q) => q.id), [1, 4, 2]);
    });

    test('a retry moves to the next line, a renewal keeps the line', () async {
      final site = FakeSite(
        lines: {
          'origin': const [LivePlayLine('rtmp://a.example/live?sign=1'), LivePlayLine('rtmp://b.example/live?sign=1')],
        },
      );
      final resolver = RecordStreamResolver((_) => site);
      final first = await resolver.resolve(roomId: '1', platform: 'fake', preferredQuality: '原画');
      expect(first.line!.url, startsWith('rtmp://a.'));
      final next = await resolver.resolve(
        roomId: '1',
        platform: 'fake',
        preferredQuality: '原画',
        previousQualityId: first.qualityCursorId,
        previousLineIndex: first.lineIndex,
      );
      expect(next.line!.url, startsWith('rtmp://b.'));
      expect(next.lineLabel, '线路2');
      final renewed = await resolver.resolve(
        roomId: '1',
        platform: 'fake',
        preferredQuality: '原画',
        previousQualityId: next.qualityCursorId,
        previousLineIndex: next.lineIndex,
        renewCurrent: true,
      );
      expect(renewed.line!.url, startsWith('rtmp://b.'));
    });

    test('offline, banned and unknown rooms stop before FFmpeg; transport failures stay retryable', () async {
      final site = FakeSite(status: LiveStatus.offline);
      final resolver = RecordStreamResolver((id) => id == 'fake' ? site : null);
      Future<RecordStreamException> failure() async {
        try {
          await resolver.resolve(roomId: '1', platform: 'fake', preferredQuality: '原画');
        } on RecordStreamException catch (error) {
          return error;
        }
        fail('resolved');
      }

      expect((await failure()).type, RecordStreamErrorType.notLive);
      site.status = LiveStatus.unknown;
      expect((await failure()).retryable, isTrue);
      site
        ..status = LiveStatus.live
        ..detailError = const NetworkFailure('fake');
      expect((await failure()).type, RecordStreamErrorType.networkError);
      site.detailError = const NotFound('fake');
      expect((await failure()).retryable, isFalse);
      await expectLater(
        resolver.resolve(roomId: '1', platform: 'other', preferredQuality: '原画'),
        throwsA(isA<RecordStreamException>().having((e) => e.retryable, 'retryable', isFalse)),
      );
    });

    test('a paid room without a stream says so instead of retrying (22-1)', () async {
      final site = FakeSite(restriction: LiveRestriction.paid, lines: {});
      final resolver = RecordStreamResolver((_) => site);
      await expectLater(
        resolver.resolve(roomId: '1', platform: 'fake', preferredQuality: '原画'),
        throwsA(
          isA<RecordStreamException>()
              .having((e) => e.type, 'type', RecordStreamErrorType.restricted)
              .having((e) => e.restriction, 'restriction', LiveRestriction.paid)
              .having((e) => e.retryable, 'retryable', isFalse),
        ),
      );
    });

    test('a lease travels with the selected line', () async {
      final refreshAt = DateTime.utc(2026, 10, 1, 12);
      final site = FakeSite(
        lines: {
          'origin': [
            LivePlayLine(
              'rtmp://a.example/live',
              lease: PlayLease(refreshAt: refreshAt, expiresAt: refreshAt),
            ),
          ],
        },
      );
      // getPlayUrls drops metadata; a LivePlayUrlResolver keeps it.
      final stream = await RecordStreamResolver((_) => _LineSite(site))
          .resolve(roomId: '1', platform: 'fake', preferredQuality: '原画');
      expect(stream.refreshAt, refreshAt);
      expect(stream.usableAt(refreshAt), isFalse);
    });
  });

  test('live FLV and HLS lines are recorded through the loopback relay, other schemes directly', () async {
    final opener = RecordInputOpener();
    addTearDown(opener.close);
    const quality = LivePlayQuality(quality: '原画');
    Future<MediaInput> open(String url) => opener.open(
      ResolvedRecordStream(source: LineSource(LivePlayLine(url)), quality: quality, qualityCursorId: '1', lineIndex: 0),
      site: 'fake',
    );
    final flv = await open('https://cdn.example/live/1.flv?sign=a');
    expect(flv.private, isTrue);
    expect(flv.uri.host, '127.0.0.1');
    expect(flv.headers, isEmpty);
    final hls = await open('https://cdn.example/live/1.m3u8');
    expect(hls.private, isTrue);
    expect(hls.uri.path, isNot(flv.uri.path));
    final rtmp = await open('rtmp://cdn.example/live/1');
    expect(rtmp.private, isFalse);
    await flv.close();
    expect(flv.isUsable, isFalse);
  });

  group('recorder', () {
    late Directory root;
    late FakeSite site;
    late FakeFfmpeg ffmpeg;
    late Recorder recorder;
    late List<String> persisted;
    var settings = RecordSettings();

    setUp(() {
      root = Directory.systemTemp.createTempSync('live_record');
      site = FakeSite();
      ffmpeg = FakeFfmpeg();
      persisted = [];
      settings = RecordSettings();
      recorder = Recorder(
        sites: (id) => id == 'fake' ? site : null,
        ffmpeg: ffmpeg,
        storage: RecordStorage(defaultDirectory: () async => root.path, configuredPath: () => ''),
        settings: () => settings,
        persist: (json) async => persisted.add(json),
        outputSampleInterval: const Duration(milliseconds: 20),
        startGap: Duration.zero,
      );
    });

    tearDown(() async {
      await recorder.dispose();
      root.deleteSync(recursive: true);
    });

    Future<void> until(bool Function() condition, {Duration within = const Duration(seconds: 10)}) async {
      final deadline = DateTime.now().add(within);
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('timed out');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    LiveRoom room() => LiveRoom(roomId: '1', platform: 'fake', nick: '主播', liveStatus: LiveStatus.live);

    test('records, stops at the user request and joins the attempt into MP4', () async {
      final task = (await recorder.addTask(room()))!;
      await until(() => task.status == RecordStatus.running);
      expect(ffmpeg.runs.single, containsAllInOrder(['-i', 'rtmp://cdn-a.example/live/1?sign=a']));
      expect(task.selectedQuality, '原画');
      await until(() => task.fileSize > 0 && task.bitrate >= 0);
      final directory = task.outputDir!;
      expect(directory, contains('fake${Platform.pathSeparator}主播'));
      await recorder.stopTask(task);
      expect(task.status, RecordStatus.stopped);
      expect(task.pendingAttempts, isEmpty);
      final files = Directory(directory).listSync().map((entity) => entity.path.split(Platform.pathSeparator).last);
      expect(files, ['${task.recordingFilePrefix}.mp4']);
      expect(ffmpeg.executions.first.cancelled, isTrue);
      await recorder.flush();
      expect(persisted.last, isNot(contains('rtmp://')));
    });

    test('a live EOF reconnects quickly with a new attempt and joins both at the end', () async {
      ffmpeg
        ..captureExit = 0
        ..captureSeconds = const Duration(milliseconds: 50);
      final task = (await recorder.addTask(room()))!;
      await until(() => task.status == RecordStatus.reconnecting);
      expect(task.lastErrorStage, 'ffmpeg.unexpectedeof');
      expect(task.pendingAttempts, hasLength(1));
      ffmpeg.captureExit = null;
      await until(() => ffmpeg.runs.length == 2 && task.status == RecordStatus.running);
      await recorder.stopTask(task);
      expect(task.status, RecordStatus.stopped);
      expect(task.pendingAttempts, isEmpty);
      expect(ffmpeg.runs.where((run) => run.contains('concat')), hasLength(2));
    }, timeout: const Timeout(Duration(seconds: 20)));

    group('after the broadcast ends', () {
      // The platform still says live and serves a URL, but every capture
      // ends at once with an EOF (a closed or 404 signed stream).
      setUp(() {
        settings = RecordSettings(maxRetryCount: 1);
        ffmpeg
          ..captureExit = 0
          ..captureSeconds = const Duration(seconds: 1);
      });

      List<List<String>> captures() => [
        for (final run in ffmpeg.runs)
          if (!run.contains('concat')) run,
      ];
      List<List<String>> joins() => [
        for (final run in ffmpeg.runs)
          if (run.contains('concat')) run,
      ];

      test(
        'the fast retries stop at twice the limit, the attempts are joined and the task waits for the room',
        () async {
          final task = (await recorder.addTask(room()))!;
          await until(() => task.status == RecordStatus.waitingLive, within: const Duration(seconds: 20));
          expect(captures(), hasLength(2));
          expect(joins(), hasLength(2));
          expect(task.pendingAttempts, isEmpty);
          expect(task.lastOutputPath, endsWith('.mp4'));
          expect(File(task.lastOutputPath!).existsSync(), isTrue);
          await Future<void>.delayed(const Duration(seconds: 3));
          expect(captures(), hasLength(2));
          expect(task.status, RecordStatus.waitingLive);
        },
        timeout: const Timeout(Duration(seconds: 40)),
      );

      test('开播自动录 off: the fast retries running out end the session saved, not failed', () async {
        final task = (await recorder.addTask(room(), autoRecord: false))!;
        await until(() => task.status.isFinished, within: const Duration(seconds: 20));
        expect(task.status, RecordStatus.completed);
        expect(task.lastError, isNull);
        expect(task.pendingAttempts, isEmpty);
        expect(task.lastOutputPath, endsWith('.mp4'));
      }, timeout: const Timeout(Duration(seconds: 40)));

      test('a network outage keeps reconnecting without using up the limit', () async {
        final task = (await recorder.addTask(room()))!;
        await until(() => task.status == RecordStatus.reconnecting);
        site.detailError = Exception('offline network');
        await until(() => task.retryCount > 2, within: const Duration(seconds: 20));
        expect(task.status, RecordStatus.reconnecting);
        expect(task.lastErrorStage, isNotNull);
        site.detailError = null;
        ffmpeg.captureExit = null;
        await until(() => task.status == RecordStatus.running, within: const Duration(seconds: 20));
        expect(captures(), hasLength(2));
      }, timeout: const Timeout(Duration(seconds: 60)));

      test('with the live check on, the task checks the room again after the join', () async {
        settings = RecordSettings(maxRetryCount: 1, enablePolling: true, liveCheckInterval: 10);
        final task = (await recorder.addTask(room()))!;
        await until(() => task.status == RecordStatus.waitingLive, within: const Duration(seconds: 20));
        expect(task.pendingAttempts, isEmpty);
        ffmpeg.captureExit = null;
        await until(
          () => captures().length == 3 && task.status == RecordStatus.running,
          within: const Duration(seconds: 20),
        );
      }, timeout: const Timeout(Duration(seconds: 60)));
    });

    test('when the room reports offline, the session is joined before it waits again', () async {
      ffmpeg
        ..captureExit = 0
        ..captureSeconds = const Duration(seconds: 1);
      final task = (await recorder.addTask(room(), autoRecord: true))!;
      await until(() => task.status == RecordStatus.reconnecting);
      expect(task.pendingAttempts, hasLength(1));
      final statuses = <RecordStatus>[];
      final subscription = recorder.changes.listen((_) => statuses.add(task.status));
      addTearDown(subscription.cancel);
      site.status = LiveStatus.offline;
      await until(() => task.status == RecordStatus.waitingLive, within: const Duration(seconds: 20));
      expect(statuses, contains(RecordStatus.processing));
      expect(statuses.indexOf(RecordStatus.processing), lessThan(statuses.indexOf(RecordStatus.waitingLive)));
      expect(task.pendingAttempts, isEmpty);
      expect(task.lastOutputPath, endsWith('.mp4'));
      expect(task.lastError, isNull);
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('with the live check on, a room found offline by a start is checked again', () async {
      settings = RecordSettings(enablePolling: true, liveCheckInterval: 10);
      site.status = LiveStatus.offline;
      final task = (await recorder.addTask(room()))!;
      await until(() => task.status == RecordStatus.waitingLive);
      site.status = LiveStatus.live;
      await until(() => task.status == RecordStatus.running, within: const Duration(seconds: 20));
      expect(ffmpeg.runs, hasLength(1));
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('an offline room waits for the live check', () async {
      site.status = LiveStatus.offline;
      final task = (await recorder.addTask(room()))!;
      await until(() => task.status == RecordStatus.waitingLive);
      expect(ffmpeg.runs, isEmpty);
      expect(task.lastError, isNull);
    });

    test('a packet cut off by the stop is a discarded tail, not damage: the attempt joins', () async {
      ffmpeg.stopLog = '[in#0/flv @ 0x1] Packet corrupt (stream = 0, dts = 13840), dropping it.';
      final task = (await recorder.addTask(room()))!;
      await until(() => task.status == RecordStatus.running);
      await recorder.stopTask(task);
      expect(task.status, RecordStatus.stopped);
      expect(task.lastError, isNull);
      expect(task.pendingAttempts, isEmpty);
      expect(task.lastOutputPath, endsWith('.mp4'));
      expect(task.inputTailDiscarded, isTrue);
    });

    test('a damaged attempt is joined and keeps its source (H01.6)', () async {
      final task = (await recorder.addTask(room()))!;
      await until(() => task.status == RecordStatus.running);
      ffmpeg.executions.single.log('[h264 @ 0x1] Packet corrupt (stream = 0, dts = 1)');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await recorder.stopTask(task);
      expect(task.status, RecordStatus.stopped);
      expect(task.lastError, isNull);
      expect(task.pendingAttempts, isEmpty);
      expect(task.lastOutputPath, endsWith('.mp4'));
      expect(task.inputDamagedKept, isTrue);
      expect(Directory(task.outputDir!).listSync().where((file) => file.path.endsWith('.ts')), hasLength(1));
    });

    test('HLS audio drops at segment boundaries are not damage (H01.6, YY on the K90)', () async {
      final task = (await recorder.addTask(room()))!;
      await until(() => task.status == RecordStatus.running);
      // FFmpeg Kit hands over each av_log call: a stream line comes in parts.
      [
        '  Stream #0:0',
        '[0x100]',
        ': Video: h264 (High), yuv420p, 1280x720, 25 fps\n',
        '  Stream #0:1',
        '[0x101]',
        ': Audio: aac (LC), 44100 Hz, stereo, fltp\n',
        "Output #0, mpegts, to 'seg.ts':\n",
        '  Stream #0:0: Video: h264\n',
      ].forEach(ffmpeg.executions.single.log);
      for (var i = 0; i < 5; i++) {
        ffmpeg.executions.single.log(
          '[mpegts @ 0x1] Packet corrupt (stream = 1, dts = ${257745150 + i * 180000}), dropping it.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await recorder.stopTask(task);
      expect(task.status, RecordStatus.stopped);
      expect(task.lastError, isNull);
      expect(task.lastOutputPath, endsWith('.mp4'));
      expect(task.inputDamagedKept, isFalse);
      expect(Directory(task.outputDir!).listSync().where((file) => file.path.endsWith('.ts')), isEmpty);
    });

    test('restore joins an interrupted recording and drops unsupported platforms', () async {
      final directory = Directory('${root.path}/fake/a/2026-10-01/10-00-00')..createSync(recursive: true);
      const prefix = '20261001_100000_000';
      File('${directory.path}/${prefix}_000000.clock-v1.ts').writeAsBytesSync(List.filled(10, 1));
      File('${directory.path}/$prefix.clock-v1.csv').writeAsStringSync('${prefix}_000000.clock-v1.ts,0.0,4.0\n');
      final stored = RecordTask(
        taskId: 'fake_1',
        roomId: '1',
        platform: 'fake',
        title: '',
        nick: 'a',
        avatar: '',
        cover: '',
        createTime: DateTime(2026, 10, 1, 10),
        status: RecordStatus.running,
        outputDir: directory.path,
      );
      final other = RecordTask.fromJson({...stored.toJson(), 'taskId': 'gone_1', 'platform': 'gone'});
      await recorder.restore(jsonEncode([stored.toJson(), other.toJson()]));
      final task = recorder.tasks.single;
      expect(task.status, RecordStatus.stopped);
      expect(File('${directory.path}/$prefix.mp4').existsSync(), isTrue);
    });

    test("the live room's quality is the one resolved, for this task only (U.2f)", () async {
      site
        ..qualities = const [
          LivePlayQuality(quality: '原画', id: 'origin', sort: 2),
          LivePlayQuality(quality: '超清', id: 'hd', sort: 1),
        ]
        ..lines = {
          'origin': const [LivePlayLine('rtmp://cdn-a.example/live/origin')],
          'hd': const [LivePlayLine('rtmp://cdn-a.example/live/hd')],
        };
      final task = (await recorder.addTask(room(), quality: '超清', recordDanmaku: true, autoRecord: false))!;
      expect(task.qualityOverride, '超清');
      expect(task.recordDanmakuOverride, isTrue);
      expect(task.autoRecord, isFalse);
      await until(() => task.status == RecordStatus.running);
      expect(task.selectedQuality, '超清');
      expect(ffmpeg.runs.single, contains('rtmp://cdn-a.example/live/hd'));
      await recorder.stopTask(task);

      recorder.setTaskOptions(task, quality: '原画');
      expect(task.qualityOverride, '原画');
      await recorder.startTask(task);
      await until(() => task.status == RecordStatus.running && task.selectedQuality == '原画');
      expect(ffmpeg.runs.last, contains('rtmp://cdn-a.example/live/origin'));
      await recorder.stopTask(task);
      expect(task.lastOutputPath, endsWith('.mp4'));
      await recorder.flush();
      expect(persisted.last, contains('"qualityOverride":"原画"'));
    });

    test('开播自动录: off finishes after the broadcast, on waits again; on for a stopped task resumes', () async {
      // The broadcast ends: FFmpeg reaches the end, the retry finds the room
      // offline.
      ffmpeg
        ..captureExit = 0
        ..captureSeconds = const Duration(milliseconds: 50);
      final once = (await recorder.addTask(room(), autoRecord: false))!;
      await until(() => once.status == RecordStatus.reconnecting);
      site.status = LiveStatus.offline;
      await until(() => once.status == RecordStatus.completed);
      expect(once.pendingAttempts, isEmpty);
      expect(once.lastOutputPath, endsWith('.mp4'));
      await recorder.removeTask(once);

      site.status = LiveStatus.live;
      final kept = (await recorder.addTask(room(), autoRecord: true))!;
      await until(() => kept.status == RecordStatus.reconnecting);
      site.status = LiveStatus.offline;
      await until(() => kept.status == RecordStatus.waitingLive);
      await recorder.stopTask(kept);
      expect(kept.status, RecordStatus.stopped);

      settings = RecordSettings(enablePolling: true, liveCheckInterval: 10);
      site.status = LiveStatus.offline;
      await recorder.monitorTask(kept);
      expect(kept.status, RecordStatus.waitingLive);
      expect(kept.wasStoppedByUser, isFalse);
      await recorder.refreshTaskStatus(kept);
      expect(kept.lastLiveCheckAt, isNotNull);
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('the queue holds tasks above the concurrency limit', () async {
      settings = RecordSettings(maxTaskCount: 1);
      final first = (await recorder.addTask(room()))!;
      final second = (await recorder.addTask(
        LiveRoom(roomId: '2', platform: 'fake', nick: 'b', liveStatus: LiveStatus.live),
      ))!;
      await until(() => first.status == RecordStatus.running);
      expect(second.status, RecordStatus.queued);
      await recorder.stopTask(first);
      await until(() => second.status == RecordStatus.running);
      await recorder.removeTask(second);
      expect(recorder.tasks, [first]);
    });
  });
}

final class _LineSite extends LiveSite implements LivePlayUrlResolver {
  new(this.inner);

  final FakeSite inner;

  @override
  String get id => inner.id;

  @override
  String get name => inner.name;

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) => inner.getRoomDetail(roomId: roomId);

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) => inner.getPlayQualities(detail: detail);

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution.lines(inner.lines['${quality.selectionId}'] ?? const []);
}
