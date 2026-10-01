// The music domain without network: matcher and importer, LRC and the
// lyric chain, the play queue, daily recommendations, the audio cache, the
// third-party settings and pasted playlist links.
import 'dart:math';

import 'package:live_vod/live_vod.dart';
import 'package:test/test.dart';

import 'fixture.dart';

VodArchive _video(
  String bvid, {
  String title = '',
  int seconds = 200,
  String type = '',
  int typeId = 0,
  int views = 0,
}) => VodArchive(
  bvid: bvid,
  title: title,
  duration: Duration(seconds: seconds),
  typeName: type,
  typeId: typeId,
  stat: VodStat(views: views),
);

void main() {
  group('matcher', () {
    test('the recorded search for 晴天 - 周杰伦 ranks a title with both first', () {
      final hits = VodParse.searchVideos(Fixture.load('V23-search-video').body).items;
      const track = ImportedTrack(name: '晴天', artist: '周杰伦', duration: Duration(seconds: 269));
      final ranked = TrackMatcher.rank(track, hits);
      expect(ranked.first.reason, 'both');
      expect(ranked.first.archive.title, contains('晴天'));
      expect(ranked.first.score, greaterThan(100000));
      expect(TrackMatcher.keyword(track), '晴天 - 周杰伦');
    });

    test('scoring rules: excluded partitions, length gate, one side, preferred partitions, plays', () {
      const track = ImportedTrack(name: 'Hello World', artist: 'Someone', duration: Duration(seconds: 200));
      final ranked = TrackMatcher.rank(track, [
        _video('BV1', title: 'hello world someone', type: '翻唱'), // excluded
        _video('BV2', title: 'hello world', seconds: 260), // one side, 60 s off: dropped
        _video('BV3', title: 'hello world live', seconds: 205), // one side: 10 - 5
        _video('BV4', title: 'hello world', type: 'MV', views: 1000), // 10 + 1000 + 15
        _video('BV5', title: 'something else'), // nothing shared: dropped
        _video('BV6', title: 'world tour', seconds: 210), // a shared word: 5 - 10
      ]);
      expect([for (final match in ranked) (match.archive.bvid, match.score)], [('BV4', 1025), ('BV3', 5), ('BV6', -5)]);
    });

    test('a shared Chinese run of four characters still counts', () {
      const track = ImportedTrack(name: '阳光彩虹小白马', artist: '大张伟', duration: Duration(seconds: 200));
      final ranked = TrackMatcher.rank(track, [_video('BV1', title: '【翻弹】阳光彩虹小白马吉他版', seconds: 190)]);
      expect(ranked.single.reason, 'chinese');
    });

    test('the importer paces searches, reports progress and can stop', () async {
      final sleeps = <Duration>[];
      final keywords = <String>[];
      final importer = PlaylistImporter(
        search: (keyword) async {
          keywords.add(keyword);
          return keyword.startsWith('A') ? [_video('BVa', title: 'A x', seconds: 100)] : <VodArchive>[];
        },
        sleep: (duration) async => sleeps.add(duration),
      );
      final progress = <int>[];
      final result = await importer.run(const [
        ImportedTrack(name: 'A', artist: 'x', duration: Duration(seconds: 100)),
        ImportedTrack(name: 'B', artist: 'y', duration: Duration(seconds: 100)),
      ], onProgress: (p) => progress.add(p.done));
      expect(keywords, ['A - x', 'B - y']);
      expect(sleeps, [const Duration(milliseconds: 1200)]);
      expect(progress, [1, 2]);
      expect(result.matched.single.match.archive.bvid, 'BVa');
      expect(result.unmatched.single.name, 'B');
      final stopped = await importer.run(const [
        ImportedTrack(name: 'A', artist: 'x', duration: Duration.zero),
      ], isCancelled: () => true);
      expect(stopped.cancelled, isTrue);
      expect(stopped.unmatched, hasLength(1));
    });
  });

  group('third-party settings and links', () {
    test('defaults are the TV services; settings may move them, bad values keep defaults', () {
      const defaults = ThirdPartyEndpoints();
      expect(defaults.neteasePlaylist, 'https://rp.u2x1.work');
      expect(defaults.kugouPlaylist, 'https://kg.u2x1.work');
      expect(defaults.rangotecLyric, 'https://tools.rangotec.com');
      final moved = ThirdPartyEndpoints.fromJson(const {
        'neteasePlaylist': 'http://192.168.1.5:3000/',
        'kugouPlaylist': 'ftp://x',
      });
      expect(moved.neteasePlaylist, 'http://192.168.1.5:3000');
      expect(moved.kugouPlaylist, defaults.kugouPlaylist);
      expect(ThirdPartyEndpoints.fromJson(moved.toJson()).neteasePlaylist, 'http://192.168.1.5:3000');
    });

    test('pasted links, prefixed ids and bare ids', () {
      expect(PlaylistImportSource.parse('https://music.163.com/#/playlist?id=19723756&userid=1'), (
        platform: PlaylistPlatform.netease,
        id: '19723756',
      ));
      expect(PlaylistImportSource.parse('https://www.kugou.com/songlist/gcid_3zvmr1dz1z0z0f7/'), (
        platform: PlaylistPlatform.kugou,
        id: 'gcid_3zvmr1dz1z0z0f7',
      ));
      expect(PlaylistImportSource.parse('collection_3_2132040296_689_0'), (
        platform: PlaylistPlatform.kugou,
        id: 'collection_3_2132040296_689_0',
      ));
      expect(PlaylistImportSource.parse('https://y.qq.com/n/ryqq/playlist/7256912512'), (
        platform: PlaylistPlatform.tencent,
        id: '7256912512',
      ));
      expect(PlaylistImportSource.parse('netease:123'), (platform: PlaylistPlatform.netease, id: '123'));
      expect(PlaylistImportSource.parse('123', platform: PlaylistPlatform.kugou), (
        platform: PlaylistPlatform.kugou,
        id: '123',
      ));
      expect(PlaylistImportSource.parse('hello there'), isNull);
    });
  });

  group('lyrics', () {
    test('stamp formats, several stamps per line, offset and tags', () {
      final document = Lrc.parse('''
[ti:Song][ar:Singer]
[offset:500]
[00:01]one
[00:02.5]two
[00:03.25][00:10.250]three
[00:04:50]four
[01:00:05.000]five
not a lyric
''');
      expect(document.artist, '');
      expect(
        [for (final line in document.lines) (line.start.inMilliseconds, line.text)],
        [(500, 'one'), (2000, 'two'), (2750, 'three'), (4000, 'four'), (9750, 'three'), (3604500, 'five')],
      );
      expect(document.indexAt(const Duration(seconds: 3)), 2);
      expect(document.indexAt(Duration.zero), -1);
      final tagged = Lrc.parse('[ti:晴天]\n[ar:周杰伦]\n[01:05.00]late start');
      expect(tagged.title, '晴天');
      expect(tagged.lines.single.start, const Duration(minutes: 1, seconds: 5), reason: 'no [00: needed');
    });

    test('titles are cleaned and checked', () {
      expect(Lrc.cleanTitle('【4K】P3. 晴天 (Live)'), '晴天');
      expect(Lrc.cleanTitle('第3首 稻香'), '稻香');
      expect(Lrc.cleanTitle('03 七里香'), '七里香');
      expect(Lrc.plausible('晴天', '晴天 (Live)'), isTrue);
      expect(Lrc.plausible('晴天', '雨天'), isFalse);
      expect(Lrc.plausible('Hello World', 'hello world!'), isTrue);
    });

    test('the chain: first fitting candidate wins and is stored; picks override; misses are remembered', () async {
      final store = MemoryVodStore();
      var calls = 0;
      final lookup = LyricLookup(
        store: store,
        sources: [
          (query) async {
            calls++;
            return const [LyricCandidate(source: 'a', title: '雨天', lrc: '[00:01.00]wrong song')];
          },
          (query) async => const [LyricCandidate(source: 'b', lrc: '[ti:晴天]\n[00:01.00]right')],
        ],
      );
      final found = await lookup.find(const LyricQuery(title: 'P1 晴天'));
      expect(found!.lines.single.text, 'right');
      expect(store.values['music.lyric.cache.晴天'], contains('right'));
      await lookup.find(const LyricQuery(title: '晴天'));
      expect(calls, 1, reason: 'the stored hit answers');
      await lookup.pick('晴天', '[00:02.00]mine');
      expect((await lookup.find(const LyricQuery(title: '晴天')))!.lines.single.text, 'mine');
      final candidates = await lookup.candidates(const LyricQuery(title: '晴天'));
      expect([for (final c in candidates) c.candidate.source], ['manual', 'b']);
      await lookup.clearPick('晴天');
      expect((await lookup.find(const LyricQuery(title: '晴天')))!.lines.single.text, 'right');

      final empty = LyricLookup(store: MemoryVodStore(), sources: [(query) async => const <LyricCandidate>[]]);
      expect(await empty.find(const LyricQuery(title: 'x')), isNull);
    });
  });

  group('queue', () {
    PlayQueue<String> queue(List<String> items, {PlayMode mode = PlayMode.sequence, bool wrap = true}) =>
        PlayQueue<String>(idOf: (item) => item, mode: mode, wrap: wrap, random: Random(7))..replace(items);

    test('sequence wraps for music and stops for a video; repeat-one stays only when auto', () {
      final music = queue(['a', 'b', 'c'])..jumpTo(2);
      expect(music.next(auto: true), 0);
      final video = queue(['p1', 'p2'], wrap: false)..jumpTo(1);
      expect(video.next(auto: true), isNull);
      expect(video.next(), 0, reason: 'manual next still wraps');
      final repeat = queue(['a', 'b'], mode: PlayMode.repeatOne);
      expect(repeat.next(auto: true), 0);
      expect(repeat.next(), 1);
      expect(repeat.previous(), 0);
    });

    test('shuffle plays every item once per round and previous walks back the order', () {
      final q = queue(['a', 'b', 'c', 'd', 'e'], mode: PlayMode.shuffle);
      final seen = <String>[q.current!];
      for (var i = 0; i < 4; i++) {
        q.next(auto: true);
        seen.add(q.current!);
      }
      expect(seen.toSet(), hasLength(5));
      final last = q.current;
      q.previous();
      expect(q.current, seen[3]);
      q.next();
      expect(q.current, last);
      q.next();
      expect(q.current, isNot(last), reason: 'a new round does not start with the song just played');
    });

    test('play next, enqueue, remove and move keep the current item', () {
      final q = queue(['a', 'b', 'c']);
      expect(q.playNext('c'), PlayNextResult.moved);
      expect(q.items, ['a', 'c', 'b']);
      expect(q.playNext('c'), PlayNextResult.alreadyNext);
      expect(q.playNext('d'), PlayNextResult.inserted);
      expect(q.items, ['a', 'd', 'c', 'b']);
      expect(q.enqueue('a'), isFalse);
      expect(q.enqueue('e'), isTrue);
      q.jumpTo(2);
      expect(q.removeAt(0), isFalse);
      expect(q.current, 'c');
      expect(q.removeAt(1), isTrue);
      expect(q.current, 'b');
      q.move(0, 2);
      expect(q.items, ['b', 'e', 'd']);
      expect(q.current, 'b');
      final empty = PlayQueue<String>(idOf: (item) => item);
      expect(empty.playNext('x'), PlayNextResult.started);
      expect(empty.current, 'x');
    });

    test('failures move on and stop after min(length, 5) in a row', () {
      final q = queue(['a', 'b', 'c']);
      expect(q.failed(), 1);
      expect(q.failed(), 2);
      expect(q.failed(), isNull);
      q.opened();
      expect(q.failed(), isNotNull);
    });
  });

  group('daily recommendations', () {
    test('a day list from related music, cached for the day and folder, history kept', () async {
      final store = MemoryVodStore();
      var now = DateTime(2026, 10, 1, 9);
      var relatedCalls = 0;
      final recommender = DailyRecommender(
        store: store,
        now: () => now,
        random: Random(1),
        folderArchives: (id) async => [for (var i = 0; i < 3; i++) _video('BVseed$id$i')],
        related: (seed) async {
          relatedCalls++;
          return [
            _video('BVgame', typeId: 17, seconds: 300), // not music
            _video('BVshort', typeId: 193, seconds: 30), // under a minute
            _video('BVpick${seed.bvid}', typeId: 130, seconds: 240),
          ];
        },
      );
      expect(await recommender.today(), isNull, reason: 'no folder chosen');
      await recommender.setDefaultFolder(5, '我的收藏');
      final first = await recommender.today();
      expect(first!.map((a) => a.bvid).toSet(), {'BVpickBVseed50', 'BVpickBVseed51', 'BVpickBVseed52'});
      expect(relatedCalls, 3);
      expect((await recommender.today())!.length, 3);
      expect(relatedCalls, 3, reason: 'same day and folder: the stored list');
      now = DateTime(2026, 10, 2, 9);
      final next = await recommender.today();
      expect(next, isEmpty, reason: 'every related pick was recommended yesterday');
      await recommender.setDefaultFolder(6, 'other');
      expect((await recommender.today())!.length, 3);
      final reroll = await recommender.reroll(first);
      expect(reroll, isNull, reason: 'the only candidates were already recommended');
    });
  });

  group('audio cache', () {
    test('keys, commit, lookup, LRU trim with kept files, leftovers removed on load', () async {
      final files = _Files();
      var now = DateTime.utc(2026, 10);
      final cache = AudioCache(files, maxBytes: 250, now: () => now);
      final key = AudioCacheKey.of(bvid: 'BV1zKZrYAEi8', cid: 29153362694);
      expect(key, 'BV1zKZrYAEi8_29153362694');
      expect(AudioCacheKey.of(bvid: 'BV/../x', cid: 1, lossless: true), 'BVx_1_hires');

      Future<void> download(String key, int size) async {
        final part = cache.begin(key)!;
        files.data[part] = size;
        now = now.add(const Duration(minutes: 1));
        await cache.commit(key);
      }

      await download('a', 100);
      expect(cache.begin('a'), isNull, reason: 'already cached');
      await download('b', 100);
      expect(cache.lookup('a'), 'a.m4a');
      now = now.add(const Duration(minutes: 1));
      final part = cache.begin('c')!;
      files.data[part] = 100;
      final evicted = await cache.commit('c', keep: {'b'});
      expect(evicted, ['a'], reason: 'b is kept although it is older');
      expect(files.data.keys, unorderedEquals(['b.m4a', 'c.m4a']));
      expect(cache.usage.bytes, 200);

      final empty = cache.begin('d')!;
      files.data[empty] = 0;
      expect(await cache.commit('d'), isEmpty);
      expect(cache.lookup('d'), isNull);
      cache.begin('e');
      await cache.abort('e');
      expect(cache.isDownloading('e'), isFalse);

      files.data['x.m4a.part'] = 5;
      final reloaded = AudioCache(files, maxBytes: 250);
      await reloaded.load();
      expect(reloaded.keys, unorderedEquals(['b', 'c']));
      expect(files.data.containsKey('x.m4a.part'), isFalse);
    });
  });
}

final class _Files implements AudioCacheFiles {
  final Map<String, int> data = {};

  @override
  Future<List<CachedFile>> list() async => [
    for (final entry in data.entries) (name: entry.key, size: entry.value, modified: DateTime.utc(2026)),
  ];

  @override
  Future<int?> sizeOf(String name) async => data[name];

  @override
  Future<void> rename(String from, String to) async {
    final size = data.remove(from);
    if (size != null) data[to] = size;
  }

  @override
  Future<void> delete(String name) async => data.remove(name);
}
