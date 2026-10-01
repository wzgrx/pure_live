import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/backup/backup_page.dart';
import 'package:pure_live/features/backup/tv_sync.dart';
import 'package:pure_live/features/search/search_history.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/backup/backup_data.dart';
import 'package:pure_live/shared/backup/backup_files.dart';

import '../../shared/fake_qr_camera.dart';
import '../../support.dart';

final DateTime _now = DateTime(2026, 10, 1, 20);

LiveRoom _room(String id, {String platform = 'douyu'}) =>
    LiveRoom(platform: platform, roomId: id, title: 'Title $id', nick: 'Nick $id');

/// A 3.x backup (`backupVersion: 3`) with [rooms] followed and [history].
Map<String, Object?> _legacyBackup(List<LiveRoom> rooms, {List<LiveRoom> history = const []}) => {
  'backupVersion': 3,
  'favorite': {
    'favoriteRooms': [for (final room in rooms) room.toJson()],
    'favoriteAreas': <Object?>[],
    'shieldList': ['spoiler'],
  },
  'history': {
    'historyRooms': [for (final room in history) room.toJson()],
  },
};

Future<List<String>> _followIds(LiveStore store) async => [for (final room in await store.follows.all()) room.roomId];

void main() {
  setUpAll(loadStrings);

  group('data', () {
    late AppServices services;
    setUp(() async => services = await testServices());
    tearDown(() => services.close());

    test('the preview counts what a 3.x backup changes and lists the parts it keeps', () async {
      final store = services.store;
      await store.follows.add(_room('1'));
      await store.follows.add(_room('2'));
      await store.history.record(_room('9'));
      final preview = await previewRestore(
        store,
        _legacyBackup([_room('2'), _room('3'), _room('4')], history: [_room('9')]),
        BackupScope.all,
      );
      expect(preview.version, 3);
      expect(preview.scope, BackupScope.all);
      final follows = preview.parts.firstWhere((part) => part.kind == RestorePartKind.follows);
      expect((follows.current, follows.incoming, follows.added, follows.removed), (2, 3, 2, 1));
      final history = preview.parts.firstWhere((part) => part.kind == RestorePartKind.history);
      expect(history.unchanged, isTrue);
      expect(preview.parts.map((part) => part.kind), contains(RestorePartKind.keywords));
      expect(preview.kept, containsAll([RestorePartKind.tags, RestorePartKind.webdav, RestorePartKind.search]));
      expect(preview.changesSomething, isTrue);
      expect(() => previewRestore(store, {'nothing': 1}, BackupScope.all), throwsFormatException);
    });

    test('a follows-only file restores follows even when asked for everything', () async {
      final store = services.store;
      final service = BackupService(store);
      await store.follows.add(_room('1'));
      await store.history.record(_room('9'));
      final file = await exportBackup(service, store, BackupScope.follows);
      await store.follows.replaceAll([_room('5')]);
      final preview = await previewRestore(store, file, BackupScope.all);
      expect(preview.scope, BackupScope.follows);
      expect(preview.followsOnlyFile, isTrue);
      await restoreBackup(service, store, file, preview.scope);
      expect(await _followIds(store), ['1']);
      expect((await store.history.all()).single.roomId, '9');
    });

    test('full backups carry the search words both ways (M13.4 question)', () async {
      final store = services.store;
      final service = BackupService(store);
      await store.meta.set(SearchHistory.key, jsonEncode(['lol', 'LOL', ' music ']));
      final file = await exportBackup(service, store, BackupScope.all);
      expect(file[searchSection], {
        'history': ['lol', 'music'],
      });
      expect(file['backupVersion'], 4);
      expect(file['sensitiveDataIncluded'], isFalse);

      await store.meta.set(SearchHistory.key, jsonEncode(['other']));
      final preview = await previewRestore(store, file, BackupScope.all);
      final search = preview.parts.firstWhere((part) => part.kind == RestorePartKind.search);
      expect((search.added, search.removed), (2, 1));
      await restoreBackup(service, store, file, BackupScope.all);
      expect(jsonDecode((await store.meta.get(SearchHistory.key))!), ['lol', 'music']);

      // A 3.x backup has no search words: they stay.
      await restoreBackup(service, store, _legacyBackup([_room('1')]), BackupScope.all);
      expect(jsonDecode((await store.meta.get(SearchHistory.key))!), ['lol', 'music']);
    });

    test('file names, the TV document and TV addresses', () async {
      expect(backupFileName(BackupScope.all, _now), 'purelive_2026-10-01T20_00_00.txt');
      expect(backupFileName(BackupScope.follows, _now), 'purelive_favorites_2026-10-01T20_00_00.txt');
      final dir = await Directory.systemTemp.createTemp('backup_names');
      addTearDown(() => dir.delete(recursive: true));
      File(p(dir, 'purelive_a.txt')).writeAsStringSync('{}');
      expect(freeBackupFile(dir, 'purelive_a.txt').path, p(dir, 'purelive_a_2.txt'));

      final full = await BackupService(services.store).exportAll();
      final document = tvSyncDocument(full);
      expect(document.keys, containsAll(['favoriteRooms', 'historyRooms', 'customIptvUserAgent']));
      expect(document.containsKey('backupVersion'), isFalse);

      expect(normalizeTvAddress('192.168.1.5:8888'), 'http://192.168.1.5:8888');
      expect(normalizeTvAddress('HTTP://TV.local/'), 'http://tv.local');
      expect(normalizeTvAddress('http://user@tv:1/'), isNull);
      expect(normalizeTvAddress('http://tv:1/api?x=1'), isNull);
    });
  });

  group('page', () {
    late Directory folder;

    Future<AppServices> pump(
      WidgetTester tester, {
      String? Function()? pick,
      Size size = const Size(500, 1400),
      bool opensFolder = false,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(testServices))!;
      addTearDown(() => tester.runAsync(services.close));
      folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('backup_page')))!;
      final made = folder;
      addTearDown(() => tester.runAsync(() => made.delete(recursive: true)));
      final strings = (await tester.runAsync(loadStrings))!;
      final toasts = <String>[];
      final previous = AppNavigator.toast;
      AppNavigator.toast = toasts.add;
      addTearDown(() => AppNavigator.toast = previous);
      _toasts = toasts;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appServicesProvider.overrideWithValue(services),
            backupClockProvider.overrideWithValue(() => _now),
            backupDefaultFolderProvider.overrideWithValue(() async => made),
            backupPickerProvider.overrideWithValue((_, {required initial, required pickFile}) async => pick?.call()),
            backupOpensFolderProvider.overrideWithValue(opensFolder),
          ],
          child: LiveUiScope(
            config: LiveUiConfig(strings: strings.ui),
            child: MaterialApp(
              theme: const LiveTheme(primaryColor: Colors.blue).light,
              home: const BackupPage(route: RouteArgs(RoutePath.kBackup)),
            ),
          ),
        ),
      );
      await _settle(tester);
      return services;
    }

    Future<void> writeBackups() async {
      await File(p(folder, 'purelive_2026-09-01T10_00_00.txt')).writeAsString(jsonEncode(_legacyBackup([_room('2')])));
      await File(p(folder, 'purelive_favorites_2026-09-02T10_00_00.txt'))
          .writeAsString(jsonEncode(_legacyBackup([_room('3')])));
    }

    Future<void> refresh(WidgetTester tester) async {
      await tester.drag(find.byKey(const ValueKey('backup-list')), const Offset(0, 400));
      await _settle(tester);
    }

    testWidgets('groups, rows and icons in 3.x order; the cloud account row; no log group (Q1)', (tester) async {
      await pump(tester);
      final groups = ['云端和其他设备', '本地备份', '目录中的备份', '备份目录'];
      for (final (i, title) in groups.indexed) {
        expect(find.text(title), findsOneWidget, reason: title);
        if (i > 0) expect(_top(tester, title), greaterThan(_top(tester, groups[i - 1])));
      }
      final rows = [
        ('云端账号（已停用）', AppIcons.cloudOff),
        ('WebDAV', AppIcons.webDav),
        ('设备同步', AppIcons.deviceSync),
        ('同步TV数据', AppIcons.syncTv),
        ('创建备份', AppIcons.backupCreate),
        ('恢复备份', AppIcons.backupRestore),
        ('仅导出关注列表', AppIcons.backupCreate),
        ('仅导入关注列表', AppIcons.backupRestore),
        ('备份目录（默认）', AppIcons.backupFolder),
      ];
      for (final (i, (title, icon)) in rows.indexed) {
        expect(
          find.descendant(of: _row(title), matching: find.byIcon(icon)),
          findsOneWidget,
          reason: title,
        );
        if (i > 0) expect(_top(tester, title), greaterThan(_top(tester, rows[i - 1].$1)), reason: title);
      }
      expect(find.text('备份到 WebDAV 服务器'), findsOneWidget);
      expect(find.text('保存设置、关注、历史、分组、屏蔽词和搜索记录（不含账号 Cookie 和 WebDAV 密码）'), findsOneWidget);
      expect(find.text('改用 WebDAV 或设备同步；点这里看怎么迁移旧的云端配置'), findsOneWidget);
      // 3.x's Firebase row and log group are gone (c2, c9).
      expect(find.textContaining('Firebase'), findsNothing);
      expect(find.text('日志管理'), findsNothing);
      expect(find.text('启用本地日志'), findsNothing);
      expect(find.text('改回默认目录'), findsNothing, reason: 'only after picking a folder');
      expect(find.text('打开备份目录'), findsNothing, reason: 'computers only');
      expect(find.byKey(const ValueKey('backup-files-empty')), findsOneWidget);
      expect(find.text('这个目录里还没有备份'), findsOneWidget);
    });

    testWidgets('creates a backup in the default folder and lists it', (tester) async {
      final services = await pump(tester);
      await tester.runAsync(() => services.store.follows.add(_room('1')));
      expect(find.text('这个目录里还没有备份'), findsOneWidget);
      expect(find.text(folder.path), findsOneWidget);

      await tester.tap(find.text('创建备份'));
      await _settle(tester);
      final file = File(p(folder, 'purelive_2026-10-01T20_00_00.txt'));
      expect(file.existsSync(), isTrue);
      final saved = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      expect((saved['favorite']! as Map)['favoriteRooms'], hasLength(1));
      expect(_toasts, ['已备份到 purelive_2026-10-01T20_00_00.txt']);
      expect(find.text('purelive_2026-10-01T20_00_00.txt'), findsOneWidget);
      expect(find.textContaining('完整备份'), findsOneWidget);
      expect(find.text('目录中的备份 · 1'), findsOneWidget);
    });

    testWidgets('restores a 3.x file from the folder after showing what changes; the others grey out meanwhile', (
      tester,
    ) async {
      final services = await pump(tester);
      await tester.runAsync(() async {
        await services.store.follows.add(_room('1'));
        await File(p(folder, 'purelive_2026-09-01T10_00_00.txt'))
            .writeAsString(jsonEncode(_legacyBackup([_room('2'), _room('3')])));
      });
      // The list picks the new file up on refresh.
      await refresh(tester);
      await tester.tap(find.text('purelive_2026-09-01T10_00_00.txt'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('backup-preview')), findsOneWidget);
      expect(find.text('3.x 备份（版本 3）'), findsOneWidget);
      expect(find.text('关注的直播间：1 → 2（新增 2，移除 1）'), findsOneWidget);
      expect(find.textContaining('文件中没有、保持不变'), findsOneWidget);
      // One thing at a time: the other backup actions grey out, WebDAV and
      // device sync stay (c7).
      expect(_greyed(tester, '创建备份'), isTrue);
      expect(_greyed(tester, '同步TV数据'), isTrue);
      expect(_greyed(tester, '备份目录（默认）'), isTrue);
      expect(_greyed(tester, 'WebDAV'), isFalse);
      expect(_greyed(tester, '设备同步'), isFalse);

      // Cancelling changes nothing.
      await tester.tap(find.text('取消'));
      await _settle(tester);
      expect(await tester.runAsync(() => _followIds(services.store)), ['1']);
      expect(_greyed(tester, '创建备份'), isFalse);

      await tester.tap(find.text('purelive_2026-09-01T10_00_00.txt'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('backup-restore-confirm')));
      await _settle(tester);
      expect(await tester.runAsync(() => _followIds(services.store)), ['2', '3']);
      expect(_toasts, ['恢复备份成功']);
    });

    testWidgets("a file's ⋮, right click and long press open the same small menu; delete asks first", (tester) async {
      await pump(tester);
      await tester.runAsync(writeBackups);
      await refresh(tester);
      expect(find.text('目录中的备份 · 2'), findsOneWidget);
      const full = 'purelive_2026-09-01T10_00_00.txt';
      const follows = 'purelive_favorites_2026-09-02T10_00_00.txt';
      expect(_top(tester, follows), lessThan(_top(tester, full)), reason: 'newest first');
      expect(find.descendant(of: _row(full), matching: find.byIcon(AppIcons.backupFile)), findsOneWidget);
      expect(find.descendant(of: _row(follows), matching: find.byIcon(AppIcons.backupFollows)), findsOneWidget);
      expect(find.textContaining('仅关注列表'), findsOneWidget);
      final more = find.descendant(of: _row(full), matching: find.byIcon(AppIcons.moreVertical));
      expect(tester.getCenter(more).dx, greaterThan(tester.getCenter(find.text(full)).dx));

      Future<List<String>> menuRows() async {
        await tester.pumpAndSettle();
        final rows = [
          for (final key in ['backup-menu-restore-all', 'backup-menu-restore-follows', 'backup-menu-delete'])
            if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) key,
        ];
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        return rows;
      }

      await tester.tap(more);
      final all = ['backup-menu-restore-all', 'backup-menu-restore-follows', 'backup-menu-delete'];
      expect(await menuRows(), all);
      await tester.tap(find.text(full), buttons: kSecondaryButton);
      expect(await menuRows(), all, reason: 'right click = ⋮');
      await tester.longPress(find.text(full));
      expect(await menuRows(), all, reason: 'long press = ⋮');
      await tester.tap(find.descendant(of: _row(follows), matching: find.byIcon(AppIcons.moreVertical)));
      expect(await menuRows(), ['backup-menu-restore-follows', 'backup-menu-delete'], reason: 'follows only');

      // The menu: icons, the red delete after a line.
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('恢复全部设置'), findsOneWidget);
      expect(find.text('仅恢复关注列表'), findsOneWidget);
      expect(find.byType(PopupMenuDivider), findsOneWidget);
      final error = Theme.of(tester.element(find.text('删除'))).colorScheme.error;
      expect(tester.widget<Text>(find.text('删除')).style?.color, error);
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('确定要删除备份文件“$full”吗？'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('backup-delete-confirm')));
      await _settle(tester);
      expect(File(p(folder, full)).existsSync(), isFalse);
      expect(find.text(full), findsNothing);
      expect(find.text('目录中的备份 · 1'), findsOneWidget);
    });

    testWidgets('a folder that cannot be read says so and retries', (tester) async {
      await pump(tester);
      await tester.runAsync(() => Process.run('chmod', ['000', folder.path]));
      addTearDown(() => tester.runAsync(() => Process.run('chmod', ['755', folder.path])));
      await refresh(tester);
      expect(find.byKey(const ValueKey('backup-files-error')), findsOneWidget);
      expect(find.text('无法读取备份目录'), findsOneWidget);
      await tester.runAsync(() => Process.run('chmod', ['755', folder.path]));
      await tester.tap(find.byKey(const ValueKey('backup-files-retry')));
      await _settle(tester);
      expect(find.byKey(const ValueKey('backup-files-empty')), findsOneWidget);
    });

    testWidgets('a picked folder becomes the backup folder; "改回默认目录" goes back', (tester) async {
      late Directory other;
      final services = await pump(tester, pick: () => other.path);
      other = (await tester.runAsync(() => Directory.systemTemp.createTemp('backup_other')))!;
      addTearDown(() => tester.runAsync(() => other.delete(recursive: true)));
      await tester.tap(find.text('备份目录（默认）'));
      await _settle(tester);
      expect(services.store.settings.get(Settings.backupDirectory), other.path);
      expect(find.text('备份目录'), findsNWidgets(2), reason: 'the group and the row');
      expect(find.text(other.path), findsOneWidget);
      expect(find.descendant(of: _row('改回默认目录'), matching: find.byIcon(AppIcons.restoreDefault)), findsOneWidget);
      await tester.tap(find.text('改回默认目录'));
      await _settle(tester);
      expect(services.store.settings.get(Settings.backupDirectory), '');
      expect(find.text('备份目录（默认）'), findsOneWidget);
    });

    testWidgets('a file that is not a backup is refused before anything changes', (tester) async {
      final services = await pump(tester, pick: () => p(folder, 'notes.txt'));
      await tester.runAsync(() async {
        await services.store.follows.add(_room('1'));
        await File(p(folder, 'notes.txt')).writeAsString('["not", "a", "backup"]');
      });
      await tester.tap(find.text('恢复备份'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('backup-preview')), findsNothing);
      expect(_toasts, ['这不是纯粹直播的备份文件，或文件已损坏']);
      expect(await tester.runAsync(() => _followIds(services.store)), ['1']);
    });

    testWidgets('同步TV数据: phones open the scanner (3.x, Q2), computers ask for the address', (tester) async {
      FakeQrCamera.install();
      addTearDown(FakeQrCamera.uninstall);
      await pump(tester);
      await tester.tap(find.text('同步TV数据'));
      await _settle(tester);
      expect(find.byType(TvSyncScanPage), findsOneWidget);
      expect(find.text('扫描电视端显示的服务器二维码'), findsOneWidget);
      Navigator.of(tester.element(find.byType(TvSyncScanPage))).pop();
      await _settle(tester);

      FakeQrCamera.uninstall();
      await tester.tap(find.text('同步TV数据'));
      await _settle(tester);
      expect(find.byType(TvSyncScanPage), findsNothing);
      expect(find.text('输入电视端同步页显示的地址，发送关注、历史、屏蔽词和弹幕设置（不含账号）'), findsOneWidget);
      expect(find.byKey(const ValueKey('backup-tv-scan')), findsNothing, reason: 'no camera here');
      await tester.enterText(find.byKey(const ValueKey('backup-tv-address')), '192.168.1.100:88a');
      await tester.tap(find.byKey(const ValueKey('backup-tv-send')));
      await tester.pump();
      expect(find.text('设备地址无效'), findsOneWidget, reason: 'said under the field');
    });

    testWidgets('landscape phone: one centred column, a 48 bar', (tester) async {
      await pump(tester, size: const Size(852, 393));
      final row = tester.getRect(_row('WebDAV'));
      expect(row.width, lessThanOrEqualTo(720));
      expect((row.left - (852 - row.right)).abs(), lessThan(1));
      expect(tester.getSize(find.byType(AppBar)).height, 48);
    });

    testWidgets('wide: 720 wide and centred; computers open the backup folder', (tester) async {
      await pump(tester, size: const Size(1280, 1400), opensFolder: true);
      final row = tester.getRect(_row('WebDAV'));
      expect(row.width, 720);
      expect((row.left - (1280 - row.right)).abs(), lessThan(1));
      expect(find.descendant(of: _row('打开备份目录'), matching: find.byIcon(AppIcons.backupOpenFolder)), findsOneWidget);
      expect(_top(tester, '打开备份目录'), greaterThan(_top(tester, '备份目录（默认）')));
    });
  });

  group('TV sync scanner (U.11a c8)', () {
    Future<List<String>> pump(WidgetTester tester, Future<bool> Function(String origin) send) async {
      FakeQrCamera.install();
      addTearDown(FakeQrCamera.uninstall);
      tester.view
        ..physicalSize = const Size(393, 852)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final strings = (await tester.runAsync(loadStrings))!;
      final sent = <String>[];
      await tester.pumpWidget(
        LiveUiScope(
          config: LiveUiConfig(strings: strings.ui),
          child: MaterialApp(
            theme: const LiveTheme(primaryColor: Colors.blue).light,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TvSyncScanPage(
                          send: (origin) {
                            sent.add(origin);
                            return send(origin);
                          },
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return sent;
    }

    testWidgets('the bar: torch then camera switch; the hint and "手动输入地址" under the picture', (tester) async {
      await pump(tester, (_) async => true);
      expect(find.text('扫描二维码'), findsOneWidget);
      final torch = find.byKey(const ValueKey('qr-torch'));
      final flip = find.byKey(const ValueKey('qr-switch-camera'));
      expect(tester.getCenter(torch).dx, lessThan(tester.getCenter(flip).dx));
      expect(find.descendant(of: torch, matching: find.byIcon(AppIcons.torchOff)), findsOneWidget);
      await tester.tap(torch);
      await tester.pump();
      expect(find.descendant(of: torch, matching: find.byIcon(AppIcons.torchOn)), findsOneWidget);
      // The icons take the bar's colour (3.x drew grey and yellow, B8).
      final barColor = IconTheme.of(tester.element(find.byIcon(AppIcons.torchOn))).color;
      expect(tester.widget<Icon>(find.byIcon(AppIcons.torchOn)).color, isNull);
      expect(barColor, isNotNull);
      await tester.tap(flip);
      expect(FakeQrCamera.last!.switches, 1);
      expect(find.text('扫描电视端显示的服务器二维码'), findsOneWidget);
      expect(find.byKey(const ValueKey('qr-manual')), findsOneWidget);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('qr-manual'))).dy,
        greaterThan(tester.getTopLeft(find.text('扫描电视端显示的服务器二维码')).dy),
      );
    });

    testWidgets('scanned: sending to the TV, then done / scan again', (tester) async {
      final reply = Completer<bool>();
      final sent = await pump(tester, (_) => reply.future);
      final camera = FakeQrCamera.last!..read('192.168.1.100:8888');
      await tester.pump();
      expect(sent, ['http://192.168.1.100:8888']);
      expect(find.text('正在同步'), findsOneWidget);
      expect(find.text('正在发送到电视 192.168.1.100:8888'), findsOneWidget);
      expect(camera.disposed, isTrue, reason: 'the camera stops while sending');
      expect(find.byKey(const ValueKey('qr-torch')), findsNothing);
      reply.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('同步成功'), findsOneWidget);
      expect(find.text('关注、历史、屏蔽词和弹幕设置已发送到电视'), findsOneWidget);
      expect(find.byIcon(AppIcons.syncDone), findsOneWidget);
      expect(tester.getCenter(find.text('完成')).dx, lessThan(tester.getCenter(find.text('再扫一次')).dx));
      await tester.tap(find.text('再扫一次'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fake-camera')), findsOneWidget, reason: 'scanning again');
      FakeQrCamera.last!.read('192.168.1.100:8888');
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byType(TvSyncScanPage), findsNothing, reason: '"完成" goes back');
    });

    testWidgets('failed: the reason, "重试" sends again, "输入地址" types it', (tester) async {
      final sent = await pump(tester, (_) async => false);
      FakeQrCamera.last!.read('192.168.1.100:8888');
      await tester.pumpAndSettle();
      expect(find.text('同步失败'), findsOneWidget);
      expect(find.text('同步失败，请确认电视端已打开同步页并在同一局域网'), findsOneWidget);
      expect(find.byIcon(AppIcons.syncFailed), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(sent, ['http://192.168.1.100:8888', 'http://192.168.1.100:8888']);
      await tester.tap(find.text('输入地址'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('backup-tv-address')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('backup-tv-address')), '10.0.0.2:9000');
      await tester.tap(find.byKey(const ValueKey('backup-tv-send')));
      await tester.pumpAndSettle();
      expect(sent.last, 'http://10.0.0.2:9000');
    });

    testWidgets('the camera cannot start: say so, "重试" or "输入地址"', (tester) async {
      await pump(tester, (_) async => true);
      FakeQrCamera.last!.fail();
      await tester.pumpAndSettle();
      expect(find.text('相机当前不可用'), findsOneWidget);
      expect(find.text('请检查相机权限后重试，或者直接输入电视端同步页显示的地址。'), findsOneWidget);
      expect(find.byIcon(AppIcons.cameraUnavailable), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('输入地址'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('fake-camera')), findsOneWidget);
    });
  });
}

List<String> _toasts = [];

String p(Directory dir, String name) => '${dir.path}${Platform.pathSeparator}$name';

/// Lets the store and the file system (real async work) finish, then the
/// frames.
Future<void> _settle(WidgetTester tester) async {
  // A folder listing takes several hops between real I/O and the test's
  // fake clock, and a loading spinner never settles: pump in small steps.
  for (var i = 0; i < 16; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

double _top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text).first).dy;

/// The settings row titled [title].
Finder _row(String title) => find.ancestor(of: find.text(title), matching: find.byType(SettingsRow)).first;

/// Whether the row titled [title] is greyed out.
bool _greyed(WidgetTester tester, String title) => find
    .ancestor(of: find.text(title).first, matching: find.byWidgetPredicate((w) => w is Opacity && w.opacity < 1))
    .evaluate()
    .isNotEmpty;
