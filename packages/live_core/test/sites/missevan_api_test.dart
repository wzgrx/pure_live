// Missevan parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/missevan/legacy_expected.dart from 3.x's MissevanApi and
// MissevanSite). Every intended difference is listed with its reason;
// everything else must match. The synthetic cases port 3.x's
// missevan_adapter_test.dart.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('missevan', name);

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences). 3.x wrote null where
/// the immutable model writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
}

/// 3.x's room projection: toJson plus `link`.
Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

Map<String, dynamic> _legacy(String name) => _sample(name).legacy as Map<String, dynamic>;

List<Map<String, dynamic>> _maps(Object? value) => (value! as List).cast<Map<String, dynamic>>();

String _ok(Object? info) => jsonEncode({'code': 0, 'info': info});

/// The recorded `info` of [name].
Map<String, dynamic> _info(String name) =>
    (jsonDecode(_sample(name).body) as Map<String, dynamic>)['info'] as Map<String, dynamic>;

const _hls = 'http://d1-missevan104.bilivideo.com/live/sample.m3u8?expires=1900000000&sign=fixture%2Bonly';
const _flv = 'http://d1-missevan04.bilivideo.com/live/sample.flv?expires=1900000000&sign=fixture';

/// 3.x's test row.
Map<String, dynamic> _row(int id, {int open = 1}) => {
  'room_id': id,
  'creator_id': 200,
  'creator_username': 'Fixture',
  'name': '音频测试',
  'cover_url': 'https://static.maoercdn.com/fixture.png',
  'creator_iconurl': '//static.maoercdn.com/avatar.png',
  'status': {'open': open, 'broadcasting': false},
  'statistics': {'score': 321, 'online': 0, 'accumulation': 9000, 'attention_count': 12},
  'channel': {'hls_pull_url': _hls, 'flv_pull_url': _flv},
};

/// 3.x's test detail.
Map<String, dynamic> _detail({int id = 100, int open = 1}) => {
  'room': _row(id, open: open),
  'creator': {'user_id': 200, 'iconurl': 'https://static.maoercdn.com/avatar.png', 'introduction': 'fixture'},
};

/// 3.x's test page of [count] rooms.
Map<String, dynamic> _page(int p, {int count = 65}) => {
  'pagination': <String, Object?>{'p': p, 'pagesize': 20, 'maxpage': (count + 19) ~/ 20, 'count': count},
  'Datas': [for (var i = (p - 1) * 20; i < p * 20 && i < count; i++) _row(i + 1)],
};

