import 'dart:convert';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/app.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/core/recording.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/about/releases.dart';
import 'package:pure_live_app/features/about/update_state.dart';
import 'package:pure_live_app/features/backup/backup_flow.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';
import 'package:pure_live_app/features/onboarding/first_run.dart';
import 'package:pure_live_app/features/onboarding/startup.dart';

import 'fakes.dart';

class _NoRefresh extends FollowRefreshNotifier {
  @override
  Future<FollowRefreshResult?> build() async => null;
}

/// GitHub without releases.
final class _NoReleases implements LiveHttp {
  int requests = 0;

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests++;
    return LiveResponse(status: 200, bytes: utf8.encode('[]'), url: request.url);
  }

  @override
  void close() {}
}

void main() {
  group('first run', () {
    late LiveStore store;
    late ProviderContainer container;

    setUp(() async {
      store = await LiveStore.inMemory();
      container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    });

    tearDown(() async {
      container.dispose();
      await store.close();
    });

    FirstRunGate gate(ProviderContainer container) => FirstRunGate(
      isDone: () => container.read(appPrefsProvider).firstRunDone,
      markDone: container.read(appPrefsProvider.notifier).markFirstRunDone,
      followCount: store.follows.count,
    );

    test('the wizard is offered once, also across restarts', () async {
      expect(await gate(container).take(), isTrue);
      expect(await gate(container).take(), isFalse);
      final prefs = await AppPrefs.load(store.meta);
      expect(prefs.firstRunDone, isTrue);
      final restarted = ProviderContainer(
        overrides: [
          storeProvider.overrideWithValue(store),
          appPrefsProvider.overrideWith(() => AppPrefsNotifier(prefs)),
        ],
      );
      addTearDown(restarted.dispose);
      expect(await gate(restarted).take(), isFalse);
    });

    test('an installation that already follows rooms is not offered it, and it stays that way', () async {
      await store.follows.follow(RoomSnapshot(ref: RoomRef('douyu', '5526219')));
      expect(await gate(container).take(), isFalse);
      expect((await AppPrefs.load(store.meta)).firstRunDone, isTrue);
    });

    test('app preferences start with the defaults and persist', () async {
      const defaults = AppPrefs();
      expect(defaults.clipboardRecognition, isTrue);
      expect(defaults.crashReports, isFalse, reason: 'crash reports are off by default (F-NEW-11)');
      final loaded = await AppPrefs.load(store.meta);
      expect((loaded.clipboardRecognition, loaded.crashReports, loaded.firstRunDone), (true, false, false));
      await container.read(appPrefsProvider.notifier).setClipboardRecognition(enabled: false);
      await container.read(appPrefsProvider.notifier).setCrashReports(enabled: true);
      expect(container.read(appPrefsProvider).crashReports, isTrue);
      final reloaded = await AppPrefs.load(store.meta);
      expect((reloaded.clipboardRecognition, reloaded.crashReports), (false, true));
    });
  });

  testWidgets('the first launch opens the wizard over the start page, and skipping returns', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    final github = _NoReleases();
    var offered = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          recordManagerProvider.overrideWithValue(fakeRecordManager()),
          storeProvider.overrideWithValue(store),
          sitesProvider.overrideWithValue({for (final id in platformOrder) id: PlatformSite(FakeSite(id))}),
          followsProvider.overrideWith((ref) => Stream.value(const [])),
          followRefreshProvider.overrideWith(_NoRefresh.new),
          updateCheckerProvider.overrideWithValue(UpdateChecker(github)),
          firstRunGateProvider.overrideWithValue(
            FirstRunGate(isDone: () => offered, markDone: () async => offered = true, followCount: () async => 0),
          ),
        ],
        child: const StartupTasks(child: PureLiveApp()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用纯粹直播 v4'), findsOneWidget);
    expect(find.text('从备份文件导入'), findsOneWidget);
    expect(find.text('从 WebDAV 导入'), findsOneWidget);
    expect(find.text('从另一台设备导入'), findsOneWidget);
    expect(offered, isTrue);

    await tester.tap(find.text('跳过，直接开始'));
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用纯粹直播 v4'), findsNothing);
    expect(find.text('还没有关注的主播'), findsOneWidget);

    // The automatic update check runs 2 s after the first frame.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(github.requests, 1);
  });

  testWidgets('the restore confirmation shows the dry run, the mode and the passphrase field', (tester) async {
    final store = (await tester.runAsync(LiveStore.inMemory))!;
    addTearDown(() => tester.runAsync(store.close));
    final plans = (await tester.runAsync(() async {
      final source = await LiveStore.inMemory();
      await source.follows.follow(RoomSnapshot(ref: RoomRef('huya', '660000'), anchorName: '主播'));
      final document = await BackupService(
        source,
        secrets: await SecretStore.memory({SecretRefs.cookie('huya'): 'cookie'}),
        kdfIterations: 1000,
      ).export(passphrase: 'passphrase');
      await source.close();
      final service = BackupService(store, secrets: await SecretStore.memory(), kdfIterations: 1000);
      return {
        RestoreMode.full: await service.plan(document),
        RestoreMode.follows: await service.plan(document, mode: RestoreMode.follows),
      };
    }))!;
    RestoreChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showDialog<RestoreChoice>(
              context: context,
              builder: (context) => RestoreConfirmDialog(plans: plans, source: '来自 测试手机'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('来自 测试手机'), findsOneWidget);
    expect(find.text('关注：读到 1 项'), findsOneWidget);
    expect(find.text('口令（可选）'), findsOneWidget);

    await tester.tap(find.text('仅恢复关注'));
    await tester.pumpAndSettle();
    expect(find.text('口令（可选）'), findsNothing, reason: 'accounts are never part of a follows-only restore');

    await tester.tap(find.text('完整恢复'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'passphrase');
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(choice?.mode, RestoreMode.full);
    expect(choice?.passphrase, 'passphrase');
  });
}
