import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:pure_live/core/common/http_client.dart' as network;
import 'package:pure_live/core/iptv/services/iptv_sync_engine.dart';

import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pure_live/common/services/settings/iptv_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/core/iptv/local/database.dart';
import 'package:pure_live/core/iptv/services/iptv_import_manager.dart';
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
  late Directory cache;
  late AppDatabase db;
  late IptvImportManager manager;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('iptv-replacement-');
    cache = await Directory('${directory.path}/cache').create();
    db = _Database(NativeDatabase(File('${directory.path}/test.sqlite')));
    Get.testMode = true;
    Get.put(DbService()..db = db);
    Get.put<SettingsService>(_Settings());
    manager = IptvImportManager(cacheDirectory: () async => cache);
  });
  tearDown(() async {
    Get.reset();
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<File> input(String content, [String ext = 'm3u']) =>
      File('${directory.path}/input.$ext').writeAsString(content);
  Future<bool> import(File file, {bool hot = false, String name = 'Fixture'}) =>
      manager.importIptvFile(file: file, providerName: name, isHot: hot, forceUpdate: true, showTips: false);
  Future<void> reopen() async {
    await db.close();
    Get.delete<DbService>(force: true);
    db = _Database(NativeDatabase(File('${directory.path}/test.sqlite')));
    Get.put(DbService()..db = db);
  }

  Future<String> snapshot() async => jsonEncode({
    'providers': (await db.getAllProviders()).map((e) => e.toJson()).toList(),
    'channels': (await db.select(db.channels).get()).map((e) => e.toJson()).toList(),
    'mappings': (await db.getAllMappings()).map((e) => e.toJson()).toList(),
    'favorites': (await db.select(db.favoriteListChannels).get()).map((e) => e.toJson()).toList(),
  });
  Future<void> failWrites() => db.customStatement(
    "CREATE TRIGGER fail_channel BEFORE INSERT ON channels WHEN NEW.name = 'FAIL' BEGIN SELECT RAISE(ABORT, 'playlist fixture failure'); END",
  );
  for (final brokenTail in [
    '#EXTINF:-1,Missing URL\n',
    '#EXTINF:-1 tvg-name="Unclosed,Lost\nhttps://fixture/lost\n',
    '#EXTINF:-1,Lost\nnot-a-url\n',
  ]) {
    test('M3U partial parse failure preserves saved database and cache: $brokenTail', () async {
      expect(await import(await input(_m3u())), isTrue);
      final before = await snapshot();
      final savedFile = File((await db.getAllProviders()).single.url!);
      final oldBytes = await savedFile.readAsBytes();
      expect(await import(await input(_m3u(url: 'https://fixture/new') + brokenTail)), isFalse);
      await reopen();
      expect(await snapshot(), before);
      expect(await savedFile.readAsBytes(), oldBytes);
      expect(await cache.list().length, 1);
    });
  }
  test('unique URL fallback never crosses conflicting TVG identities', () async {
    expect(await import(await input('#EXTM3U\n#EXTINF:-1 tvg-id="old",Old\nhttps://fixture/live\n')), isTrue);
    final old = (await db.select(db.channels).get()).single;
    expect(await import(await input('#EXTM3U\n#EXTINF:-1 tvg-id="new",New\nhttps://fixture/live\n')), isTrue);
    final updated = (await db.select(db.channels).get()).single;
    expect(updated.id, isNot(old.id));
    expect(updated.tvgId, 'new');
  });
  test('shared stream URL never guesses IDs for multiple renamed channels', () async {
    expect(
      await import(
        await input('#EXTM3U\n#EXTINF:-1,Old A\nhttps://fixture/live\n#EXTINF:-1,Old B\nhttps://fixture/live\n'),
      ),
      isTrue,
    );
    final before = await snapshot();
    final old = File((await db.getAllProviders()).single.url!);
    final bytes = await old.readAsBytes();
    expect(
      await import(
        await input('#EXTM3U\n#EXTINF:-1,New A\nhttps://fixture/live\n#EXTINF:-1,New B\nhttps://fixture/live\n'),
      ),
      isFalse,
    );
    await reopen();
    expect(await snapshot(), before);
    expect(await old.readAsBytes(), bytes);
  });

  test('M3U parser upgrade preserves legacy truncated names by unique stream identity', () async {
    expect(await import(await input('#EXTM3U\n#EXTINF:-1,World\nhttps://fixture/live\n')), isTrue);
    final old = (await db.select(db.channels).get()).single;
    await (db.update(db.channels)..where((t) => t.id.equals(old.id))).write(
      const ChannelsCompanion(favorite: drift.Value(true), hidden: drift.Value(true)),
    );
    expect(await import(await input('#EXTM3U\n#EXTINF:-1 tvg-id="news",News, World\nhttps://fixture/live\n')), isTrue);
    await reopen();
    final updated = (await db.select(db.channels).get()).single;
    expect(updated.id, old.id);
    expect(updated.name, 'News, World');
    expect(updated.tvgId, 'news');
    expect(updated.favorite, isTrue);
    expect(updated.hidden, isTrue);
  });

  test('M3U final metadata and comma display name reach the database intact', () async {
    expect(await import(await input('#EXTM3U\n#EXTINF:-1 tvg-id="news",News, World\nhttps://fixture/live\n')), isTrue);
    await reopen();
    final channel = (await db.select(db.channels).get()).single;
    expect(channel.tvgId, 'news');
    expect(channel.name, 'News, World');
  });

  test('provider catch-up metadata persists and refreshes on the stable channel identity', () async {
    String feed(String days, String correction) =>
        '#EXTM3U catchup-correction="$correction"\n'
        '#EXTINF:-1 tvg-id="news" catchup="append" '
        'catchup-source="&start={utc}&duration={duration}" catchup-days="$days",News\n'
        'https://fixture/live\n';

    expect(await import(await input(feed('3.5', '-2.5'))), isTrue);
    final first = (await db.select(db.channels).get()).single;
    expect(first.catchupMode, 'append');
    expect(first.catchupSource, '&start={utc}&duration={duration}');
    expect(first.catchupDays, 3.5);
    expect(first.catchupCorrectionHours, -2.5);

    expect(await import(await input(feed('7', '1.25'))), isTrue);
    await reopen();
    final refreshed = (await db.select(db.channels).get()).single;
    expect(refreshed.id, first.id);
    expect(refreshed.catchupMode, 'append');
    expect(refreshed.catchupSource, '&start={utc}&duration={duration}');
    expect(refreshed.catchupDays, 7);
    expect(refreshed.catchupCorrectionHours, 1.25);
  });

  test('forced same-name refresh updates one provider instead of creating a duplicate', () async {
    expect(await import(await input(_m3u())), isTrue);
    final old = (await db.getAllProviders()).single;
    expect(await import(await input(_m3u(url: 'https://fixture/new.m3u8'))), isTrue);
    await reopen();
    expect(await db.getAllProviders(), hasLength(1));
    expect((await db.getAllProviders()).single.id, old.id);
  });
  test('replacement retains provider settings and channel favorites with stable identities', () async {
    expect(await import(await input(_m3u()), hot: true), isTrue);
    final provider = (await db.getAllProviders()).single;
    final channel = (await db.select(db.channels).get()).single;
    await (db.update(db.providers)..where((t) => t.id.equals(provider.id))).write(
      ProvidersCompanion(
        enabled: const drift.Value(false),
        sortOrder: const drift.Value(7),
        createdAt: drift.Value(DateTime.utc(2020)),
      ),
    );
    await (db.update(db.channels)..where((t) => t.id.equals(channel.id))).write(
      const ChannelsCompanion(favorite: drift.Value(true), hidden: drift.Value(true), sortOrder: drift.Value(8)),
    );
    expect(await import(await input(_m3u(url: 'https://fixture/new.m3u8')), hot: true), isTrue);
    await reopen();
    final updated = (await db.getAllProviders()).single;
    expect(updated.enabled, isFalse);
    expect(updated.sortOrder, 7);
    expect(updated.createdAt.toUtc(), DateTime.utc(2020));
    final current = (await db.select(db.channels).get()).single;
    expect(current.id, channel.id);
    expect(current.favorite, isTrue);
    expect(current.hidden, isTrue);
    expect(current.sortOrder, 8);
    expect(current.streamUrl, 'https://fixture/new.m3u8');
  });
  test('failed refresh preserves old database and saved local playlist bytes', () async {
    expect(await import(await input(_m3u()), hot: true), isTrue);
    final old = await snapshot();
    final local = File((await db.getAllProviders()).single.url!);
    final bytes = await local.readAsBytes();
    await failWrites();
    expect(
      await import(await input('${_m3u()}#EXTINF:-1 tvg-id="bad",FAIL\nhttps://fixture/bad\n'), hot: true),
      isFalse,
    );
    await reopen();
    expect(await snapshot(), old);
    expect(await local.readAsBytes(), bytes);
  });
  test('failed refresh never overwrites the previous saved playlist file', () async {
    expect(await import(await input(_m3u()), hot: true), isTrue);
    final local = File((await db.getAllProviders()).single.url!);
    final bytes = await local.readAsBytes();
    await failWrites();
    expect(await import(await input(_m3u(name: 'FAIL')), hot: true), isFalse);
    expect(await local.readAsBytes(), bytes);
  });
  test('a failed new import leaves neither partial database rows nor owned files', () async {
    await db.getAllProviders();
    await failWrites();
    final old = await snapshot();
    expect(await import(await input(_m3u(name: 'FAIL'))), isFalse);
    await reopen();
    expect(await snapshot(), old);
    expect(await cache.list().toList(), isEmpty);
  });
  test('different streams sharing a TVG ID survive as separate channels', () async {
    final content = '${_m3u()}#EXTINF:-1 tvg-id="news" group-title="News",News\nhttps://fixture/backup.m3u8\n';
    expect(await import(await input(content)), isTrue);
    expect(await db.select(db.channels).get(), hasLength(2));
  });
  test('TXT channel identity survives a URL refresh', () async {
    expect(await import(await input('News,https://fixture/old\n', 'txt'), hot: true), isTrue);
    final old = (await db.select(db.channels).get()).single;
    await db.toggleFavorite(old.id);
    expect(await import(await input('News,https://fixture/new\n', 'txt'), hot: true), isTrue);
    final current = (await db.select(db.channels).get()).single;
    expect(current.id, old.id);
    expect(current.favorite, isTrue);
  });
  test('parsed channel number and stream type are persisted', () async {
    expect(
      await import(
        await input(
          '#EXTM3U\n#EXTINF:-1 tvg-id="movie" tvg-chno="42" group-title="movie",Movie\nhttps://fixture/movie/42\n',
        ),
        hot: true,
      ),
      isTrue,
    );
    final channel = (await db.select(db.channels).get()).single;
    expect(channel.channelNumber, 42);
    expect(channel.streamType, 'vod');
  });
  test('successful local replacement retires only its previous owned file', () async {
    final original = await input(_m3u());
    expect(await import(original), isTrue);
    final old = File((await db.getAllProviders()).single.url!);
    final unrelated = await File('${cache.path}/keep.m3u').writeAsString('user file');
    expect(await import(await input(_m3u(url: 'https://fixture/new'))), isTrue);
    final current = File((await db.getAllProviders()).single.url!);
    expect(current.path, isNot(old.path));
    expect(await old.exists(), isFalse);
    expect(await original.exists(), isTrue);
    expect(await unrelated.readAsString(), 'user file');
    expect(await current.readAsString(), _m3u(url: 'https://fixture/new'));
  });
  test('same-file local sync reads the active snapshot without deleting its input first', () async {
    expect(await import(await input(_m3u())), isTrue);
    final provider = (await db.getAllProviders()).single;
    final oldChannel = (await db.select(db.channels).get()).single;
    final engine = IptvSyncEngine(importManager: manager, temporaryDirectory: () async => directory);
    expect(await engine.syncPlaylist(provider), isTrue);
    expect((await db.getAllProviders()).single.id, provider.id);
    expect((await db.select(db.channels).get()).single, oldChannel);
    expect(await File((await db.getAllProviders()).single.url!).exists(), isTrue);
  });
  test('replacement never deletes an external source file referenced by a legacy provider', () async {
    expect(await import(await input(_m3u())), isTrue);
    final external = await File('${directory.path}/external.m3u').writeAsString('external data');
    final provider = (await db.getAllProviders()).single;
    await (db.update(
      db.providers,
    )..where((t) => t.id.equals(provider.id))).write(ProvidersCompanion(url: drift.Value(external.path)));
    expect(await import(await input(_m3u(url: 'https://fixture/new'))), isTrue);
    expect(await external.readAsString(), 'external data');
  });
  test('reordered same-TVG streams keep their own IDs and favorites', () async {
    final a = '#EXTINF:-1 tvg-id="news" group-title="News",News\nhttps://fixture/a\n';
    final b = '#EXTINF:-1 tvg-id="news" group-title="News",News\nhttps://fixture/b\n';
    expect(await import(await input('#EXTM3U\n$a$b')), isTrue);
    final before = {for (final c in await db.select(db.channels).get()) c.streamUrl: c.id};
    await db.toggleFavorite(before['https://fixture/a']!);
    expect(await import(await input('#EXTM3U\n$b$a')), isTrue);
    final current = await db.select(db.channels).get();
    expect({for (final c in current) c.streamUrl: c.id}, before);
    expect(current.singleWhere((c) => c.favorite).streamUrl, 'https://fixture/a');
  });
  test('ambiguous multi-line identity rotation preserves the previous complete snapshot', () async {
    String feed(String suffix) =>
        '#EXTM3U\n#EXTINF:-1 tvg-id="news" group-title="News",News\nhttps://fixture/a$suffix\n#EXTINF:-1 tvg-id="news" group-title="News",News\nhttps://fixture/b$suffix\n';
    expect(await import(await input(feed(''))), isTrue);
    final before = await snapshot();
    final files = await cache.list().toList();
    expect(await import(await input(feed('?new'))), isFalse);
    expect(await snapshot(), before);
    expect((await cache.list().toList()).map((e) => e.path), files.map((e) => e.path));
  });
  test('identical duplicate entries coalesce without suppressing distinct stream variants', () async {
    final entry = '#EXTINF:-1 tvg-id="news" group-title="News",News\nhttps://fixture/a\n';
    expect(await import(await input('#EXTM3U\n$entry$entry')), isTrue);
    expect(await db.select(db.channels).get(), hasLength(1));
  });
  test('disabled channel auto-update preserves all channel fields', () async {
    expect(await import(await input(_m3u())), isTrue);
    await db
        .update(db.channels)
        .write(const ChannelsCompanion(isAutoUpdate: drift.Value(false), favorite: drift.Value(true)));
    final old = (await db.select(db.channels).get()).single;
    expect(await import(await input(_m3u(url: 'https://fixture/new'))), isTrue);
    expect((await db.select(db.channels).get()).single, old);
  });
  test('favorite list membership and locked EPG mapping remain linked after refresh', () async {
    expect(await import(await input(_m3u())), isTrue);
    final provider = (await db.getAllProviders()).single;
    final channel = (await db.select(db.channels).get()).single;
    await db.into(db.favoriteLists).insert(FavoriteListsCompanion.insert(id: 'list', name: 'Favorites'));
    await db.addChannelToList('list', channel.id);
    await db.upsertEpgSource(EpgSourcesCompanion.insert(id: 'epg', name: 'EPG', url: 'https://fixture/epg'));
    await db.upsertMapping(
      EpgMappingsCompanion.insert(
        channelId: channel.id,
        providerId: provider.id,
        epgChannelId: 'manual',
        epgSourceId: 'epg',
        locked: const drift.Value(true),
        source: const drift.Value('manual'),
      ),
    );
    final mapping = (await db.getAllMappings()).single;
    final favorite = (await db.select(db.favoriteListChannels).get()).single;
    expect(await import(await input(_m3u(url: 'https://fixture/new'))), isTrue);
    await reopen();
    expect((await db.getAllMappings()).single, mapping);
    expect((await db.select(db.favoriteListChannels).get()).single, favorite);
    expect((await db.getChannelById(channel.id))!.streamUrl, 'https://fixture/new');
  });
  test('mapping write failure rolls back provider, channels, references and staged file', () async {
    expect(await import(await input(_m3u())), isTrue);
    await db.upsertEpgSource(EpgSourcesCompanion.insert(id: 'epg', name: 'EPG', url: 'https://fixture/epg'));
    await db.upsertEpgChannels([
      EpgChannelsCompanion.insert(id: 'epg-news', sourceId: 'epg', channelId: 'news', displayName: 'News'),
    ]);
    SettingsService.to.iptv.selectedSourceId.value = 'epg';
    final before = await snapshot();
    final files = (await cache.list().toList()).map((e) => e.path).toList();
    await db.customStatement(
      "CREATE TRIGGER fail_mapping BEFORE INSERT ON epg_mappings BEGIN SELECT RAISE(ABORT, 'mapping failure'); END",
    );
    expect(await import(await input(_m3u(url: 'https://fixture/new'))), isFalse);
    await reopen();
    expect(await snapshot(), before);
    expect((await cache.list().toList()).map((e) => e.path), files);
  });
  test('concurrent same-name imports settle as one consistent provider', () async {
    final a = await File('${directory.path}/a.m3u').writeAsString(_m3u(url: 'https://fixture/a'));
    final b = await File('${directory.path}/b.m3u').writeAsString(_m3u(url: 'https://fixture/b'));
    expect(await Future.wait([import(a), import(b)]), [true, true]);
    await reopen();
    final provider = (await db.getAllProviders()).single;
    final channel = (await db.select(db.channels).get()).single;
    expect(await File(provider.url!).readAsString(), _m3u(url: channel.streamUrl));
    expect(await cache.list().toList(), hasLength(1));
  });
  test('an obsolete explicit provider snapshot does not overwrite a newer edit', () async {
    expect(await import(await input(_m3u())), isTrue);
    final old = (await db.getAllProviders()).single;
    await db.update(db.providers).write(const ProvidersCompanion(name: drift.Value('Renamed')));
    final before = await snapshot();
    expect(
      await manager.importIptvFile(
        file: await input(_m3u(url: 'https://fixture/new')),
        providerName: old.name,
        expectedProvider: old,
        forceUpdate: true,
        showTips: false,
      ),
      isFalse,
    );
    expect(await snapshot(), before);
  });
  test('unrelated same-name legacy providers are never deleted by forced import', () async {
    for (final id in ['one', 'two']) {
      await db.upsertProvider(
        ProvidersCompanion.insert(id: id, name: 'Fixture', type: 'm3u', url: drift.Value('https://fixture/$id')),
      );
    }
    final before = await snapshot();
    expect(await import(await input(_m3u())), isFalse);
    expect(await snapshot(), before);
  });
  test('web text retains a durable source after its temporary input is removed', () async {
    expect(await manager.importFromWebString(_m3u(), 'Fixture.m3u', forceUpdate: true, showTips: false), isTrue);
    final provider = (await db.getAllProviders()).single;
    expect(await File(provider.url!).readAsString(), _m3u());
    expect(await cache.list().toList(), hasLength(1));
  });

  for (final scenario in ['success', 'invalid', 'sql failure', 'http failure', 'edited while downloading']) {
    test('real HTTP synchronization $scenario preserves identity and cleans its own temporary files', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final url = 'http://127.0.0.1:${server.port}/playlist.m3u?token=fixture';
      final first = await input(_m3u());
      expect(
        await manager.importIptvFile(
          file: first,
          providerName: 'Fixture',
          url: url,
          forceUpdate: true,
          showTips: false,
        ),
        isTrue,
      );
      final provider = (await db.getAllProviders()).single;
      final channel = (await db.select(db.channels).get()).single;
      await db.toggleFavorite(channel.id);
      if (scenario == 'sql failure') await failWrites();
      var before = await snapshot();
      var requests = 0;
      final subscription = server.listen((request) async {
        requests++;
        if (scenario == 'edited while downloading') {
          await db.update(db.providers).write(const ProvidersCompanion(enabled: drift.Value(false)));
          before = await snapshot();
        }
        request.response.statusCode = scenario == 'http failure' ? 500 : 200;
        request.response.headers.contentType = ContentType.text;
        request.response.write(
          scenario == 'invalid'
              ? '#EXTM3U\nnot-a-channel'
              : _m3u(name: scenario == 'sql failure' ? 'FAIL' : 'News', url: 'https://fixture/new'),
        );
        await request.response.close();
      });
      final dio = Dio()
        ..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => _RealHttpOverrides().createHttpClient(null));
      final oldDio = network.HttpClient.instance.dio;
      network.HttpClient.instance.dio = dio;
      final temp = await Directory('${directory.path}/sync').create();
      try {
        final engine = IptvSyncEngine(importManager: manager, temporaryDirectory: () async => temp);
        expect(await engine.syncPlaylist(provider), scenario == 'success');
        expect(requests, 1);
        await reopen();
        if (scenario == 'success') {
          expect((await db.getAllProviders()).single.id, provider.id);
          final result = (await db.select(db.channels).get()).single;
          expect(result.id, channel.id);
          expect(result.favorite, isTrue);
          expect(result.streamUrl, 'https://fixture/new');
        } else {
          expect(await snapshot(), before);
        }
        expect(await temp.list().toList(), isEmpty);
        expect(await cache.list().toList(), isEmpty);
      } finally {
        network.HttpClient.instance.dio = oldDio;
        dio.close(force: true);
        await subscription.cancel();
        await server.close(force: true);
      }
    });
  }
  for (final status in [200, 404, 500]) {
    test('network TXT import with signed URL HTTP $status cleans all download files', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        request.response.statusCode = status;
        request.response.write('News,https://fixture/live\n');
        await request.response.close();
      });
      final dio = Dio()
        ..httpClientAdapter = IOHttpClientAdapter(createHttpClient: () => _RealHttpOverrides().createHttpClient(null));
      final oldDio = network.HttpClient.instance.dio;
      network.HttpClient.instance.dio = dio;
      try {
        expect(
          await manager.importFromNetworkUrl(
            'http://127.0.0.1:${server.port}/playlist.txt?token=fixture',
            'Fixture.txt',
            forceUpdate: true,
            showTips: false,
          ),
          status == 200,
        );
        expect(await cache.list().toList(), isEmpty);
        expect(await db.getAllProviders(), hasLength(status == 200 ? 1 : 0));
      } finally {
        network.HttpClient.instance.dio = oldDio;
        dio.close(force: true);
        await subscription.cancel();
        await server.close(force: true);
      }
    });
  }
  test('foreign-key enabled replacement removes obsolete memberships without damaging retained channels', () async {
    await db.customStatement('PRAGMA foreign_keys = ON');
    expect(await import(await input(_m3u())), isTrue);
    final provider = (await db.getAllProviders()).single;
    final old = (await db.select(db.channels).get()).single;
    await db.into(db.favoriteLists).insert(FavoriteListsCompanion.insert(id: 'list', name: 'Favorites'));
    await db.addChannelToList('list', old.id);
    final group = await db.into(db.failoverGroups).insert(FailoverGroupsCompanion.insert(name: 'Backup'));
    await db
        .into(db.failoverGroupChannels)
        .insert(FailoverGroupChannelsCompanion.insert(groupId: group, channelId: old.id));
    await db.upsertEpgSource(EpgSourcesCompanion.insert(id: 'epg', name: 'EPG', url: 'https://fixture/epg'));
    await db.upsertMapping(
      EpgMappingsCompanion.insert(
        channelId: old.id,
        providerId: provider.id,
        epgChannelId: 'old',
        epgSourceId: 'epg',
        locked: const drift.Value(true),
      ),
    );
    expect(
      await import(
        await input('#EXTM3U\n#EXTINF:-1 tvg-id="other" group-title="Other",Other\nhttps://fixture/other\n'),
      ),
      isTrue,
    );
    expect(await db.getChannelById(old.id), isNull);
    expect(await db.select(db.favoriteListChannels).get(), isEmpty);
    expect(await db.select(db.failoverGroupChannels).get(), isEmpty);
    expect(await db.getAllMappings(), isEmpty);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    expect((await db.getAllProviders()).single.id, provider.id);
  });
  test('source change rolls back the nested mapping savepoint but commits the valid playlist', () async {
    expect(await import(await input(_m3u())), isTrue);
    final provider = (await db.getAllProviders()).single;
    final channel = (await db.select(db.channels).get()).single;
    for (final id in ['A', 'B']) {
      await db.upsertEpgSource(EpgSourcesCompanion.insert(id: id, name: id, url: 'https://fixture/$id'));
    }
    await db.upsertEpgChannels([
      EpgChannelsCompanion.insert(id: 'epg-news', sourceId: 'A', channelId: 'news', displayName: 'News'),
    ]);
    await db.upsertMapping(
      EpgMappingsCompanion.insert(
        channelId: channel.id,
        providerId: provider.id,
        epgChannelId: 'old',
        epgSourceId: 'B',
      ),
    );
    final mapping = (await db.getAllMappings()).single;
    SettingsService.to.iptv.selectedSourceId.value = 'A';
    (db as _Database).afterMappings = () async {
      SettingsService.to.iptv.selectedSourceId.value = 'B';
    };
    expect(await import(await input(_m3u(url: 'https://fixture/new'))), isTrue);
    await reopen();
    expect((await db.getAllMappings()).single, mapping);
    expect((await db.getChannelById(channel.id))!.streamUrl, 'https://fixture/new');
    expect(await File((await db.getAllProviders()).single.url!).exists(), isTrue);
  });
  test('cache preparation failure leaves the previous complete database intact', () async {
    expect(await import(await input(_m3u())), isTrue);
    final before = await snapshot();
    final failing = IptvImportManager(cacheDirectory: () async => throw FileSystemException('fixture cache failure'));
    expect(
      await failing.importIptvFile(
        file: await input(_m3u(url: 'https://fixture/new')),
        providerName: 'Fixture',
        forceUpdate: true,
        showTips: false,
      ),
      isFalse,
    );
    expect(await snapshot(), before);
  });
  test('legacy mismatched ID prefix is retained by feed identity rather than hash recomputation', () async {
    await db.upsertProvider(ProvidersCompanion.insert(id: 'legacy-provider', name: 'Fixture', type: 'm3u'));
    await db.upsertChannels([
      ChannelsCompanion.insert(
        id: 'different-provider_123',
        providerId: 'legacy-provider',
        name: 'News',
        tvgId: const drift.Value('news'),
        streamUrl: 'https://fixture/old',
        favorite: const drift.Value(true),
      ),
    ]);
    expect(await import(await input(_m3u(url: 'https://fixture/new'))), isTrue);
    final channel = (await db.select(db.channels).get()).single;
    expect(channel.id, 'different-provider_123');
    expect(channel.favorite, isTrue);
    expect(channel.providerId, 'legacy-provider');
  });
  test('late failure in a thousand-channel replacement preserves every old channel and file', () async {
    String large(bool fail) {
      final content = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < 1001; i++) {
        content.write(
          '#EXTINF:-1 tvg-id="id-$i" group-title="All",${fail && i == 1000 ? 'FAIL' : 'Channel $i'}\nhttps://fixture/${fail ? 'new' : 'old'}/$i\n',
        );
      }
      return content.toString();
    }

    expect(await import(await input(large(false))), isTrue);
    expect(await db.select(db.channels).get(), hasLength(1001));
    final before = await snapshot();
    final saved = File((await db.getAllProviders()).single.url!);
    final bytes = await saved.readAsBytes();
    await failWrites();
    expect(await import(await input(large(true))), isFalse);
    await reopen();
    expect(await snapshot(), before);
    expect(await saved.readAsBytes(), bytes);
    expect(await cache.list().toList(), hasLength(1));
  });
  for (final language in ['zh', 'en']) {
    for (final action in ['back', 'cancel', 'confirm', 'write failure', 'edit while waiting']) {
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
          expect(await import(await input(_m3u()), name: sourceName), isTrue);
          if (action == 'write failure') await failWrites();
          before = await snapshot();
          file = await input(_m3u(name: action == 'write failure' ? 'FAIL' : 'News', url: 'https://fixture/new'));
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
            manager
                .importIptvFile(file: file, providerName: sourceName, showTips: false)
                .then((value) => outcome = value),
          );
          for (int i = 0; i < 100 && Get.isDialogOpen != true; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(outcome, isNull);
        if (action == 'edit while waiting') {
          await tester.runAsync(() async {
            await db.update(db.providers).write(const ProvidersCompanion(enabled: drift.Value(false)));
            before = await snapshot();
          });
        }
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
            expect((await db.select(db.channels).get()).single.streamUrl, 'https://fixture/new');
          }
        });
      });
    }
  }
  for (final representation in ['file URI', 'alternate separator']) {
    test('shared playlist cache survives another provider reference using $representation', () async {
      expect(await import(await input(_m3u())), isTrue);
      final old = File((await db.getAllProviders()).single.url!);
      final reference = representation == 'file URI' ? old.uri.toString() : old.path.replaceAll(r'\', '/');
      if (Platform.isWindows || representation == 'file URI') expect(reference, isNot(old.path));
      await db.upsertProvider(
        ProvidersCompanion.insert(id: 'other', name: 'Other', type: 'm3u', url: drift.Value(reference)),
      );
      expect(await import(await input(_m3u(url: 'https://fixture/new'))), isTrue);
      expect(await old.exists(), isTrue);
      final other = (await db.getProviderById('other'))!;
      final engine = IptvSyncEngine(importManager: manager, temporaryDirectory: () async => directory);
      expect(await engine.syncPlaylist(other), isTrue);
      expect(await old.exists(), isFalse);
      expect(await File((await db.getProviderById('other'))!.url!).exists(), isTrue);
    });
  }
}

String _m3u({String name = 'News', String url = 'https://fixture/old.m3u8'}) =>
    '#EXTM3U\n#EXTINF:-1 tvg-id="news" group-title="News",$name\n$url\n';

class _Settings extends SettingsService {
  @override
  final iptv = _IptvSettings();
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _IptvSettings implements IptvSettingsController {
  @override
  final selectedSourceId = ''.obs;
  @override
  final isAutoSyncEnabled = false.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RealHttpOverrides extends HttpOverrides {}

class _Translations extends AssetLoader {
  const _Translations(this.values);
  final Map<String, dynamic> values;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => values;
}

class _Database extends AppDatabase {
  _Database(super.executor) : super.forTesting();
  Future<void> Function()? afterMappings;
  @override
  Future<void> upsertMappings(List<EpgMappingsCompanion> entries) async {
    await super.upsertMappings(entries);
    await afterMappings?.call();
  }
}
