// Missevan parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/missevan/legacy_expected.dart from 3.x's MissevanApi and
// MissevanSite). Every intended difference is listed with its reason (an
// upgrade row of docs/specs/UPGRADES.md, or a unified principle); everything else
// must match. The synthetic cases port 3.x's missevan_adapter_test.dart.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

Fixture _sample(String name) => Fixture.load('missevan', name);

/// Keys 3.x never wrote (M2.1); [_expectParity] checks them apart.
const _v4Keys = ['startedAt', 'restriction'];

/// Asserts that [actual] (a `toJson`) equals 3.x's [legacy] map on every key
/// 3.x wrote, except [changed] (intended differences), and that the v4 keys
/// are exactly [added]. 3.x wrote null where the immutable model writes ''.
void _expectParity(
  Map<String, Object?> actual,
  Map<String, dynamic> legacy, {
  Set<String> changed = const {},
  Map<String, Object?> added = const {},
  String? reason,
}) {
  for (final MapEntry(:key, :value) in legacy.entries) {
    if (changed.contains(key)) continue;
    expect(actual[key] ?? '', value ?? '', reason: '${reason ?? ''} $key');
  }
  for (final key in _v4Keys) {
    expect(actual[key], added[key], reason: '${reason ?? ''} $key (v4 key)');
  }
}

/// The recorded rows of a list or search sample.
List<Map<String, dynamic>> _recordedRows(String name) {
  final info = _info(name);
  return ((info['Datas'] ?? info['data']) as List).cast<Map<String, dynamic>>();
}

/// The start time of a live row as the adapter writes it: `status.open_time`
/// (epoch milliseconds) in ISO 8601 UTC; nothing when the row has none.
Map<String, Object?> _startKeys(Map<String, dynamic> row) {
  final status = row['status'] as Map<String, dynamic>;
  final open = status['open_time'];
  if (status['open'] != 1 || open is! int) return const {};
  return {'startedAt': DateTime.fromMillisecondsSinceEpoch(open, isUtc: true).toIso8601String()};
}

