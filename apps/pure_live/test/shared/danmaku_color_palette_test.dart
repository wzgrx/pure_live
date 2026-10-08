// A08.7: the mini window danmaku colour unfolds a palette under its row
// instead of a centred dialog.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/shared/danmaku/danmaku_color_palette.dart';

import '../support.dart';

Finder _key(String key) => find.byKey(ValueKey(key));

Future<List<Color>> _pump(
  WidgetTester tester, {
  Color color = const Color(0xFFFFFFFF),
  bool enabled = true,
  double width = 360,
}) async {
  tester.view
    ..physicalSize = Size(width, 800)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final picked = <Color>[];
  var current = color;
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme().light,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ListView(
            children: [
              DanmakuColorPickerRow(
                settingKey: 'pipColor',
                title: '统一弹幕颜色',
                color: current,
                enabled: enabled,
                onChanged: (value) => setState(() {
                  picked.add(value);
                  current = value;
                }),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return picked;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(_key('danmaku-setting-pipColor'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadStrings);

  testWidgets('a tap unfolds the palette under the row and folds it again; no dialog', (tester) async {
    await _pump(tester);
    expect(_key('danmaku-color-palette'), findsNothing);
    expect(find.byIcon(AppIcons.dropDown), findsOneWidget);
    await _open(tester);
    expect(_key('danmaku-color-palette'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byIcon(AppIcons.foldUp), findsOneWidget);
    expect(
      tester.getTopLeft(_key('danmaku-color-palette')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(_key('danmaku-setting-pipColor')).dy),
    );
    // Ten swatches and the hex field.
    for (final color in danmakuColorSwatches) {
      expect(_key('danmaku-color-${color.toARGB32().toRadixString(16)}'), findsOneWidget);
    }
    expect(_key('danmaku-color-hex'), findsOneWidget);
    await _open(tester);
    expect(_key('danmaku-color-palette'), findsNothing);
  });

  testWidgets('a swatch applies at once; the tick and the ring move to it; 48-point targets', (tester) async {
    final picked = await _pump(tester);
    await _open(tester);
    final red = _key('danmaku-color-fffe0302');
    final size = tester.getSize(red);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    // The current one (white) has the tick.
    expect(
      find.descendant(of: _key('danmaku-color-ffffffff'), matching: _key('danmaku-color-selected')),
      findsOneWidget,
    );
    await tester.tap(red);
    await tester.pumpAndSettle();
    expect(picked, [const Color(0xFFFE0302)]);
    expect(find.descendant(of: red, matching: _key('danmaku-color-selected')), findsOneWidget);
    expect(_key('danmaku-color-selected'), findsOneWidget);
    // Still open: pick another right away.
    expect(_key('danmaku-color-palette'), findsOneWidget);
    expect(find.text('#FFFE0302'), findsOneWidget);
  });

  testWidgets('the hex field applies on Enter; a wrong value says why and stays open', (tester) async {
    final picked = await _pump(tester);
    await _open(tester);
    await tester.enterText(_key('danmaku-color-hex'), '00A2FF');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(picked, [const Color(0xFF00A2FF)]);
    expect(
      find.descendant(of: _key('danmaku-color-ff00a2ff'), matching: _key('danmaku-color-selected')),
      findsOneWidget,
    );

    await tester.enterText(_key('danmaku-color-hex'), 'XYZ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('请输入 6 位十六进制颜色，例如 2196F3'), findsOneWidget);
    expect(_key('danmaku-color-palette'), findsOneWidget);
    expect(picked, hasLength(1));

    await tester.enterText(_key('danmaku-color-hex'), '12345');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('请输入 6 位十六进制颜色，例如 2196F3'), findsOneWidget);
    expect(tester.widget<TextField>(_key('danmaku-color-hex')).controller!.text, '12345', reason: 'not cleared');
    expect(picked, hasLength(1));
  });

  testWidgets('greyed out while the platform colours are kept: a tap does not unfold it', (tester) async {
    await _pump(tester, enabled: false);
    final row = find.ancestor(of: _key('danmaku-setting-pipColor'), matching: find.byType(InkWell)).first;
    expect(tester.widget<InkWell>(row).onTap, isNull);
    await tester.tap(_key('danmaku-setting-pipColor'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(_key('danmaku-color-palette'), findsNothing);
  });

  test('typed colours: six digits are opaque, eight keep theirs, anything else is refused', () {
    expect(parseDanmakuColor('FE0302'), const Color(0xFFFE0302));
    expect(parseDanmakuColor('#fe0302'), const Color(0xFFFE0302));
    expect(parseDanmakuColor('80FE0302'), const Color(0x80FE0302));
    expect(parseDanmakuColor('XYZ'), isNull);
    expect(parseDanmakuColor(''), isNull);
    expect(parseDanmakuColor('12345'), isNull);
  });
}
