import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/utils/windows_multi_instance_launcher.dart';

void main() {
  test('room command-line payload round-trips without platform response blobs', () {
    final room = LiveRoom(
      roomId: '23030429',
      platform: 'BILIBILI',
      title: '测试直播间',
      nick: '主播',
      status: true,
      liveStatus: LiveStatus.live,
      data: Object(),
      danmakuData: Object(),
    );
    final args = WindowsMultiInstanceLauncher.buildArguments(room: room, processId: 42, timestampMicros: 123456);

    expect(args.first, '--instance=window_42_123456');
    expect(args.length, 2);
    final decoded = WindowsMultiInstanceLauncher.roomFromArgs(args);
    expect(decoded, isNotNull);
    expect(decoded!.roomId, '23030429');
    expect(decoded.platform, 'bilibili');
    expect(decoded.title, '测试直播间');
    expect(decoded.nick, '主播');
    expect(decoded.data, isNull);
    expect(decoded.danmakuData, isNull);
  });

  test('instance ids are sanitized and malformed room payloads are ignored', () {
    expect(WindowsMultiInstanceLauncher.instanceIdFromArgs(const ['--instance=room ../A-1']), 'room.A-1');
    expect(WindowsMultiInstanceLauncher.instanceIdFromArgs(const ['--instance=../../']), isEmpty);
    expect(WindowsMultiInstanceLauncher.instanceIdFromArgs(const ['--instance=NUL']), 'instance_NUL');
    expect(WindowsMultiInstanceLauncher.roomFromArgs(const ['--open-room=not_base64!']), isNull);
  });

  test('room payload carries canonical offline state instead of a stale legacy boolean', () {
    final room = LiveRoom(roomId: 'ended', platform: 'huya', status: true, liveStatus: LiveStatus.offline);

    final decoded = WindowsMultiInstanceLauncher.roomFromArgs([WindowsMultiInstanceLauncher.encodeRoomArgument(room)]);

    expect(decoded, isNotNull);
    expect(decoded!.effectiveLiveStatus, LiveStatus.offline);
    expect(decoded.status, isFalse);
  });

  test('only the settings file the launcher wrote is imported', () {
    const temp = '/tmp/fixture-temp';
    const id = 'window_42_1790000000';
    List<String> args(String path, {String instance = id}) => [
      '${WindowsMultiInstanceLauncher.instancePrefix}$instance',
      '${WindowsMultiInstanceLauncher.configPrefix}$path',
    ];

    expect(
      WindowsMultiInstanceLauncher.configFileFromArgs(args('$temp/pure_live_instance_ab12/$id.json'), tempRoot: temp),
      '$temp/pure_live_instance_ab12/$id.json',
    );
    for (final path in [
      '/home/user/Documents/settings.json',
      '$temp/other_ab12/$id.json',
      '$temp/pure_live_instance_ab12/window_other.json',
      '$temp/pure_live_instance_ab12/../../etc/$id.json',
      '$temp/$id.json',
      '',
    ]) {
      expect(WindowsMultiInstanceLauncher.configFileFromArgs(args(path), tempRoot: temp), isNull, reason: path);
    }
    expect(
      WindowsMultiInstanceLauncher.configFileFromArgs([
        '${WindowsMultiInstanceLauncher.configPrefix}$temp/pure_live_instance_ab12/$id.json',
      ], tempRoot: temp),
      isNull,
      reason: 'the main window never imports a hand-over file',
    );
  });
}
