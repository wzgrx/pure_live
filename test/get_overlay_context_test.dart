import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/get/get.dart';

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  testWidgets('overlay context resolves the navigator overlay and can insert an entry', (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: Text('home'))));
    await tester.pump(const Duration(milliseconds: 1));
    final context = Get.overlayContext;
    expect(context, isNotNull);
    expect(Overlay.maybeOf(context!), same(Get.key.currentState!.overlay));
    expect(Navigator.of(context), same(Get.key.currentState));
    final entry = OverlayEntry(builder: (_) => const Positioned(top: 10, left: 10, child: Text('entry')));
    Overlay.of(context).insert(entry);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('entry'), findsOneWidget);
    entry.remove();
    await tester.pump();
    entry.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom sheet uses a valid overlay context and preserves its route on return', (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold(body: Text('home'))));
    await tester.pump();
    final sheet = Get.bottomSheet<void>(const SizedBox(height: 120, child: Text('sheet')));
    await tester.pumpAndSettle();
    expect(find.text('sheet'), findsOneWidget);
    expect(Overlay.maybeOf(Get.overlayContext!), same(Get.key.currentState!.overlay));
    Navigator.of(Get.overlayContext!).pop();
    await tester.pumpAndSettle();
    await sheet;
    expect(find.text('sheet'), findsNothing);
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested navigator does not capture root overlay or dialog lookup', (tester) async {
    final nested = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Navigator(
            key: nested,
            onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => const Text('nested home')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(Overlay.maybeOf(Get.overlayContext!), same(Get.key.currentState!.overlay));
    expect(Overlay.maybeOf(Get.overlayContext!), isNot(same(nested.currentState!.overlay)));
    final dialog = Get.dialog<void>(const AlertDialog(content: Text('root dialog')));
    await tester.pumpAndSettle();
    expect(find.text('root dialog'), findsOneWidget);
    Navigator.of(Get.overlayContext!, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    await dialog;
    expect(find.text('root dialog'), findsNothing);
    expect(find.text('nested home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
