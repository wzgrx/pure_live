import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:pure_live/features/recorder/recorder_texts.dart';
import 'package:pure_live/platform/recording_platform.dart';

import '../../support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadStrings);

  test('a refused restricted room is explained with the live room words (22-1)', () {
    final task = RecordTask(
      taskId: 'tiktok_a',
      roomId: 'a',
      platform: 'tiktok',
      title: 't',
      nick: '主播甲',
      avatar: '',
      cover: '',
      createTime: DateTime(2026),
    );
    final notice = RecordNotice(
      task,
      RecordNoticeKind.resolveFailed,
      streamError: const RecordStreamException(
        RecordStreamErrorType.restricted,
        'no stream',
        retryable: false,
        restriction: LiveRestriction.subscribersOnly,
      ),
    );
    expect(recordNoticeText(notice), '主播甲: 该直播仅限主播的订阅者或会员观看');
    task
      ..lastErrorStage = 'ffmpeg.inputopen'
      ..lastError = 'Connection refused';
    final failure = recordFailureText(task);
    expect(failure.summary, contains('录制内核未能打开当前直播线路'));
    expect(failure.detail, 'Connection refused');
  });

  test('a failed join says in Chinese that the segments are kept, the diagnostic below (H01.5)', () {
    final task =
        RecordTask(
            taskId: 'bilibili_1',
            roomId: '1',
            platform: 'bilibili',
            title: 't',
            nick: '主播甲',
            avatar: '',
            cover: '',
            createTime: DateTime(2026),
          )
          ..lastErrorStage = 'merge'
          ..lastError = 'Joining the recording failed';
    final failure = recordFailureText(task);
    expect(failure.summary, '最近失败（文件合并）：分段没能合成 MP4，原始分段保留在录制文件夹里');
    expect(failure.detail, 'Joining the recording failed');
  });

  test('a limited quality is said like the player says it', () {
    final task = RecordTask(
      taskId: 'bilibili_1',
      roomId: '1',
      platform: 'bilibili',
      title: 't',
      nick: '主播甲',
      avatar: '',
      cover: '',
      createTime: DateTime(2026),
    );
    expect(recordNoticeText(RecordNotice(task, RecordNoticeKind.qualityLimited, quality: '超清')), '平台实际返回 超清，已按真实画质录制');
    expect(recordNoticeText(RecordNotice(task, RecordNoticeKind.qualityLimited)), isNull);
  });

  test(
    "Android's recording service: one start for many tasks, refused after Android stopped it until a user start",
    () async {
      const channel = MethodChannel('pure_live/recorder');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final calls = <Object?>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add((call.arguments as Map)['active']);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final interrupted = <String>[];
      final first = Object();
      final second = Object();
      late final AndroidRecordKeepAlive keepAlive;
      keepAlive = AndroidRecordKeepAlive(
        title: () => 'title',
        text: () => 'text',
        onInterrupted: (reason) async {
          interrupted.add(reason);
          await keepAlive.release(first);
        },
      );

      await keepAlive.acquire(first);
      await keepAlive.acquire(second);
      await keepAlive.release(second);
      expect(calls, [true]);

      await messenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('interrupted', {'reason': 'timeout'})),
        (_) {},
      );
      expect(interrupted, ['timeout']);
      expect(calls, [true, false], reason: 'the stop still reaches Android so the locks are released');
      await expectLater(
        keepAlive.acquire(Object()),
        throwsA(isA<RecordKeepAliveException>().having((error) => error.reason, 'reason', 'timeout')),
      );

      keepAlive.allowUserRetry();
      await keepAlive.acquire(first);
      expect(calls, [true, false, true]);
    },
  );
}
