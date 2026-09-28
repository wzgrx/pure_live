import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

import 'symbols_font.dart';

/// Principles §2.6, risk: release builds shrink icon fonts to the glyphs the
/// app uses (icon tree shaking), and Flutter's subsetter once lost the
/// filled forms of variable icons (flutter/flutter#183381; Material Symbols
/// switches to a filled glyph through a GSUB feature variation at FILL 1).
/// PR #183857 kept every glyph of variable fonts and was reverted; the
/// actual fix was a newer HarfBuzz in the subsetter.
///
/// This runs the `font-subset` tool of the SDK running the tests, the one
/// `flutter build` runs, on Material Symbols Rounded with the code points of
/// every [LiveIcons] glyph, and checks that each glyph draws the same from
/// the subset as from the whole font at fill 0 and 1, grade 0 and -25, and
/// weight 400 and 500. The release build itself is checked on the device.
void main() {
  final root = flutterRoot;
  final platform = Platform.isWindows ? 'windows-x64' : (Platform.isMacOS ? 'darwin-x64' : 'linux-x64');
  final tool = [
    root ?? '',
    'bin',
    'cache',
    'artifacts',
    'engine',
    platform,
    'font-subset',
  ].join(Platform.pathSeparator);
  final executable = Platform.isWindows ? '$tool.exe' : tool;
  final skip = File(executable).existsSync() ? null : 'font-subset not found at $executable';
  const subsetFamily = 'SubsetSymbolsRounded';
  final codePoints = {for (final icon in LiveIcons.values) ?icon.glyph?.codePoint}.toList()..sort();
  late int subsetBytes;

  setUpAll(() async {
    if (skip != null) return;
    await loadSymbolsFont();
    final dir = Directory.systemTemp.createTempSync('live_ui_subset');
    addTearDown(() => dir.deleteSync(recursive: true));
    final input = File('${dir.path}/full.ttf')
      ..writeAsBytesSync((await rootBundle.load(symbolsFontAsset)).buffer.asUint8List());
    final output = '${dir.path}/subset.ttf';
    // As flutter_tools calls it: output, input, then code points on stdin.
    final process = await Process.start(executable, [output, input.path]);
    process.stdin.writeln(codePoints.join(' '));
    await process.stdin.close();
    final code = await process.exitCode;
    expect(code, 0, reason: 'font-subset failed');
    final subset = File(output).readAsBytesSync();
    subsetBytes = subset.length;
    await (FontLoader(subsetFamily)..addFont(Future.value(ByteData.sublistView(subset)))).load();
  });

  testWidgets(
    'every glyph draws the same from the subset font at fill 0 and 1, both grades and weights',
    skip: skip != null,
    (tester) async {
      // The subset keeps what was asked for and little else.
      expect(subsetBytes, lessThan(1 << 20));
      const cell = 32.0;
      const columns = 16;
      final rows = (codePoints.length / columns).ceil();
      tester.view
        ..physicalSize = Size(columns * cell, rows * cell)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();

      Future<Uint8List> draw(String family, List<ui.FontVariation> axes) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: Wrap(
                  children: [
                    for (final point in codePoints)
                      SizedBox.square(
                        dimension: cell,
                        child: Center(
                          child: Text(
                            String.fromCharCode(point),
                            style: TextStyle(
                              fontFamily: family,
                              fontSize: 24,
                              height: 1,
                              color: const Color(0xFF000000),
                              fontVariations: [...axes, const ui.FontVariation('opsz', 24)],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData();
          image.dispose();
          return data!.buffer.asUint8List();
        });
        return bytes!;
      }

      final drawnWhole = <Uint8List>[];
      for (final fill in [0.0, 1.0]) {
        for (final grade in [0.0, -25.0]) {
          for (final weight in [400.0, 500.0]) {
            final axes = [
              ui.FontVariation('FILL', fill),
              ui.FontVariation('GRAD', grade),
              ui.FontVariation('wght', weight),
            ];
            final whole = await draw(symbolsFamily, axes);
            final subset = await draw(subsetFamily, axes);
            drawnWhole.add(whole);
            // The whole font draws something (it did load).
            expect(whole.any((byte) => byte != 0xFF), isTrue);
            var differing = 0;
            for (var i = 0; i < whole.length; i++) {
              if (whole[i] != subset[i]) differing++;
            }
            expect(differing, 0, reason: 'fill $fill, grade $grade, weight $weight: $differing bytes differ');
          }
        }
      }
      // Each axis changes the drawing, so the comparison covers every state.
      for (var i = 0; i < drawnWhole.length; i++) {
        for (var j = i + 1; j < drawnWhole.length; j++) {
          expect(listEquals(drawnWhole[i], drawnWhole[j]), isFalse, reason: 'states $i and $j draw alike');
        }
      }
    },
  );
}
