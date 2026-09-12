import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/iptv_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/iptv/local/database.dart';
import 'package:pure_live/core/iptv/local/epg_channel_identity.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/core/iptv/models/channel.dart' as model;
import 'package:pure_live/core/iptv/services/channel_detail_controller.dart';
import 'package:pure_live/core/iptv/services/epg_import_manager.dart';
import 'package:pure_live/core/iptv/services/iptv_import_manager.dart';
import 'package:pure_live/core/site/iptv/iptv_site.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/plugins/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory settingsDirectory;
  late Directory directory;
  late AppDatabase db;
  late _Settings settings;
  setUpAll(() async {
    settingsDirectory = await Directory.systemTemp.createTemp('epg-identity-settings-');
    Hive.init(settingsDirectory.path);
    await HivePrefUtil.init();
  });
  tearDownAll(() async {
    await Hive.close();
    await settingsDirectory.delete(recursive: true);
  });
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('epg-identity-');
    db = AppDatabase.forTesting(NativeDatabase(File('${directory.path}/test.sqlite')));
    Get.testMode = true;
    Get.put(DbService()..db = db);
    settings = Get.put<SettingsService>(_Settings()) as _Settings;
  });
  tearDown(() async {
    Get.reset();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<String> importSource(String name, {String channelId = 'common', String? title}) async {
    final now = DateTime.now().toUtc();
    final file = await File('${directory.path}/input.json').writeAsString(
      jsonEncode({
        'channels': [
          {'id': channelId, 'displayName': 'Common'},
        ],
        'programmes': [
          {
            'channelId': channelId,
            'title': title ?? name,
            'start': now.subtract(const Duration(minutes: 1)).toIso8601String(),
            'stop': now.add(const Duration(minutes: 30)).toIso8601String(),
          },
        ],
      }),
    );
    expect(
      await EpgImportManager().importEpgFile(file: file, sourceName: name, forceUpdate: true, showTips: false),
      isTrue,
    );
    return (await db.getAllEpgSources()).singleWhere((s) => s.name == name).id;
  }

  Future<void> seedPlaylist() async {
    await db.upsertProvider(ProvidersCompanion.insert(id: 'provider', name: 'Playlist', type: 'm3u'));
    await db.upsertChannels([
      ChannelsCompanion.insert(
        id: 'room',
        providerId: 'provider',
        name: 'Common',
        tvgId: const drift.Value('common'),
        streamUrl: 'http://example.test/live.m3u8',
      ),
    ]);
  }

  test('two imported sources retain independent channels with identical raw IDs', () async {
    final a = await importSource('A');
    final b = await importSource('B');
    expect(await db.getEpgChannelsForSource(a), hasLength(1));
    expect(await db.getEpgChannelsForSource(b), hasLength(1));
    final ca = (await db.getEpgChannelsForSource(a)).single;
    final cb = (await db.getEpgChannelsForSource(b)).single;
    expect(ca.id, isNot(cb.id));
    expect(ca.channelId, 'common');
    expect(cb.channelId, 'common');
  });

  test('programme and now-playing queries return only the referenced source', () async {
    await importSource('A');
    final b = await importSource('B');
    final channel = (await db.getEpgChannelsForSource(b)).single;
    final now = DateTime.now();
    expect(
      (await db.getProgrammes(
        epgChannelId: channel.id,
        start: now.subtract(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 1)),
      )).map((p) => p.title),
      ['B'],
    );
    expect((await db.getNowPlaying([channel.id])).map((p) => p.title), ['B']);
    expect((await db.getNowPlayingWindow([channel.id], now, now)).map((p) => p.title), ['B']);
  });

  test('refreshing one source does not steal another source channel', () async {
    final a = await importSource('A');
    final b = await importSource('B');
    final oldB = (await db.getEpgChannelsForSource(b)).single;
    expect(await importSource('A', title: 'A refreshed'), a);
    expect(await db.getEpgChannelsForSource(b), [oldB]);
  });

  test('room detail uses selected source schedule for identical raw IDs', () async {
    await importSource('A');
    final b = await importSource('B');
    await seedPlaylist();
    settings.iptv.selectedSourceId.value = b;
    final room = await IptvSite().getRoomDetail(platform: 'iptv', roomId: 'room');
    expect(room.currentProgramme, 'B');
  });

  test('stored provider catch-up metadata reaches the playback room unchanged', () async {
    await db.upsertProvider(ProvidersCompanion.insert(id: 'archive', name: 'Archive', type: 'm3u'));
    await db.upsertChannels([
      ChannelsCompanion.insert(
        id: 'archive-room',
        providerId: 'archive',
        name: 'Archive room',
        streamUrl: 'https://fixture/live',
        catchupMode: const drift.Value('append'),
        catchupSource: const drift.Value('&start={utc}&duration={duration}'),
        catchupDays: const drift.Value(3.5),
        catchupCorrectionHours: const drift.Value(-2.5),
      ),
    ]);

    final stored = await db.getChannelById('archive-room');
    final room = await IptvSite().getRoomDetail(platform: 'iptv', roomId: 'archive-room');

    expect(stored?.catchupMode, 'append');
    expect(stored?.catchupSource, '&start={utc}&duration={duration}');
    expect(stored?.catchupDays, 3.5);
    expect(stored?.catchupCorrectionHours, -2.5);
    expect(room.catchUpMode, 'append');
    expect(room.catchUpSource, '&start={utc}&duration={duration}');
    expect(room.catchUpDays, 3.5);
    expect(room.catchUpCorrectionHours, -2.5);
  });

  test('channel detail never mixes schedules from equal raw IDs', () async {
    await importSource('A');
    final b = await importSource('B');
    final controller = ChannelDetailController();
    await controller.loadChannelEpg(
      const model.Channel(
        id: 'room',
        providerId: 'provider',
        name: 'Common',
        streamUrl: 'http://example.test/live.m3u8',
      ),
      b,
    );
    expect(controller.upcomingProgs.map((p) => p.title), ['B']);
    expect(controller.nowPlayingProg.value?.title, 'B');
  });

  test('several mappings sharing a raw TVG ID do not break a new room lookup', () async {
    await importSource('A');
    final b = await importSource('B');
    await seedPlaylist();
    settings.iptv.selectedSourceId.value = b;
    for (final id in ['one', 'two']) {
      await db.upsertMapping(
        EpgMappingsCompanion.insert(channelId: id, providerId: 'provider', epgChannelId: 'common', epgSourceId: b),
      );
    }
    final room = await IptvSite().getRoomDetail(platform: 'iptv', roomId: 'room');
    expect(room.currentProgramme, 'B');
  });
  Future<void> reopen({bool legacy = false, bool freshLegacy = false}) async {
    await db.close();
    Get.delete<DbService>(force: true);
    final file = File('${directory.path}/test.sqlite');
    if (freshLegacy && await file.exists()) await file.delete();
    final connection = NativeDatabase(file);
    db = legacy ? _LegacyDatabase(connection) : AppDatabase.forTesting(connection);
    Get.put(DbService()..db = db);
  }

  Future<void> legacySource(String id, {String raw = 'common', String? stored, bool channelRow = true}) async {
    await db.upsertEpgSource(
      EpgSourcesCompanion.insert(
        id: id,
        name: id,
        url: 'https://example.test/$id.xml',
        enabled: const drift.Value(false),
        isAutoUpdate: const drift.Value(false),
        refreshIntervalHours: const drift.Value(72),
        createdAt: drift.Value(DateTime.utc(2020)),
      ),
    );
    if (channelRow) {
      await db.upsertEpgChannels([
        EpgChannelsCompanion.insert(
          id: stored ?? raw,
          sourceId: id,
          channelId: raw,
          displayName: 'Name $id',
          iconUrl: const drift.Value('https://example.test/icon.png'),
        ),
      ]);
    }
    await db.insertProgrammes([
      EpgProgrammesCompanion.insert(
        sourceId: id,
        epgChannelId: raw,
        title: id,
        description: const drift.Value('Description'),
        subtitle: const drift.Value('Subtitle'),
        episodeNum: const drift.Value('S1E2'),
        category: const drift.Value('News'),
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
    'reminders': (await db.select(db.epgReminders).get()).map((e) => e.toJson()).toList(),
    'recordings': (await db.select(db.scheduledRecordings).get()).map((e) => e.toJson()).toList(),
  });

  test('framed IDs distinguish delimiter Unicode and framed-looking feed IDs', () {
    final pairs = [
      ('a:b', 'c'),
      ('a', 'b:c'),
      ('a', '频道 / " :'),
      ('a', 'epg:["a","common"]'),
      ('a', 'common'),
      ('b', 'common'),
    ];
    expect(pairs.map((p) => epgChannelKey(p.$1, p.$2)).toSet(), hasLength(pairs.length));
    expect(epgChannelKey('a', 'common'), epgChannelKey('a', 'common'));
  });

  test('legacy raw room references resolve only inside the explicit source', () async {
    final a = await importSource('A');
    final b = await importSource('B');
    expect(await db.resolveEpgChannelId(a, 'common'), epgChannelKey(a, 'common'));
    expect(await db.resolveEpgChannelId(b, 'common'), epgChannelKey(b, 'common'));
    expect(await db.resolveEpgChannelId(a, epgChannelKey(b, 'common')), isNull);
    expect(await db.resolveEpgChannelId('', 'common'), isNull);
  });

  test('category and room use the same selected source instead of a stale mapping', () async {
    final a = await importSource('A');
    final b = await importSource('B');
    await seedPlaylist();
    await db.upsertMapping(
      EpgMappingsCompanion.insert(
        channelId: 'room',
        providerId: 'provider',
        epgChannelId: epgChannelKey(a, 'common'),
        epgSourceId: a,
        locked: const drift.Value(true),
      ),
    );
    settings.iptv.selectedSourceId.value = b;
    final rooms = await IptvSite().getCategoryRooms(LiveArea(areaId: 'room'));
    expect(rooms.single.currentProgramme, 'B');
    expect(rooms.single.epgId, epgChannelKey(b, 'common'));
    settings.iptv.selectedSourceId.value = '';
    expect((await IptvSite().getCategoryRooms(LiveArea(areaId: 'room'))).single.epgId, isNull);
  });

  test('locked raw mapping resolves within its source and is not overwritten', () async {
    await importSource('A');
    final b = await importSource('B');
    await seedPlaylist();
    await db.upsertMapping(
      EpgMappingsCompanion.insert(
        channelId: 'room',
        providerId: 'provider',
        epgChannelId: 'common',
        epgSourceId: b,
        locked: const drift.Value(true),
        source: const drift.Value('manual'),
      ),
    );
    final before = (await db.getAllMappings()).single;
    settings.iptv.selectedSourceId.value = b;
    expect((await IptvSite().getRoomDetail(platform: 'iptv', roomId: 'room')).currentProgramme, 'B');
    expect((await db.getAllMappings()).single, before);
  });

  test('missing locked mapping remains unresolved instead of fuzzy reassignment', () async {
    final b = await importSource('B');
    await seedPlaylist();
    await db.upsertMapping(
      EpgMappingsCompanion.insert(
        channelId: 'room',
        providerId: 'provider',
        epgChannelId: 'removed',
        epgSourceId: b,
        locked: const drift.Value(true),
        source: const drift.Value('manual'),
      ),
    );
    settings.iptv.selectedSourceId.value = b;
    expect((await IptvSite().getRoomDetail(platform: 'iptv', roomId: 'room')).epgId, isNull);
  });

  test('schema 6 migration preserves source settings locked mappings and user actions', () async {
    await reopen(legacy: true, freshLegacy: true);
    await legacySource('A', stored: 'legacy-A');
    await legacySource('B', stored: 'legacy-B');
    await db.upsertMapping(
      EpgMappingsCompanion.insert(
        channelId: 'room',
        providerId: 'provider',
        epgChannelId: 'common',
        epgSourceId: 'B',
        locked: const drift.Value(true),
        source: const drift.Value('manual'),
        confidence: const drift.Value(0.91),
        updatedAt: drift.Value(DateTime.utc(2020)),
      ),
    );
    for (final id in ['linked', 'ambiguous', 'unique']) {
      await db.addReminder(
        EpgRemindersCompanion.insert(
          id: id,
          epgChannelId: id == 'unique' ? 'legacy-A' : 'common',
          channelId: drift.Value(id == 'linked' ? 'room' : null),
          programmeTitle: 'Keep reminder',
          programmeStart: DateTime.utc(2036),
          programmeStop: DateTime.utc(2036, 1, 1, 1),
          minutesBefore: const drift.Value(15),
          fired: const drift.Value(true),
          createdAt: drift.Value(DateTime.utc(2020)),
        ),
      );
    }
    await db
        .into(db.scheduledRecordings)
        .insert(
          ScheduledRecordingsCompanion.insert(
            id: 'recording',
            epgChannelId: 'common',
            channelId: const drift.Value('room'),
            programmeTitle: 'Keep recording',
            programmeStart: DateTime.utc(2036),
            programmeStop: DateTime.utc(2036, 1, 1, 1),
            status: const drift.Value('completed'),
            outputPath: const drift.Value('existing.mp4'),
            createdAt: drift.Value(DateTime.utc(2020)),
          ),
        );
    final oldSources = await db.getAllEpgSources();
    final oldMapping = (await db.getAllMappings()).single;
    final oldProgrammes = await db.select(db.epgProgrammes).get();
    final oldReminders = await db.select(db.epgReminders).get();
    final oldRecording = (await db.select(db.scheduledRecordings).get()).single;
    await reopen();
    expect(await db.getAllEpgSources(), oldSources);
    expect((await db.customSelect('PRAGMA user_version').get()).single.read<int>('user_version'), 8);
    for (final id in ['A', 'B']) {
      final ch = (await db.getEpgChannelsForSource(id)).single;
      expect(ch.id, epgChannelKey(id, 'common'));
      expect(ch.channelId, 'common');
      expect(ch.displayName, 'Name $id');
      final programmes = await db.getProgrammes(
        epgChannelId: ch.id,
        start: DateTime.utc(2035),
        end: DateTime.utc(2037),
      );
      expect(programmes.single.copyWith(epgChannelId: 'common'), oldProgrammes.singleWhere((p) => p.sourceId == id));
    }
    expect((await db.getAllMappings()).single, oldMapping.copyWith(epgChannelId: epgChannelKey('B', 'common')));
    final newReminders = await db.select(db.epgReminders).get();
    for (final old in oldReminders) {
      final key = old.id == 'linked'
          ? epgChannelKey('B', 'common')
          : old.id == 'unique'
          ? epgChannelKey('A', 'common')
          : 'common';
      expect(newReminders.singleWhere((r) => r.id == old.id), old.copyWith(epgChannelId: key));
    }
    expect(
      (await db.select(db.scheduledRecordings).get()).single,
      oldRecording.copyWith(epgChannelId: epgChannelKey('B', 'common')),
    );
    final migrated = await snapshot();
    await reopen();
    expect(await snapshot(), migrated);
    // Explicit version rewinding is stable for references with surviving channel rows.
    await db.customStatement('PRAGMA user_version = 6');
    await reopen();
    expect(await snapshot(), migrated);
    expect(await db.customSelect("SELECT name FROM sqlite_temp_master WHERE name = 'epg_identity_v7'").get(), isEmpty);
  });

  test('migration retains orphaned-source programme and mapping references', () async {
    await reopen(legacy: true, freshLegacy: true);
    await legacySource('A', channelRow: false);
    await legacySource('B');
    await db.upsertMapping(
      EpgMappingsCompanion.insert(
        channelId: 'room',
        providerId: 'provider',
        epgChannelId: 'common',
        epgSourceId: 'A',
        locked: const drift.Value(true),
      ),
    );
    await reopen();
    expect(await db.getEpgChannelsForSource('A'), isEmpty);
    expect((await db.getAllMappings()).single.epgChannelId, epgChannelKey('A', 'common'));
    expect(
      (await db.getProgrammes(
        epgChannelId: epgChannelKey('A', 'common'),
        start: DateTime.utc(2035),
        end: DateTime.utc(2037),
      )).single.title,
      'A',
    );
  });

  test('migration snapshots avoid old-to-new key rewrite chains', () async {
    await reopen(legacy: true, freshLegacy: true);
    await legacySource('A', raw: 'plain');
    final looksFramed = epgChannelKey('A', 'plain');
    await db.upsertEpgChannels([
      EpgChannelsCompanion.insert(
        id: looksFramed,
        sourceId: 'A',
        channelId: looksFramed,
        displayName: 'Framed feed ID',
      ),
    ]);
    await db.insertProgrammes([
      EpgProgrammesCompanion.insert(
        sourceId: 'A',
        epgChannelId: looksFramed,
        title: 'Framed',
        start: DateTime.utc(2036),
        stop: DateTime.utc(2036, 1, 1, 1),
      ),
    ]);
    await reopen();
    final channels = await db.getEpgChannelsForSource('A');
    expect(channels.map((c) => c.id).toSet(), {epgChannelKey('A', 'plain'), epgChannelKey('A', looksFramed)});
    final programmes = await db.select(db.epgProgrammes).get();
    expect(programmes.singleWhere((p) => p.title == 'A').epgChannelId, epgChannelKey('A', 'plain'));
    expect(programmes.singleWhere((p) => p.title == 'Framed').epgChannelId, epgChannelKey('A', looksFramed));
  });

  test('failed migration rolls back programme rewrites and remains retryable at version 6', () async {
    await reopen(legacy: true, freshLegacy: true);
    await legacySource('A');
    await db.upsertMapping(
      EpgMappingsCompanion.insert(channelId: 'room', providerId: 'provider', epgChannelId: 'common', epgSourceId: 'A'),
    );
    final old = await snapshot();
    await db.customStatement(
      "CREATE TRIGGER migration_failure BEFORE UPDATE ON epg_mappings "
      "BEGIN SELECT RAISE(ABORT, 'identity fixture failure'); END",
    );
    await reopen();
    await expectLater(
      db.getAllEpgSources(),
      throwsA(predicate<Object>((e) => e.toString().contains('identity fixture failure'))),
    );
    await reopen(legacy: true);
    expect((await db.customSelect('PRAGMA user_version').get()).single.read<int>('user_version'), 6);
    expect(await snapshot(), old);
    await db.customStatement('DROP TRIGGER migration_failure');
    await reopen();
    expect((await db.getEpgChannelsForSource('A')).single.id, epgChannelKey('A', 'common'));
  });
  test('auto mapping retains raw TVG matching and writes the source-scoped reference', () async {
    await importSource('A');
    final b = await importSource('B');
    await seedPlaylist();
    settings.iptv.selectedSourceId.value = b;
    await IptvImportManager().runAutoEpgMapping(providerId: 'provider');
    final mapping = (await db.getAllMappings()).single;
    expect(mapping.epgChannelId, epgChannelKey(b, 'common'));
    expect(mapping.epgSourceId, b);
    expect((await IptvSite().getRoomDetail(platform: 'iptv', roomId: 'room')).currentProgramme, 'B');
  });

  test('stale same-channel mapping from a different provider is not reused', () async {
    final a = await importSource('A');
    final b = await importSource('B');
    await seedPlaylist();
    settings.iptv.selectedSourceId.value = b;
    for (final provider in ['stale-provider', 'provider']) {
      final source = provider == 'provider' ? b : a;
      await db.upsertMapping(
        EpgMappingsCompanion.insert(
          channelId: 'room',
          providerId: provider,
          epgChannelId: epgChannelKey(source, 'common'),
          epgSourceId: source,
          locked: const drift.Value(true),
        ),
      );
    }
    expect((await IptvSite().getRoomDetail(platform: 'iptv', roomId: 'room')).currentProgramme, 'B');
    expect(await db.getAllMappings(), hasLength(2));
  });

  test('version commits with orphaned identities before a later open failure', () async {
    await reopen(legacy: true, freshLegacy: true);
    await legacySource('A', channelRow: false);
    await db.close();
    Get.delete<DbService>(force: true);
    db = _FailAfterMigrationDatabase(NativeDatabase(File('${directory.path}/test.sqlite')));
    Get.put(DbService()..db = db);
    await expectLater(db.getAllEpgSources(), throwsA(isA<StateError>()));
    await reopen();
    expect((await db.customSelect('PRAGMA user_version').get()).single.read<int>('user_version'), 8);
    expect((await db.select(db.epgProgrammes).get()).single.epgChannelId, epgChannelKey('A', 'common'));
  });

  test('future database version stays intact when downgrade is attempted', () async {
    await importSource('A');
    final old = await snapshot();
    await db.customStatement('PRAGMA user_version = 9');
    await reopen();
    await expectLater(db.getAllEpgSources(), throwsA(isA<StateError>()));
    await db.close();
    Get.delete<DbService>(force: true);
    db = _HistoricalDatabase(NativeDatabase(File('${directory.path}/test.sqlite')), 9);
    Get.put(DbService()..db = db);
    expect((await db.customSelect('PRAGMA user_version').get()).single.read<int>('user_version'), 9);
    expect(await snapshot(), old);
  });

  for (int version = 1; version <= 5; version++) {
    test('historical schema $version upgrades data and later tables through version 8', () async {
      await db.close();
      Get.delete<DbService>(force: true);
      db = _HistoricalDatabase(NativeDatabase(File('${directory.path}/test.sqlite')), version);
      Get.put(DbService()..db = db);
      await db.customStatement(
        "INSERT INTO epg_sources (id, name, url, enabled, refresh_interval_hours) "
        "VALUES ('old', 'Old source', 'https://example.test/old.xml', 0, 72)",
      );
      await db.customStatement(
        "INSERT INTO epg_channels (id, source_id, channel_id, display_name) VALUES ('common', 'old', 'common', 'Common')",
      );
      await db.customStatement(
        "INSERT INTO epg_programmes (source_id, epg_channel_id, title, start, stop) VALUES ('old', 'common', 'Old show', 2082758400, 2082762000)",
      );
      expect((await db.customSelect('PRAGMA user_version').get()).single.read<int>('user_version'), version);
      await reopen();
      final source = (await db.getAllEpgSources()).single;
      expect(source.id, 'old');
      expect(source.enabled, isFalse);
      expect(source.refreshIntervalHours, 72);
      expect(source.isAutoUpdate, isTrue);
      expect((await db.getEpgChannelsForSource('old')).single.id, epgChannelKey('old', 'common'));
      expect((await db.select(db.epgProgrammes).get()).single.epgChannelId, epgChannelKey('old', 'common'));
      expect(await db.select(db.favoriteLists).get(), isEmpty);
      expect(await db.select(db.epgReminders).get(), isEmpty);
      expect(await db.select(db.scheduledRecordings).get(), isEmpty);
      expect(await db.select(db.failoverGroups).get(), isEmpty);
      expect((await db.customSelect('PRAGMA user_version').get()).single.read<int>('user_version'), 8);
    });
  }

  test('schema 7 adds nullable provider and programme catch-up metadata without changing existing rows', () async {
    await db.close();
    Get.delete<DbService>(force: true);
    db = _HistoricalDatabase(NativeDatabase(File('${directory.path}/test.sqlite')), 7);
    Get.put(DbService()..db = db);
    await db.customStatement("INSERT INTO providers (id, name, type) VALUES ('old', 'Old', 'm3u')");
    await db.customStatement(
      "INSERT INTO channels (id, provider_id, name, stream_url) "
      "VALUES ('old-room', 'old', 'Old room', 'https://fixture/live')",
    );
    await db.customStatement(
      "INSERT INTO epg_sources (id, name, url) VALUES ('epg', 'EPG', 'https://fixture/epg.xml')",
    );
    await db.customStatement(
      "INSERT INTO epg_programmes (epg_channel_id, source_id, title, start, stop) "
      "VALUES ('old-epg', 'epg', 'Old programme', 2082758400, 2082762000)",
    );
    await reopen();

    final channel = await db.getChannelById('old-room');
    expect(channel?.name, 'Old room');
    expect(channel?.streamUrl, 'https://fixture/live');
    expect(channel?.catchupMode, isNull);
    expect(channel?.catchupSource, isNull);
    expect(channel?.catchupDays, isNull);
    expect(channel?.catchupCorrectionHours, isNull);
    expect((await db.select(db.epgProgrammes).get()).single.catchupId, isNull);
    expect((await db.customSelect('PRAGMA user_version').get()).single.read<int>('user_version'), 8);
  });
}

class _Settings extends SettingsService {
  final _iptv = IptvSettingsController();
  @override
  IptvSettingsController get iptv => _iptv;
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _LegacyDatabase extends AppDatabase {
  _LegacyDatabase(super.executor) : super.forTesting();
  @override
  int get schemaVersion => 6;
  @override
  drift.MigrationStrategy get migration => drift.MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _dropCatchupColumns(this);
    },
  );
}

/// Reconstruct the schemas described by AppDatabase's existing migration steps.
class _HistoricalDatabase extends AppDatabase {
  _HistoricalDatabase(super.executor, this.version) : super.forTesting();
  final int version;
  @override
  int get schemaVersion => version;
  @override
  drift.MigrationStrategy get migration => drift.MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      if (version < 2) {
        await customStatement('DROP TABLE favorite_list_channels');
        await customStatement('DROP TABLE favorite_lists');
      }
      if (version < 3) {
        await customStatement('DROP TABLE epg_reminders');
        await customStatement('DROP TABLE scheduled_recordings');
      }
      if (version < 4) {
        await customStatement('ALTER TABLE epg_programmes DROP COLUMN subtitle');
        await customStatement('ALTER TABLE epg_programmes DROP COLUMN episode_num');
      }
      if (version < 5) {
        await customStatement('DROP TABLE failover_group_channels');
        await customStatement('DROP TABLE failover_groups');
      }
      if (version < 6) {
        await customStatement('ALTER TABLE providers DROP COLUMN is_auto_update');
        await customStatement('ALTER TABLE epg_sources DROP COLUMN is_auto_update');
      }
      if (version < 8) await _dropCatchupColumns(this);
    },
  );
}

Future<void> _dropCatchupColumns(AppDatabase db) async {
  await db.customStatement('ALTER TABLE channels DROP COLUMN catchup_mode');
  await db.customStatement('ALTER TABLE channels DROP COLUMN catchup_source');
  await db.customStatement('ALTER TABLE channels DROP COLUMN catchup_days');
  await db.customStatement('ALTER TABLE channels DROP COLUMN catchup_correction_hours');
  await db.customStatement('ALTER TABLE epg_programmes DROP COLUMN catchup_id');
}

class _FailAfterMigrationDatabase extends AppDatabase {
  _FailAfterMigrationDatabase(super.executor) : super.forTesting();
  @override
  drift.MigrationStrategy get migration {
    final base = super.migration;
    return drift.MigrationStrategy(
      onCreate: base.onCreate,
      onUpgrade: (m, from, to) async {
        await base.onUpgrade(m, from, to);
        throw StateError('fixture failure after committed migration');
      },
    );
  }
}
