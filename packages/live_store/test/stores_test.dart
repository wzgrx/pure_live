import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late LiveStore store;
  setUp(() async => store = await memoryStore());
  tearDown(() => store.close());

  group('follows', () {
    test('add, find, remove; invalid and duplicate rooms are refused (3.x validity)', () async {
      expect(await store.follows.add(LiveRoom(platform: 'Douyu', roomId: ' 5526219 ', nick: 'a')), isTrue);
      expect(await store.follows.add(LiveRoom(platform: 'douyu', roomId: '5526219')), isFalse);
      for (final id in ['', '0', 'null', 'undefined', 'NaN', 'none']) {
        expect(
          await store.follows.add(LiveRoom(platform: 'douyu', roomId: id)),
          isFalse,
          reason: id,
        );
      }
      expect((await store.follows.find('DOUYU', '5526219'))?.nick, 'a');
      expect(await store.follows.remove(LiveRoom(platform: 'douyu', roomId: '5526219')), isTrue);
      expect(await store.follows.count(), 0);
    });

    test('identity ignores case where the platform does (M2.1, 11-8)', () async {
      await store.follows.add(LiveRoom(platform: 'twitch', roomId: 'Shroud'));
      expect(await store.follows.add(LiveRoom(platform: 'twitch', roomId: 'shroud')), isFalse);
      expect(await store.follows.add(LiveRoom(platform: 'youtube', roomId: 'UCabc')), isTrue);
      expect(await store.follows.add(LiveRoom(platform: 'youtube', roomId: 'UCABC')), isTrue);
    });

    test('a refresh without a name keeps the stored one (X-2)', () async {
      await store.follows.add(LiveRoom(platform: 'jdlive', roomId: '1', nick: 'Shop', title: 'Sale'));
      final changed = await store.follows.update([
        LiveRoom(platform: 'jdlive', roomId: '1', liveStatus: LiveStatus.live),
        LiveRoom(platform: 'jdlive', roomId: 'not-followed', nick: 'x'),
      ]);
      final room = (await store.follows.all()).single;
      expect(changed, 1);
      expect(room.nick, 'Shop');
      expect(room.title, 'Sale');
      expect(room.liveStatus, LiveStatus.live);
    });

    test('watchAll emits after each committed write', () async {
      final seen = <int>[];
      final sub = store.follows.watchAll().listen((rooms) => seen.add(rooms.length));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await store.follows.add(LiveRoom(platform: 'bilibili', roomId: '1'));
      await store.follows.add(LiveRoom(platform: 'bilibili', roomId: '2'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(seen.first, 0);
      expect(seen.last, 2);
    });
  });

  group('history (3.x history_metadata_test)', () {
    test('newest first, moves on rewatch, keeps the limit', () async {
      await store.history.setLimit(2);
      final t = DateTime.utc(2026, 10);
      await store.history.record(
        LiveRoom(platform: 'huya', roomId: '1'),
        now: t,
      );
      await store.history.record(
        LiveRoom(platform: 'huya', roomId: '2'),
        now: t.add(const Duration(minutes: 1)),
      );
      await store.history.record(
        LiveRoom(platform: 'huya', roomId: '1'),
        now: t.add(const Duration(minutes: 2)),
      );
      await store.history.record(
        LiveRoom(platform: 'huya', roomId: '3'),
        now: t.add(const Duration(minutes: 3)),
      );
      final rooms = await store.history.all();
      expect([for (final r in rooms) r.roomId], ['3', '1']);
      expect(rooms.last.lastWatchedAt, t.add(const Duration(minutes: 2)).millisecondsSinceEpoch);
    });

    test('limit 0 keeps everything', () async {
      await store.history.setLimit(0);
      for (var i = 0; i < 60; i++) {
        await store.history.record(LiveRoom(platform: 'huya', roomId: '${i + 1}'));
      }
      expect(await store.history.all(), hasLength(60));
    });

    test('clearing what was shown keeps a room watched again since', () async {
      final t = DateTime.utc(2026, 10);
      await store.history.record(
        LiveRoom(platform: 'huya', roomId: '1'),
        now: t,
      );
      await store.history.record(
        LiveRoom(platform: 'huya', roomId: '2'),
        now: t,
      );
      final shown = await store.history.all();
      await store.history.record(
        LiveRoom(platform: 'huya', roomId: '1'),
        now: t.add(const Duration(seconds: 5)),
      );
      await store.history.clear(shown);
      expect([for (final r in await store.history.all()) r.roomId], ['1']);
    });
  });

  group('tags', () {
    test('names are unique without case; deleting a tag removes it from rooms', () async {
      final a = await store.tags.add('Games');
      expect(await store.tags.add(' games '), isNull);
      expect(await store.tags.validateName(''), TagNameValidation.empty);
      final b = await store.tags.add('Music');
      final room = LiveRoom(platform: 'bilibili', roomId: '1');
      await store.tags.setTagsOf(room, [a!.id, b!.id, 'unknown', a.id]);
      expect(await store.tags.tagsOf(room), [a.id, b.id]);
      await store.tags.delete(a.id);
      expect(await store.tags.tagsOf(room), [b.id]);
      await store.tags.pinToTop(b.id);
      expect((await store.tags.all()).first.id, b.id);
    });
  });

  group('block lists', () {
    test('trimmed, case-insensitive unique, per kind', () async {
      expect(await store.blockLists.add(BlockKind.keyword, ' 广告 '), isTrue);
      expect(await store.blockLists.add(BlockKind.keyword, 'AD'), isTrue);
      expect(await store.blockLists.add(BlockKind.keyword, 'ad'), isFalse);
      expect(await store.blockLists.add(BlockKind.keyword, '  '), isFalse);
      expect(await store.blockLists.add(BlockKind.user, 'ad'), isTrue);
      expect(await store.blockLists.list(BlockKind.keyword), ['广告', 'AD']);
      await store.blockLists.remove(BlockKind.keyword, 'ad');
      expect(await store.blockLists.list(BlockKind.keyword), ['广告']);
    });
  });

  group('settings', () {
    test('defaults from 3.x, clamping, choices, persistence', () async {
      expect(store.settings.get(Settings.danmakuSpeed), 120);
      expect(store.settings.get(Settings.preferH264), isTrue);
      expect(store.settings.get(Settings.youtubeShowAllChat), isFalse);
      expect(store.settings.get(Settings.showUnplayableInDiscover), isFalse);
      expect(store.settings.get(Settings.detectClipboardRooms), isTrue);
      expect(store.settings.get(Settings.douyuForceRenew), isFalse);
      await store.settings.set(Settings.autoRefreshInterval, 1);
      await store.settings.set(Settings.themeMode, 'Purple');
      expect(store.settings.get(Settings.autoRefreshInterval), 5);
      expect(store.settings.get(Settings.themeMode), 'System');
      final reopened = await SettingsStore.load(store.database);
      expect(reopened.get(Settings.autoRefreshInterval), 5);
    });

    test('interface mode: auto by default, three choices, kept on this device (M14.1)', () async {
      expect(store.settings.get(Settings.uiMode), 'auto');
      await store.settings.set(Settings.uiMode, 'tv');
      expect(store.settings.get(Settings.uiMode), 'tv');
      await store.settings.set(Settings.uiMode, 'watch');
      expect(store.settings.get(Settings.uiMode), 'auto');
      expect(Settings.uiMode.scope, SettingScope.internal);
      expect(Settings.byKey('uiMode'), Settings.uiMode);
    });

    test('B02: "暂停时的弹幕" stands with the video by default; two choices, backed up', () async {
      expect(store.settings.get(Settings.danmakuPausedBehavior), 'pause');
      await store.settings.set(Settings.danmakuPausedBehavior, 'continue');
      expect(store.settings.get(Settings.danmakuPausedBehavior), 'continue');
      await store.settings.set(Settings.danmakuPausedBehavior, 'stop');
      expect(store.settings.get(Settings.danmakuPausedBehavior), 'pause');
      expect(Settings.byKey('danmakuPausedBehavior'), Settings.danmakuPausedBehavior);
      expect(Settings.danmakuPausedBehavior.scope, isNot(SettingScope.internal));
    });

    test('watch emits the current value and changes', () async {
      final values = <bool>[];
      final sub = store.settings.watch(Settings.hideDanmaku).listen(values.add);
      await Future<void>.delayed(Duration.zero);
      await store.settings.set(Settings.hideDanmaku, true);
      await store.settings.reset(Settings.hideDanmaku);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(values, [false, true, false]);
    });
  });

  group('secrets', () {
    test('cookies are sealed, normalised, and readable synchronously after reopening', () async {
      await store.secrets.setCookie('Bilibili', ' SESSDATA=1\n ');
      expect(store.secrets.cookieFor('bilibili'), 'SESSDATA=1');
      final rows = await store.database.rows('SELECT sealed FROM secrets');
      expect(String.fromCharCodes(rows.single.read<List<int>>('sealed')), isNot(contains('SESSDATA')));
      final again = await SecretStore.load(store.database, const FakeCipher());
      expect(again.cookieFor('bilibili'), 'SESSDATA=1');
    });

    test('a value sealed on another device reads as signed out', () async {
      await store.secrets.setCookie('douyu', 'a=1');
      final other = await SecretStore.load(store.database, const FakeCipher.foreign());
      expect(other.cookieFor('douyu'), isNull);
      expect(other.unreadable, {SecretRefs.cookie('douyu')});
    });
  });

  group('webdav', () {
    test('passwords live in the secret store; the current server is kept by name', () async {
      const config = WebDavConfig(name: 'nas', address: 'https://nas.local/dav', username: 'u', password: 'p');
      expect(await store.webdav.add(config), isTrue);
      expect(await store.webdav.add(config), isFalse);
      await store.webdav.select('nas');
      expect(await store.webdav.current(), config);
      expect(store.secrets.read(SecretRefs.webdav('nas')), 'p');
      await store.webdav.remove('nas');
      expect(store.secrets.read(SecretRefs.webdav('nas')), isNull);
      expect(await store.webdav.current(), isNull);
    });

    test('address rules (3.x webdav_config_test)', () {
      expect(WebDavConfig.isValidAddress('https://dav.example.com/backup'), isTrue);
      expect(WebDavConfig.isValidAddress('ftp://dav.example.com'), isFalse);
      expect(WebDavConfig.isValidAddress('https://user@dav.example.com'), isFalse);
      expect(WebDavConfig.isValidAddress('https://dav.example.com/?a=1'), isFalse);
    });
  });
}
