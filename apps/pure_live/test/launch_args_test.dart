import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/launch_args.dart';

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

  test('only the hand-over file the launcher wrote is imported', () {
    final temp = p.join(Directory.systemTemp.path, 'fixture-temp');
    const id = 'window_42_1790000000';
    List<String> args(String path, {String instance = id}) => [
      '${LaunchArgs.instancePrefix}$instance',
      '${LaunchArgs.configPrefix}$path',
    ];
    final handOver = p.join(temp, 'pure_live_instance_ab12', '$id.json');

    expect(LaunchArgs.configFileFromArgs(args(handOver), tempRoot: temp), p.normalize(p.absolute(handOver)));
    for (final path in [
      p.join(Directory.systemTemp.path, 'elsewhere', 'settings.json'),
      p.join(temp, 'other_ab12', '$id.json'),
      p.join(temp, 'pure_live_instance_ab12', 'window_other.json'),
      p.join(temp, 'pure_live_instance_ab12', '..', '..', 'etc', '$id.json'),
      p.join(temp, '$id.json'),
      '',
    ]) {
      expect(LaunchArgs.configFileFromArgs(args(path), tempRoot: temp), isNull, reason: path);
    }
    expect(
      LaunchArgs.configFileFromArgs(['${LaunchArgs.configPrefix}$handOver'], tempRoot: temp),
      isNull,
      reason: 'the main window never imports a hand-over file',
    );
  });

  test('a new window gets the data and the cookies, never in plain text (M9 issue 12)', () async {
    final cipher = FakeCipher();
    final source = await LiveStore.memory(cipher: cipher);
    final target = await LiveStore.memory(cipher: cipher);
    addTearDown(source.close);
    addTearDown(target.close);
    await source.follows.add(LiveRoom(platform: 'bilibili', roomId: '1', nick: 'A'));
    await source.settings.set(Settings.enableAppProxy, true);
    await source.secrets.setCookie('bilibili', 'SESSDATA=secret-value');
    final temp = await Directory.systemTemp.createTemp('handoff_test_');
    addTearDown(() => temp.delete(recursive: true));

    final path = await NewWindowHandoff.write(source, cipher, instanceId: 'window_1', tempRoot: temp);
    final file = File(path);
    expect(await file.readAsString(), isNot(contains('secret-value')));
    expect(
      LaunchArgs.configFileFromArgs(
        LaunchArgs.build(instanceId: 'window_1', configFile: path),
        tempRoot: temp.path,
      ),
      path,
    );

    expect(await NewWindowHandoff.restore(target, cipher, file), isTrue);
    expect((await target.follows.all()).single.nick, 'A');
    expect(target.settings.get(Settings.enableAppProxy), isTrue);
    expect(target.secrets.cookieFor('bilibili'), 'SESSDATA=secret-value');
    expect(file.parent.existsSync(), isFalse, reason: 'the hand-over file is deleted');
  });
}
