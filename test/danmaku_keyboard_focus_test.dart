import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/widgets/keyboard/video_keyboard.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';

class _Player extends Fake implements VideoController {
  int exits = 0;
  @override
  Future<void> toggleFullScreen() async {
    exits++;
    GlobalPlayerState.to.isFullscreen.value = false;
  }
}

void main() {
  testWidgets('mounting two barrage surfaces preserves composer focus and input', (tester) async {
    final focus = FocusNode();
    final text = TextEditingController();
    final show = ValueNotifier(false);
    addTearDown(focus.dispose);
    addTearDown(text.dispose);
    addTearDown(show.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(focusNode: focus, controller: text, autofocus: true),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: show,
                  builder: (_, visible, _) => visible
                      ? Stack(
                          children: List.generate(
                            2,
                            (_) => FlameBarrageWidget(
                              config: const BarrageConfig(),
                              emojiAtlas: EmojiAtlas.instance,
                              controller: BarrageController(),
                              enablePointerEvents: true,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    show.value = true;
    await tester.pump();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    tester.testTextInput.enterText('local message');
    expect(text.text, 'local message');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final interactive in [false, true]) {
    testWidgets('real barrage leaves fullscreen Escape to player (pointer=$interactive)', (tester) async {
      Get.testMode = true;
      Get.put(GlobalPlayerState());
      addTearDown(() {
        Get.reset();
        Get.testMode = false;
      });
      final player = _Player();
      final barrage = BarrageController();
      GlobalPlayerState.to.isFullscreen.value = true;
      await tester.pumpWidget(
        MaterialApp(
          home: VideoKeyboardShortcuts(
            controller: player,
            child: FlameBarrageWidget(
              config: const BarrageConfig(),
              emojiAtlas: EmojiAtlas.instance,
              controller: barrage,
              enablePointerEvents: interactive,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(barrage.engine, isA<BarrageEngine>());
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(player.exits, 1, reason: 'The danmaku canvas must not consume the room shortcut.');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