void main() {
  group('S01 catalog', () {
    final meta = _sample('S01-meta');

    test('3.x failed on the 团播 tab; the areas it knew match, 团播 joins them in place (REG-MISSEVAN-005)', () {
      final legacy = _legacy('S01-meta');
      expect(legacy['getCategores'], {'throws': 'MissevanException', 'message': 'Missevan schema'});
      final categories = MissevanApi.categories(meta.body, status: meta.status);
      final known = _maps(legacy['getCategoresWithoutListTab']).single;
      final category = categories.single;
      expect((category.id, category.name), (known['id'], known['name']));
      final areas = category.children.where((area) => area.areaType != 'list').toList();
      final legacyAreas = _maps(known['children']);
      expect(areas, hasLength(legacyAreas.length));
      for (final (index, area) in areas.indexed) {
        _expectParity(area.toJson(), legacyAreas[index], reason: 'S01[$index]');
      }
      expect(category.children.map((area) => '${area.areaType}:${area.areaId}:${area.areaName}'), [
        'catalog:105:配音',
        'catalog:104:音乐',
        'catalog:116:情感',
        'list:4:团播',
        'tag:1:新星',
        'catalog:115:放松',
        'catalog:122:古风',
      ]);
      final team = category.children[3];
      expect(team.typeName, '猫耳 FM');
      expect(team.areaPic, 'https://static.maoercdn.com/live/catalog/icon/tuanbo.png');
    });

    test('a catalog and a tag with the same number are different areas (REG-MISSEVAN-003)', () {
      const catalog = LiveArea(platform: 'missevan', areaType: 'catalog', areaId: '104');
      const tag = LiveArea(platform: 'missevan', areaType: 'tag', areaId: '104');
      const team = LiveArea(platform: 'missevan', areaType: 'list', areaId: '104');
      expect(catalog.hasSameIdentity(tag), isFalse);
      expect(catalog.hasSameIdentity(team), isFalse);
      expect(MissevanApi.areaQuery(catalog), {'catalog_id': '104'});
      expect(MissevanApi.areaQuery(tag), {'tag_id': '104'});
      expect(MissevanApi.areaQuery(team), {'type': '104'});
      final restored = LiveArea.fromJson(const {'platform': 'missevan', 'areaType': 'tag', 'areaId': '1'});
      expect(MissevanApi.areaQuery(restored), {'tag_id': '1'});
    });

    test("another platform's area, an unknown namespace or a bad id is a caller error (3.x)", () {
      for (final area in [
        const LiveArea(platform: 'other', areaType: 'catalog', areaId: '1'),
        const LiveArea(areaType: 'catalog', areaId: '1'),
        const LiveArea(platform: 'missevan', areaType: 'future', areaId: '1'),
        const LiveArea(platform: 'missevan', areaType: 'tag', areaId: '../1'),
        const LiveArea(platform: 'missevan', areaType: 'tag', areaId: '01'),
        const LiveArea(platform: 'missevan', areaType: 'tag'),
      ]) {
        expect(() => MissevanApi.areaQuery(area), throwsArgumentError, reason: '$area ${area.areaType}');
      }
    });

    test('other unknown tab types are skipped; a broken known tab still fails the catalog (3.x)', () {
      final mixed = _ok({
        'tabs': [
          {'type': 'future', 'future_id': 9, 'name': 'x'},
          {'type': 'catalog', 'catalog_id': 1, 'name': '音乐'},
          {'type': 'tag', 'tag_id': '1', 'name': '新星'},
        ],
      });
      expect(MissevanApi.categories(mixed).single.children.map((area) => (area.areaType, area.areaId)), [
        ('catalog', '1'),
        ('tag', '1'),
      ]);
      for (final tabs in <Object?>[
        <Object?>[],
        null,
        'tabs',
        [
          {'type': 'unknown', 'unknown_id': 1, 'name': 'x'},
        ],
        [
          {'type': 'catalog', 'catalog_id': 1, 'name': 'x'},
          {'type': 'catalog', 'catalog_id': 1, 'name': 'y'},
        ],
        [
          {'type': 'catalog', 'catalog_id': 0, 'name': 'x'},
        ],
        [
          {'type': 'tag', 'tag_id': 2, 'name': ' '},
        ],
        [
          {'type': 'list', 'list_id': 4, 'name': '团播'},
        ],
        ['not a tab'],
      ]) {
        expect(() => MissevanApi.categories(_ok({'tabs': tabs})), throwsA(isA<ApiChanged>()), reason: '$tabs');
      }
    });
  });

  group('S02 directory pages', () {
    for (final (name, page) in [
      ('S02-list-p1', 1),
      ('S02-list-last', 29),
      ('S02-list-beyond', 30),
      ('S02-list-catalog', 1),
      ('S02-list-tag', 1),
    ]) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final result = MissevanApi.directoryPage(fixture.body, page: page, status: fixture.status);
        final legacy = _legacy(name)['getDirectoryPage'] as Map<String, dynamic>;
        expect((result.page, result.hasMore), (legacy['page'], legacy['hasMore']));
        final rooms = _maps(legacy['rooms']);
        expect(result.rooms.map((room) => room.roomId), rooms.map((room) => room['roomId']));
        for (final (index, room) in result.rooms.indexed) {
          _expectParity(_projection(room), rooms[index], reason: '$name[$index]');
          expect(room.isLiveNow, isTrue);
          expect(room.data, isNull, reason: 'list cards carry no pull URLs');
        }
      });
    }

    test('S02-list-team: 3.x refused the list namespace; its page parses like any other', () {
      expect(_legacy('S02-list-team')['getDirectoryPage'], {
        'throws': 'MissevanException',
        'message': 'Missevan schema',
      });
      final fixture = _sample('S02-list-team');
      expect(fixture.url.queryParameters, {'p': '1', 'type': '4'});
      final result = MissevanApi.directoryPage(fixture.body, page: 1);
      expect(result.rooms, hasLength(20));
      expect(result.hasMore, isTrue);
      final rows = _maps(_info('S02-list-team')['Datas']);
      expect(
        rows.every((row) => (row['status'] as Map<String, dynamic>)['open_mode'] == 1),
        isTrue,
        reason: 'team broadcasts only',
      );
    });

    test('rows past pagesize are kept; pages go by number and end at maxpage (REG-MISSEVAN-001)', () {
      final first = MissevanApi.directoryPage(_sample('S02-list-p1').body, page: 1);
      expect(first.rooms, hasLength(22), reason: 'pagesize 20, 22 rows (promoted rooms)');
      expect(first.hasMore, isTrue);
      expect(MissevanApi.directoryPage(_sample('S02-list-last').body, page: 29).hasMore, isFalse);
      final beyond = MissevanApi.directoryPage(_sample('S02-list-beyond').body, page: 30);
      expect(beyond.rooms, isEmpty);
      expect(beyond.hasMore, isFalse);
      final info = _page(1)..['Datas'] = [for (var i = 1; i <= 22; i++) _row(i)];
      expect(MissevanApi.directoryPage(_ok(info), page: 1).rooms, hasLength(22));
    });

    test('offline rows are left out and repeated rows kept once; an all-offline page still has more (3.x)', () {
      final info = _page(1)..['Datas'] = [_row(1), _row(1), _row(2, open: 0), _row(3)];
      final page = MissevanApi.directoryPage(_ok(info), page: 1);
      expect(page.rooms.map((room) => room.roomId), ['1', '3']);
      final closed = _page(1, count: 21)..['Datas'] = [for (var i = 1; i <= 20; i++) _row(i, open: 0)];
      final empty = MissevanApi.directoryPage(_ok(closed), page: 1);
      expect(empty.rooms, isEmpty);
      expect(empty.hasMore, isTrue);
      expect(MissevanApi.directoryPage(_ok(_page(1, count: 0)), page: 1).rooms, isEmpty);
    });

    test('heat is the score, never viewers (REG-MISSEVAN-002)', () {
      final room = MissevanApi.directoryPage(_sample('S02-list-p1').body, page: 1).rooms.first;
      expect((room.popularity, room.watching), ('88900', '88900'));
      expect(room.effectiveAudienceMetricType, AudienceMetricType.popularity);
      expect(room.effectiveOnlineViewers, isEmpty, reason: 'statistics.online is always 0');
      expect(room.supportsRealOnlineCount, isFalse);
      expect(room.audienceValue(preferRealOnline: true, platformEnabled: true), '88900');
    });

    test('a page that does not echo its request is ApiChanged, not a short page (3.x)', () {
      for (final change in <Map<String, Object?>>[
        {'p': 2},
        {'pagesize': 30},
        {'maxpage': -1},
        {'maxpage': null},
        {'count': -1},
      ]) {
        final info = _page(1);
        (info['pagination']! as Map<String, Object?>).addAll(change);
        expect(() => MissevanApi.directoryPage(_ok(info), page: 1), throwsA(isA<ApiChanged>()), reason: '$change');
      }
      final many = _page(1)..['Datas'] = List.generate(101, (index) => _row(index + 1));
      expect(() => MissevanApi.directoryPage(_ok(many), page: 1), throwsA(isA<ApiChanged>()));
      final past = _page(4)..['pagination'] = {'p': 5, 'pagesize': 20, 'maxpage': 4, 'count': 65};
      expect(() => MissevanApi.directoryPage(_ok(past), page: 5), throwsA(isA<ApiChanged>()));
      expect(
        () => MissevanApi.directoryPage(_ok({'pagination': _page(1)['pagination']}), page: 1),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('a row without a valid state, score, room or creator id fails the page (3.x)', () {
      for (final edit in <void Function(Map<String, dynamic>)>[
        (row) => row['status'] = {'open': null},
        (row) => row['status'] = {'open': 2},
        (row) => row['status'] = {'open': true},
        (row) => row['status'] = {'open': 'invalid'},
        (row) => row['status'] = null,
        (row) => row['statistics'] = {'score': -1},
        (row) => row['statistics'] = null,
        (row) => row['room_id'] = '0100',
        (row) => row['creator_id'] = null,
      ]) {
        final row = _row(1);
        edit(row);
        final info = _page(1)..['Datas'] = [row];
        expect(() => MissevanApi.directoryPage(_ok(info), page: 1), throwsA(isA<ApiChanged>()), reason: '$row');
      }
      final text = _row(1)..['status'] = {'open': '1'};
      expect(MissevanApi.directoryPage(_ok(_page(1)..['Datas'] = [text]), page: 1).rooms, hasLength(1));
    });

    test('a card as 3.x built it: protocol-relative avatar made https, missing text empty', () {
      final row = _row(7)
        ..remove('name')
        ..['creator_introduction'] = '  介绍  '
        ..['announcement'] = '公告'
        ..['catalog_name'] = '音乐';
      final room = MissevanApi.directoryPage(_ok(_page(1)..['Datas'] = [row]), page: 1).rooms.single;
      expect(room.avatar, 'https://static.maoercdn.com/avatar.png');
      expect(room.title, '');
      expect((room.introduction, room.notice, room.area), ('介绍', '公告', '音乐'));
      expect(room.userId, '200');
      expect(room.link, 'https://fm.missevan.com/live/7');
      expect(room.followers, '0', reason: 'lists never read attention_count (3.x)');
    });
  });

  group('S03 search', () {
    for (final name in ['S03-search', 'S03-search-p2', 'S03-search-empty']) {
      test('$name matches 3.x', () {
        final fixture = _sample(name);
        final page = int.parse(fixture.url.queryParameters['p']!);
        final rooms = MissevanApi.searchRooms(fixture.body, page: page, pageSize: 20, status: fixture.status);
        final legacy = _maps(_legacy(name)['searchRooms']);
        expect(rooms.map((room) => room.roomId), legacy.map((room) => room['roomId']));
        for (final (index, room) in rooms.indexed) {
          _expectParity(_projection(room), legacy[index], reason: '$name[$index]');
        }
        expect(_legacy(name)['supportsSearchPaginationFor'], isTrue);
      });
    }

    test('live and offline rooms both come back', () {
      final rooms = MissevanApi.searchRooms(_sample('S03-search').body, page: 1, pageSize: 20);
      expect(rooms.where((room) => room.isLiveNow), hasLength(5));
      expect(rooms.where((room) => room.isExplicitlyOfflineNow), hasLength(15));
    });

    test('the page must echo the page and its size (3.x)', () {
      final body = _ok({
        'data': [_row(100)],
        'pagination': {'p': 99, 'pagesize': 20, 'maxpage': 1, 'count': 1},
      });
      expect(() => MissevanApi.searchRooms(body, page: 1, pageSize: 20), throwsA(isA<ApiChanged>()));
      final sized = _ok({
        'data': [_row(100), _row(100), _row(101, open: 0)],
        'pagination': {'p': 1, 'pagesize': 30, 'maxpage': 1, 'count': 2},
      });
      expect(() => MissevanApi.searchRooms(sized, page: 1, pageSize: 20), throwsA(isA<ApiChanged>()));
      expect(MissevanApi.searchRooms(sized, page: 1, pageSize: 30).map((room) => room.roomId), ['100', '101']);
    });

    test("keywords 3.x's search accepted", () {
      expect(MissevanApi.isSearchable(' 配音 '), isTrue);
      expect(MissevanApi.isSearchable('x' * 100), isTrue);
      expect(MissevanApi.isSearchable('x' * 101), isFalse);
      expect(MissevanApi.isSearchable('a\nb'), isFalse);
      expect(MissevanApi.isSearchable('a\u007fb'), isFalse);
      expect(MissevanApi.isSearchable('  '), isFalse);
    });
  });

  group('S04 detail and streams', () {
    test('S04-live: the room, its qualities, URLs and renewal times match 3.x', () {
      final fixture = _sample('S04-live');
      final legacy = _legacy('S04-live');
      final room = MissevanApi.detail(fixture.body, roomId: '453091860', status: fixture.status);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh']) {
        _expectParity(_projection(room), legacy[key] as Map<String, dynamic>, reason: key);
      }
      expect(room.followers, '2748');
      expect(room.introduction, endsWith('hlh6428'), reason: "the creator's, trimmed");
      expect(room.area, isEmpty, reason: 'the detail has no catalog_name');
      final qualities = MissevanApi.qualities(room.data! as MissevanRoomData);
      final expected = _maps(legacy['getPlayQualites']);
      expect(qualities, hasLength(expected.length));
      for (final (index, quality) in qualities.indexed) {
        final want = expected[index];
        expect((quality.quality, quality.id, quality.sort), (want['quality'], want['id'], want['sort']));
        final urls = _maps(want['getPlayUrls']);
        expect(quality.data, urls.map((url) => url['url']));
        final resolution = MissevanApi.resolution(quality);
        expect(resolution.urls, urls.map((url) => url['url']));
        final lease = resolution.lines.single.lease!;
        expect(lease.refreshAt.toIso8601String(), urls.single['getPlayUrlRefreshAt']);
        expect(lease.expiresAt!.toIso8601String(), urls.single['getPlayUrlInvalidAt']);
      }
    });

    test('S04-live: one line per quality with the media headers, format and lease', () {
      final room = MissevanApi.detail(_sample('S04-live').body, roomId: '453091860');
      final [hls, flv] = MissevanApi.qualities(room.data! as MissevanRoomData);
      final hlsLine = MissevanApi.resolution(hls).lines.single;
      final flvLine = MissevanApi.resolution(flv).lines.single;
      expect((hlsLine.format, hlsLine.lineId), (StreamFormat.hls, 'hls'));
      expect((flvLine.format, flvLine.lineId), (StreamFormat.flv, 'flv'));
      for (final line in [hlsLine, flvLine]) {
        expect(line.url, startsWith('https://d1-missevan'));
        expect(Uri.parse(line.url).host, endsWith('.bilivideo.com'));
        expect(line.headers, {
          'referer': 'https://fm.missevan.com/',
          'origin': 'https://fm.missevan.com',
          'user-agent': 'Mozilla/5.0',
        });
        expect(line.headers.keys, isNot(contains('cookie')));
        expect(line.codec, isNull, reason: 'audio with a placeholder picture; the player goes by the tracks');
      }
      expect(hlsLine.lease!.cutsConnection, isTrue, reason: 'the signed playlist is fetched again and again');
      expect(flvLine.lease!.cutsConnection, isFalse);
      expect(MissevanApi.resolution(hls).appliedQualityData, 'hls');
    });

    test('S04-offline: 3.x gave no qualities; the stale addresses are not read (REG-MISSEVAN-004)', () {
      final fixture = _sample('S04-offline');
      final legacy = _legacy('S04-offline');
      final room = MissevanApi.detail(fixture.body, roomId: '507069668');
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh']) {
        _expectParity(_projection(room), legacy[key] as Map<String, dynamic>, reason: key);
      }
      expect(legacy['getPlayQualites'], isEmpty);
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.data, isNull);
      final channel = (_info('S04-offline')['room'] as Map<String, dynamic>)['channel'] as Map<String, dynamic>;
      expect(channel['flv_pull_url'], isNotEmpty, reason: 'the site still lists an old broadcast');
    });

    test('a room number or link search: the room without its pull URLs, as 3.x', () {
      for (final (name, id) in [('S04-live', '453091860'), ('S04-offline', '507069668')]) {
        final room = MissevanApi.detail(_sample(name).body, roomId: id, media: false);
        final legacy = _maps(_legacy(name)['searchRooms']).single;
        _expectParity(_projection(room), legacy, reason: name);
        expect(room.data, isNull);
        expect(_legacy(name)['supportsSearchPaginationFor'], isFalse);
      }
    });

    test('S04-notfound: HTTP 404 with code 500030004 is NotFound', () {
      final fixture = _sample('S04-notfound');
      expect(_legacy('S04-notfound')['getRoomDetail'], {'throws': 'MissevanException', 'message': 'Missevan notFound'});
      expect(_legacy('S04-notfound')['searchRooms'], isEmpty);
      expect(() => MissevanApi.detail(fixture.body, roomId: '1', status: fixture.status), throwsA(isA<NotFound>()));
      expect(() => MissevanApi.detail(fixture.body, roomId: '1'), throwsA(isA<NotFound>()), reason: 'the code alone');
    });

    test('3.x fixture: HTTPS URLs, stable transport ids, heat and followers', () {
      final room = MissevanApi.detail(_ok(_detail()), roomId: '100');
      expect(room.isLiveNow, isTrue);
      expect(room.link, 'https://fm.missevan.com/live/100');
      expect((room.effectivePopularity, room.effectiveOnlineViewers, room.effectiveTotalViewers), ('321', '', ''));
      expect(room.followers, '12');
      expect(room.avatar, 'https://static.maoercdn.com/avatar.png');
      expect(room.introduction, 'fixture');
      final qualities = MissevanApi.qualities(room.data! as MissevanRoomData);
      expect(qualities.map((quality) => quality.selectionId), ['hls', 'flv']);
      expect(qualities.map((quality) => quality.quality), ['HLS', 'FLV']);
      expect(qualities.map((quality) => quality.sort), [2, 1]);
      expect(MissevanApi.resolution(qualities.first).urls, [_hls.replaceFirst('http:', 'https:')]);
      expect(qualities.clear, throwsUnsupportedError);
      expect(() => (qualities.first.data! as List<String>).add('x'), throwsUnsupportedError);
    });

    test('an offline room ignores even malformed stream data (3.x)', () {
      final info = _detail(open: 0);
      (info['room'] as Map<String, dynamic>)['channel'] = 'stale';
      final room = MissevanApi.detail(_ok(info), roomId: '100');
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.data, isNull);
    });

    test('a room or creator other than the one asked for is ApiChanged (3.x)', () {
      expect(() => MissevanApi.detail(_ok(_detail(id: 101)), roomId: '100'), throwsA(isA<ApiChanged>()));
      final info = _detail();
      (info['creator'] as Map<String, dynamic>)['user_id'] = 201;
      expect(() => MissevanApi.detail(_ok(info), roomId: '100'), throwsA(isA<ApiChanged>()));
      final orphan = _detail()..remove('creator');
      expect(MissevanApi.detail(_ok(orphan), roomId: '100').avatar, 'https://static.maoercdn.com/avatar.png');
    });

    test('a live room without pull URLs or with a foreign one is ApiChanged; one URL is one quality (3.x)', () {
      for (final channel in <Object?>[
        <String, Object?>{},
        {'hls_pull_url': 10},
        {'flv_pull_url': 'https://example.org/a.flv'},
        {'hls_pull_url': '', 'flv_pull_url': null},
        'not a channel',
      ]) {
        final info = _detail();
        (info['room'] as Map<String, dynamic>)['channel'] = channel;
        expect(() => MissevanApi.detail(_ok(info), roomId: '100'), throwsA(isA<ApiChanged>()), reason: '$channel');
      }
      final info = _detail();
      (info['room'] as Map<String, dynamic>)['channel'] = {'flv_pull_url': _flv};
      final qualities = MissevanApi.qualities(MissevanApi.detail(_ok(info), roomId: '100').data! as MissevanRoomData);
      expect(qualities.map((quality) => (quality.id, quality.sort)), [('flv', 2)]);
    });

    test('pull URLs: https, the signed query kept byte for byte, default ports dropped (3.x)', () {
      expect(MissevanApi.mediaUrl(_hls, format: StreamFormat.hls), _hls.replaceFirst('http:', 'https:'));
      final explicit = _hls.replaceFirst('.com/', '.com:80/');
      expect(MissevanApi.mediaUrl(explicit, format: StreamFormat.hls), _hls.replaceFirst('http:', 'https:'));
      for (final value in [
        'https://bilivideo.com.evil/sample.m3u8',
        'https://127.0.0.1/sample.m3u8',
        'https://user@d1.bilivideo.com/sample.m3u8',
        'https://d1.bilivideo.com:81/sample.m3u8',
        'https://d1.bilivideo.com/sample.flv',
        'https://d1.bilivideo.com/sample.m3u8#fragment',
        'https://d1.bilivideo.com/sample.m3u8?expires=1900000000000',
        '$_hls&expires=1900000001',
        'ftp://d1.bilivideo.com/sample.m3u8',
        '',
      ]) {
        expect(() => MissevanApi.mediaUrl(value, format: StreamFormat.hls), throwsA(isA<ApiChanged>()), reason: value);
      }
    });

    test('leases: expiry at `expires`, renewal a minute before, nothing without it (3.x)', () {
      final expiry = DateTime.fromMillisecondsSinceEpoch(1900000000000, isUtc: true);
      final lease = MissevanApi.lease(_hls)!;
      expect(lease.expiresAt, expiry);
      expect(lease.refreshAt, expiry.subtract(const Duration(minutes: 1)));
      expect(MissevanApi.lease(_flv)!.cutsConnection, isFalse);
      expect(MissevanApi.lease('https://d1.bilivideo.com/sample.m3u8'), isNull);
      expect(MissevanApi.lease('https://example.org/a.m3u8?expires=1900000000'), isNull);
      expect(MissevanApi.lease('not a url'), isNull);
    });
  });

  group('envelope', () {
    test('HTTP failures are typed and never look offline (3.x)', () {
      for (final (status, matcher) in [
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
        (204, isA<NetworkFailure>()),
      ]) {
        expect(
          () => MissevanApi.info('signed URL should not be logged', what: 'live/100', status: status),
          throwsA(matcher),
          reason: '$status',
        );
      }
    });

    test('unknown codes, bodies that are not JSON objects and missing info stay errors (3.x)', () {
      for (final body in [
        '{}',
        '[]',
        '<html>challenge</html>',
        '{"code":0,"info":null}',
        '{"code":true,"info":{}}',
        '{"code":99,"info":{}}',
        '{"code":1,"info":"x"}',
      ]) {
        expect(() => MissevanApi.info(body, what: 'x'), throwsA(isA<ApiChanged>()), reason: body);
      }
      expect(() => MissevanApi.info('{"code":500030004}', what: 'x'), throwsA(isA<NotFound>()));
      expect(MissevanApi.info('{"code":"0","info":{"a":1}}', what: 'x'), {'a': 1});
    });

    test('an answer over 1 MiB of UTF-8 is refused (3.x)', () {
      final body = jsonEncode({
        'code': 0,
        'info': {'large': List.filled(400000, '音').join()},
      });
      expect(body.length, lessThan(MissevanApi.responseLimit));
      expect(() => MissevanApi.info(body, what: 'x'), throwsA(isA<ApiChanged>()));
    });
  });

  group('links', () {
    test('exact room links only; numbers never become arbitrary paths (3.x)', () {
      Uri parse(String text) => Uri.parse(text);
      expect(MissevanApi.roomIdFromUri(parse('https://fm.missevan.com/live/100/?share=1')), '100');
      expect(MissevanApi.roomIdFromUri(parse('http://fm.missevan.com/live/453091860')), '453091860');
      expect(MissevanApi.roomIdFromUri(parse('https://FM.MISSEVAN.COM/live/100')), '100');
      for (final input in [
        'https://fm.missevan.com.evil/live/100',
        'https://evil@fm.missevan.com/live/100',
        'https://fm.missevan.com:8787/live/100',
        'https://fm.missevan.com/api/v2/live/100',
        'https://fm.missevan.com/live/100/movie',
        'https://fm.missevan.com/live/%2F100',
        'https://fm.missevan.com/live/0123',
        'https://fm.missevan.com/catalog/100',
        'https://www.missevan.com/live/100',
        'file:///live/100',
      ]) {
        expect(MissevanApi.roomIdFromUri(parse(input)), isNull, reason: input);
      }
      expect(MissevanApi.roomIdFromUri(null), isNull);
      for (final input in ['0', '-1', '1/2', '../100', '01', '100?x=1', '1234567890123456789']) {
        expect(MissevanApi.idPattern.hasMatch(input), isFalse, reason: input);
      }
    });
  });
}