/// The unified placeholder rule: the site's default picture as a cover is
/// left empty, so 3.x's `cover` differs for such rows.
Set<String> _placeholderKeys(Map<String, dynamic> row) =>
    row['cover_url'] == MissevanApi.placeholderCover ? const {'cover'} : const {};

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

    test('3.x failed on the 团播 tab; the areas it knew match apart from the group (REG-MISSEVAN-005, 13-3)', () {
      final legacy = _legacy('S01-meta');
      expect(legacy['getCategores'], {'throws': 'MissevanException', 'message': 'Missevan schema'});
      final categories = MissevanApi.categories(meta.body, status: meta.status);
      final known = _maps(legacy['getCategoresWithoutListTab']).single;
      expect((known['id'], known['name']), ('missevan', MissevanApi.legacyCategoryName));
      final areas = [for (final category in categories) ...category.children.where((area) => area.areaType != 'list')];
      final legacyAreas = {for (final area in _maps(known['children'])) '${area['areaType']}:${area['areaId']}': area};
      expect(areas, hasLength(legacyAreas.length));
      for (final area in areas) {
        final key = '${area.areaType}:${area.areaId}';
        final legacyArea = legacyAreas[key]!;
        // 13-3: 3.x put every tab under 猫耳 FM; the area's identity
        // (platform, namespace, id) is unchanged.
        _expectParity(area.toJson(), legacyArea, changed: {'typeName'}, reason: 'S01 $key');
        expect(legacyArea['typeName'], MissevanApi.legacyCategoryName);
        expect(area.typeName, MissevanApi.namespaceNames[area.areaType]);
        expect(area.hasSameIdentity(LiveArea.fromJson(legacyArea)), isTrue, reason: 'a followed area keeps working');
      }
    });

    test('the tabs are grouped by namespace, in the order the site lists them (13-3)', () {
      final categories = MissevanApi.categories(meta.body, status: meta.status);
      expect(categories.map((category) => (category.id, category.name)), [
        ('catalog', '分区'),
        ('list', '团播'),
        ('tag', '标签'),
      ]);
      expect(categories.map((category) => category.children.map((area) => '${area.areaId}:${area.areaName}')), [
        ['105:配音', '104:音乐', '116:情感', '115:放松', '122:古风'],
        ['4:团播'],
        ['1:新星'],
      ]);
      for (final category in categories) {
        for (final area in category.children) {
          expect((area.platform, area.areaType, area.typeName), ('missevan', category.id, category.name));
        }
      }
      final team = categories[1].children.single;
      expect(team.areaPic, 'https://static.maoercdn.com/live/catalog/icon/tuanbo.png');
      final tagFirst = _ok({
        'tabs': [
          {'type': 'tag', 'tag_id': 1, 'name': '新星'},
          {'type': 'catalog', 'catalog_id': 104, 'name': '音乐'},
          {'type': 'tag', 'tag_id': 2, 'name': '热门'},
        ],
      });
      expect(MissevanApi.categories(tagFirst).map((category) => (category.id, category.children.length)), [
        ('tag', 2),
        ('catalog', 1),
      ]);
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

    test('unknown tab types and broken or repeated tabs are skipped; no usable tab is ApiChanged (容错)', () {
      final mixed = _ok({
        'tabs': [
          {'type': 'future', 'future_id': 9, 'name': 'x'},
          {'type': 'catalog', 'catalog_id': 1, 'name': '音乐'},
          {'type': 'catalog', 'catalog_id': 1, 'name': '重复'},
          {'type': 'catalog', 'catalog_id': 0, 'name': 'x'},
          {'type': 'tag', 'tag_id': 2, 'name': ' '},
          {'type': 'list', 'list_id': 4, 'name': '团播'},
          'not a tab',
          {'type': 'tag', 'tag_id': '1', 'name': '新星'},
        ],
      });
      final categories = MissevanApi.categories(mixed);
      expect(categories.map((category) => category.id), ['catalog', 'tag']);
      expect(categories.expand((category) => category.children).map((area) => (area.areaType, area.areaId)), [
        ('catalog', '1'),
        ('tag', '1'),
      ]);
      expect(categories.first.children.single.areaName, '音乐', reason: 'the first of a repeated tab wins');
      for (final tabs in <Object?>[
        <Object?>[],
        null,
        'tabs',
        [
          {'type': 'unknown', 'unknown_id': 1, 'name': 'x'},
        ],
        [
          {'type': 'catalog', 'catalog_id': 0, 'name': 'x'},
          {'type': 'tag', 'tag_id': 2, 'name': ' '},
        ],
        [
          {'type': 'list', 'list_id': 4, 'name': '团播'},
        ],
        ['not a tab'],
        List.generate(101, (index) => {'type': 'catalog', 'catalog_id': index + 1, 'name': '$index'}),
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
        final rows = {for (final row in _recordedRows(name)) '${row['room_id']}': row};
        for (final (index, room) in result.rooms.indexed) {
          final row = rows[room.roomId]!;
          _expectParity(
            _projection(room),
            rooms[index],
            changed: _placeholderKeys(row),
            // The start time (unified principle); a list row does not say
            // whether the room is restricted.
            added: _startKeys(row),
            reason: '$name[$index]',
          );
          expect(room.isLiveNow, isTrue);
          expect(room.data, isNull, reason: 'list cards carry no pull URLs');
          expect(room.startedAt, isNotNull, reason: 'every recorded live row has open_time');
        }
      });
    }

    test('the site placeholder cover is left empty (unified placeholder rule)', () {
      final page = MissevanApi.directoryPage(_sample('S02-list-last').body, page: 29);
      final room = page.rooms.singleWhere((room) => room.roomId == '869228979');
      final recorded = _recordedRows('S02-list-last').singleWhere((row) => row['room_id'] == 869228979);
      expect(recorded['cover_url'], MissevanApi.placeholderCover);
      expect(room.cover, isEmpty);
      expect(room.avatar, isNotEmpty, reason: "the streamer's own avatar stays");
      final stored = LiveRoom(roomId: '869228979', platform: 'missevan', cover: 'https://static.maoercdn.com/old.jpg');
      expect(stored.mergeFrom(room).cover, 'https://static.maoercdn.com/old.jpg', reason: 'a stored cover stays');
      final placeholders = [
        for (final name in [
          'S02-list-p1',
          'S02-list-last',
          'S02-list-catalog',
          'S02-list-tag',
          'S02-list-team',
          'S03-search',
          'S03-search-p2',
        ])
          ..._recordedRows(name).where((row) => _placeholderKeys(row).isNotEmpty),
      ];
      expect(placeholders, hasLength(6), reason: 'the recorded rows with the placeholder cover');
      final row = _row(5)..['cover_url'] = 'http://static.maoercdn.com/avatars/icon01.png?x=1';
      expect(MissevanApi.directoryPage(_ok(_page(1)..['Datas'] = [row]), page: 1).rooms.single.cover, isEmpty);
    });

    test('a live row starts at status.open_time; offline and bad values have no start (unified principle)', () {
      final room = MissevanApi.directoryPage(_sample('S02-list-p1').body, page: 1).rooms.first;
      expect(room.startedAt, DateTime.utc(2026, 9, 27, 12, 58, 55, 88));
      expect(room.restriction, isNull, reason: 'a list row does not say');
      Map<String, dynamic> timed(Object? time, {int open = 1}) =>
          _row(1, open: open)..['status'] = {'open': open, 'open_time': time};
      expect(MissevanApi.detail(_ok({'room': timed(1790481150876)}), roomId: '1', media: false).startedAt, isNotNull);
      for (final value in [0, null, '', 'x', 1790481150, -1, 946684799999, 17904811508760]) {
        final info = _page(1)..['Datas'] = [timed(value)];
        expect(MissevanApi.directoryPage(_ok(info), page: 1).rooms.single.startedAt, isNull, reason: '$value');
      }
      expect(MissevanApi.startedAt('1790481150876'), DateTime.utc(2026, 9, 27, 3, 52, 30, 876));
      final search = _ok({
        'data': [timed(1790481150876, open: 0)],
        'pagination': {'p': 1, 'pagesize': 20, 'maxpage': 1, 'count': 1},
      });
      expect(MissevanApi.searchRooms(search, page: 1, pageSize: 20).single.startedAt, isNull, reason: 'offline');
    });

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
      // The listeners come only with the chat's room/statistics (M5.12): the
      // count is pending on a list card.
      expect(room.supportsRealOnlineCount, isTrue);
      expect(room.audienceValue(preferRealOnline: false, platformEnabled: true), '88900');
      expect(room.audienceValue(preferRealOnline: true, platformEnabled: true), isEmpty);
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

    test('a row without a valid state, score, room or creator id is skipped; a page of only such rows is ApiChanged '
        '(容错; 3.x failed the page)', () {
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
        final mixed = _page(1)..['Datas'] = [row, _row(2), 'not a row'];
        expect(MissevanApi.directoryPage(_ok(mixed), page: 1).rooms.map((room) => room.roomId), ['2'], reason: '$row');
        final search = _ok({
          'data': [_row(3, open: 0), row],
          'pagination': {'p': 1, 'pagesize': 20, 'maxpage': 1, 'count': 2},
        });
        expect(MissevanApi.searchRooms(search, page: 1, pageSize: 20).map((room) => room.roomId), [
          '3',
        ], reason: '$row');
        final only = _page(1)..['Datas'] = [row, 'not a row'];
        expect(() => MissevanApi.directoryPage(_ok(only), page: 1), throwsA(isA<ApiChanged>()), reason: '$row');
        final onlySearch = _ok({
          'data': [row],
          'pagination': {'p': 1, 'pagesize': 20, 'maxpage': 1, 'count': 1},
        });
        expect(
          () => MissevanApi.searchRooms(onlySearch, page: 1, pageSize: 20),
          throwsA(isA<ApiChanged>()),
          reason: '$row',
        );
      }
      final text = _row(1)..['status'] = {'open': '1'};
      expect(MissevanApi.directoryPage(_ok(_page(1)..['Datas'] = [text]), page: 1).rooms, hasLength(1));
      expect(
        () => MissevanApi.detail(
          _ok({
            'room': _row(1)..['status'] = {'open': 2},
          }),
          roomId: '1',
        ),
        throwsA(isA<ApiChanged>()),
        reason: 'the room itself is no row to skip',
      );
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
        final rows = {for (final row in _recordedRows(name)) '${row['room_id']}': row};
        for (final (index, room) in rooms.indexed) {
          final row = rows[room.roomId]!;
          expect(_startKeys(row), isEmpty, reason: 'search rows carry no open_time');
          _expectParity(_projection(room), legacy[index], changed: _placeholderKeys(row), reason: '$name[$index]');
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

    test('keywords: trimmed; over 100 characters cut to the first 100 (13-4); control characters refused (3.x)', () {
      expect(MissevanApi.searchKeyword(' 配音 '), '配音');
      expect(MissevanApi.searchKeyword('x' * 100), 'x' * 100);
      expect(MissevanApi.searchKeyword('配' * 101), '配' * 100, reason: '3.x refused it');
      expect(MissevanApi.searchKeyword('${'y' * 99} ${'z' * 50}'), 'y' * 99, reason: 'trimmed after the cut');
      final emoji = '\u{1F600}' * 120;
      expect(MissevanApi.searchKeyword(emoji), '\u{1F600}' * 100, reason: 'code points: an emoji is never split');
      expect(MissevanApi.searchKeyword('${'a' * 99}\u{1F600}b'), '${'a' * 99}\u{1F600}');
      for (final keyword in ['a\nb', 'a\u007fb', '  ', '', '${'x' * 150}\u0000']) {
        expect(MissevanApi.searchKeyword(keyword), isNull, reason: keyword);
        expect(MissevanApi.isSearchable(keyword), isFalse, reason: keyword);
      }
      expect(MissevanApi.isSearchable('x' * 101), isTrue);
      expect(MissevanApi.maxKeywordLength, 100);
    });
  });

  group('S04 detail and streams', () {
    test('S04-live: the room matches 3.x; its start time, no restriction (unified principles)', () {
      final fixture = _sample('S04-live');
      final legacy = _legacy('S04-live');
      final room = MissevanApi.detail(fixture.body, roomId: '453091860', status: fixture.status);
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh']) {
        _expectParity(
          _projection(room),
          legacy[key] as Map<String, dynamic>,
          added: {'startedAt': '2026-09-27T03:52:30.876Z', 'restriction': 'none'},
          reason: key,
        );
      }
      expect(room.followers, '2748');
      expect(room.introduction, endsWith('hlh6428'), reason: "the creator's, trimmed");
      expect(room.area, isEmpty, reason: 'the detail has no catalog_name');
      expect(room.danmakuData, isNull, reason: 'only asked for on room entry');
    });

    test("S04-live: one quality 原画 whose lines are 3.x's two qualities, FLV first (13-1)", () {
      final legacy = _maps(_legacy('S04-live')['getPlayQualites']);
      expect(legacy.map((quality) => (quality['quality'], quality['id'], quality['sort'])), [
        ('HLS', 'hls', 2),
        ('FLV', 'flv', 1),
      ]);
      final room = MissevanApi.detail(_sample('S04-live').body, roomId: '453091860');
      final quality = MissevanApi.qualities(room.data! as MissevanRoomData).single;
      expect((quality.quality, quality.id, quality.selectionId), ('原画', '10000', '10000'));
      final resolution = MissevanApi.resolution(quality);
      expect(resolution.appliedQualityData, '10000');
      expect(resolution.lines.map((line) => line.lineId), ['flv', 'hls']);
      final byId = {for (final want in legacy) want['id']: _maps(want['getPlayUrls']).single};
      for (final line in resolution.lines) {
        final want = byId[line.lineId]!;
        expect(line.url, want['url'], reason: '${line.lineId}: byte for byte');
        expect(line.lease!.refreshAt.toIso8601String(), want['getPlayUrlRefreshAt']);
        expect(line.lease!.expiresAt!.toIso8601String(), want['getPlayUrlInvalidAt']);
        expect(Uri.parse(line.url).queryParameters['qn'], MissevanApi.originalQualityId);
      }
    });

    test('S04-live: each line with the media headers, format and lease', () {
      final room = MissevanApi.detail(_sample('S04-live').body, roomId: '453091860');
      final [flvLine, hlsLine] = MissevanApi.resolution(MissevanApi.qualities(room.data! as MissevanRoomData).single)
          .lines;
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
    });

    test("3.x's quality ids map to the one quality, for M9 (13-1)", () {
      expect(MissevanApi.legacyQualityIds, {'hls': '10000', 'flv': '10000'});
      expect(MissevanApi.qualityIdFromLegacy('hls'), '10000');
      expect(MissevanApi.qualityIdFromLegacy(' FLV '), '10000');
      expect(MissevanApi.qualityIdFromLegacy('10000'), '10000');
      expect(MissevanApi.qualityIdFromLegacy('other'), 'other');
      for (final want in _maps(_legacy('S04-live')['getPlayQualites'])) {
        expect(MissevanApi.qualityIdFromLegacy(want['id'] as String), MissevanApi.originalQualityId);
      }
    });

    test('S04-offline: 3.x gave no qualities; the stale addresses are not read (REG-MISSEVAN-004)', () {
      final fixture = _sample('S04-offline');
      final legacy = _legacy('S04-offline');
      final room = MissevanApi.detail(fixture.body, roomId: '507069668');
      for (final key in ['getRoomDetail', 'getRoomDetailForRefresh']) {
        // Offline: open_time is the 2021 broadcast's, so no start time; no
        // restriction said.
        _expectParity(_projection(room), legacy[key] as Map<String, dynamic>, reason: key);
      }
      expect(legacy['getPlayQualites'], isEmpty);
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(room.data, isNull);
      final channel = (_info('S04-offline')['room'] as Map<String, dynamic>)['channel'] as Map<String, dynamic>;
      expect(channel['flv_pull_url'], isNotEmpty, reason: 'the site still lists an old broadcast');
      final status = (_info('S04-offline')['room'] as Map<String, dynamic>)['status'] as Map<String, dynamic>;
      expect(status['open_time'], 1639706765164, reason: 'the last broadcast, not a start to show');
    });

    test('a room number or link search: the room without its pull URLs, as 3.x', () {
      for (final (name, id, added) in [
        ('S04-live', '453091860', {'startedAt': '2026-09-27T03:52:30.876Z'}),
        ('S04-offline', '507069668', const <String, Object?>{}),
      ]) {
        final room = MissevanApi.detail(_sample(name).body, roomId: id, media: false);
        final legacy = _maps(_legacy(name)['searchRooms']).single;
        // The start time (unified principle); without the pull URLs read, no
        // restriction is said.
        _expectParity(_projection(room), legacy, added: added, reason: name);
        expect(room.data, isNull);
        expect(_legacy(name)['supportsSearchPaginationFor'], isFalse);
      }
    });

    test('danmaku arguments on request: the room and its socket, live or not (13-2)', () {
      for (final (name, id) in [('S04-live', '453091860'), ('S04-offline', '507069668')]) {
        final room = MissevanApi.detail(_sample(name).body, roomId: id, withDanmaku: true);
        final args = room.danmakuData! as MissevanDanmakuArgs;
        expect(args.roomId, id);
        expect(args.url.toString(), 'wss://im.missevan.com/ws?room_id=$id');
        expect(args.headers, MissevanApi.headers);
        expect(args.headers.keys, isNot(contains('cookie')), reason: "the guest session is the connection's");
        expect(room.toJson().keys, isNot(contains('danmakuData')), reason: 'never stored');
      }
      expect(MissevanApi.guestSession.toString(), 'https://fm.missevan.com/api/user/info');
      expect(_sample('S05-user-info').url, MissevanApi.guestSession);
    });

    test('danmaku socket: only wss on missevan.com for this room; otherwise the known form', () {
      Uri socket(Object? sockets) => MissevanApi.danmakuArgs({'websocket': sockets}, roomId: '100').url;
      const fallback = 'wss://im.missevan.com/ws?room_id=100';
      expect(socket(['wss://im2.missevan.com/ws?room_id=100']).toString(), 'wss://im2.missevan.com/ws?room_id=100');
      expect(socket(['wss://missevan.com/ws']).toString(), 'wss://missevan.com/ws');
      expect(
        socket(['wss://evil.example/ws?room_id=100', ' wss://im.missevan.com/ws?room_id=100 ']).toString(),
        fallback,
      );
      for (final sockets in <Object?>[
        null,
        'wss://im.missevan.com/ws?room_id=100',
        <Object?>[],
        [10],
        ['ws://im.missevan.com/ws?room_id=100'],
        ['https://im.missevan.com/ws?room_id=100'],
        ['wss://im.missevan.com.evil.example/ws?room_id=100'],
        ['wss://user@im.missevan.com/ws?room_id=100'],
        ['wss://im.missevan.com/ws?room_id=101'],
        ['wss://im.missevan.com/ws?room_id=%zz'],
      ]) {
        expect(socket(sockets).toString(), fallback, reason: '$sockets');
      }
    });

    test('S04-notfound: HTTP 404 with code 500030004 is NotFound', () {
      final fixture = _sample('S04-notfound');
      expect(_legacy('S04-notfound')['getRoomDetail'], {'throws': 'MissevanException', 'message': 'Missevan notFound'});
      expect(_legacy('S04-notfound')['searchRooms'], isEmpty);
      expect(() => MissevanApi.detail(fixture.body, roomId: '1', status: fixture.status), throwsA(isA<NotFound>()));
      expect(() => MissevanApi.detail(fixture.body, roomId: '1'), throwsA(isA<NotFound>()), reason: 'the code alone');
    });

    test('3.x fixture: HTTPS URLs, stable line ids, heat and followers', () {
      final room = MissevanApi.detail(_ok(_detail()), roomId: '100');
      expect(room.isLiveNow, isTrue);
      expect(room.link, 'https://fm.missevan.com/live/100');
      expect((room.effectivePopularity, room.effectiveOnlineViewers, room.effectiveTotalViewers), ('321', '', ''));
      expect(room.followers, '12');
      expect(room.avatar, 'https://static.maoercdn.com/avatar.png');
      expect(room.introduction, 'fixture');
      expect(room.restriction, LiveRestriction.none, reason: 'the site hands the pull URLs to anyone');
      expect(room.startedAt, isNull, reason: 'no open_time in this row');
      final qualities = MissevanApi.qualities(room.data! as MissevanRoomData);
      expect(qualities.map((quality) => (quality.selectionId, quality.quality)), [('10000', '原画')]);
      final resolution = MissevanApi.resolution(qualities.single);
      expect(resolution.urls, [_flv.replaceFirst('http:', 'https:'), _hls.replaceFirst('http:', 'https:')]);
      expect(resolution.lines.map((line) => line.lineId), ['flv', 'hls']);
      expect(qualities.clear, throwsUnsupportedError);
      expect(() => (qualities.single.data! as List<String>).add('x'), throwsUnsupportedError);
      expect(MissevanApi.qualities(const MissevanRoomData()), isEmpty);
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

    test('a live room without a usable pull URL is ApiChanged; a bad URL only loses its line (容错)', () {
      for (final channel in <Object?>[
        <String, Object?>{},
        {'hls_pull_url': 10},
        {'flv_pull_url': 'https://example.org/a.flv'},
        {'hls_pull_url': '', 'flv_pull_url': null},
        {'hls_pull_url': _flv, 'flv_pull_url': _hls},
        'not a channel',
      ]) {
        final info = _detail();
        (info['room'] as Map<String, dynamic>)['channel'] = channel;
        expect(() => MissevanApi.detail(_ok(info), roomId: '100'), throwsA(isA<ApiChanged>()), reason: '$channel');
      }
      for (final (channel, lines) in <(Map<String, Object?>, List<String>)>[
        ({'flv_pull_url': _flv}, ['flv']),
        ({'hls_pull_url': _hls, 'flv_pull_url': 'https://example.org/a.flv'}, ['hls']),
        ({'hls_pull_url': 'https://d1.bilivideo.com/a.m3u8#x', 'flv_pull_url': _flv}, ['flv']),
        ({'hls_pull_url': _hls, 'flv_pull_url': 7}, ['hls']),
      ]) {
        final info = _detail();
        (info['room'] as Map<String, dynamic>)['channel'] = channel;
        final room = MissevanApi.detail(_ok(info), roomId: '100');
        expect(room.restriction, LiveRestriction.none);
        final quality = MissevanApi.qualities(room.data! as MissevanRoomData).single;
        expect(quality.selectionId, '10000');
        expect(MissevanApi.resolution(quality).lines.map((line) => line.lineId), lines, reason: '$channel');
      }
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
