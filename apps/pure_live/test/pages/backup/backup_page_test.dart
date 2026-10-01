import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/pages/backup/backup_data.dart';
import 'package:pure_live/pages/backup/backup_files.dart';
import 'package:pure_live/pages/backup/backup_page.dart';
import 'package:pure_live/pages/backup/tv_sync.dart';
import 'package:pure_live/pages/search/search_history.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

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

    Future<AppServices> pump(WidgetTester tester, {String? Function()? pick}) async {
      tester.view
        ..physicalSize = const Size(500, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = (await tester.runAsync(testServices))!;
      addTearDown(() => tester.runAsync(services.close));
      folder = (await tester.runAsync(() => Directory.systemTemp.createTemp('backup_page')))!;
      addTearDown(() => tester.runAsync(() => folder.delete(recursive: true)));
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
            backupDefaultFolderProvider.overrideWithValue(() async => folder),
            backupPickerProvider.overrideWithValue((_, {required initial, required pickFile}) async => pick?.call()),
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
    });

    testWidgets('restores a 3.x file from the folder after showing what changes', (tester) async {
      final services = await pump(tester);
      await tester.runAsync(() async {
        await services.store.follows.add(_room('1'));
        await File(p(folder, 'purelive_2026-09-01T10_00_00.txt'))
            .writeAsString(jsonEncode(_legacyBackup([_room('2'), _room('3')])));
      });
      // The list picks the new file up on refresh.
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await _settle(tester);
      await tester.tap(find.text('purelive_2026-09-01T10_00_00.txt'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('backup-preview')), findsOneWidget);
      expect(find.text('3.x 备份（版本 3）'), findsOneWidget);
      expect(find.text('关注的直播间：1 → 2（新增 2，移除 1）'), findsOneWidget);
      expect(find.textContaining('文件中没有、保持不变'), findsOneWidget);

      // Cancelling changes nothing.
      await tester.tap(find.text('取消'));
      await _settle(tester);
      expect(await tester.runAsync(() => _followIds(services.store)), ['1']);

      await tester.tap(find.text('purelive_2026-09-01T10_00_00.txt'));
      await _settle(tester);
      await tester.tap(find.byKey(const ValueKey('backup-restore-confirm')));
      await _settle(tester);
      expect(await tester.runAsync(() => _followIds(services.store)), ['2', '3']);
      expect(_toasts, ['恢复备份成功']);
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
