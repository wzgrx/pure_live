import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/shared/app_prompts.dart';
import 'package:pure_live/shared/rooms/room_prompt.dart';

import '../support.dart';

Future<BuildContext> _pump(WidgetTester tester, {double width = 393, double height = 852}) async {
  tester.view
    ..physicalSize = Size(width, height)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final strings = (await tester.runAsync(loadStrings))!;
  await tester.pumpWidget(
    LiveUiScope(
      config: LiveUiConfig(strings: strings.ui),
      child: MaterialApp(
        theme: const LiveTheme(primaryColor: Colors.blue).light,
        home: const Scaffold(body: Text('home')),
      ),
    ),
  );
  return tester.element(find.text('home'));
}

/// A prompt that stays open until [close] is called.
final class _Prompt {
  final Completer<String> _done = Completer();
  bool shown = false;

  Future<String> present() {
    shown = true;
    return _done.future;
  }

  void close(String value) => _done.complete(value);
}

LiveRoom _room() => LiveRoom(platform: 'bilibili', roomId: '21452505', title: '深夜电台 · 点歌接龙到天亮', nick: '晚风');

void main() {
  group('one prompt at a time (U.3c c7)', () {
    testWidgets('a second prompt waits; the share prompt goes before the update prompt', (tester) async {
      await _pump(tester);
      final prompts = AppPrompts(listenRoutes: (_) {});
      final first = _Prompt();
      final update = _Prompt();
      final share = _Prompt();
      final results = <String?>[];
      unawaited(prompts.show(AppPromptKind.update, first.present).then(results.add));
      unawaited(prompts.show(AppPromptKind.update, update.present).then(results.add));
      unawaited(prompts.show(AppPromptKind.share, share.present).then(results.add));
      await tester.pump();
      expect([first.shown, update.shown, share.shown], [true, false, false]);
      expect(prompts.isShowing, isTrue);
      expect(prompts.waiting, 2);

      first.close('a');
      await tester.pump();
      await tester.pump();
      // The share prompt jumps the queue.
      expect([update.shown, share.shown], [false, true]);
      share.close('b');
      await tester.pump();
      await tester.pump();
      expect(update.shown, isTrue);
      update.close('c');
      await tester.pump();
      await tester.pump();
      expect(results, ['a', 'b', 'c']);
      expect(prompts.isShowing, isFalse);
    });

    testWidgets('a prompt that is not ready waits until a route change says it is', (tester) async {
      await _pump(tester);
      late void Function(RouteEvent) notify;
      final prompts = AppPrompts(listenRoutes: (listener) => notify = listener);
      var ready = false;
      final prompt = _Prompt();
      unawaited(prompts.show(AppPromptKind.update, prompt.present, ready: () => ready));
      await tester.pump();
      expect(prompt.shown, isFalse);
      ready = true;
      notify(RouteEvent(RouteEventKind.pop, MaterialPageRoute<void>(builder: (_) => const SizedBox())));
      await tester.pump();
      expect(prompt.shown, isTrue);
      prompt.close('done');
      await tester.pump();
    });
  });

  group('the share prompt (U.3d c11)', () {
    testWidgets('title, where it came from, the room in one row, the platform by name; cancel and enter', (
      tester,
    ) async {
      final context = await _pump(tester);
      final prompts = AppPrompts(listenRoutes: (_) {});
      final answer = showRoomPrompt(context, room: _room(), prompts: prompts);
      await tester.pumpAndSettle();
      expect(find.text('打开分享的直播间'), findsOneWidget);
      expect(find.text('从剪贴板识别到分享口令'), findsOneWidget);
      expect(find.text('深夜电台 · 点歌接龙到天亮'), findsOneWidget);
      expect(find.text('晚风 · 哔哩哔哩 · 房间号 21452505'), findsOneWidget);
      // 3.x: "分享", the platform's id, a box in the box.
      expect(find.text('分享'), findsNothing);
      expect(find.textContaining('bilibili'), findsNothing);
      final avatar = tester.getRect(find.byType(CommonAvatar));
      final title = tester.getRect(find.text('深夜电台 · 点歌接龙到天亮'));
      expect(avatar.size, const Size(48, 48));
      expect(title.left, greaterThan(avatar.right));
      expect(tester.getCenter(find.text('取消')).dx, lessThan(tester.getCenter(find.text('进入房间')).dx));
      for (final label in ['取消', '进入房间', '从剪贴板识别到分享口令']) {
        expect(tester.renderObject<RenderParagraph>(find.text(label)).text.style?.fontSize, 14, reason: label);
      }
      // The one dialog (U.1d): the theme's 24-point corners (3.x: 16).
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.shape, isNull);
      expect(find.byKey(const ValueKey('room-prompt')), findsOneWidget);
      await tester.tap(find.text('进入房间'));
      await tester.pumpAndSettle();
      expect(await answer, RoomPromptChoice.enter);

      final dismissed = showRoomPrompt(context, room: _room(), prompts: prompts);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await dismissed, RoomPromptChoice.dismiss);

      // Enter is "进入房间" on a computer.
      final entered = showRoomPrompt(context, room: _room(), prompts: prompts);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await entered, RoomPromptChoice.enter);
    });

    testWidgets('narrow or a large font: the avatar above the names', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final context = await _pump(tester);
      unawaited(
        showRoomPrompt(
          context,
          room: _room(),
          prompts: AppPrompts(listenRoutes: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      final avatar = tester.getRect(find.byType(CommonAvatar));
      final title = tester.getRect(find.text('深夜电台 · 点歌接龙到天亮'));
      expect(title.top, greaterThan(avatar.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('over a landscape room it is the same dialog, at most 400 wide', (tester) async {
      final context = await _pump(tester, width: 852, height: 393);
      unawaited(
        showRoomPrompt(
          context,
          room: _room(),
          prompts: AppPrompts(listenRoutes: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      final material = find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first;
      expect(tester.getSize(material).width, lessThanOrEqualTo(400.5));
      expect(tester.takeException(), isNull);
    });
  });
}
