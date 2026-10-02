import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/settings/playback_tiles.dart';
import 'package:pure_live/platform/system_permissions.dart';
import 'package:pure_live/shared/permission_prompts.dart';

import '../support.dart';

// F.0a c4, c6 and docs/A-界面设计/A14-系统界面/A14.1-系统界面 c12–c14: the explanations before
// the system's permission dialogs.

final class _Permissions extends SystemPermissions {
  new({this.state = NotificationPermission.granted, this.grant = true, this.battery = true})
    : super(channel: const MethodChannel('test/permissions'));

  NotificationPermission state;
  bool grant;
  bool battery;
  final calls = <String>[];

  @override
  bool get applies => true;

  @override
  Future<NotificationPermission> notifications() async => state;

  @override
  Future<bool> requestNotifications() async {
    calls.add('request');
    if (grant) state = NotificationPermission.granted;
    return grant;
  }

  @override
  Future<bool> batteryUnrestricted() async => battery;

  @override
  Future<bool> requestBatteryUnrestricted() async {
    calls.add('battery');
    return battery = true;
  }

  @override
  Future<bool> openNotificationSettings() async {
    calls.add('settings');
    return true;
  }
}

void main() {
  setUpAll(loadStrings);

  final navigator = GlobalKey<NavigatorState>();
  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: SizedBox()),
    ),
  );

  /// Runs [confirm] and answers its dialogs with [answers] (button labels).
  Future<PermissionAnswer> run(WidgetTester tester, Future<PermissionAnswer> confirm, List<String> answers) async {
    PermissionAnswer? answer;
    unawaited(confirm.then((value) => answer = value));
    for (final label in answers) {
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
    }
    await tester.pumpAndSettle();
    return answer!;
  }

  BackgroundPermissions questions(_Permissions permissions, {Future<void> Function()? resumed}) =>
      BackgroundPermissions(permissions: permissions, navigator: () => navigator.currentContext, resumed: resumed);

  testWidgets('allowed already: no question', (tester) async {
    await pumpApp(tester);
    final permissions = _Permissions();
    expect(await run(tester, questions(permissions).confirm(), []), PermissionAnswer.granted);
    expect(permissions.calls, isEmpty);
  });

  testWidgets("3.x's two explanations as the app's dialogs (c12): notifications, then the battery", (tester) async {
    await pumpApp(tester);
    final permissions = _Permissions(state: NotificationPermission.askable, battery: false);
    final confirm = questions(permissions).confirm();
    await tester.pumpAndSettle();
    final dialog = find.byKey(const ValueKey('permission-dialog'));
    expect(find.descendant(of: dialog, matching: find.text('需要通知权限')), findsOneWidget);
    expect(find.text('为了在后台播放时显示控制条并防止直播中断，我们需要开启通知权限。'), findsOneWidget);
    // Title on the left, "取消" before the main button at the bottom right.
    final title = tester.getTopLeft(find.text('需要通知权限'));
    final message = tester.getTopLeft(find.text('为了在后台播放时显示控制条并防止直播中断，我们需要开启通知权限。'));
    expect(title.dx, message.dx);
    expect(tester.getCenter(find.text('取消')).dx, lessThan(tester.getCenter(find.text('去开启')).dx));
    expect(tester.getCenter(find.text('去开启')).dy, greaterThan(message.dy));
    expect(await run(tester, confirm, ['去开启', '去开启']), PermissionAnswer.granted);
    expect(permissions.calls, ['request', 'battery']);
  });

  testWidgets('cancel keeps the switch off; a refusal says denied; the battery never blocks (3.x)', (tester) async {
    await pumpApp(tester);
    final permissions = _Permissions(state: NotificationPermission.askable, grant: false, battery: false);
    expect(await run(tester, questions(permissions).confirm(), ['取消']), PermissionAnswer.cancelled);
    expect(await run(tester, questions(permissions).confirm(), ['去开启']), PermissionAnswer.denied);
    permissions
      ..state = NotificationPermission.granted
      ..calls.clear();
    expect(await run(tester, questions(permissions).confirm(), ['取消']), PermissionAnswer.granted);
    expect(permissions.calls, isEmpty, reason: 'battery declined, the switch still turns on');
  });

  testWidgets('refused for good (c13): "通知权限已关闭", "去设置", looks again back in the app', (tester) async {
    await pumpApp(tester);
    final permissions = _Permissions(state: NotificationPermission.blocked);
    final back = Completer<void>();
    PermissionAnswer? answer;
    unawaited(questions(permissions, resumed: () => back.future).confirm().then((value) => answer = value));
    await tester.pumpAndSettle();
    expect(find.text('通知权限已关闭'), findsOneWidget);
    expect(find.text('系统设置里关掉了“纯粹直播”的通知，后台播放要用它显示控制条。打开后回到这里再开一次。'), findsOneWidget);
    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();
    expect(permissions.calls, ['settings']);
    expect(answer, isNull, reason: 'waits for the return to the app');
    permissions.state = NotificationPermission.granted;
    back.complete();
    await tester.pumpAndSettle();
    expect(answer, PermissionAnswer.granted);

    permissions.state = NotificationPermission.blocked;
    expect(
      await run(tester, questions(permissions, resumed: () async {}).confirm(), ['去设置']),
      PermissionAnswer.denied,
      reason: 'still off after the settings page',
    );
  });

  testWidgets('the settings switch maps the answers (U.6c gate)', (tester) async {
    final permissions = _Permissions(state: NotificationPermission.askable);
    final container = ProviderContainer(
      overrides: [
        backgroundPermissionsProvider.overrideWithValue(
          BackgroundPermissions(permissions: permissions, navigator: () => null),
        ),
      ],
    );
    addTearDown(container.dispose);
    final gate = container.read(switchGateProvider)!;
    expect(await gate(Settings.enableBackgroundPlay), SwitchGateResult.denied, reason: 'no window to ask in');
    permissions.state = NotificationPermission.granted;
    expect(await gate(Settings.enableBackgroundPlay), SwitchGateResult.granted);
    expect(ProviderContainer().read(switchGateProvider), isNull, reason: 'nothing to ask off Android');
  });

  group('recording (c14)', () {
    testWidgets('notifications explained once, only in front; recording never waits', (tester) async {
      await pumpApp(tester);
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      final permissions = _Permissions(state: NotificationPermission.askable);
      var front = false;
      final prompts = RecordingPermissionPrompts(
        permissions: permissions,
        meta: store.meta,
        navigator: () => navigator.currentContext,
        inFront: () => front,
      );
      await prompts.notificationsOnce();
      expect(find.byKey(const ValueKey('permission-dialog')), findsNothing, reason: 'not while in the background');
      front = true;
      unawaited(prompts.notificationsOnce());
      await tester.pumpAndSettle();
      expect(find.text('录制时通知栏会显示录制状态和“停止录制”。没有通知权限时录制照常进行，但看不到这条通知，后台录制也更容易被系统停止。'), findsOneWidget);
      await tester.tap(find.text('以后再说'));
      await tester.pumpAndSettle();
      expect(permissions.calls, isEmpty);
      await prompts.notificationsOnce();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('permission-dialog')), findsNothing, reason: 'once');
      expect(await store.meta.get(RecordingPermissionPrompts.askedKey), isNotNull);
    });

    testWidgets('all-files access is explained before the system page; cancel opens nothing', (tester) async {
      await pumpApp(tester);
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      final prompts = RecordingPermissionPrompts(
        permissions: _Permissions(),
        meta: store.meta,
        navigator: () => navigator.currentContext,
      );
      bool? answer;
      unawaited(prompts.explainStorage().then((value) => answer = value));
      await tester.pumpAndSettle();
      expect(find.text('需要所有文件访问权限'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);
    });
  });
}
