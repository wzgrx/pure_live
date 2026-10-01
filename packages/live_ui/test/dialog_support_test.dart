import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  testWidgets('DialogButtonsTheme puts the buttons on the 14-point role; DialogKeys: Enter and Esc', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: const LiveTheme().light,
        home: Scaffold(
          body: Column(
            children: [
              TextButton(onPressed: () {}, child: const Text('outside')),
              DialogButtonsTheme(
                child: DialogKeys(
                  onEnter: () => calls.add('enter'),
                  onEscape: () => calls.add('escape'),
                  child: Row(
                    children: [
                      TextButton(onPressed: () => calls.add('cancel'), child: const Text('取消')),
                      FilledButton(onPressed: () => calls.add('ok'), child: const Text('确定')),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    double size(String text) => tester.renderObject<RenderParagraph>(find.text(text)).text.style!.fontSize!;
    // The theme's button label is 13 (3.x); inside a dialog it is 14.
    expect(size('outside'), 13);
    expect(size('取消'), 14);
    expect(size('确定'), 14);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(calls, ['enter', 'escape']);

    // A focused button keeps its own Enter.
    Focus.of(tester.element(find.text('取消'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(calls.last, 'cancel');
  });
}
