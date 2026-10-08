import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/page_toasts.dart';

// A02.4 c3: "已取消关注 X · 撤销" followed the user from the room to home
// (K90, an accessibility service on, so it never ran out).

void main() {
  late GoRouter router;
  late GlobalKey<ScaffoldMessengerState> messenger;

  Future<void> pumpApp(WidgetTester tester) async {
    messenger = GlobalKey<ScaffoldMessengerState>();
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/room',
          builder: (context, state) => const Scaffold(body: Text('room')),
        ),
      ],
    );
    addTearDown(router.dispose);
    final stop = closeToastsOnNewPage(router, () => messenger.currentState);
    addTearDown(stop);
    await tester.pumpWidget(
      MaterialApp.router(scaffoldMessengerKey: messenger, theme: const LiveTheme().light, routerConfig: router),
    );
    unawaited(router.push<void>('/room'));
    await tester.pumpAndSettle();
  }

  AppToast undo() => AppToast('已取消关注“前排”', actionLabel: '撤销', onAction: () {});

  testWidgets('leaving the page closes its undo toast', (tester) async {
    await pumpApp(tester);
    showAppToastOn(messenger.currentState!, undo());
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsOneWidget);
    router.pop();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a dialog over the page keeps it; plain words outlive the page', (tester) async {
    await pumpApp(tester);
    showAppToastOn(messenger.currentState!, undo());
    await tester.pumpAndSettle();
    final context = tester.element(find.text('room'));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => const AlertDialog(content: Text('dialog')),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('dialog'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('撤销'), findsOneWidget);

    showAppToastOn(messenger.currentState!, const AppToast('已复制'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
