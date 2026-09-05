import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/widgets/keyboard/video_keyboard.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';

class _PresentationController implements VideoController {
  int fullscreenExits = 0;
  int widescreenExits = 0;

  @override
  Future<void> toggleFullScreen() async {
    fullscreenExits++;
    GlobalPlayerState.to.isFullscreen.value = false;
  }

  @override
  Future<void> toggleWindowFullScreen() async {
    widescreenExits++;
    GlobalPlayerState.to.isWindowFullscreen.value = false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('a focused child consumes Escape before room presentation', (tester) async {
    Get.testMode = true;
    Get.put(GlobalPlayerState());
    final controller = _PresentationController();
    var childEscapes = 0;
    addTearDown(() {
      Get.reset();
      Get.testMode = false;
    });
    GlobalPlayerState.to.isFullscreen.value = true;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoKeyboardShortcuts(
          controller: controller,
          child: CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => childEscapes++},
            child: const Focus(autofocus: true, child: Text('editing')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(childEscapes, 1);
    expect(controller.fullscreenExits, 0);
  });

  testWidgets('holding Escape exits a presentation once and does not pop the room', (tester) async {
    Get.testMode = true;
    Get.put(GlobalPlayerState());
    final controller = _PresentationController();
    addTearDown(() {
      Get.reset();
      Get.testMode = false;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => VideoKeyboardShortcuts(controller: controller, child: const Text('room')),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    GlobalPlayerState.to.isWindowFullscreen.value = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    expect(controller.widescreenExits, 1);
    expect(find.text('room'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('Escape in a fullscreen room menu does not change presentation', (tester) async {
    Get.testMode = true;
    Get.put(GlobalPlayerState());
    final controller = _PresentationController();
    addTearDown(() {
      Get.reset();
      Get.testMode = false;
    });
    GlobalPlayerState.to.isFullscreen.value = true;
    await tester.pumpWidget(
      MaterialApp(
        home: VideoKeyboardShortcuts(
          controller: controller,
          child: Scaffold(
            body: PopupMenuButton<int>(
              itemBuilder: (_) => [const PopupMenuItem(value: 1, child: Text('menu-content'))],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('menu-content'), findsNothing);
    expect(controller.fullscreenExits, 0);
    expect(GlobalPlayerState.to.isFullscreen.value, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.fullscreenExits, 1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('named Get room retains its route when a menu receives Escape', (tester) async {
    Get.testMode = true;
    Get.put(GlobalPlayerState());
    addTearDown(() {
      Get.reset();
      Get.testMode = false;
    });
    await tester.pumpWidget(
      GetMaterialApp(
        initialRoute: '/home',
        getPages: [
          GetPage(
            name: '/home',
            page: () => Scaffold(
              body: TextButton(
                onPressed: () => Get.toNamed<void>('/live_play', parameters: {'site': 'huya'}),
                child: const Text('open'),
              ),
            ),
          ),
          GetPage(
            name: '/live_play',
            page: () => VideoKeyboardShortcuts(
              controller: null,
              child: Scaffold(
                body: Column(
                  children: [
                    const Text('live-room'),
                    PopupMenuButton<int>(
                      itemBuilder: (_) => [const PopupMenuItem(value: 1, child: Text('menu-content'))],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('menu-content'), findsNothing);
    expect(find.text('live-room'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('live-room'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final overlay in ['menu', 'dialog', 'sheet']) {
    testWidgets('Escape dismisses $overlay without also popping its live room', (tester) async {
      Get.testMode = true;
      Get.put(GlobalPlayerState());
      addTearDown(() {
        Get.reset();
        Get.testMode = false;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => VideoKeyboardShortcuts(
                    controller: null,
                    child: Scaffold(
                      body: Builder(
                        builder: (roomContext) => Column(
                          children: [
                            const Text('live-room'),
                            PopupMenuButton<int>(
                              key: const Key('menu'),
                              itemBuilder: (_) => [const PopupMenuItem(value: 1, child: Text('overlay-content'))],
                            ),
                            TextButton(
                              onPressed: () => showDialog<void>(
                                context: roomContext,
                                builder: (_) => const AlertDialog(content: Text('overlay-content')),
                              ),
                              child: const Text('dialog'),
                            ),
                            TextButton(
                              onPressed: () => showModalBottomSheet<void>(
                                context: roomContext,
                                builder: (_) => const SizedBox(height: 120, child: Text('overlay-content')),
                              ),
                              child: const Text('sheet'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(overlay == 'menu' ? find.byKey(const Key('menu')) : find.text(overlay));
      await tester.pumpAndSettle();
      expect(find.text('overlay-content'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('overlay-content'), findsNothing);
      expect(find.text('live-room'), findsOneWidget, reason: 'The same key must not also leave the room.');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('live-room'), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });
  }

  test('Escape pops a normal live room route', () {
    expect(
      resolveEscapePresentationAction(pip: false, fullscreen: false, widescreen: false),
      EscapePresentationAction.popRoute,
    );
  });

  test('Escape exits the active fullscreen presentation', () {
    expect(
      resolveEscapePresentationAction(pip: false, fullscreen: true, widescreen: false),
      EscapePresentationAction.exitFullscreen,
    );
  });

  test('Escape exits widescreen instead of entering fullscreen', () {
    expect(
      resolveEscapePresentationAction(pip: false, fullscreen: false, widescreen: true),
      EscapePresentationAction.exitWidescreen,
    );
  });

  test('PiP owns Escape even if stale presentation flags remain set', () {
    expect(
      resolveEscapePresentationAction(pip: true, fullscreen: true, widescreen: true),
      EscapePresentationAction.none,
    );
  });

  testWidgets('Escape pops an offline room before a VideoController exists', (tester) async {
    Get.testMode = true;
    Get.put(GlobalPlayerState());
    addTearDown(() {
      Get.reset();
      Get.testMode = false;
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const VideoKeyboardShortcuts(controller: null, child: Text('offline-room')),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('offline-room'), findsOneWidget);

    // A failed room may inherit stale presentation flags from an interrupted
    // source load. With no VideoController those flags must not swallow Escape.
    GlobalPlayerState.to.isFullscreen.value = true;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('offline-room'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
