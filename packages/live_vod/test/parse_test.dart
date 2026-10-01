// The parsers over the samples recorded on 2026-10-01 (anonymous, read
// only): catalogs, detail, streams, comments, account errors, search, PGC,
// danmaku and the third-party answers.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_vod/live_vod.dart';
import 'package:test/test.dart';

import 'fixture.dart';

T _parse<T>(String sample, T Function(String body, int status) parse) {
  final fixture = Fixture.load(sample);
  return parse(fixture.body, fixture.status);
}

void main() {
  group('catalogs', () {
    test('popular: 20 archives with owner, cover and counters, more pages', () {
      final page = _parse('V01-popular', (b, s) => VodParse.popular(b, status: s));
      expect(page.items, hasLength(20));
      expect(page.hasMore, isTrue);
      final first = page.items.first;
      expect(first.bvid, startsWith('BV'));
      expect(first.cover, startsWith('http'));
      expect(first.owner.mid, greaterThan(0));
      expect(first.stat.views, greaterThan(0));
      expect(first.duration, greaterThan(Duration.zero));
    });

    test('music ranking and related keep the partition id the daily list filters on', () {
      final ranking = _parse('V02-ranking-music', (b, s) => VodParse.ranking(b, status: s));
      expect(ranking, hasLength(10));
      expect(ranking.first.typeId, 31);
      final related = _parse('V06-related', (b, s) => VodParse.related(b, status: s));
      expect(related, hasLength(10));
      expect(related.first.typeId, 193);
      expect(related.first.typeName, 'MV');
    });

    test('home feed keeps videos only', () {
      final feed = _parse('V03-rcmd', (b, s) => VodParse.recommended(b, status: s));
      expect(feed, isNotEmpty);
      expect(feed.every((archive) => archive.bvid.startsWith('BV') && archive.cid > 0), isTrue);
    });

    test('view: every part with its cid; the retired region feed is NotFound', () {
      final archive = _parse('V05-view', (b, s) => VodParse.view(b, status: s));
      expect(archive.bvid, 'BV1zKZrYAEi8');
      expect(archive.parts.map((part) => part.cid), [29153362694, 29185216423]);
      expect(archive.parts.last.title, '现场版录像片段');
      expect(archive.parts.last.duration, const Duration(seconds: 19));
      expect(archive.typeId, 59);
      expect(archive.typeName, isEmpty, reason: 'view sends an empty tname now');
      expect(archive.cid, 29153362694);
      expect(VodArchive.fromJson(archive.toJson()).parts, hasLength(2));
      expect(() => _parse('V04-region-retired', (b, s) => VodParse.ranking(b, status: s)), throwsA(isA<NotFound>()));
    });
  });

  group('streams', () {
    final headers = {'user-agent': BilibiliApi.userAgent, 'referer': 'https://www.bilibili.com/video/BV1zKZrYAEi8/'};

    test('DASH: qualities, renditions best first, AVC preferred, best audio, expiry from deadline', () {
      final streams = _parse('V08-playurl-dash', (b, s) => VodParse.streams(b, headers: headers, status: s));
      expect(streams.isDash, isTrue);
      expect(streams.quality, 32);
      expect(streams.qualities.map((q) => q.qn), [32, 16]);
      expect(streams.videos.map((v) => v.id), [32, 32, 32, 16, 16, 16]);
      final video = streams.videoFor(80)!;
      expect(video.id, 32, reason: 'the best quality at or below the request');
      expect(video.codec, 'avc');
      expect(streams.videoFor(16, codecs: const ['av1'])!.codec, 'av1');
      final audio = streams.bestAudio()!;
      expect(audio.id, 30232);
      expect(audio.codec, 'aac');
      expect(audio.backupUrls, hasLength(2));
      expect(streams.expiresAt, isNotNull);
      final lines = streams.linesOf(video);
      expect(lines, hasLength(3));
      expect(lines.first.headers['referer'], contains('BV1zKZrYAEi8'));
      expect(lines.first.lineId, startsWith('bdbv@'));
      expect(lines.first.lease!.expiresAt, streams.expiresAt);
    });

    test('muxed MP4: one durl segment', () {
      final streams = _parse('V09-playurl-mp4', (b, s) => VodParse.streams(b, headers: headers, status: s));
      expect(streams.isDash, isFalse);
      expect(streams.segments, hasLength(1));
      expect(streams.segments.single.length, const Duration(milliseconds: 40844));
      expect(streams.linesOfSegment(streams.segments.single).single.url, startsWith('https://'));
    });

    test('the signed playurl answered guests with the 412 page', () {
      expect(
        () => _parse('V07-playurl-wbi-412', (b, s) => VodParse.streams(b, headers: headers, status: s)),
        throwsA(isA<RateLimited>()),
      );
    });

    test('PGC: a free episode is DASH, a member-only one a marked 3-minute preview', () {
      final free = _parse('P05-playurl-free', (b, s) => VodParse.streams(b, headers: headers, status: s));
      expect(free.isDash, isTrue);
      expect(free.isPreview, isFalse);
      expect(free.needsVip, isFalse);
      expect(free.qualities.first.qn, 120);
      final vip = _parse('P06-playurl-vip', (b, s) => VodParse.streams(b, headers: headers, status: s));
      expect(vip.isPreview, isTrue);
      expect(vip.needsVip, isTrue);
      expect(vip.segments.single.length, const Duration(milliseconds: 180179));
      expect(vip.duration, const Duration(milliseconds: 1425214));
      expect(vip.qualities.first.needsVip, isTrue);
    });
  });

  group('player, comments, account', () {
    test('player info: no subtitles for guests, the BGM and its title', () {
      final info = _parse('V10-player-v2', (b, s) => VodParse.playerInfo(b, status: s));
      expect(info.subtitles, isEmpty);
      expect(info.bgmMusicId, 'MA409252858597271902');
      expect(info.bgmTitle, '阳光彩虹小白马');
    });

    test('comments: guests get the first hot comments and no next offset', () {
      final page = _parse('V12-reply-p1', (b, s) => VodParse.comments(b, status: s));
      expect(page.comments, hasLength(3));
      expect(page.pinned, hasLength(1));
      expect(page.pinned.single.pinned, isTrue);
      expect(page.total, 4461);
      expect(page.isEnd, isTrue);
      expect(page.nextOffset, isNull);
      final first = page.comments.first;
      expect(first.rpid, 259374509376);
      expect(first.user.name, '无迹可寻owa');
      expect(first.replyCount, 4);
      expect(first.createdAt, DateTime.utc(2025, 4, 2, 15, 19, 12));
    });

    test('next_offset is read when the cursor has one', () {
      const body =
          '{"code":0,"data":{"cursor":{"is_end":false,"all_count":9,'
          r'"pagination_reply":{"next_offset":"{\"type\":1,\"data\":{\"cursor\":42}}"}},"replies":[]}}';
      final page = VodParse.comments(body);
      expect(page.isEnd, isFalse);
      expect(page.nextOffset, '{"type":1,"data":{"cursor":42}}');
    });

    test('replies page', () {
      final page = _parse('V14-reply-reply', (b, s) => VodParse.replies(b, status: s));
      expect(page.items, hasLength(4));
      expect(page.hasMore, isFalse);
      expect(page.items.first.text, '绷不住了哈哈');
    });

    test('guest answers: login-only lists, the signed space reads, empty collections', () {
      expect(() => _parse('V15-dynamic-guest', (b, s) => VodParse.dynamics(b, status: s)), throwsA(isA<NeedsLogin>()));
      expect(() => _parse('V21-history-guest', (b, s) => VodParse.history(b, status: s)), throwsA(isA<NeedsLogin>()));
      expect(
        () => _parse('V16-space-acc-352', (b, s) => VodParse.userSpace(b, infoStatus: s)),
        throwsA(isA<RiskControl>()),
      );
      expect(() => _parse('V17-space-arc-352', (b, s) => VodParse.uploads(b, status: s)), throwsA(isA<RiskControl>()));
      final collections = _parse('V18-space-seasons', (b, s) => VodParse.collections(b, mid: 28454359, status: s));
      expect(collections.items, isEmpty);
      final stat = _parse('V20-relation-stat', (b, s) => VodParse.relationStat(b, status: s));
      expect(stat.followers, 55318);
    });
  });

  group('search', () {
    test('videos: highlights removed, clock durations, partition names', () {
      final page = _parse('V23-search-video', (b, s) => VodParse.searchVideos(b, status: s));
      expect(page.items, hasLength(9), reason: 'the fifth row is a paid course (type ketang)');
      final first = page.items.first;
      expect(first.title, isNot(contains('<em')));
      expect(first.title, contains('晴天'));
      expect(first.duration, const Duration(minutes: 4, seconds: 30));
      expect(first.typeName, '音乐综合');
      expect(first.cover, startsWith('https://'));
      expect(page.hasMore, isTrue);
    });

    test('users, empty season search, hotwords, suggestions', () {
      final users = _parse('V24-search-user', (b, s) => VodParse.searchUsers(b, status: s));
      expect(users.items.first.owner.name, '杰威尔音乐');
      expect(users.items.first.liveRoomId, 25932192);
      expect(_parse('V25-search-bangumi', (b, s) => VodParse.searchSeasons(b, status: s)).items, isEmpty);
      final hotwords = _parse('V26-hotwords', (b, s) => VodParse.hotwords(b, status: s));
      expect(hotwords, hasLength(10));
      expect(hotwords.first.keyword, isNotEmpty);
      final suggestions = VodParse.suggestions(Fixture.load('V27-suggest').body);
      expect(suggestions.first, '晴天');
      expect(VodParse.suggestions('not json'), isEmpty);
    });
  });

  group('PGC', () {
    test('timeline days and releases', () {
      final days = _parse('P01-timeline', (b, s) => VodParse.timeline(b, status: s));
      expect(days, hasLength(13));
      expect(days.where((day) => day.isToday), hasLength(1));
      final entry = days.first.episodes.first;
      expect(entry.seasonId, 298872);
      expect(entry.index, '第1话~第4话');
      expect(entry.releasedAt, isNotNull);
    });

    test('index cards mark member-only seasons', () {
      final page = _parse('P02-index', (b, s) => VodParse.index(b, status: s));
      expect(page.items, hasLength(20));
      expect(page.hasMore, isTrue);
      final first = page.items.first;
      expect(first.seasonId, 47836);
      expect(first.firstEpId, 826497);
      expect(first.needsVip, isTrue);
      expect(first.score, '9.7');
    });

    test('season: episodes with status and skip ranges', () {
      final season = _parse('P04-season', (b, s) => VodParse.season(b, status: s));
      expect(season.seasonId, 47836);
      expect(season.title, '鬼灭之刃 柱训练篇');
      expect(season.episodes, hasLength(8));
      expect(season.score, 9.7);
      expect(season.styles, isNotEmpty);
      final free = season.episodes.first;
      final member = season.episodes[1];
      expect(free.needsVip, isFalse);
      expect(member.epId, 826498);
      expect(member.needsVip, isTrue);
      expect(member.duration, const Duration(seconds: 1426));
      expect(season.paymentTip, contains('大会员'));
    });
  });

  group('danmaku', () {
    test('view gives the segment count; segments and XML parse sorted', () {
      final view = VodDanmakuParse.view(Fixture.load('D01-dm-view').bytes);
      expect(view.segments, 1);
      expect(view.segmentLength, const Duration(minutes: 6));
      expect(VodDanmakuParse.view(const [], duration: const Duration(minutes: 13)).segments, 3);
      final segment = VodDanmakuParse.segment(Fixture.load('D02-dm-seg').bytes);
      expect(segment, hasLength(60));
      expect(segment.every((d) => d.text.isNotEmpty && d.id.isNotEmpty), isTrue);
      for (var i = 1; i < segment.length; i++) {
        expect(segment[i].progress >= segment[i - 1].progress, isTrue);
      }
      final xml = VodDanmakuParse.xml(Fixture.load('D03-dm-xml').body);
      expect(xml, isNotEmpty);
      expect(xml.every((d) => d.text.isNotEmpty), isTrue);
    });

    test('an unknown string field inside an element does not shift the rest (TV bug)', () {
      // elem: 2 progress=1500, 6 midHash="abcdef12", 7 content="hi", 3 mode=1
      final elem = [0x10, 0xDC, 0x0B, 0x32, 8, ...'abcdef12'.codeUnits, 0x3A, 2, 0x68, 0x69, 0x18, 1];
      final bytes = [0x0A, elem.length, ...elem];
      final parsed = VodDanmakuParse.segment(bytes);
      expect(parsed.single.text, 'hi');
      expect(parsed.single.progress, const Duration(milliseconds: 1500));
      expect(VodDanmakuParse.segment([...bytes, 0x0A, 9, 1]).single.text, 'hi', reason: 'a truncated tail is dropped');
    });
  });

  group('third parties', () {
    test('NetEase and KuGou playlists (KuGou names are artist first)', () {
      final netease = PlaylistImportSource.neteaseTracks(
        jsonDecode(Fixture.load('T01-netease-playlist').body) as Map<String, dynamic>,
      );
      expect(netease, hasLength(10));
      expect(netease.first.name, '九月底');
      expect(netease.first.artist, '余佳运');
      expect(netease.first.duration, const Duration(milliseconds: 257272));
      final kugouJson = jsonDecode(Fixture.load('T02-kugou-playlist').body) as Map<String, dynamic>;
      final kugou = PlaylistImportSource.kugouTracks(kugouJson['data'] as Map<String, dynamic>);
      expect(kugou.first.name, '断了的弦');
      expect(kugou.first.artist, '周杰伦');
      expect(kugou.first.duration, const Duration(milliseconds: 297560));
    });

    test('rangotec candidates parse with their start-end stamps', () {
      final candidates = ThirdPartyLyrics.rangotecCandidates(Fixture.load('T03-rangotec').body);
      expect(candidates, hasLength(3));
      expect(candidates.first.title, '晴天');
      final document = Lrc.parse(candidates.first.lrc);
      expect(document.lines.first.start, Duration.zero);
      expect(document.lines.first.end, const Duration(seconds: 4, milliseconds: 770));
      expect(document.lines[1].start, const Duration(seconds: 4, milliseconds: 772));
      expect(LyricLookup.accept('晴天', candidates.first), isNotNull);
    });

    test('lrc.cx and the BGM lyric file', () {
      final lrccx = Lrc.parse(Fixture.load('T04-lrccx').body);
      expect(lrccx.lines.first.start, const Duration(seconds: 29, milliseconds: 188));
      final bgm = Lrc.parse(Fixture.load('M02-bgm-lyric').body);
      expect(bgm.title, '阳光彩虹小白马');
      expect(bgm.artist, '大张伟');
      expect(bgm.isEmpty, isFalse);
    });
  });
}
