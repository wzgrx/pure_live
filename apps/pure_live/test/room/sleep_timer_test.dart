import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live_app/features/room/sleep_timer.dart';

void main() {
  testWidgets('F-TMR-01: ends after the chosen time; cancel stops it; a restart replaces it', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final timer = container.read(sleepTimerProvider.notifier)..start(const Duration(minutes: 30));
    var state = container.read(sleepTimerProvider);
    expect(state.active, isTrue);
    expect(state.duration, const Duration(minutes: 30));
    expect(state.remaining(DateTime.now()).inMinutes, inInclusiveRange(29, 30));

    await tester.pump(const Duration(minutes: 29));
    expect(container.read(sleepTimerProvider).fired, 0);
    await tester.pump(const Duration(minutes: 1));
    state = container.read(sleepTimerProvider);
    expect(state.fired, 1);
    expect(state.active, isFalse);

    timer
      ..start(const Duration(minutes: 10))
      ..cancel();
    await tester.pump(const Duration(minutes: 11));
    expect(container.read(sleepTimerProvider).fired, 1);

    timer
      ..start(const Duration(minutes: 10))
      ..start(const Duration(minutes: 20));
    await tester.pump(const Duration(minutes: 11));
    expect(container.read(sleepTimerProvider).fired, 1, reason: 'the restart replaced the 10-minute timer');
    await tester.pump(const Duration(minutes: 9));
    expect(container.read(sleepTimerProvider).fired, 2);
  });

  testWidgets('F-TMR-02: 退出应用 fires the pause first, then quits', (tester) async {
    var quits = 0;
    final container = ProviderContainer(
      overrides: [
        appQuitProvider.overrideWithValue(() async {
          quits++;
        }),
      ],
    );
    addTearDown(container.dispose);
    container.read(sleepTimerProvider.notifier).start(const Duration(minutes: 1), action: SleepAction.exit);
    await tester.pump(const Duration(minutes: 1));
    expect(container.read(sleepTimerProvider).fired, 1);
    expect(quits, 0, reason: 'the room pauses before the app goes');
    await tester.pump(const Duration(milliseconds: 300));
    expect(quits, 1);
  });

  test('remaining time reads as mm:ss or hh:mm:ss', () {
    expect(formatRemaining(const Duration(minutes: 5, seconds: 9)), '05:09');
    expect(formatRemaining(const Duration(hours: 1, minutes: 5, seconds: 9)), '01:05:09');
    expect(const SleepTimerState().remaining(DateTime.now()), Duration.zero);
  });

  testWidgets('the sheet starts a preset or a custom length, shows the time left and cancels', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  TextButton(onPressed: () => showSleepTimerSheet(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 分钟'));
    await tester.pumpAndSettle();
    expect(container.read(sleepTimerProvider).duration, const Duration(minutes: 30));
    expect(container.read(sleepTimerProvider).action, SleepAction.pause);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('后暂停播放'), findsOneWidget);
    await tester.tap(find.text('退出应用'));
    await tester.pump();
    expect(container.read(sleepTimerProvider).action, SleepAction.exit);
    expect(find.textContaining('后退出应用'), findsOneWidget);
    await tester.tap(find.text('取消定时'));
    await tester.pump();
    expect(container.read(sleepTimerProvider).active, isFalse);

    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('开始'));
    await tester.pump();
    expect(find.textContaining('请输入 1 到'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();
    final state = container.read(sleepTimerProvider);
    expect(state.duration, const Duration(minutes: 5));
    expect(state.action, SleepAction.exit, reason: 'the chosen action is kept');
    container.read(sleepTimerProvider.notifier).cancel();
    await tester.pump();
  });

  testWidgets('the top-bar chip shows only while the timer runs', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SleepTimerChip())),
      ),
    );
    expect(find.byIcon(Icons.bedtime_outlined), findsNothing);
    container.read(sleepTimerProvider.notifier).start(const Duration(minutes: 2));
    await tester.pump();
    expect(find.text('02:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
    container.read(sleepTimerProvider.notifier).cancel();
    await tester.pump();
    expect(find.byIcon(Icons.bedtime_outlined), findsNothing);
  });

  test('F-ROOM-10: restoring the picture ends a 助眠模式 timer, not one the user set', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final timer = container.read(sleepTimerProvider.notifier)..start(const Duration(minutes: 60), asmr: true);
    expect(container.read(sleepTimerProvider).asmr, isTrue);
    timer.pictureRestored();
    expect(container.read(sleepTimerProvider).active, isFalse);

    timer
      ..start(const Duration(minutes: 30))
      ..pictureRestored();
    expect(container.read(sleepTimerProvider).active, isTrue);
    timer.cancel();
  });
}
