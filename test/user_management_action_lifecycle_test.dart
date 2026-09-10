import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/modules/auth/models/user_item.dart';
import 'package:pure_live/modules/auth/user_manage_page.dart';
import 'package:pure_live/modules/auth/user_management_actions.dart';
import 'package:pure_live/modules/auth/user_server_remote_controller.dart';
import 'package:pure_live/modules/auth/utils/firebase_manager.dart';

class _Loader extends AssetLoader {
  const _Loader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>;
}

class _Actions extends UserManagementActions {
  final gate = Completer<void>();
  final calls = <String>[];
  Future<void> record(String action) {
    calls.add(action);
    return gate.future;
  }

  @override
  Future<void> deleteUser(String uid, {required bool deletePermission}) => record('delete:$uid:$deletePermission');
  @override
  Future<void> promote(String uid, String email) => record('promote:$uid');
  @override
  Future<void> demote(String uid) => record('demote:$uid');
  @override
  Future<void> setUpload(String uid, bool allowed) => record('upload:$uid:$allowed');
}

class _Controller extends UserServerRemoteController {
  int refreshes = 0;
  Completer<void>? refreshGate;
  @override
  void onInit() {
    super.onInit();
    isSuperAdmin = true;
  }

  @override
  Future<List<String>> readCloudUserIds() async => [];
  @override
  Future<Map<String, String>> readCloudRoles(List<String>? uids) async => {};

  @override
  Future<void> refreshData() async {
    refreshes++;
    await refreshGate?.future;
  }

  @override
  Future<void> loadData() async {}
}

Future<void> _invoke(dynamic state, String action, UserItem user) => switch (action) {
  'delete' => state.deleteUserComplete(user),
  'promote' => state.promoteToManager(user),
  'demote' => state.demoteManager(user),
  'ban' => state.banUserUpload(user),
  _ => state.unbanUserUpload(user),
};

