import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/styles/dynamic_color_adapter.dart';
import 'package:pure_live/modules/settings/widgets/app_color_picker_dialog.dart';

const _labels = AppColorPickerLabels(
  shades: 'Color shades',
  wheel: 'Color wheel',
  opacity: 'Opacity',
  colorCode: 'ARGB code',
  invalidColorCode: 'Invalid code',
  primary: 'Primary',
  accent: 'Accent',
  custom: 'Custom',
  wheelPicker: 'Wheel',
);

void main() {
  group('application color code parser', () {
    test('accepts RGB and full ARGB forms', () {
      expect(parseAppColorCode('0080dd', enableOpacity: true)?.toARGB32(), 0xFF0080DD);
      expect(parseAppColorCode('#800080DD', enableOpacity: true)?.toARGB32(), 0x800080DD);
      expect(parseAppColorCode('0x40010203', enableOpacity: true)?.toARGB32(), 0x40010203);
    });

    test('rejects malformed values and normalizes opaque-only settings', () {
      expect(parseAppColorCode('12345', enableOpacity: true), isNull);
      expect(parseAppColorCode('0xGG0080DD', enableOpacity: true), isNull);
      expect(parseAppColorCode('0x40010203', enableOpacity: false)?.toARGB32(), 0xFF010203);
      expect(formatAppColorCode(const Color(0x800080DD), enableOpacity: true), '0x800080DD');
      expect(formatAppColorCode(const Color(0x800080DD), enableOpacity: false), '#0080DD');
    });
  });

  testWidgets('ARGB field and opacity slider preview a full pasted color and cancel restores the original', (
    tester,
  ) async {
    const initial = Color(0xFF6750A4);
    final previews = <Color>[];

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MaterialUiThemeBridge(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppColorPickerDialog(
                context: context,
                initialColor: initial,
                onColorChanged: previews.add,
                title: 'Pick a color',
                labels: _labels,
                customColorSwatchesAndNames: const {},
                enableOpacity: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final picker = tester.widget<ColorPicker>(find.byType(ColorPicker));
    expect(picker.enableOpacity, isTrue);
    expect(picker.showColorCode, isFalse, reason: 'the app-owned ARGB field replaces the six-digit package field');
    expect(find.byKey(const ValueKey<String>('app-color-picker-code')), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('app-color-picker-code')), '0x800080DD');
    await tester.pump();
    expect(previews.last.toARGB32(), 0x800080DD);

    await tester.tap(find.byKey(const ValueKey<String>('app-color-picker-cancel')));
    await tester.pumpAndSettle();
    expect(previews.last, initial);
  });

  testWidgets('invalid code keeps the dialog open and valid code can be confirmed', (tester) async {
    Color? selected;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MaterialUiThemeBridge(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppColorPickerDialog(
                context: context,
                initialColor: const Color(0xFFFFFFFF),
                onColorChanged: (color) => selected = color,
                title: 'Pick a color',
                labels: _labels,
                customColorSwatchesAndNames: const {},
                enableOpacity: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey<String>('app-color-picker-code')), '1234');
    await tester.tap(find.byKey(const ValueKey<String>('app-color-picker-confirm')));
    await tester.pump();
    expect(find.text('Invalid code'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('app-color-picker-code')), '#7F112233');
    await tester.tap(find.byKey(const ValueKey<String>('app-color-picker-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Pick a color'), findsNothing);
    expect(selected?.toARGB32(), 0x7F112233);
  });
}
