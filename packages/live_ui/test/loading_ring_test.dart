import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  // P05 (research 2026-10-02 §4.2): the default spinner turns every frame
  // while something loads; under a ShaderMask each of those frames drew the
  // ring offscreen first (a saveLayer).
  testWidgets('the default spinner strokes its ring with a sweep shader: no mask, no offscreen layer', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: DefaultLoadingIndicator(color: Colors.pink, size: 32)),
      ),
    );
    final spinner = find.byType(DefaultLoadingIndicator);
    expect(find.descendant(of: spinner, matching: find.byType(ShaderMask)), findsNothing);
    expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);
    expect(tester.layers.whereType<OpacityLayer>(), isEmpty);

    // One circle 3.5 wide inside the 32 box (3.x's ring), its colour from a
    // gradient fading from the colour to 10 % (3.x's sweep).
    expect(tester.getSize(spinner), const Size(32, 32));
    expect(spinner, paints..circle(x: 16, y: 16, radius: 14.25, strokeWidth: 3.5, style: PaintingStyle.stroke));
    expect(
      spinner,
      paints..something((method, arguments) {
        if (method != #drawCircle) return false;
        final paint = arguments[2] as Paint;
        return paint.shader is ui.Gradient && paint.isAntiAlias;
      }),
    );

    // It turns once a second, in a layer of its own: its frames repaint the
    // ring alone, not what is around it.
    RotationTransition rotation() =>
        tester.widget<RotationTransition>(find.descendant(of: spinner, matching: find.byType(RotationTransition)));
    expect(rotation().turns.value, 0);
    await tester.pump(const Duration(milliseconds: 250));
    expect(rotation().turns.value, closeTo(0.25, 0.01));
    expect(find.ancestor(of: find.byType(RotationTransition), matching: find.byType(RepaintBoundary)), findsWidgets);
    final boundary = tester.renderObject(find.descendant(of: spinner, matching: find.byType(RepaintBoundary)).first);
    expect(boundary.isRepaintBoundary, isTrue);
  });
}
