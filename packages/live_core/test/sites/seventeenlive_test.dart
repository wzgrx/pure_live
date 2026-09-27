// 17LIVE parsing and the adapter over the recorded samples
// (spec/sites/17live.md). Legacy no longer runs (ADR 0016), so the
// expectations come from the sample bodies and the spec.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _live = '27484154';
const _offline = '28371376';

SeventeenliveSite _site(List<String> samples) =>
    SeventeenliveSite(ReplayHttp.fixtures('../../fixtures/17live', samples));

Object? _body(String sample) => jsonDecode(Fixture.load('17live', sample).body);

void main() {
  group('§2 sections', () {
    test('live broadcasts of every section but banners and archives, first appearance kept', () {
      final page = SeventeenliveParse.sectionsPage(Fixture.load('17live', 'S01-sections-jp').body);
      final sections = ((_body('S01-sections-jp')! as Map)['sections'] as List).cast<Map<String, dynamic>>();
      final expected = <String>[];
      for (final section in sections) {
        if (SeventeenliveParse.skippedSections.contains(section['id'])) continue;
        for (final grid in (section['grids'] as List? ?? const []).cast<Map<String, dynamic>>()) {
          final stream = grid['stream'] as Map<String, dynamic>?;
          if (stream == null || stream['status'] != 2) continue;
          final id = '${stream['liveStreamID']}';
          if (!expected.contains(id)) expected.add(id);
        }
      }
      expect(page.items.map((c) => c.ref.roomId), expected);
      expect(page.items.every((c) => c.state == LiveState.live), isTrue);
      expect(page.next, isNotNull);
      final card = page.items.first;
      expect(card.cover?.host, 'cdn.17app.co');
      expect(card.cover?.scheme, 'https');
      expect(card.avatar?.path, endsWith('.jpg'));
      expect(card.audience.online, isNotNull);
    });

    test('the next page ends the directory (archives only, empty cursor)', () {
      final first = SeventeenliveParse.sectionsPage(Fixture.load('17live', 'S01-sections-jp').body);
      final second = SeventeenliveParse.sectionsPage(
        Fixture.load('17live', 'S01-sections-jp-p2').body,
        cursor: first.next!.value,
      );
      expect(second.isLast, isTrue);
      expect(second.items.every((c) => c.state == LiveState.live), isTrue);
    });

    test('regions are separate directories', () {
      final tw = SeventeenliveParse.sectionsPage(Fixture.load('17live', 'S02-sections-tw').body);
      final jp = SeventeenliveParse.sectionsPage(Fixture.load('17live', 'S01-sections-jp').body);
      expect(tw.items, isNotEmpty);
      expect(
        tw.items.map((c) => c.ref.roomId).toSet().intersection(jp.items.map((c) => c.ref.roomId).toSet()),
        isEmpty,
      );
    });
  });

  test('§3 search: current broadcasts only', () {
    final found = SeventeenliveParse.searchPage(Fixture.load('17live', 'S03-search').body).items.single;
    expect(found.ref.roomId, _live);
    expect(found.followers, 2775);
    expect(SeventeenliveParse.searchPage(Fixture.load('17live', 'S03-search-none').body).items, isEmpty);
  });

  group('§4 detail', () {
    test('a live room: online and cumulative viewers, start time, bio', () {
      final detail = SeventeenliveParse.detail(Fixture.load('17live', 'S04-live-live').body, roomId: _live);
      final raw = _body('S04-live-live')! as Map<String, dynamic>;
      expect(detail.ref, RoomRef('17live', _live));
      expect(detail.state, LiveState.live);
      expect(detail.card.title, (raw['caption'] as String).trim());
      expect(detail.card.anchorName, (raw['userInfo'] as Map)['displayName']);
      expect(
        detail.card.audience,
        Audience(online: raw['liveViewerCount'] as int, cumulative: raw['viewerCount'] as int),
      );
      expect(detail.card.liveSince, DateTime.fromMillisecondsSinceEpoch((raw['beginTime'] as int) * 1000, isUtc: true));
      expect(detail.link, Uri.parse('https://17.live/ja/live/27484154'));
      expect(detail.introduction, isNotEmpty);
      expect(detail.danmakuKeys, {'roomId': _live});
    });

    test('offline rooms keep no figures; unknown rooms are NotFound; a foreign answer is an API change', () {
      final offline = SeventeenliveParse.detail(Fixture.load('17live', 'S04-live-offline').body, roomId: _offline);
      expect(offline.state, LiveState.offline);
      expect(offline.card.audience, Audience.none);
      expect(offline.danmakuKeys, isEmpty);
      final missing = Fixture.load('17live', 'S04-live-notfound');
      expect(missing.status, 520);
      expect(
        () => SeventeenliveParse.detail(missing.body, roomId: '999999999', status: missing.status),
        throwsA(isA<NotFound>()),
      );
      expect(
        () => SeventeenliveParse.detail(Fixture.load('17live', 'S04-live-live').body, roomId: _offline),
        throwsA(isA<ApiChanged>()),
      );
      expect(
        () => SeventeenliveParse.root('{"errorCode":7,"errorMessage":"invalid"}', what: 'x', status: 420),
        throwsA(isA<ApiChanged>()),
      );
    });
  });

  group('§5 streams', () {
    test('four qualities; H.264 by default; one line per provider in answer order over https', () {
      final set = SeventeenliveParse.streams(
        Fixture.load('17live', 'S04-live-live').body,
        roomId: _live,
        headers: SeventeenliveSite.mediaHeaders,
      );
      expect(set.qualities.map((q) => q.id), ['source', 'enhanced', 'hd', 'h264']);
      expect(set.selected.id, 'h264');
      expect(set.lines.map((l) => l.lineId), ['tencent', 'wansu']);
      expect(set.lines.every((l) => l.url.scheme == 'https' && l.url.path.endsWith('_h264.flv')), isTrue);
      expect(set.lines.first.codec, 'avc');
      expect(set.lines.first.format, StreamFormat.flv);
      expect(set.lines.first.headers['referer'], 'https://17.live/');
      final source = SeventeenliveParse.streams(
        Fixture.load('17live', 'S04-live-live').body,
        roomId: _live,
        headers: const {},
        wanted: 'source',
      );
      expect(source.lines.first.url.path, isNot(contains('_')));
      expect(source.lines.first.codec, isNull, reason: 'the broadcaster’s codec, possibly FLV codec 12');
    });

    test('an offline room has no stream', () {
      expect(
        () => SeventeenliveParse.streams(
          Fixture.load('17live', 'S04-live-offline').body,
          roomId: _offline,
          headers: const {},
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });
  });

  test('§1 links', () {
    for (final link in [
      'https://17.live/ja/live/27484154',
      'https://17.live/live/27484154',
      'https://www.17.live/zh-Hant/live/27484154',
      'https://17.live/ja/profile/r/27484154',
      '見てね https://17.live/ja/live/27484154 ！',
    ]) {
      expect(SeventeenliveParse.roomIdOf(link), _live, reason: link);
    }
    expect(SeventeenliveParse.roomIdOf('https://17.live/ja/profile/u/abc'), isNull);
    expect(SeventeenliveParse.roomIdOf('https://example.test/live/27484154'), isNull);
    expect(SeventeenliveParse.image('7C17FBBB.jpg'), Uri.parse('https://cdn.17app.co/7C17FBBB.jpg'));
    expect(SeventeenliveParse.image('http://evil.test/a.jpg'), isNull);
  });

  group('adapter over ReplayHttp', () {
    test('catalog: three regions, JP recommended with its cursor', () async {
      final site = _site(['S01-sections-jp', 'S01-sections-jp-p2', 'S02-sections-tw']);
      final areas = (await site.categories()).single.areas;
      expect(areas.map((a) => a.id), ['JP', 'TW', 'HK']);
      final first = await site.recommended();
      expect(first.items, isNotEmpty);
      expect((await site.recommended(cursor: first.next)).isLast, isTrue);
      expect((await site.areaRooms(areas[1])).items, isNotEmpty);
    });

    test('search by keyword, by room number and by link', () async {
      final site = _site(['S03-search', 'S04-live-live']);
      expect((await site.search('花音')).items.single.ref.roomId, _live);
      expect((await site.search(_live)).items.single.state, LiveState.live);
      expect((await site.search('https://17.live/ja/live/27484154')).items.single.ref.roomId, _live);
    });

    test('detail and streams', () async {
      final site = _site(['S04-live-live']);
      final detail = await site.detail(RoomRef('17live', _live));
      final set = await site.streams(
        detail,
        quality: const Quality(id: 'hd', label: '高清', rank: 0),
      );
      expect(set.selected.id, 'hd');
      expect(await site.resolve('https://17.live/ja/live/27484154'), RoomRef('17live', _live));
    });
  });
}
