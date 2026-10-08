import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/danmaku/message_panel.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/routes/app_navigator.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// D02.2 on the long-press panel's keyword page: a bad `/…/` is said under
/// the field and not blocked; a good one is.
void main() {
  testWidgets('the keyword page checks a pattern before blocking it', (tester) async {
    final store = (await tester.runAsync(() => LiveStore.memory(cipher: FakeCipher())))!;
    final session = fakeSession(FakeEngine());
    final strings = (await tester.runAsync(loadStrings))!;
    final controller = LiveRoomController(
      room: liveRoom(),
      site: FakeSite(liveRoom()),
      session: session,
      danmaku: FakeDanmaku(),
      danmakuSupported: true,
      store: store,
      refreshInterval: Duration.zero,
    );
    final previousToast = AppNavigator.toast;
    AppNavigator.toast = (_) {};
    addTearDown(() async {
      AppNavigator.toast = previousToast;
      controller.dispose();
      await tester.runAsync(session.dispose);
      await tester.runAsync(store.close);
    });
    var closed = 0;
    await tester.pumpWidget(
      LiveUiScope(
        config: LiveUiConfig(strings: strings.ui),
        child: MaterialApp(
          theme: const LiveTheme(primaryColor: Colors.blue).light,
          home: Scaffold(
            body: RoomMessagePanel(
              controller: controller,
              message: const LiveMessage(
                type: LiveMessageType.chat,
                userName: '路人',
                message: '/[0-9/',
                color: LiveMessageColor.white,
              ),
              onClose: () => closed++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('live-play-block-keyword')));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('live-play-keyword-input'));
    expect(tester.widget<TextField>(input).maxLength, 200, reason: 'a pattern may be longer than 40');

    await tester.tap(find.byKey(const ValueKey('live-play-keyword-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('正则写法不对，没有加进去'), findsOneWidget);
    expect(closed, 0, reason: 'the panel stays to put it right');
    expect(await tester.runAsync(() => store.blockLists.list(BlockKind.keyword)), isEmpty);

    await tester.enterText(input, '/[0-9]+/');
    await tester.pumpAndSettle();
    expect(find.text('正则写法不对，没有加进去'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('live-play-keyword-confirm')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(await tester.runAsync(() => store.blockLists.list(BlockKind.keyword)), ['/[0-9]+/']);
  });
}
