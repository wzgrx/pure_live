import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:pure_live/core/common/http_client.dart' as network;
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pure_live/core/iptv/services/epg_sync_engine.dart';
import 'package:pure_live/core/iptv/local/database.dart';
import 'package:pure_live/core/iptv/services/epg_import_manager.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/plugins/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> chinese;
  late Map<String, dynamic> english;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    chinese = jsonDecode(await File('assets/translations/zh.json').readAsString()) as Map<String, dynamic>;
    english = jsonDecode(await File('assets/translations/en.json').readAsString()) as Map<String, dynamic>;
  });
  late Directory directory;
  late File databaseFile;
  late AppDatabase db;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('purelive-epg-import-');
    databaseFile = File('${directory.path}/test.sqlite');
    db = AppDatabase.forTesting(NativeDatabase(databaseFile));
    Get.testMode = true;
    Get.put(DbService()..db = db);
  });
  tearDown(() async {
    Get.reset();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<File> input(String content, [String extension = 'xml']) async =>
      File('${directory.path}/input.$extension').writeAsString(content);

  Future<bool> import(File file) => EpgImportManager().importEpgFile(
    file: file,
    sourceName: 'Fixture',
    forceUpdate: true,
    showTips: false,
    url: 'https://example.test/feed.xml',
  );

  Future<void> seed(String id, String name) async {
    await db.upsertEpgSource(
      EpgSourcesCompanion.insert(
        id: id,
        name: name,
        url: 'https://example.test/old.xml',
        enabled: const drift.Value(false),
        isAutoUpdate: const drift.Value(false),
        refreshIntervalHours: const drift.Value(72),
        createdAt: drift.Value(DateTime.utc(2020)),
        lastRefresh: drift.Value(DateTime.utc(2030)),
      ),
    );
    await db.upsertEpgChannels([
      EpgChannelsCompanion.insert(id: '$id-old', sourceId: id, channelId: '$id-old', displayName: 'Old $id'),
    ]);
    await db.insertProgrammes([
      EpgProgrammesCompanion.insert(
        sourceId: id,
        epgChannelId: '$id-old',
        title: 'Old $id',
        start: DateTime.utc(2036),
        stop: DateTime.utc(2036, 1, 1, 1),
      ),
    ]);
  }

  Future<String> snapshot() async => jsonEncode({
    'sources': (await db.getAllEpgSources()).map((e) => e.toJson()).toList(),
    'channels': (await db.select(db.epgChannels).get()).map((e) => e.toJson()).toList(),
    'programmes': (await db.select(db.epgProgrammes).get()).map((e) => e.toJson()).toList(),
    'mappings': (await db.getAllMappings()).map((e) => e.toJson()).toList(),
  });

  Future<void> reopen() async {
    await db.close();
    Get.reset();
    db = AppDatabase.forTesting(NativeDatabase(databaseFile));
    Get.put(DbService()..db = db);
  }

  Future<void> failLateBatch() => db.customStatement('''
    CREATE TRIGGER fail_late_programme BEFORE INSERT ON epg_programmes
    WHEN NEW.title = 'FAIL' BEGIN SELECT RAISE(ABORT, 'fixture late batch failure'); END
  ''');

  test('real XML parser and SQLite persist every batch after reopen', () async {
    expect(await import(await input(_xml(count: 501))), isTrue);
    await reopen();
    expect(await db.getAllEpgSources(), hasLength(1));
    expect(await db.select(db.epgChannels).get(), hasLength(1));
    expect(await db.select(db.epgProgrammes).get(), hasLength(501));
  });

  for (final extension in ['xml', 'json', 'gz']) {
    test('UTF-8 $extension preserves channel and programme text', () async {
      final content = extension == 'json'
          ? jsonEncode({
              'channels': [
                {'id': 'new', 'displayName': '新闻 📺'},
              ],
              'programmes': [
                {
                  'channelId': 'new',
                  'title': '晚间新闻 é',
                  'start': '2036-01-01T00:00:00Z',
                  'stop': '2036-01-01T01:00:00Z',
                },
              ],
            })
          : _xml(channel: '新闻 📺', title: '晚间新闻 é');
      final file = extension == 'gz'
          ? await File('${directory.path}/input.gz').writeAsBytes(gzip.encode(utf8.encode(content)))
          : await input(content, extension);
      expect(await import(file), isTrue);
      expect((await db.select(db.epgChannels).get()).single.displayName, '新闻 📺');
      expect((await db.select(db.epgProgrammes).get()).single.title, '晚间新闻 é');
    });
  }

  test('malformed replacement keeps original durable snapshot', () async {
    await seed('existing', 'Fixture');
    final before = await snapshot();
    expect(await import(await input('<tv><broken>')), isFalse);
    await reopen();
    expect(await snapshot(), before);
  });

  test('successful replacement preserves user source settings and identity', () async {
    await seed('existing', 'Fixture');
    final old = (await db.getAllEpgSources()).single;
    expect(await import(await input(_xml())), isTrue);
    await reopen();
    final source = (await db.getAllEpgSources()).single;
    expect(source.id, old.id);
    expect(source.enabled, old.enabled);
    expect(source.isAutoUpdate, old.isAutoUpdate);
    expect(source.refreshIntervalHours, old.refreshIntervalHours);
    expect(source.createdAt, old.createdAt);
    expect(source.lastRefresh, isNot(old.lastRefresh));
    expect(source.url, 'https://example.test/feed.xml');
    expect((await db.select(db.epgProgrammes).get()).single.title, 'New');
    expect((await db.select(db.epgChannels).get()).single.displayName, 'New channel');
  });

  test('new import failing after 500 programmes leaves no partial source', () async {
    await db.getAllEpgSources();
    await failLateBatch();
    final before = await snapshot();
    expect(await import(await input(_xml(count: 501, failLast: true))), isFalse);
    await reopen();
    expect(await snapshot(), before);
  });

  test('replacement failure after first batch restores entire old source', () async {
    await seed('existing', 'Fixture');
    await seed('other', 'Other');
    await failLateBatch();
    final before = await snapshot();
    expect(await import(await input(_xml(count: 501, failLast: true))), isFalse);
    await reopen();
    expect(await snapshot(), before);
  });

  test('failed replacement also restores duplicate-name sources', () async {
    await seed('existing', 'Fixture');
    await seed('duplicate', ' fixture ');
    await failLateBatch();
    final before = await snapshot();
    expect(await import(await input(_xml(count: 501, failLast: true))), isFalse);
    await reopen();
    expect(await snapshot(), before);
  });
  test('source deletion failure rolls back duplicate cleanup', () async {
    await seed('existing', 'Fixture');
    await seed('duplicate', 'fixture');
    await db.customStatement(
      "CREATE TRIGGER fail_delete BEFORE DELETE ON epg_sources "
      "BEGIN SELECT RAISE(ABORT, 'fixture delete failure'); END",
    );
    final before = await snapshot();
    expect(await import(await input(_xml())), isFalse);
    await reopen();
    expect(await snapshot(), before);
  });

  test('channel write failure rolls back programme deletion and source metadata', () async {
    await seed('existing', 'Fixture');
    await db.customStatement(
      "CREATE TRIGGER fail_channel BEFORE INSERT ON epg_channels "
      "BEGIN SELECT RAISE(ABORT, 'fixture channel failure'); END",
    );
    final before = await snapshot();
    expect(await import(await input(_xml())), isFalse);
    await reopen();
    expect(await snapshot(), before);
  });

  test('successful duplicate replacement retains primary and unrelated source', () async {
    await seed('existing', 'Fixture');
    await seed('duplicate', ' fixture ');
    await seed('other', 'Other');
    final other = (await db.getAllEpgSources()).last;
    expect(await import(await input(_xml())), isTrue);
    await reopen();
    expect((await db.getAllEpgSources()).map((e) => e.id), ['existing', 'other']);
    expect((await db.getAllEpgSources()).last, other);
    expect((await db.select(db.epgProgrammes).get()).map((e) => e.title), containsAll(['Old other', 'New']));
  });

  test('invalid UTF-8 does not replace saved EPG', () async {
    await seed('existing', 'Fixture');
    final before = await snapshot();
    final file = await File('${directory.path}/invalid.xml').writeAsBytes([
      ...utf8.encode('<tv><channel id="bad"><display-name>'),
      0xff,
      ...utf8.encode('</display-name></channel></tv>'),
    ]);
    expect(await import(file), isFalse);
    expect(await snapshot(), before);
  });

  test('cache directory failure returns false without touching database', () async {
    await seed('existing', 'Fixture');
    final before = await snapshot();
    final manager = EpgImportManager(cacheDirectory: () async => throw FileSystemException('fixture directory'));
    expect(await manager.importFromNetworkUrl('http://127.0.0.1/feed.xml', 'Fixture', showTips: false), isFalse);
    expect(await snapshot(), before);
  });

  for (final format in ['xml', 'json', 'gz']) {
    for (final query in ['', '?key=fixture#fragment']) {
      test('real HTTP $format$query imports and removes temporary files', () async {
        final content = format == 'json'
            ? jsonEncode({
                'channels': [
                  {'id': 'new', 'displayName': '新闻 📺'},
                ],
                'programmes': [
                  {'channelId': 'new', 'title': 'New', 'start': '2036-01-01T00:00:00Z', 'stop': '2036-01-01T01:00:00Z'},
                ],
              })
            : _xml(channel: '新闻 📺');
        final bytes = format == 'gz' ? gzip.encode(utf8.encode(content)) : utf8.encode(content);
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final received = <Uri>[];
        final subscription = server.listen((request) async {
          received.add(request.uri);
          request.response.headers.contentType = ContentType.binary;
          request.response.add(bytes);
          await request.response.close();
        });
        final dio = Dio()
          ..httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () => _RealHttpOverrides().createHttpClient(null),
          );
        network.HttpClient.instance.dio = dio;
        try {
          final cache = await Directory('${directory.path}/cache').create();
          final manager = EpgImportManager(cacheDirectory: () async => cache);
          final url = 'http://127.0.0.1:${server.port}/feed.$format$query';
          expect(await manager.importFromNetworkUrl(url, 'Fixture', forceUpdate: true, showTips: false), isTrue);
          expect(received.single.path, '/feed.$format');
          expect(received.single.query, query.isEmpty ? '' : 'key=fixture');
          await reopen();
          expect((await db.getAllEpgSources()).single.url, url);
          expect((await db.select(db.epgChannels).get()).single.displayName, '新闻 📺');
          expect(await db.select(db.epgProgrammes).get(), hasLength(1));
          expect(await cache.list().toList(), isEmpty);
        } finally {
          dio.close(force: true);
          await subscription.cancel();
          await server.close(force: true);
        }
      });
    }
  }

  for (final status in [404, 500]) {
    test('HTTP $status keeps old data and leaves no partial download', () async {
      await seed('existing', 'Fixture');
      final before = await snapshot();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.statusCode = status;
        request.response.write('fixture error');
        await request.response.close();
      });
      final dio = Dio()
        ..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => _RealHttpOverrides().createHttpClient(null));
      network.HttpClient.instance.dio = dio;
      try {
        final cache = await Directory('${directory.path}/cache').create();
        final manager = EpgImportManager(cacheDirectory: () async => cache);
        expect(
          await manager.importFromNetworkUrl(
            'http://127.0.0.1:${server.port}/feed.xml',
            'Fixture',
            forceUpdate: true,
            showTips: false,
          ),
          isFalse,
        );
        expect(await snapshot(), before);
        expect(await cache.list().toList(), isEmpty);
      } finally {
        dio.close(force: true);
        await subscription.cancel();
        await server.close(force: true);
      }
    });
  }
  for (final format in ['xml', 'gz']) {
    test('declared Latin-1 $format remains supported', () async {
      final bytes = latin1.encode('<?xml version="1.0" encoding="ISO-8859-1"?>${_xml(channel: 'Café', title: 'été')}');
      final file = await File('${directory.path}/latin1.$format')
          .writeAsBytes(format == 'gz' ? gzip.encode(bytes) : bytes);
      expect(await import(file), isTrue);
      expect((await db.select(db.epgChannels).get()).single.displayName, 'Café');
      expect((await db.select(db.epgProgrammes).get()).single.title, 'été');
    });
  }

  for (final format in ['xml', 'json']) {
    test('UTF-8 BOM $format imports', () async {
      final content = format == 'xml'
          ? _xml()
          : jsonEncode({
              'channels': [
                {'id': 'new', 'displayName': 'New channel'},
              ],
            });
      final file = await File('${directory.path}/bom.$format')
          .writeAsBytes([0xef, 0xbb, 0xbf, ...utf8.encode(content)]);
      expect(await import(file), isTrue);
      expect((await db.select(db.epgChannels).get()).single.displayName, 'New channel');
    });
  }

  for (final status in [200, 404]) {
    test('sync engine real HTTP $status signed gzip uses transaction and cleans files', () async {
      await seed('existing', 'Fixture');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      int requests = 0;
      final subscription = server.listen((request) async {
        requests++;
        request.response.statusCode = status;
        request.response.add(gzip.encode(utf8.encode(_xml(channel: '新闻 📺'))));
        await request.response.close();
      });
      final dio = Dio()
        ..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => _RealHttpOverrides().createHttpClient(null));
      network.HttpClient.instance.dio = dio;
      final originalPaths = PathProviderPlatform.instance;
      final cache = await Directory('${directory.path}/sync').create();
      PathProviderPlatform.instance = _TemporaryPaths(cache.path);
      try {
        final url = 'http://127.0.0.1:${server.port}/feed.xml.gz?key=fixture';
        await (db.update(
          db.epgSources,
        )..where((t) => t.id.equals('existing'))).write(EpgSourcesCompanion(url: drift.Value(url)));
        final source = (await db.getAllEpgSources()).single;
        final before = await snapshot();
        expect(await EpgSyncEngine.instance.updateEpgCache(source, forceUpdate: true), status == 200);
        expect(requests, 1);
        await reopen();
        if (status == 200) {
          final updated = (await db.getAllEpgSources()).single;
          expect(updated.enabled, isFalse);
          expect(updated.isAutoUpdate, isFalse);
          expect(updated.refreshIntervalHours, 72);
          expect((await db.select(db.epgChannels).get()).single.displayName, '新闻 📺');
        } else {
          expect(await snapshot(), before);
        }
        expect(await cache.list().toList(), isEmpty);
      } finally {
        PathProviderPlatform.instance = originalPaths;
        dio.close(force: true);
        await subscription.cancel();
        await server.close(force: true);
      }
    });
  }

  test('failure during final pruning rolls back all prior batches', () async {
    await seed('existing', 'Fixture');
    await seed('other', 'Other');
    await (db.update(
      db.epgProgrammes,
    )..where((t) => t.sourceId.equals('other'))).write(EpgProgrammesCompanion(stop: drift.Value(DateTime.utc(2000))));
    await db.customStatement(
      "CREATE TRIGGER fail_prune BEFORE DELETE ON epg_programmes "
      "WHEN OLD.source_id = 'other' BEGIN SELECT RAISE(ABORT, 'fixture prune failure'); END",
    );
    final before = await snapshot();
    expect(await import(await input(_xml(count: 501))), isFalse);
    await reopen();
    expect(await snapshot(), before);
  });

  test('repeated successful replacement removes obsolete programme batches', () async {
    expect(await import(await input(_xml(count: 501))), isTrue);
    final id = (await db.getAllEpgSources()).single.id;
    expect(await import(await input(_xml(title: 'Replaced'))), isTrue);
    await reopen();
    expect((await db.getAllEpgSources()).single.id, id);
    expect((await db.select(db.epgProgrammes).get()).single.title, 'Replaced');
  });

  for (final language in ['zh', 'en']) {
    for (final action in ['back', 'cancel', 'confirm', 'write failure']) {
      testWidgets('replacement dialog $language $action completes import at large text', (tester) async {
        final strings = language == 'zh' ? chinese : english;
        final sourceName = 'Fixture ${List.filled(12, '节目单 Subscription').join(' ')}';
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late File file;
        late String before;
        await tester.runAsync(() async {
          await seed('existing', sourceName);
          if (action == 'write failure') await failLateBatch();
          before = await snapshot();
          file = await input(_xml(count: 501, failLast: action == 'write failure'));
        });
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        });
        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('zh'), Locale('en')],
            startLocale: Locale(language),
            saveLocale: false,
            path: 'assets/translations',
            assetLoader: _Translations(strings),
            child: Builder(
              builder: (context) => GetMaterialApp(
                locale: context.locale,
                localizationsDelegates: context.localizationDelegates,
                supportedLocales: context.supportedLocales,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
                  child: child!,
                ),
                home: const Scaffold(body: Text('Fixture page')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        bool? outcome;
        await tester.runAsync(() async {
          unawaited(
            EpgImportManager()
                .importEpgFile(file: file, sourceName: sourceName, showTips: false)
                .then((value) => outcome = value),
          );
          for (int i = 0; i < 100 && Get.isDialogOpen != true; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(outcome, isNull);
        if (action == 'back') {
          await tester.binding.handlePopRoute();
        } else {
          await tester.tap(
            find.widgetWithText(TextButton, strings[action == 'cancel' ? 'cancel' : 'confirm'] as String),
          );
        }
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          for (int i = 0; i < 200 && outcome == null; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(outcome, action == 'confirm');
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Fixture page'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          if (action != 'confirm') {
            expect(await snapshot(), before);
          } else {
            expect(await db.select(db.epgProgrammes).get(), hasLength(501));
          }
        });
      });
    }
  }
}

String _xml({int count = 1, String channel = 'New channel', String title = 'New', bool failLast = false}) =>
    '<tv><channel id="new"><display-name>$channel</display-name></channel>'
    '${List.generate(count, (i) => '<programme channel="new" start="20360101000000 +0000" stop="20360101010000 +0000">'
        '<title>${failLast && i == count - 1 ? 'FAIL' : title}</title></programme>').join()}'
    '</tv>';

class _RealHttpOverrides extends HttpOverrides {}

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}
