import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

void main() {
  RecordTask task() => RecordTask(
    taskId: 'douyu_1',
    roomId: '1',
    platform: 'douyu',
    title: 't',
    nick: 'n',
    avatar: '',
    cover: '',
    createTime: DateTime(2026, 10, 1, 8, 9, 10, 11),
  );

  test('3.x JSON prefers enum names, tolerates numeric drift and resets the timestamp sentinel', () {
    final restored = RecordTask.fromJson({
      'roomId': 1,
      'platform': 'DOUYU',
      'status': 0,
      'statusName': 'running',
      'liveStatus': '1',
      'recordedSeconds': 2147483647,
      'fileSize': '42',
      'autoReconnect': 'false',
      'selectedLineIndex': 2.0,
    });
    expect(restored.taskId, 'douyu_1');
    expect(restored.status, RecordStatus.running);
    expect(restored.liveStatus, LiveStatus.offline);
    expect(restored.recordedSeconds, 0);
    expect(restored.fileSize, 42);
    expect(restored.autoReconnect, isFalse);
    expect(restored.selectedLineIndex, 2);
    expect(restored.audienceMetricType, AudienceMetricType.popularity);
    expect(RecordTask.fromJson({'status': 'x'}).status, RecordStatus.stopped);
  });

  test("the live room's own choices are stored only when set; 3.x JSON follows the settings (U.2f)", () {
    final plain = task().toJson();
    for (final key in ['qualityOverride', 'recordDanmakuOverride', 'autoRecord', 'lastOutputPath']) {
      expect(plain.containsKey(key), isFalse, reason: '$key keeps 3.x JSON as it was');
    }
    final legacy = RecordTask.fromJson(plain);
    expect(legacy.qualityOverride, isNull);
    expect(legacy.recordDanmakuOverride, isNull);
    expect(legacy.autoRecord, isNull);
    expect(legacy.preferredQuality('超清'), '超清');
    expect(legacy.recordsChat(fallback: true), isTrue);

    final chosen = task()
      ..qualityOverride = '蓝光'
      ..recordDanmakuOverride = false
      ..autoRecord = true
      ..lastOutputPath = '/r/a.mp4'
      ..lastLiveCheckAt = DateTime(2026, 10, 2)
      ..nextRetryAt = DateTime(2026, 10, 2);
    final json = chosen.toJson();
    expect(json, containsPair('qualityOverride', '蓝光'));
    expect(json.containsKey('lastLiveCheckAt'), isFalse, reason: 'runtime only');
    final restored = RecordTask.fromJson(json);
    expect(restored.qualityOverride, '蓝光');
    expect(restored.recordDanmakuOverride, isFalse);
    expect(restored.autoRecord, isTrue);
    expect(restored.lastOutputPath, '/r/a.mp4');
    expect(restored.preferredQuality('原画'), '蓝光');
    expect(restored.recordsChat(fallback: true), isFalse);
    expect(RecordTask.fromJson({...json, 'autoRecord': 'false'}).autoRecord, isFalse);
  });

  test('signed URLs and credentials are never persisted', () {
    final original = task()
      ..currentUrl = 'https://cdn.example/live.flv?token=secret'
      ..markFailure(stage: 'stream', error: 'GET https://cdn.example/a?sign=x failed\nCookie: SESSDATA=y');
    final json = original.toJson();
    expect(json.containsKey('currentUrl'), isFalse);
    expect('$json', isNot(contains('secret')));
    expect(original.lastError, isNot(contains('SESSDATA')));
    expect(original.lastError, contains('[stream-url]'));
    final restored = RecordTask.fromJson({...json, 'lastError': 'key=abc token=def', 'lastErrorStage': 'weird'});
    expect(restored.lastError, 'key=[redacted] token=[redacted]');
    expect(restored.lastErrorStage, isNull);
    expect(RecordTask.fromJson({...json, 'lastErrorStage': 'ffmpeg.httpAccess'}).lastErrorStage, 'ffmpeg.httpaccess');
  });

  test('pending attempts deduplicate and never lose a damage verdict', () {
    final value = task()
      ..queuePendingAttempt(directoryPath: '/r', filePrefix: 'a', inputIntegrityError: true)
      ..queuePendingAttempt(directoryPath: '/r', filePrefix: 'a')
      ..queuePendingAttempt(directoryPath: '/r', filePrefix: 'b');
    expect(value.pendingAttempts, hasLength(2));
    expect(value.pendingAttempts.first.inputIntegrityError, isTrue);
    final restored = RecordTask.fromJson({
      'pendingAttempts': [
        {'directoryPath': '/r', 'filePrefix': 'a'},
        {'directoryPath': '/r', 'filePrefix': 'a', 'inputIntegrityError': true},
        {'directoryPath': '', 'filePrefix': 'c'},
      ],
    });
    expect(restored.pendingAttempts.single.inputIntegrityError, isTrue);
  });

  test('a retry keeps the session start and totals, a new recording resets them', () {
    final value = task()
      ..beginNewRecording(now: DateTime(2026, 10, 1, 10))
      ..recordedSeconds = 30
      ..fileSize = 100
      ..inputCoverageIncomplete = true
      ..beginNewAttempt(now: DateTime(2026, 10, 1, 10, 5));
    expect(value.recordingStartedAt, DateTime(2026, 10, 1, 10));
    expect(value.recordedSeconds, 30);
    expect(value.inputCoverageIncomplete, isTrue);
    expect(value.recordingFilePrefix, '20261001_100500_000');
    value.beginNewRecording(now: DateTime(2026, 10, 1, 11));
    expect(value.recordedSeconds, 0);
    expect(value.inputCoverageIncomplete, isFalse);
  });

  test('display order groups actionable states, newest session first', () {
    final running = task()..status = RecordStatus.running;
    final stoppedNew = RecordTask.fromJson({...task().toJson(), 'taskId': 'b', 'status': 8})
      ..recordingStartedAt = DateTime(2026, 10, 2);
    final stoppedOld = RecordTask.fromJson({...task().toJson(), 'taskId': 'c', 'status': 8});
    final grouped = RecordTask.forDisplay([stoppedOld, running, stoppedNew], groupByStatus: true);
    expect(grouped.map((task) => task.taskId), ['douyu_1', 'b', 'c']);
  });

  test('settings clamp out-of-range values like 3.x', () {
    final settings = RecordSettings(segmentTime: 5, maxTaskCount: 99, rwTimeout: 7, defaultQuality: 'x');
    expect(settings.segmentTime, 60);
    expect(settings.maxTaskCount, 10);
    expect(settings.rwTimeout, 15);
    expect(settings.defaultQuality, '原画');
  });

  test('folder names are portable path components', () {
    expect(safePathComponent(r'a/b\c:d*?"<>|'), 'a_b_c_d_');
    expect(safePathComponent('con'), '_con');
    expect(safePathComponent('...'), 'unknown');
    expect(safePinyinComponent('斗鱼'), 'douyu');
  });
}
