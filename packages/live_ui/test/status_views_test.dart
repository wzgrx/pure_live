import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
    home: Scaffold(body: child),
  );

  group('principles §2.5, §7.8: skeletons', () {
    testWidgets('the grid keeps the given columns, gap and card height, fills the page and never moves', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(393, 700)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(const SkeletonGrid(columns: 2, gap: 8, padding: EdgeInsets.fromLTRB(16, 8, 16, 8), cellHeight: 150)),
      );
      final covers = find.descendant(of: find.byType(SkeletonGrid), matching: find.byType(AspectRatio));
      // (700 - 16 + 8) / (150 + 8) → 5 rows of 2.
      expect(covers, findsNWidgets(10));
      final first = tester.getRect(covers.at(0));
      final second = tester.getRect(covers.at(1));
      final third = tester.getRect(covers.at(2));
      expect(first.left, 16);
      expect(second.left - first.right, 8, reason: 'the gap');
      expect(first.width, (393 - 32 - 8) / 2);
      expect(third.top - first.top, 158, reason: 'card height plus gap');
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.hasRunningAnimations, isFalse, reason: 'static: no shimmer');
      expect(find.bySemanticsLabel('正在加载'), findsOneWidget);
    });

    testWidgets('a compact grid draws one text bar per card, a standard grid two', (tester) async {
      int bars(WidgetTester tester) => tester
          .widgetList<FractionallySizedBox>(
            find.descendant(of: find.byType(SkeletonGrid), matching: find.byType(FractionallySizedBox)),
          )
          .length;
      const geometry = (columns: 2, gap: 8.0, padding: EdgeInsets.zero, cellHeight: 400.0);
      await tester.pumpWidget(
        host(
          SizedBox(
            height: 300,
            child: SkeletonGrid(
              columns: geometry.columns,
              gap: geometry.gap,
              padding: geometry.padding,
              cellHeight: geometry.cellHeight,
            ),
          ),
        ),
      );
      expect(bars(tester), 4);
      await tester.pumpWidget(
        host(
          SizedBox(
            height: 300,
            child: SkeletonGrid(
              columns: geometry.columns,
              gap: geometry.gap,
              padding: geometry.padding,
              cellHeight: geometry.cellHeight,
              density: CardDensity.compact,
            ),
          ),
        ),
      );
      expect(bars(tester), 2);
    });

    testWidgets('the list fills the page with avatar rows', (tester) async {
      tester.view
        ..physicalSize = const Size(393, 720)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const SkeletonList()));
      expect(find.byType(SkeletonList), findsOneWidget);
      final circles = tester
          .widgetList<DecoratedBox>(find.descendant(of: find.byType(SkeletonList), matching: find.byType(DecoratedBox)))
          .where((box) => (box.decoration as BoxDecoration).shape == BoxShape.circle);
      expect(circles, hasLength(10), reason: '720 / 72 rows');
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('principles §3.3: MessageView', () {
    testWidgets('an illustration above the title and up to three buttons, the first filled', (tester) async {
      final pressed = <String>[];
      await tester.pumpWidget(
        host(
          MessageView(
            illustration: Illustration.followsEmpty,
            title: '还没有关注的主播',
            message: '说明',
            actionLabel: '去发现',
            onAction: () => pressed.add('discover'),
            actions: [
              MessageAction('粘贴链接', () => pressed.add('paste')),
              MessageAction('导入旧数据或备份', () => pressed.add('import')),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final picture = tester.widget<IllustrationView>(find.byType(IllustrationView));
      expect(picture.illustration, Illustration.followsEmpty);
      expect(tester.getSize(find.byType(IllustrationView)), const Size(160, 120));
      expect(find.byType(Icon), findsNothing, reason: 'the picture replaces the icon');
      expect(find.widgetWithText(FilledButton, '去发现'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '粘贴链接'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '导入旧数据或备份'), findsOneWidget);
      await tester.tap(find.text('粘贴链接'));
      await tester.tap(find.text('导入旧数据或备份'));
      await tester.tap(find.text('去发现'));
      expect(pressed, ['paste', 'import', 'discover']);
    });

    testWidgets('an error without a picture keeps the small icon and retries', (tester) async {
      var retried = false;
      await tester.pumpWidget(host(MessageView.error(title: '出错', onAction: () => retried = true)));
      expect(find.byType(IllustrationView), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, isTrue);
    });

    testWidgets('a fourth button is a mistake', (tester) async {
      await tester.pumpWidget(
        host(
          MessageView(
            title: 't',
            onAction: () {},
            onSecondary: () {},
            actions: [MessageAction('a', () {}), MessageAction('b', () {})],
          ),
        ),
      );
      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('on TV the picture is 200 dp wide', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: PureTheme.tv(Appearance.dark, platform: TargetPlatform.android),
          home: const TvScope(
            config: TvConfig(enabled: true),
            child: Scaffold(
              body: MessageView(illustration: Illustration.noResults, title: '没有结果'),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(IllustrationView)), const Size(200, 150));
    });
  });
}
