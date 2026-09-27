// v4 Douyu parsing against the recorded samples, compared with the legacy
// parser's frozen output. Deviations the spec requires are asserted explicitly.
import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  test('S01 categories match legacy ids, names and area icons', () {
    final fixture = Fixture.load('douyu', 'S01-cate-list');
    final categories = DouyuParse.categories(fixture.body);
    final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
    expect(categories.map((c) => c.id), legacy.map((c) => c['id']));
    expect(categories.map((c) => c.name), legacy.map((c) => c['name']));
    for (final (index, category) in categories.indexed) {
      final areas = (legacy[index]['children'] as List).cast<Map<String, dynamic>>();
      expect(category.areas.map((a) => a.id), areas.map((a) => a['areaId']));
      expect(category.areas.map((a) => a.name), areas.map((a) => a['areaName']));
      expect(category.areas.map((a) => a.icon?.toString()), areas.map((a) => _blankToNull(a['areaPic'])));
    }
  });

  void expectCardsMatchLegacy(List<RoomCard> rooms, List<Map<String, dynamic>> legacy) {
    expect(rooms.map((r) => r.ref.roomId), legacy.map((r) => r['roomId']));
    expect(rooms.map((r) => r.title), legacy.map((r) => decodeHtmlEntities(r['title'] as String)));
    expect(rooms.map((r) => r.anchorName), legacy.map((r) => r['nick']));
    expect(rooms.map((r) => r.cover?.toString()), legacy.map((r) => r['cover']));
    expect(rooms.map((r) => r.audience.popularity), legacy.map((r) => parseChineseCount(r['popularity'])));
  }

  group('S02/S03 room lists', () {
    for (final (sample, page) in [
      ('S02-mixlist-page1', 1),
      ('S02-mixlist-last', 6),
      ('S02-mixlist-beyond', 7),
      ('S03-allpage-page1', 1),
      ('S03-allpage-last', 218),
      ('S03-allpage-beyond', 1000),
    ]) {
      test(sample, () {
        final fixture = Fixture.load('douyu', sample);
        final result = DouyuParse.roomListPage(fixture.body, page: page);
        expectCardsMatchLegacy(result.items, (fixture.legacy as List).cast());
        expect(result.items.every((r) => r.state == LiveState.live), isTrue);
        // Ends on an empty page or at pgcnt (mixList has 6 pages), never by count.
        final expectLast = sample.endsWith('beyond') || sample == 'S02-mixlist-last';
        expect(result.isLast, expectLast, reason: 'page $page');
      });
    }
  });

  group('S04 search', () {
    for (final sample in ['S04-search-page1', 'S04-search-page2', 'S04-search-mixed', 'S04-search-empty']) {
      test(sample, () {
        final fixture = Fixture.load('douyu', sample);
        final page = int.parse(fixture.url.queryParameters['page']!);
        final result = DouyuParse.searchPage(fixture.body, page: page);
        final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
        expect(result.items.map((r) => r.ref.roomId), legacy.map((r) => r['roomId']));
        expect(result.items.map((r) => r.title), legacy.map((r) => decodeHtmlEntities(r['title'] as String)));
        expect(result.items.map((r) => r.audience.popularity), legacy.map((r) => parseChineseCount(r['popularity'])));
        for (final (index, room) in result.items.indexed) {
          // Legacy marks roomType 3 loop rooms offline; the spec calls them replay.
          final legacyLive = legacy[index]['status'] == true;
          expect(room.state == LiveState.live, legacyLive, reason: room.ref.key);
        }
        expect(result.isLast, legacy.isEmpty);
      });
    }

    test('S04 error responses are typed, legacy threw', () {
      for (final sample in ['S04-search-error-kw', 'S04-search-error-blank']) {
        final fixture = Fixture.load('douyu', sample);
        expect(() => DouyuParse.searchPage(fixture.body, page: 1), throwsA(isA<ApiChanged>()), reason: sample);
      }
    });

    test('S04 loop rooms (roomType 3) are replay, not offline', () {
      final fixture = Fixture.load('douyu', 'S04-search-mixed');
      final states = DouyuParse.searchPage(fixture.body, page: 1).items.map((r) => r.state).toSet();
      expect(states, containsAll([LiveState.live, LiveState.replay]));
    });
  });

  group('S05 room detail', () {
    for (final sample in ['S05-live', 'S05-offline', 'S05-replay-videoloop']) {
      test(sample, () {
        final fixture = Fixture.load('douyu', sample);
        final detail = DouyuParse.detail(fixture.body, status: fixture.status);
        final legacy = (fixture.legacy as Map<String, dynamic>)['room'] as Map<String, dynamic>;
        expect(detail.ref.roomId, legacy['roomId']);
        expect(detail.card.title, decodeHtmlEntities(legacy['title'] as String));
        expect(detail.card.anchorName, legacy['nick']);
        expect(detail.card.cover?.toString(), legacy['cover']);
        expect(detail.avatar?.toString(), legacy['avatar']);
        expect(detail.card.area, legacy['area']);
        expect(detail.card.audience.popularity, parseChineseCount(legacy['popularity']));
        expect(detail.state == LiveState.live, legacy['status'] == true);
        expect(detail.state == LiveState.replay, legacy['isRecord'] == true);
        expect(detail.danmakuKeys, {'rid': legacy['roomId']});
        // Legacy leaves HTML entities in the introduction (&mdash;); v4 decodes.
        final introduction = _blankToNull(legacy['introduction']);
        expect(detail.introduction, introduction == null ? null : decodeHtmlEntities(introduction));
      });
    }

    test('S05 a room that does not exist is NotFound (legacy threw FormatException)', () {
      final fixture = Fixture.load('douyu', 'S05-not-found');
      expect(((fixture.legacy as Map<String, dynamic>)['throws'] as Map<String, dynamic>)['type'], 'FormatException');
      expect(() => DouyuParse.detail(fixture.body, status: fixture.status), throwsA(isA<NotFound>()));
    });

    test('S05 an alias sent to betard is refused with 403', () {
      final fixture = Fixture.load('douyu', 'S05-alias-betard');
      expect(() => DouyuParse.detail(fixture.body, status: fixture.status), throwsA(isA<RiskControl>()));
    });
  });

  group('S08/S09 play responses', () {
    for (final sample in ['S08-meta-4489985', 'S08-meta-24422']) {
      test('$sample qualities, CDNs and URL match legacy', () {
        final fixture = Fixture.load('douyu', sample);
        final data = DouyuParse.playData(fixture.body, status: fixture.status);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final qualities = (legacy['parsePlayQualities'] as List).cast<Map<String, dynamic>>();
        expect(DouyuParse.qualities(data).map((q) => q.id), qualities.map((q) => '${q['rate']}'));
        expect(DouyuParse.qualities(data).map((q) => q.label), qualities.map((q) => q['quality']));
        expect(DouyuParse.cdns(data), legacy['parseCdnCodes']);
        expect(DouyuParse.mediaUrl(data)?.toString(), legacy['parsePlayUrl']);
      });
    }

    for (final sample in [
      'S09-4489985-r0-hw-h5',
      'S09-24422-r0-hw-h5',
      'S09-24422-r0-hs-h5',
      'S09-24422-r2-hw-h5',
      'S09-24422-r0-tct-h5',
    ]) {
      test('$sample confirmed rate, URL and lease', () {
        final fixture = Fixture.load('douyu', sample);
        final data = DouyuParse.playData(fixture.body, status: fixture.status);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final url = DouyuParse.mediaUrl(data)!;
        expect(url.toString(), legacy['parsePlayUrl']);
        final resolved = legacy['resolvePlayUrl'] as Map<String, dynamic>;
        expect(DouyuParse.confirmedRate(data), '${resolved['appliedQualityData']}');
        final lease = DouyuParse.lease(url, fixture.capturedAt);
        final expire = int.parse(url.queryParameters['expire'] ?? '0');
        if (expire > 0) {
          expect(lease!.cutsConnection, isTrue);
          expect(lease.expiresAt!.difference(fixture.capturedAt), Duration(seconds: expire));
          expect(lease.expiresAt!.difference(lease.refreshAt), Duration(seconds: expire >= 180 ? 45 : expire ~/ 4));
        } else {
          expect(lease, isNull);
        }
      });
    }

    test('S10 offline room is StreamUnavailable; the did mismatch 403 is RiskControl', () {
      final offline = Fixture.load('douyu', 'S10-offline');
      expect(() => DouyuParse.playData(offline.body, status: offline.status), throwsA(isA<StreamUnavailable>()));
      final wrongDid = Fixture.load('douyu', 'S10-wrong-did');
      expect(() => DouyuParse.playData(wrongDid.body, status: wrongDid.status), throwsA(isA<RiskControl>()));
    });
  });

  group('rules without samples', () {
    test('confirmed rate rejects fractions, negatives and text', () {
      for (final value in [1.5, -1, 'x', null]) {
        expect(DouyuParse.confirmedRate({'rate': value}), isNull, reason: '$value');
      }
      expect(DouyuParse.confirmedRate({'rate': '0'}), '0');
      expect(DouyuParse.confirmedRate({'rate': 4}), '4');
    });

    test('CDN list: current CDN first, scdn last, empty means server choice', () {
      expect(
        DouyuParse.cdns({
          'rtmp_cdn': 'ws-h5',
          'cdnsWithName': [
            {'cdn': 'scdnctshh'},
            {'cdn': 'hw-h5'},
            {'cdn': 'hw-h5'},
          ],
        }),
        ['ws-h5', 'hw-h5', 'scdnctshh'],
      );
      expect(DouyuParse.cdns(const {}), ['']);
    });

    test('media URL: absolute rtmp_live wins; a bare CDN base is never media', () {
      expect(DouyuParse.mediaUrl({'rtmp_live': 'https://a.test/x.flv?x=1&amp;y=2'})!.queryParameters['y'], '2');
      expect(
        DouyuParse.mediaUrl({'rtmp_url': 'https://a.test/live/', 'rtmp_live': '/r.flv'}).toString(),
        'https://a.test/live/r.flv',
      );
      expect(DouyuParse.mediaUrl({'flv_url': 'https://a.test/live'}), isNull);
    });
  });
}

/// Legacy writes a missing field as '' (or 'null'); v4 uses null.
String? _blankToNull(Object? value) => value == null || value == '' || value == 'null' ? null : value as String;
