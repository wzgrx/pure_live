import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/data_root.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/recording.dart';

import 'support.dart';

void main() {
  // Ported from 3.x test/windows_multi_instance_launcher_test.dart.
  test('room command-line payload round-trips without platform response blobs', () {
    final room = LiveRoom(
      roomId: '23030429',
      platform: 'BILIBILI',
      title: '测试直播间',
      nick: '主播',
      liveStatus: LiveStatus.live,
      data: Object(),
      danmakuData: Object(),
    );
    final args = LaunchArgs.build(room: room, processId: 42, timestampMicros: 123456);

    expect(args.first, '--instance=window_42_123456');
    expect(args, hasLength(2));
    final decoded = LaunchArgs.roomFromArgs(args)!;
    expect(decoded.roomId, '23030429');
    expect(decoded.platform, 'bilibili');
    expect(decoded.title, '测试直播间');
    expect(decoded.nick, '主播');
    expect(decoded.data, isNull);
    expect(decoded.danmakuData, isNull);
  });

  test('instance ids are sanitized and malformed room payloads are ignored', () {
    expect(LaunchArgs.instanceIdFromArgs(const ['--instance=room ../A-1']), 'room.A-1');
    expect(LaunchArgs.instanceIdFromArgs(const ['--instance=../../']), isEmpty);
    expect(LaunchArgs.instanceIdFromArgs(const ['--instance=NUL']), 'instance_NUL');
    expect(LaunchArgs.roomFromArgs(const ['--open-room=not_base64!']), isNull);
  });

  test('room payload carries the offline state', () {
    final room = LiveRoom(roomId: 'ended', platform: 'huya', liveStatus: LiveStatus.offline);
    final decoded = LaunchArgs.roomFromArgs([LaunchArgs.encodeRoomArgument(room)])!;
    expect(decoded.effectiveLiveStatus, LiveStatus.offline);
    expect(decoded.isLiveNow, isFalse);
  });

  test('extra windows share the data folder; their log and task list are their own (U.13 c14)', () async {
    final root = Directory(p.join('data', 'UserData'));
    expect(instanceFolder(root, 'window_1').path, p.join('data', 'UserData', 'instances', 'window_1'));
    final launch = LaunchArgs.parse(const ['--instance=window_1', '--config-file=C:/Temp/x.json']);
    expect(launch.isPrimary, isFalse);
    expect(launch.room, isNull, reason: "3.x's hand-over file is ignored: nothing is copied any more");
    expect(LaunchArgs.build(instanceId: 'window_2'), ['--instance=window_2']);

    expect(recorderTasksKeyFor(''), recorderTasksKey);
    expect(recorderTasksKeyFor('window_1'), '$recorderTasksKey.window_1');
    final store = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(store.close);
    await store.meta.keepLegacyValues({'recorder_tasks': '[]'});
    expect(await savedRecorderTasks(store), '[]', reason: "the main window takes 3.x's list");
    expect(await savedRecorderTasks(store, key: recorderTasksKeyFor('window_1')), isNull);
  });
}
