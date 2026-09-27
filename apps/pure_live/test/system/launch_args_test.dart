import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live_app/features/system/launch_args.dart';

void main() {
  group('LaunchArgs (F-APP-04, F-WIN-02)', () {
    test('accepts the forms the launcher writes', () {
      expect(LaunchArgs.parse(const []), const LaunchArgs());
      expect(
        LaunchArgs.parse(const ['--instance', '--open-room=douyu:288016']),
        LaunchArgs(secondaryWindow: true, openRoom: RoomRef('douyu', '288016')),
      );
      expect(LaunchArgs.parse(const ['--open-room=kuaishou:3xabc_d-e.f']).openRoom, RoomRef('kuaishou', '3xabc_d-e.f'));
    });

    test('ignores everything else', () {
      for (final bad in [
        '--open-room=',
        '--open-room=douyu',
        '--open-room=:1',
        '--open-room=twitch:abc',
        '--open-room=DOUYU:1',
        '--open-room=douyu:0',
        '--open-room=douyu:../../etc',
        '--open-room=douyu:a b',
        '--open-room=douyu:${'1' * 65}',
        '--open-room=eyJwbGF0Zm9ybSI6ImRvdXl1In0',
      ]) {
        expect(LaunchArgs.parse([bad]).openRoom, isNull, reason: bad);
      }
      // 3.x forms: an instance id and a settings hand-off file are not accepted.
      final legacy = LaunchArgs.parse(const ['--instance=window_1_2', r'--config-file=C:\Temp\x.json']);
      expect(legacy, const LaunchArgs());
    });

    test('the first valid room wins; the new-window arguments round-trip', () {
      final args = LaunchArgs.parse(const ['--open-room=bad', '--open-room=huya:kpl', '--open-room=douyu:1']);
      expect(args.openRoom, RoomRef('huya', 'kpl'));
      final room = RoomRef('bilibili', '21452505');
      final forNew = LaunchArgs.forNewWindow(room);
      expect(forNew, ['--instance', '--open-room=bilibili:21452505']);
      expect(LaunchArgs.parse(forNew), LaunchArgs(secondaryWindow: true, openRoom: room));
    });

    test('a new window starts this executable detached with those arguments', () async {
      final started = <(String, List<String>, ProcessStartMode)>[];
      Future<Process> start(
        String executable,
        List<String> arguments, {
        ProcessStartMode mode = ProcessStartMode.normal,
      }) {
        started.add((executable, arguments, mode));
        return Future.error(const ProcessException('app.exe', [], 'not in tests'));
      }

      final room = RoomRef('douyu', '1');
      expect(await openRoomInNewWindow(room, start: start, executable: 'app.exe', supported: true), isFalse);
      final (executable, arguments, mode) = started.single;
      expect(executable, 'app.exe');
      expect(arguments, ['--instance', '--open-room=douyu:1']);
      expect(mode, ProcessStartMode.detached);
      expect(await openRoomInNewWindow(room, start: start, supported: false), isFalse);
      expect(started, hasLength(1));
    });
  });
}
