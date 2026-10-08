// J06.2: the 3.x import's report reaches the app log and the exported log.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/app_log.dart';
import 'package:pure_live/app/bootstrap.dart';
import 'package:pure_live/app/iptv_library.dart';
import 'package:pure_live/app/startup.dart';

import 'support.dart';

void main() {
  late Directory temp;
  late LiveStore store;
  late AppLog log;
  setUp(() async {
    temp = Directory.systemTemp.createTempSync('pure_live_legacy_report');
    store = await LiveStore.memory(cipher: FakeCipher());
    log = AppLog(now: () => DateTime(2026, 10, 8, 9, 30));
  });
  tearDown(() async {
    await store.close();
    temp.deleteSync(recursive: true);
  });

  /// Runs the start-up's import over [files] with [import] in place of the
  /// box reader (live_store's tests read real 3.x boxes).
  Future<void> run(
    List<String> files,
    Future<LegacyImportReport> Function(LiveStore store, List<String> files) import,
  ) => importLegacyData(
    store,
    StoreIptvLibrary(store),
    hiveFiles: () async => files,
    playlistDirectory: Directory('${temp.path}/playlists'),
    importHive: import,
    appLog: log,
    now: () => DateTime.utc(2026, 10, 8, 1, 30),
  );

  test('a run that read 3.x data writes its report, a warning when a sign-in was left behind', () async {
    await run(['/data/app_settings.hive'], (store, files) async {
      await store.follows.replaceAll([LiveRoom(platform: 'bilibili', roomId: '1', nick: 'A')]);
      return LegacyImportReport()
        ..importedSources = 1
        ..follows = 1
        ..history = 2
        ..skipped.add('currentWebDavConfig')
        ..skippedSecrets.add(SecretRefs.cookie('bilibili'));
    });
    final entries = [
      for (final entry in log.entries)
        if (entry.tag == legacyLogTag) entry,
    ];
    expect(entries, hasLength(1));
    expect(entries.single.level, LogLevel.warning);
    expect(
      entries.single.message,
      '3.x import: sources 1, before 0, failed 0, follows 1, history 2, '
      'unreadable 1 (currentWebDavConfig), sign-ins not stored 1 (cookie/bilibili)',
    );
    expect(await store.meta.get(LegacyReloginNotice.key), '1');

    final summary = jsonDecode((await store.meta.get(legacyLastImportKey))!) as Map<String, Object?>;
    expect(summary['time'], '2026-10-08T01:30:00.000Z');
    expect(summary['settings'], {
      'sources': 1,
      'before': 0,
      'failed': 0,
      'follows': 1,
      'history': 2,
      'unreadable': 1,
      'signInsNotStored': 1,
    });
    expect(summary.containsKey('iptv'), isFalse);

    // Every later export starts with it.
    log
      ..header = (() async => legacyImportHeader(await store.meta.get(legacyLastImportKey)))
      ..info('t', 'later');
    final exported = (await log.export(temp)).readAsLinesSync();
    final stamp = DateTime.utc(2026, 10, 8, 1, 30).toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ');
    expect(
      exported.first,
      '3.x import ($stamp): sources 1, follows 1, history 2, unreadable 1, sign-ins not stored 1, failed 0',
    );
    expect(exported.last, endsWith('[INFO] t: later'));
  });

  test('a clean run is an info entry; an ordinary start writes nothing', () async {
    await run(['/data/app_settings.hive'], (store, files) async => LegacyImportReport()..importedSources = 1);
    expect([for (final entry in log.entries) (entry.tag, entry.level)], [(legacyLogTag, LogLevel.info)]);

    final before = await store.meta.get(legacyLastImportKey);
    await run(['/data/app_settings.hive'], (store, files) async => LegacyImportReport()..alreadyImported = 1);
    expect(log.entries, hasLength(1));
    expect(await store.meta.get(legacyLastImportKey), before);

    // The real reader without 3.x files: nothing either.
    await run(const [], LegacyMigration.importHiveFiles);
    expect(log.entries, hasLength(1));
  });

  test('a failed import is a warning, and the stand-in names are still cleared once', () async {
    await store.follows.replaceAll([LiveRoom(platform: 'jdlive', roomId: '5', nick: 'JD Live')]);
    await run(['/data/app_settings.hive'], (store, files) async => throw const FileSystemException('locked'));
    expect([for (final entry in log.entries) entry.level], [LogLevel.warning, LogLevel.info]);
    expect(log.entries.first.message, startsWith('3.x import failed'));
    expect(log.entries.last.message, contains('cleared from 1 rooms'));
    expect((await store.follows.all()).single.nick, '');
    expect(await store.meta.get(legacyLastImportKey), isNull);

    await run(const [], LegacyMigration.importHiveFiles);
    expect(log.entries, hasLength(2));
  });

  test('without a summary the export has no header line', () async {
    log
      ..header = (() async => legacyImportHeader(null))
      ..info('t', 'only');
    expect((await log.export(temp)).readAsLinesSync(), hasLength(1));
    expect(legacyImportHeader('not json'), isNull);
  });
}
