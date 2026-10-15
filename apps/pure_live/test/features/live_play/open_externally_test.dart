import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/features/live_play/buttons/room_menu_button.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/background_guide.dart';
import 'package:pure_live/routes/app_navigator.dart';

import '../../support.dart';

void main() {
  const channel = MethodChannel('pure_live/background_guide');
  final room = LiveRoom(platform: SiteIds.bilibili, roomId: '6', watching: '', link: 'https://live.bilibili.com/6');

  Future<(List<String>, List<MethodCall>)> run(WidgetTester tester, String manufacturer) async {
    currentStrings = await tester.runAsync(loadStrings);
    final toasts = <String>[];
    final calls = <MethodCall>[];
    final previous = (AppNavigator.openExternal, AppNavigator.toast);
    AppNavigator.openExternal = (uri) async => false;
    AppNavigator.toast = toasts.add;
    addTearDown(() {
      AppNavigator.openExternal = previous.$1;
      AppNavigator.toast = previous.$2;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'status' ? {'manufacturer': manufacturer, 'brand': manufacturer, 'sdk': 37} : 0;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => openRoomExternally(
              room,
              android: true,
              guide: const BackgroundGuideChannel(android: true),
              contextOf: () => context,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return (toasts, calls);
  }

  testWidgets('C03.2: a refused jump on a Xiaomi phone says where to allow it and opens the app info', (tester) async {
    final (toasts, calls) = await run(tester, 'Xiaomi');
    expect(find.text('系统拦住了跳转'), findsOneWidget);
    expect(find.textContaining('打开其他应用'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('open-room-blocked-details')));
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), ['status', 'open']);
    // The app was tried first, then the web page; no second message.
    expect(toasts, [i18n('open_app_failed_fallback_browser')]);
  });

  testWidgets('C03.2: elsewhere a refused jump keeps the message', (tester) async {
    final (toasts, _) = await run(tester, 'Google');
    expect(find.text('系统拦住了跳转'), findsNothing);
    expect(toasts.last, i18n('open_room_external_failed'));
  });
}
