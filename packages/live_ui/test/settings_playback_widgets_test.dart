// The live_ui pieces added for the playback and data settings (U.6c, U.6e):
// a value under the explanation, a red title, the danmaku preview, the
// JSON tree.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('a long value sits under the explanation in the primary colour, the chevron stays', (tester) async {
    await tester.pumpWidget(
      _app(SettingsLinkRow(title: '全屏方向', subtitle: '说明', value: '跟随直播源（推荐）', valueBelow: true, onTap: () {})),
    );
    final value = find.text('跟随直播源（推荐）');
    expect(tester.getTopLeft(value).dy, greaterThan(tester.getTopLeft(find.text(withoutOrphan('说明'))).dy));
    expect(tester.widget<Text>(value).style?.color, Theme.of(tester.element(value)).colorScheme.primary);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
  });

  testWidgets('a destructive row has a red title and icon; a busy one can spin in red', (tester) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => SettingsRow(
            title: '清空本地缓存',
            icon: Icons.delete_outline,
            titleColor: Theme.of(context).colorScheme.error,
            busy: true,
            busyColor: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
    final error = Theme.of(tester.element(find.text('清空本地缓存'))).colorScheme.error;
    expect(tester.widget<Text>(find.text('清空本地缓存')).style?.color, error);
    expect(tester.widget<Icon>(find.byIcon(Icons.delete_outline)).color, error);
    expect(tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).color, error);
  });

  testWidgets('a held counter button repeats; a tap steps once', (tester) async {
    var value = 1;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => SettingsCounterRow(
            title: '数量',
            value: '$value',
            decreaseTooltip: '减',
            increaseTooltip: '加',
            increaseKey: const ValueKey('plus'),
            onDecrease: () => setState(() => value--),
            onIncrease: value < 20 ? () => setState(() => value++) : null,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('plus')));
    await tester.pump();
    expect(value, 2);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('plus'))));
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    await tester.pump(const Duration(seconds: 1));
    expect(value, greaterThan(4));
    final held = value;
    await tester.pump(const Duration(seconds: 1));
    expect(value, held, reason: 'stops when released');
  });

  testWidgets('the danmaku preview: 16:9, its lines, "off" in the middle when off', (tester) async {
    Widget preview({required bool enabled}) => _app(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: SizedBox(
          width: 352,
          child: PipDanmakuPreview(
            enabled: enabled,
            label: '小窗弹幕预览',
            disabledLabel: '小窗弹幕已关闭',
            opacity: 0.9,
            fontSize: 12,
            fontWeight: 500,
            speed: 90,
            area: 0.5,
            maxVisible: 6,
            emitInterval: 0.35,
            fps: 30,
          ),
        ),
      ),
    );
    await tester.pumpWidget(preview(enabled: true));
    final size = tester.getSize(find.byType(PipDanmakuPreview));
    expect(size.width / size.height, closeTo(16 / 9, 0.01));
    expect(find.text('小窗弹幕已关闭'), findsNothing);
    await tester.pumpWidget(preview(enabled: false));
    expect(find.text('小窗弹幕已关闭'), findsOneWidget);
  });

  test('the JSON tree shows two levels and flattens what is open', () {
    final data = <String, Object?>{
      'v': 1,
      'a': {
        'b': {'c': 1},
        'd': [1, 2],
      },
    };
    final open = jsonTreeOpenLevels(data);
    expect(open, {'a'});
    expect([for (final line in jsonTreeLines(data, open)) line.path], ['v', 'a', 'a/b', 'a/d']);
    expect(jsonTreeOpenLevels(data, levels: 2), {'a', 'a/b', 'a/d'});
    expect(
      [
        for (final line in jsonTreeLines(data, {'a', 'a/d'})) line.path,
      ],
      ['v', 'a', 'a/b', 'a/d', 'a/d/0', 'a/d/1'],
    );
  });
}
