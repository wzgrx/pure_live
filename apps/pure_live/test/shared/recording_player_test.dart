import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/record/recording_player_page.dart';

import '../features/live_play/live_play_support.dart';
import '../support.dart';

void main() {
  test("V01.8: the recordings beside a file are its folder's videos in name order", () {
    final dir = Directory.systemTemp.createTempSync('recordings');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final name in ['b_2.mp4', 'a_1.flv', 'notes.txt', 'c_3.ts']) {
      File('${dir.path}/$name').writeAsStringSync('x');
    }
    final files = recordingsBeside('${dir.path}/b_2.mp4');
    expect(files.map((path) => path.split('/').last), ['a_1.flv', 'b_2.mp4', 'c_3.ts']);
    // A folder that cannot be read: the file alone.
    expect(recordingsBeside('/no/such/dir/x.mp4'), ['/no/such/dir/x.mp4']);
  });

  test('V01.8: a recording starts again where it was left, unless barely begun or nearly done', () {
    const hour = Duration(hours: 1);
    expect(resumePosition(const Duration(seconds: 3), hour), Duration.zero);
    expect(resumePosition(const Duration(minutes: 20), hour), const Duration(minutes: 20));
    expect(resumePosition(hour - const Duration(seconds: 2), hour), Duration.zero);
    expect(recordingPositionKey('/a/b.mp4'), recordingPositionKey('/a/b.mp4'));
    expect(recordingPositionKey('/a/b.mp4'), isNot(recordingPositionKey('/a/c.mp4')));
  });

  testWidgets('V01.8: the player shows the seek bar, speed and the other recordings of the room', (tester) async {
    currentStrings = await tester.runAsync(loadStrings);
    final services = (await tester.runAsync(testServices))!;
    addTearDown(() => tester.runAsync(services.close));
    final engine = FakeEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(engine)),
        ],
        child: const MaterialApp(
          home: RecordingPlayerPage(files: ['/r/a_1.mp4', '/r/a_2.mp4'], index: 0),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('a_1.mp4'), findsOneWidget);
    expect(find.byKey(const ValueKey('recording-seek')), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('1×'), findsOneWidget);

    // 倍速: the choices, picking one shows it.
    await tester.tap(find.byKey(const ValueKey('recording-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.5×'));
    await tester.pumpAndSettle();
    expect(find.text('1.5×'), findsOneWidget);

    // 下一段.
    await tester.tap(find.byKey(const ValueKey('recording-next')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('a_2.mp4'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('recording-next'))).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
