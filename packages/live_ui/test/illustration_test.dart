import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  test('principles §3.3: every illustration is a small SVG in the placeholder channels only', () {
    for (final illustration in Illustration.values) {
      final file = File(illustration.asset);
      expect(file.existsSync(), isTrue, reason: illustration.asset);
      final svg = file.readAsStringSync();
      expect(file.lengthSync(), lessThanOrEqualTo(4096), reason: '${illustration.asset}: at most 4 KB');
      // Every colour is a mix of the three channels that adds up to one
      // (#3300CC is 20 % line over the surface), so it maps to a mix of the
      // theme's colours; nothing is drawn in a fixed colour.
      for (final match in RegExp('#([0-9A-Fa-f]{6})').allMatches(svg)) {
        final value = int.parse(match.group(1)!, radix: 16);
        final sum = (value >> 16 & 0xFF) + (value >> 8 & 0xFF) + (value & 0xFF);
        expect(sum, 255, reason: '${illustration.asset}: ${match.group(0)} is not a channel mix');
      }
    }
  });

  test('the colour filter maps line, plane and knock-out channels to the given colours', () {
    const line = Color(0xFF424753);
    const plane = Color(0xFF2E6FE0);
    const knock = Color(0xFFFAF8FF);
    final matrix = IllustrationView.colorMatrix(line: line, plane: plane, knock: knock);
    List<double> apply(List<double> rgb) => [
      for (var row = 0; row < 3; row++)
        matrix[row * 5] * rgb[0] + matrix[row * 5 + 1] * rgb[1] + matrix[row * 5 + 2] * rgb[2],
    ];
    expect(apply([1, 0, 0]), [line.r, line.g, line.b]);
    expect(apply([0, 1, 0]), [plane.r, plane.g, plane.b]);
    expect(apply([0, 0, 1]), [knock.r, knock.g, knock.b]);
  });

  // Pixel-exact goldens are made on Linux (WSL); other hosts rasterise
  // antialiased edges a little differently.
  testWidgets('the set in light and dark (golden)', skip: !Platform.isLinux, (tester) async {
    tester.view
      ..physicalSize = const Size(1220, 300)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget row(Appearance appearance) => Theme(
      data: PureTheme.of(appearance, platform: TargetPlatform.android),
      child: Builder(
        builder: (context) => Material(
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                for (final illustration in Illustration.values)
                  Padding(padding: const EdgeInsets.only(right: 8), child: IllustrationView(illustration)),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [row(Appearance.light), row(Appearance.dark)]),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byType(Column).first, matchesGoldenFile('goldens/illustrations.png'));
  });
}