void _test(String name, Future<void> Function(WidgetTester, _Controller, _Actions, ValueNotifier<bool>) body) {
  testWidgets(name, (tester) async {
    Get.testMode = true;
    Get.reset();
    Get.put(SettingsService(), permanent: true);
    FirebaseManager.roleWeights = {'admin': 0, 'manager': 1, 'user': 2};
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final visible = ValueNotifier(true);
    final actions = _Actions();
    _Controller? c;
    try {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('zh')],
          startLocale: const Locale('zh'),
          fallbackLocale: const Locale('zh'),
          saveLocale: false,
          path: 'assets/translations',
          assetLoader: const _Loader(),
          child: Builder(
            builder: (context) => GetMaterialApp(
              locale: context.locale,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              home: Builder(
                builder: (_) {
                  if (c == null) {
                    c = _Controller();
                    Get.put<UserServerRemoteController>(c!);
                    c!.list.assignAll([UserItem(uid: 'u', email: 'u@example.invalid', role: 'user', canUpload: true)]);
                    c!.totalCount.value = 1;
                  }
                  return ValueListenableBuilder<bool>(
                    valueListenable: visible,
                    builder: (_, show, child) => show ? UserManager(actions: actions) : const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10 && c == null; i++) {
        await tester.pump(Duration.zero);
      }
      expect(c, isNotNull);
      await tester.pump(Duration.zero);
      expect(find.byType(UserManager), findsOneWidget);
      await body(tester, c!, actions, visible);
    } finally {
      if (!actions.gate.isCompleted) actions.gate.complete();
      final refreshGate = c?.refreshGate;
      if (refreshGate != null && !refreshGate.isCompleted) refreshGate.complete();
      await tester.pump(Duration.zero);
      await tester.pumpWidget(const SizedBox.shrink());
      c?.onDelete();
      await tester.pump(Duration.zero);
      Get.reset();
      visible.dispose();
      FirebaseManager.roleWeights = {};
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await Hive.openBox('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  tearDownAll(Hive.close);

  for (final action in ['delete', 'promote', 'demote', 'ban', 'unban']) {
    _test('$action late write failure after exit is handled without refresh', (tester, c, actions, visible) async {
      final dynamic state = tester.state(find.byType(UserManager));
      final user = UserItem(uid: 'u', email: 'u@example.invalid', role: 'manager', canUpload: true);
      final operation = _invoke(state, action, user);
      expect(actions.calls, hasLength(1));
      visible.value = false;
      await tester.pump(Duration.zero);
      actions.gate.completeError(StateError('write failed'));
      await tester.pump(Duration.zero);
      await operation;
      expect(c.refreshes, 0);
      expect(tester.takeException(), isNull);
    });

    _test('$action late completion never refreshes a replacement controller', (tester, c, actions, visible) async {
      final dynamic state = tester.state(find.byType(UserManager));
      final user = UserItem(
        uid: 'u',
        email: 'u@example.invalid',
        role: action == 'demote' ? 'manager' : 'user',
        canUpload: true,
      );
      final operation = _invoke(state, action, user);
      expect(actions.calls, hasLength(1));
      visible.value = false;
      await tester.pump(Duration.zero);
      Get.delete<UserServerRemoteController>(force: true);
      final replacement = Get.put<UserServerRemoteController>(_Controller()) as _Controller;
      actions.gate.complete();
      await tester.pump(Duration.zero);
      await operation;
      expect(replacement.refreshes, 0);
      expect(c.refreshes, 0);
      replacement.onDelete();
    });

    _test('$action callback after route disposal does not start a mutation', (tester, c, actions, visible) async {
      final dynamic state = tester.state(find.byType(UserManager));
      visible.value = false;
      await tester.pump(Duration.zero);
      final user = UserItem(
        uid: 'u',
        email: 'u@example.invalid',
        role: action == 'demote' ? 'manager' : 'user',
        canUpload: true,
      );
      final operation = _invoke(state, action, user);
      actions.gate.complete();
      await tester.pump(Duration.zero);
      await operation;
      expect(actions.calls, isEmpty);
      expect(c.refreshes, 0);
    });
  }

  _test('real promotion confirmation performs one write and refreshes its live owner', (
    tester,
    c,
    actions,
    visible,
  ) async {
    await tester.tap(find.text(i18n('action_promote')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(i18n('confirm')));
    await tester.pumpAndSettle();
    expect(actions.calls, ['promote:u']);
    expect(c.refreshes, 0);
    actions.gate.complete();
    await tester.pump(Duration.zero);
    expect(c.refreshes, 1);
  });

  _test('in-flight row action disables a second confirmation', (tester, c, actions, visible) async {
    await tester.tap(find.text(i18n('action_promote')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(i18n('confirm')));
    await tester.pumpAndSettle();
    expect(actions.calls, ['promote:u']);
    await tester.tap(find.text(i18n('action_promote')));
    await tester.pumpAndSettle();
    final dialogs = find.byType(AlertDialog).evaluate().length;
    if (dialogs > 0) {
      Get.back(result: false);
      await tester.pumpAndSettle();
    }
    actions.gate.complete();
    await tester.pump(Duration.zero);
    expect(dialogs, 0);
    expect(actions.calls, hasLength(1));
  });

  _test('confirming after the underlying management page closes does not write', (tester, c, actions, visible) async {
    await tester.tap(find.text(i18n('action_promote')));
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pump(Duration.zero);
    expect(find.byType(UserManager), findsNothing);
    await tester.tap(find.text(i18n('confirm')));
    await tester.pumpAndSettle();
    actions.gate.complete();
    await tester.pump(Duration.zero);
    expect(actions.calls, isEmpty);
  });

  _test('closed controller blocks all callbacks even while page remains mounted', (tester, c, actions, visible) async {
    final dynamic state = tester.state(find.byType(UserManager));
    c.onDelete();
    final user = UserItem(uid: 'u', email: 'u@example.invalid', role: 'manager', canUpload: true);
    for (final action in ['delete', 'promote', 'demote', 'ban', 'unban']) {
      await _invoke(state, action, user);
    }
    expect(actions.calls, isEmpty);
    expect(c.refreshes, 0);
  });

  _test('cancel releases row reservation without writing or closing a borrowed controller', (
    tester,
    c,
    actions,
    visible,
  ) async {
    await tester.tap(find.text(i18n('action_promote')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(i18n('cancel')));
    await tester.pumpAndSettle();
    expect(actions.calls, isEmpty);
    await tester.tap(find.text(i18n('action_ban')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    Get.back(result: false);
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pump(Duration.zero);
    expect(c.isClosed, isFalse);
  });

  _test('write failure releases row reservation so the user can retry', (tester, c, actions, visible) async {
    await tester.tap(find.text(i18n('action_promote')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(i18n('confirm')));
    await tester.pumpAndSettle();
    actions.gate.completeError(StateError('write failed'));
    await tester.pumpAndSettle();
    expect(c.refreshes, 0);
    await tester.tap(find.text(i18n('action_promote')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    Get.back(result: false);
    await tester.pumpAndSettle();
    expect(actions.calls, hasLength(1));
  });

  _test('row reservation spans refresh and consumes taps instead of opening the parent card', (
    tester,
    c,
    actions,
    visible,
  ) async {
    c.refreshGate = Completer<void>();
    await tester.tap(find.text(i18n('action_promote')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(i18n('confirm')));
    await tester.pumpAndSettle();
    actions.gate.complete();
    await tester.pumpAndSettle();
    expect(c.refreshes, 1);
    await tester.tap(find.text(i18n('action_ban')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(UserManager), findsOneWidget);
    expect(find.text(i18n('manage_users')), findsOneWidget);
    expect(actions.calls, ['promote:u']);
    c.refreshGate!.complete();
    await tester.pumpAndSettle();
    await tester.tap(find.text(i18n('action_ban')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    Get.back(result: false);
    await tester.pumpAndSettle();
  });

  _test('existing super admin and protected target checks remain intact', (tester, c, actions, visible) async {
    final dynamic state = tester.state(find.byType(UserManager));
    final user = UserItem(uid: 'u', email: 'u@example.invalid', role: 'user', canUpload: true);
    c.isSuperAdmin = false;
    for (final action in ['delete', 'promote', 'demote']) {
      await _invoke(state, action, user);
    }
    c.isSuperAdmin = true;
    final admin = UserItem(uid: 'a', email: 'a@example.invalid', role: 'admin', canUpload: true);
    await _invoke(state, 'delete', admin);
    await _invoke(state, 'demote', admin);
    expect(actions.calls, isEmpty);
  });

  _test('manager deletion retains permission deletion intent and one refresh', (tester, c, actions, visible) async {
    final dynamic state = tester.state(find.byType(UserManager));
    final user = UserItem(uid: 'u', email: 'u@example.invalid', role: 'manager', canUpload: true);
    final operation = _invoke(state, 'delete', user);
    expect(actions.calls, ['delete:u:true']);
    actions.gate.complete();
    await tester.pump(Duration.zero);
    await operation;
    expect(c.refreshes, 1);
  });

  _test('a pending row does not reserve another user row', (tester, c, actions, visible) async {
    c.list.add(UserItem(uid: 'v', email: 'v@example.invalid', role: 'user', canUpload: true));
    c.totalCount.value = 2;
    await tester.pumpAndSettle();
    await tester.tap(find.text(i18n('action_promote')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(i18n('confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(i18n('action_promote')).last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(i18n('confirm')));
    await tester.pumpAndSettle();
    expect(actions.calls, ['promote:u', 'promote:v']);
    actions.gate.complete();
    await tester.pumpAndSettle();
    expect(c.refreshes, 2);
  });
}
