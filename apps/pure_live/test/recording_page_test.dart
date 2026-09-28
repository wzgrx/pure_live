import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_record/live_record.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/features/recording/recording_page.dart';

RecordTask _task(RecordState state, {RecordFailure? failure, bool session = false}) => RecordTask(
  room: RoomRef('douyu', '9999'),
  createdAt: DateTime(2026),
  state: state,
  snapshot: const RecordRoomSnapshot(anchorName: '主播甲'),
  failure: failure,
  session: session
      ? RecordSessionInfo(layout: SessionLayout.at('/rec', RoomRef('douyu', '9999'), '主播甲', DateTime(2026)))
      : null,
);

/// Menus and dialogs animate in and out; fixed steps instead of pumpAndSettle.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  test('F-REC-01: buttons and menus follow the task state', () {
    expect(recordTaskButton(_task(RecordState.recording)), RecordTaskAction.stop);
    expect(recordTaskButton(_task(RecordState.queued)), RecordTaskAction.stop);
    expect(recordTaskButton(_task(RecordState.waitingLive)), RecordTaskAction.stop);
    expect(recordTaskButton(_task(RecordState.finalizing)), isNull, reason: 'files are being finished');
    for (final state in [RecordState.completed, RecordState.failed, RecordState.stopped]) {
      expect(recordTaskButton(_task(state)), RecordTaskAction.start, reason: '$state: 重新录制');
    }
    expect(recordTaskMenu(_task(RecordState.waitingLive)), [
      RecordTaskAction.checkNow,
      RecordTaskAction.forceStart,
      RecordTaskAction.remove,
    ]);
    expect(recordTaskMenu(_task(RecordState.queued)), [RecordTaskAction.forceStart, RecordTaskAction.remove]);
    expect(recordTaskMenu(_task(RecordState.recording, session: true)), [
      RecordTaskAction.openFolder,
      RecordTaskAction.remove,
    ]);
    expect(
      recordTaskMenu(
        _task(
          RecordState.failed,
          failure: RecordFailure(RecordErrorKind.remuxFailed, RecordStage.remux),
          session: true,
        ),
      ),
      [RecordTaskAction.retryRemux, RecordTaskAction.openFolder, RecordTaskAction.remove],
    );
  });

  test('F-REC-01: every failure stage has a name', () {
    expect(recordStageText(RecordStage.stream), '取流');
    expect(recordStageText(RecordStage.writer), '写文件');
    expect(recordStageText(RecordStage.remux), '转封装');
    for (final stage in RecordStage.values) {
      expect(recordStageText(stage), isNotEmpty);
    }
  });

  group('RecordTaskTile', () {
    late List<RecordTaskAction> actions;

    Future<void> pumpTile(WidgetTester tester, RecordTask task) {
      actions = [];
      return tester.pumpWidget(
        MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          home: Scaffold(
            body: RecordTaskTile(task: task, onAction: (action) async => actions.add(action)),
          ),
        ),
      );
    }

    testWidgets('stopping a recording asks first (F-REC-02)', (tester) async {
      await pumpTile(tester, _task(RecordState.recording));
      await tester.tap(find.byTooltip('停止录制'));
      await settle(tester);
      expect(find.text('停止录制“主播甲”？已录的部分会保存。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle(tester);
      expect(actions, isEmpty);

      await tester.tap(find.byTooltip('停止录制'));
      await settle(tester);
      await tester.tap(find.text('停止'));
      await settle(tester);
      expect(actions, [RecordTaskAction.stop]);
    });

    testWidgets('cancelling a queued task needs no confirmation', (tester) async {
      await pumpTile(tester, _task(RecordState.queued));
      await tester.tap(find.byTooltip('取消排队'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(actions, [RecordTaskAction.stop]);
    });

    testWidgets('a failed task shows the error with its stage and offers 重新录制 (F-REC-01)', (tester) async {
      await pumpTile(
        tester,
        _task(
          RecordState.failed,
          failure: RecordFailure(RecordErrorKind.allLinesFailed, RecordStage.stream),
          session: true,
        ),
      );
      expect(find.text('拿不到可录制的直播流 · 出错环节：取流'), findsOneWidget);
      await tester.tap(find.byTooltip('重新录制'));
      await settle(tester);
      expect(actions, [RecordTaskAction.start]);
    });

    testWidgets('a watched room: force start at once, removal after confirmation (F-REC-01, F-REC-02)', (tester) async {
      await pumpTile(tester, _task(RecordState.waitingLive));
      await tester.tap(find.byTooltip('更多'));
      await settle(tester);
      expect(find.text('立即检查开播'), findsOneWidget);
      await tester.tap(find.text('强制开始'));
      await settle(tester);
      expect(actions, [RecordTaskAction.forceStart]);

      await tester.tap(find.byTooltip('更多'));
      await settle(tester);
      await tester.tap(find.text('移除监控'));
      await settle(tester);
      expect(find.text('不再等待“主播甲”开播？已录的文件会保留。'), findsOneWidget);
      await tester.tap(find.text('移除'));
      await settle(tester);
      expect(actions, [RecordTaskAction.forceStart, RecordTaskAction.remove]);
    });

    testWidgets('principles §3.4: the avatar leads, the logo sits in the subtitle, figures keep its weight', (
      tester,
    ) async {
      await pumpTile(tester, _task(RecordState.completed, session: true));
      final avatar = tester.widget<InitialAvatar>(find.byType(InitialAvatar));
      expect((avatar.name, avatar.seed), ('主播甲', 'douyu:9999'));
      final logo = tester.widget<PlatformLogo>(find.byType(PlatformLogo));
      expect(logo.size, Sizes.logoSmall);
      final tile = find.byType(ListTile);
      expect(
        tester.getTopLeft(find.byType(PlatformLogo)).dy,
        greaterThan(tester.getBottomLeft(find.text('主播甲')).dy - 1),
        reason: 'below the name, in the subtitle',
      );
      expect(tester.getSize(find.byType(InitialAvatar)), const Size.square(40));
      expect(find.descendant(of: tile, matching: find.byType(PlatformLogo)), findsOneWidget);
      // The details line inherits the subtitle's regular weight.
      final details = tester.widget<Text>(find.textContaining('已完成'));
      expect(details.style!.fontWeight, isNull);
      expect(details.style!.fontFeatures, [const FontFeature.tabularFigures()]);
    });

    testWidgets('principles §2.2: 开始录制 is an outlined circle with words, never the recording dot', (tester) async {
      await pumpTile(tester, _task(RecordState.stopped));
      final start = find.widgetWithText(TextButton, '开始录制');
      expect(start, findsOneWidget);
      expect(find.descendant(of: start, matching: find.byIcon(Icons.fiber_manual_record_outlined)), findsOneWidget);
      expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
      await tester.tap(start);
      await settle(tester);
      expect(actions, [RecordTaskAction.start]);
    });

    testWidgets('deleting a finished task asks first', (tester) async {
      await pumpTile(tester, _task(RecordState.completed, session: true));
      await tester.tap(find.byTooltip('更多'));
      await settle(tester);
      await tester.tap(find.text('删除任务（保留文件）'));
      await settle(tester);
      expect(find.text('删除“主播甲”的录制任务？已录的文件会保留。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle(tester);
      expect(actions, isEmpty);
    });
  });
}
