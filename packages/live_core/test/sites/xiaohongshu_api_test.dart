// Xiaohongshu parsing against the recorded samples, compared field by field
// with 3.x's frozen output (expected.json, written by
// fixtures/xiaohongshu/legacy_expected.dart from 3.x's code). Every intended
// difference is listed with its reason; everything else must match. The
// rules without a sample are ported from 3.x's
// test/xiaohongshu_share_test.dart and test/xiaohongshu_share_link_test.dart
// (the parsing part), over the recorded live page instead of 3.x's synthetic
// test/fixtures/xiaohongshu/live.json.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _live = '570459564696889177';
const _ended = '570305058583373361';
const _missing = '569865232324657152';

Fixture _sample(String name) => Fixture.load('xiaohongshu', name);

/// Keys 3.x never wrote (M2.1); [_expectParity] checks them apart.
const _v4Keys = ['startedAt', 'restriction'];

/// 3.x's notice lines, reworded for users (the unified rule on notice
/// texts); the lines themselves are the same.
const _legacyScope = '当前以直播房间号跟踪；主播重新开播使用新房间号时，请重新导入分享链接。';
const _legacyViewers = '平台展示观看值：300万+（非已验证的实时在线人数）';

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

/// 3.x's [legacy] notice with each line reworded: the same lines, in the
/// same order.
String _reworded(String legacy) => legacy
    .split('\n')
    .map(
      (line) => switch (line) {
        _legacyScope => XiaohongshuApi.roomScopeNotice,
        _legacyViewers => XiaohongshuApi.displayViewersNotice('300万+'),
        _ => fail('an unexpected 3.x notice line: $line'),
      },
    )
    .join('\n');

/// 3.x's room projection: toJson plus `link`.
Map<String, Object?> _projection(LiveRoom room) => {...room.toJson(), 'link': room.link};

/// One entry of expected.json: `{requests, value}`.
Object? _legacyValue(String sample, String entry) =>
    ((_sample(sample).legacy as Map<String, dynamic>)[entry] as Map<String, dynamic>)['value'];

XiaohongshuPage _page(String sample, String roomId) {
  final fixture = _sample(sample);
  return XiaohongshuApi.room(fixture.body, requestedId: roomId, status: fixture.status);
}

/// `liveStream` of a recorded page, as a fresh JSON map to edit (the page's
/// own `undefined` tokens are all bare values).
Map<String, dynamic> _state([String sample = 'S01-room-live']) {
  const marker = 'window.__INITIAL_STATE__=';
  final body = _sample(sample).body;
  final start = body.indexOf(marker) + marker.length;
  final json = body.substring(start, body.indexOf('</script>', start)).replaceAll(':undefined', ':null');
  return ((jsonDecode(json) as Map<String, dynamic>)['liveStream'] as Map).cast<String, dynamic>();
}

Map<String, dynamic> _info(Map<String, dynamic> state) =>
    ((state['roomData'] as Map)['roomInfo'] as Map).cast<String, dynamic>();

/// A share page holding [state] (3.x's test page).
String _html(Map<String, dynamic> state) =>
    '<html><script>window.__INITIAL_STATE__=${jsonEncode({'liveStream': state})}</script></html>';

XiaohongshuPage _parse(Map<String, dynamic> state, {String roomId = _live}) =>
    XiaohongshuApi.room(_html(state), requestedId: roomId, status: 200);

/// [state] with its `pullConfig` rewritten by [edit].
void _editStreams(Map<String, dynamic> state, void Function(Map<String, dynamic> config) edit) {
  final info = _info(state);
  final config = jsonDecode(info['pullConfig'] as String) as Map<String, dynamic>;
  edit(config);
  info['pullConfig'] = jsonEncode(config);
}

/// Row [index] of the `h264` list of a decoded `pullConfig`.
Map<String, dynamic> _row(Map<String, dynamic> config, int index) =>
    (config['h264'] as List<dynamic>)[index] as Map<String, dynamic>;

List<XiaohongshuStream> _streams(Map<String, dynamic> state) => XiaohongshuApi.playable(_parse(state).data);

void main() {
  group('S01 share pages match 3.x', () {
    for (final (sample, roomId, added) in [
      ('S01-room-live', _live, const {'restriction': 'none'}),
      ('S01-room-ended', _ended, const <String, Object?>{}),
    ]) {
      test("$sample: room entry, follow refresh, recording and search are 3.x's room", () {
        final room = _page(sample, roomId).room;
        final entries = ['getRoomDetail', 'getRoomDetailForRefresh', 'getRoomDetailForRecording'];
        final searches = ['searchRooms(roomId)', 'searchRooms(link)'];
        for (final (entry, legacy) in [
          for (final entry in entries) (entry, _legacyValue(sample, entry)! as Map<String, dynamic>),
          for (final entry in searches) (entry, (_legacyValue(sample, entry)! as List).single as Map<String, dynamic>),
        ]) {
          // changed: notice, the same lines reworded for users (the unified
          // rule on notice texts); added: a live public room is restriction
          // none (the unified rule on restrictions), an ended one has none.
          _expectParity(_projection(room), legacy, changed: {'notice'}, added: added, reason: entry);
          expect(room.notice, _reworded(legacy['notice'] as String), reason: entry);
        }
        expect(room.roomId, roomId, reason: 'the id asked for, as 3.x stored follows');
        expect(room.userId, isNull, reason: '3.x had no streamer identity');
        expect(room.watching, isEmpty);
        expect(room.audienceType(preferRealOnline: false, platformEnabled: true), AudienceMetricType.unknown);
        expect(room.audienceValue(preferRealOnline: false, platformEnabled: true), isEmpty);
        expect(room.supportsRealOnlineCount, isFalse);
      });
    }

    test('S01 live: the display count is notice text, never an audience', () {
      final page = _page('S01-room-live', _live);
      expect(page.room.isLiveNow, isTrue);
      expect(page.data.live, isTrue);
      expect(page.data.access, XiaohongshuAccess.public);
      expect(page.data.restriction, LiveRestriction.none);
      expect(page.room.restriction, LiveRestriction.none);
      expect(page.room.startedAt, isNull, reason: 'the share page has no start time');
      expect(page.data.displayViewers, '300万+');
      expect(page.room.notice, '${XiaohongshuApi.roomScopeNotice}\n${XiaohongshuApi.displayViewersNotice('300万+')}');
      expect(page.room.notice, contains('小红书显示 300万+ 人看过'));
    });

    test('S01 live: one quality 原画 (16-3), its four addresses FLV first; 3.x ids map to it', () {
      final legacy = (_sample('S01-room-live').legacy as Map<String, dynamic>)['getPlayQualites'] as List;
      final streams = XiaohongshuApi.playable(_page('S01-room-live', _live).data);
      final qualities = XiaohongshuApi.qualities(streams);
      expect(qualities, hasLength(legacy.length));
      for (final (index, quality) in qualities.indexed) {
        final expected = legacy[index] as Map<String, dynamic>;
        // changed: quality and id, 16-3 (one quality per quality_type, named
        // by the page); the old id maps to the new one for M9.
        expect(quality.quality, '原画');
        expect(expected['quality'], '原画 · H264');
        expect(quality.id, XiaohongshuApi.qualityIdFromLegacy(expected['id'] as String));
        expect(quality.sort, expected['sort']);
        expect(quality.data, isNull);
        // changed: order, 16-3 (FLV before HLS); the same four addresses.
        final urls = XiaohongshuApi.resolution(streams, quality).urls;
        final legacyUrls = (expected['getPlayUrls'] as List).cast<String>();
        expect(urls, unorderedEquals(legacyUrls));
        expect(urls, [
          ...legacyUrls.where((url) => url.endsWith('.flv')),
          ...legacyUrls.where((u) => u.endsWith('.m3u8')),
        ]);
      }
      expect(qualities.single.selectionId, 'HD');
    });

    test("S01 live: lines carry 3.x's media headers, format, codec and CDN; the addresses do not expire", () {
      final streams = XiaohongshuApi.playable(_page('S01-room-live', _live).data);
      final resolution = XiaohongshuApi.resolution(streams, XiaohongshuApi.qualities(streams).single);
      expect(resolution.appliedQualityData, 'HD');
      expect(resolution.lines.map((line) => line.format), [
        StreamFormat.flv,
        StreamFormat.flv,
        StreamFormat.flv,
        StreamFormat.hls,
      ]);
      expect(resolution.lines.map((line) => line.lineId), [
        'flv:live-source-play',
        'flv:live-source-play-bak-tx',
        'flv:live-source-play-hw',
        'hls:live-source-play',
      ]);
      for (final line in resolution.lines) {
        expect(line.codec, 'avc');
        expect(line.lease, isNull, reason: 'plain http addresses without a signature');
        expect(line.headers, {
          'referer': 'https://www.xiaohongshu.com/',
          'user-agent': 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/87.0.4280.141 Mobile Safari/537.36',
        });
        expect(line.headers.keys, isNot(contains('cookie')));
        expect(Uri.parse(line.url).path, anyOf('/live/$_live.m3u8', '/live/$_live.flv'));
      }
    });

    test('S01 ended: offline without a stream; the recommended next room is ignored', () {
      final page = _page('S01-room-ended', _ended);
      expect(page.room.effectiveLiveStatus, LiveStatus.offline);
      expect(page.data.live, isFalse);
      expect(page.data.pullConfig, isNull);
      expect(page.data.restriction, LiveRestriction.none, reason: 'the page tells');
      expect(page.room.restriction, isNull, reason: 'an ended broadcast carries none');
      expect(_state('S01-room-ended')['nextRoomInfo'], containsPair('pullConfig', isNotEmpty));
      expect(page.room.notice, XiaohongshuApi.roomScopeNotice);
      expect(() => XiaohongshuApi.playable(page.data), throwsA(isA<StreamUnavailable>()));
      final legacy = _legacyValue('S01-room-ended', 'getPlayUrls(h264:HD)')! as Map<String, dynamic>;
      expect(legacy['message'], 'Xiaohongshu notLive');
    });

    test('S01 not found: pageStatus "error" is NotFound (3.x: an unexplained page error)', () {
      for (final entry in ['getRoomDetail', 'getRoomDetailForRefresh', 'searchRooms(roomId)']) {
        expect(
          (_legacyValue('S01-room-notfound', entry)! as Map<String, dynamic>)['message'],
          'Xiaohongshu api',
          reason: entry,
        );
      }
      expect(
        () => _page('S01-room-notfound', _missing),
        throwsA(isA<NotFound>().having((error) => error.detail, 'detail', contains('未找到直播间'))),
      );
    });
  });

  group('share page rules (3.x)', () {
    test('the hydration script: undefined outside strings only; the rest stays JSON', () {
      final state = _state();
      _info(state)['roomTitle'] = r'undefined \ "undefined"';
      final page =
          '<script>window.__INITIAL_STATE__={"global":{"jsAssetsList":undefined,"tiers":[undefined]},'
          '"liveStream":${jsonEncode(state)}};</script>';
      final parsed = XiaohongshuApi.room(page, requestedId: _live, status: 200);
      expect(parsed.room.title, r'undefined \ "undefined"');
      expect(XiaohongshuApi.playable(parsed.data), hasLength(4));
    });

    for (final source in [
      'undefinedCall()',
      'undefinedSuffix',
      '(undefined)',
      '(()=>undefined)()',
      'NaN',
      'Infinity',
    ]) {
      test('an expression that is not JSON is ApiChanged: $source', () {
        final page =
            '<script>window.__INITIAL_STATE__={"global":$source,"liveStream":${jsonEncode(_state())}}</script>';
        expect(() => XiaohongshuApi.room(page, requestedId: _live, status: 200), throwsA(isA<ApiChanged>()));
      });
    }

    for (final page in [
      '直播已结束',
      '<script>window.__INITIAL_STATE__=alert(1)</script>',
      '<script>window.__INITIAL_STATE__={"liveStream":undefined}</script>',
      '${_html(_state())}${_html(_state())}',
      'a' * (XiaohongshuApi.responseLimit + 1),
    ]) {
      test('no, two, executable or oversize states are ApiChanged (${page.length})', () {
        expect(() => XiaohongshuApi.room(page, requestedId: _live, status: 200), throwsA(isA<ApiChanged>()));
      });
    }

    test('an oversize page is counted in UTF-8 bytes', () {
      final page = '${_html(_state())}<!--${'页' * (XiaohongshuApi.responseLimit ~/ 3)}-->';
      expect(page.length, lessThan(XiaohongshuApi.responseLimit));
      expect(() => XiaohongshuApi.room(page, requestedId: _live, status: 200), throwsA(isA<ApiChanged>()));
    });

    test('a room id that is not one is refused before parsing', () {
      for (final id in ['', '0', '../123', ' 123', '123?', '123/4', '123\n', '123456789012345678901']) {
        expect(
          () => XiaohongshuApi.room(_html(_state()), requestedId: id, status: 200),
          throwsArgumentError,
          reason: jsonEncode(id),
        );
      }
    });

    for (final id in <Object?>[null, int.parse(_live), '570459564696889178']) {
      test('a live page must name exactly the room asked for: $id', () {
        final state = _state();
        _info(state)['roomId'] = id;
        expect(() => _parse(state), throwsA(isA<ApiChanged>()));
      });
    }

    test('an ended page naming another room is not accepted', () {
      final state = _state('S01-room-ended');
      _info(state)['roomId'] = _live;
      expect(() => _parse(state, roomId: _ended), throwsA(isA<ApiChanged>()));
    });

    // The kinds are the web page's enums (monetizeType Free 0, Paid 1;
    // joinLimitTypes GroupChat 1, Family 2, IpFence 4).
    for (final (name, edit, restriction, error)
        in <(String, void Function(Map<String, dynamic>), LiveRestriction, Matcher)>[
          ('paid', (info) => info['monetizeType'] = 1, LiveRestriction.paid, isA<StreamUnavailable>()),
          ('another paid kind', (info) => info['monetizeType'] = 3, LiveRestriction.paid, isA<StreamUnavailable>()),
          ('family', (info) => info['joinLimitTypes'] = [2], LiveRestriction.private, isA<StreamUnavailable>()),
          ('group chat', (info) => info['joinLimitTypes'] = [1], LiveRestriction.private, isA<StreamUnavailable>()),
          ('IP fence', (info) => info['joinLimitTypes'] = [4], LiveRestriction.regionBlocked, isA<RegionBlocked>()),
          (
            'a future limit',
            (info) => info['joinLimitTypes'] = [32],
            LiveRestriction.unplayable,
            isA<StreamUnavailable>(),
          ),
          (
            'a future limit and a fence',
            (info) => info['joinLimitTypes'] = [0, 32, 4],
            LiveRestriction.regionBlocked,
            isA<RegionBlocked>(),
          ),
          (
            'paid and fenced',
            (info) {
              info['monetizeType'] = 1;
              info['joinLimitTypes'] = [4, 1];
            },
            LiveRestriction.paid,
            isA<StreamUnavailable>(),
          ),
        ]) {
      test('$name: live with its restriction; no stream is read (not even a broken preview); playing says why', () {
        final state = _state();
        edit(_info(state));
        _info(state)['pullConfig'] = 'broken preview';
        final page = _parse(state);
        expect(page.data.access, XiaohongshuAccess.restricted);
        expect(page.data.restriction, restriction);
        expect(page.data.pullConfig, isNull);
        expect(page.room.isLiveNow, isTrue, reason: 'the room is live; it is the stream that is closed');
        expect(page.room.restriction, restriction);
        expect(page.room.isRestricted, isTrue);
        expect(page.room.followGroup, FollowGroup.live);
        expect(page.room.notice, contains(XiaohongshuApi.restrictedNotice));
        expect(() => XiaohongshuApi.playable(page.data), throwsA(error));
      });
    }

    for (final (name, edit) in <(String, void Function(Map<String, dynamic>))>[
      ('monetizeType missing', (info) => info.remove('monetizeType')),
      ('joinLimitTypes missing', (info) => info.remove('joinLimitTypes')),
    ]) {
      test('$name: access not known, no restriction; playback needs an account (3.x)', () {
        final state = _state();
        edit(_info(state));
        final page = _parse(state);
        expect(page.data.access, XiaohongshuAccess.unknown);
        expect(page.data.restriction, isNull);
        expect(page.data.pullConfig, isNull);
        expect(page.room.isLiveNow, isTrue);
        expect(page.room.restriction, isNull);
        expect(page.room.notice, contains(XiaohongshuApi.unknownAccessNotice));
        expect(page.room.notice, isNot(contains(XiaohongshuApi.restrictedNotice)));
        expect(() => XiaohongshuApi.playable(page.data), throwsA(isA<NeedsLogin>()));
      });
    }

    test('an ended or unknown room carries no restriction, even a restricted one', () {
      final ended = _state('S01-room-ended');
      _info(ended)['monetizeType'] = 1;
      final page = _parse(ended, roomId: _ended);
      expect(page.data.restriction, LiveRestriction.paid);
      expect(page.room.restriction, isNull);
      final unknown = _state();
      _info(unknown)['status'] = 9;
      expect(_parse(unknown).room.restriction, isNull);
    });

    for (final (name, edit) in <(String, void Function(Map<String, dynamic>))>[
      ('no pullConfig', (info) => info.remove('pullConfig')),
      ('an empty pullConfig', (info) => info['pullConfig'] = ''),
      ('no rows', (info) => info['pullConfig'] = '{"h264":[],"h265":[],"width":1080}'),
      ('no codec lists', (info) => info['pullConfig'] = '{"width":1080}'),
    ]) {
      test('a live public room with $name is unplayable (the unified rule on restrictions)', () {
        final state = _state();
        edit(_info(state));
        final page = _parse(state);
        expect(page.room.isLiveNow, isTrue);
        expect(page.room.restriction, LiveRestriction.unplayable);
        expect(page.room.followGroup, FollowGroup.live);
        expect(page.data.restriction, LiveRestriction.none);
        expect(() => XiaohongshuApi.playable(page.data), throwsA(isA<StreamUnavailable>()));
      });
    }

    test('a pullConfig that cannot be read is not called unplayable: playing tells why', () {
      final state = _state();
      _info(state)['pullConfig'] = '{';
      final page = _parse(state);
      expect(page.room.restriction, LiveRestriction.none);
      expect(() => XiaohongshuApi.playable(page.data), throwsA(isA<ApiChanged>()));
    });

    test('a state other than 2 and 3 stays unknown, whatever liveStatus says', () {
      final state = _state();
      _info(state)['status'] = 9;
      final page = _parse(state);
      expect(page.room.effectiveLiveStatus, LiveStatus.unknown);
      expect(page.data.live, isNull);
      expect(page.data.pullConfig, isNull);
      expect(() => XiaohongshuApi.playable(page.data), throwsA(isA<StreamUnavailable>()));
    });

    test('live without pullConfig is a live room without a stream, not offline', () {
      final state = _state();
      _info(state).remove('pullConfig');
      final page = _parse(state);
      expect(page.room.isLiveNow, isTrue);
      expect(() => XiaohongshuApi.playable(page.data), throwsA(isA<StreamUnavailable>()));
    });

    test('a title holding "直播已结束" does not change the state', () {
      final state = _state();
      _info(state)['roomTitle'] = '直播已结束';
      expect(_parse(state).room.isLiveNow, isTrue);
    });

    for (final MapEntry(key: name, value: edit) in <String, void Function(Map<String, dynamic>)>{
      'pageStatus missing': (state) => state.remove('pageStatus'),
      'roomData not an object': (state) => state['roomData'] = <Object?>[],
      'hostInfo missing': (state) => (state['roomData'] as Map).remove('hostInfo'),
      'live with liveStatus end': (state) => state['liveStatus'] = 'end',
      'a negative status': (state) => _info(state)['status'] = -1,
      'status true': (state) => _info(state)['status'] = true,
      'joinLimitTypes "0"': (state) => _info(state)['joinLimitTypes'] = '0',
      'joinLimitTypes [-1]': (state) => _info(state)['joinLimitTypes'] = [-1],
      '17 join limits': (state) => _info(state)['joinLimitTypes'] = List.filled(17, 0),
      'monetizeType false': (state) => _info(state)['monetizeType'] = false,
      'a numeric title': (state) => _info(state)['roomTitle'] = 42,
      'an overlong title': (state) => _info(state)['roomTitle'] = 'x' * 4097,
    }.entries) {
      test('ApiChanged on reading the page: $name', () {
        final state = _state();
        edit(state);
        expect(() => _parse(state), throwsA(isA<ApiChanged>()));
      });
    }

    for (final MapEntry(key: name, value: edit) in <String, void Function(Map<String, dynamic>)>{
      'pullConfig "{"': (info) => info['pullConfig'] = '{',
      'pullConfig over 65536 characters': (info) => info['pullConfig'] = ' ' * 65537,
      'pullConfig a number': (info) => info['pullConfig'] = 42,
    }.entries) {
      // 3.x failed the whole page (room entry and follow refresh too); the
      // page is read and playback fails instead.
      test('ApiChanged on playing, not on reading the page: $name', () {
        final state = _state();
        edit(_info(state));
        final page = _parse(state);
        expect(page.room.isLiveNow, isTrue);
        expect(() => XiaohongshuApi.playable(page.data), throwsA(isA<ApiChanged>()));
      });
    }

    // 16-4: 3.x failed the room for one bad row; the row is left out now,
    // and only a config without one usable row is ApiChanged.
    for (final url in [
      'http://xhscdn.com.evil.test/live/$_live.flv',
      'http://127.0.0.1/live/$_live.flv',
      'http://live.xhscdn.com/live/$_ended.flv',
      'http://u:p@live.xhscdn.com/live/$_live.flv',
      'http://live.xhscdn.com:8080/live/$_live.flv',
      'http://live.xhscdn.com/live/$_live.flv#x',
      'file:///live/$_live.flv',
      'http://live.xhscdn.com/live/$_live.flv?${'x' * 4096}',
    ]) {
      test(
        "an address outside the room's contract is left out; all of them is ApiChanged: ${url.length > 80 ? '(4 KiB)' : url}",
        () {
          final state = _state();
          _editStreams(state, (config) => _row(config, 1)['master_url'] = url);
          final streams = _streams(state);
          expect(streams.map((stream) => '${stream.url}'), isNot(contains(url)));
          expect(streams.map((stream) => stream.url.host), [
            'live-source-play.xhscdn.com',
            'live-source-play-bak-tx.xhscdn.com',
            'live-source-play-hw.xhscdn.com',
          ]);
          _editStreams(state, (config) {
            for (final row in (config['h264'] as List).cast<Map<String, dynamic>>()) {
              row['master_url'] = url;
            }
          });
          expect(() => _streams(state), throwsA(isA<ApiChanged>()));
        },
      );
    }

    for (final MapEntry(key: name, value: edit) in <String, void Function(Map<String, dynamic>)>{
      'no address': (row) => row.remove('master_url'),
      'a numeric address': (row) => row['master_url'] = 42,
      'an empty quality': (row) => row['quality_type'] = '',
      'no label': (row) => row.remove('quality_type_name'),
      'an empty label': (row) => row['quality_type_name'] = '',
      'a long quality': (row) => row['quality_type'] = 'Q' * 65,
      'a long label': (row) => row['quality_type_name'] = 'L' * 129,
    }.entries) {
      test('a row with $name is left out (16-4); only such rows is ApiChanged', () {
        final state = _state();
        _editStreams(state, (config) => edit(_row(config, 0)));
        expect(_streams(state), hasLength(3));
        _editStreams(state, (config) => (config['h264'] as List).cast<Map<String, dynamic>>().forEach(edit));
        expect(() => _streams(state), throwsA(isA<ApiChanged>()));
      });
    }

    test('a row that is not an object is left out; the other codec still plays', () {
      final state = _state();
      _editStreams(state, (config) {
        config['h265'] = [(config['h264'] as List<dynamic>)[1]];
        config['h264'] = [42, 'row', null];
      });
      final streams = _streams(state);
      expect(streams.single.codec, 'h265');
      final resolution = XiaohongshuApi.resolution(streams, XiaohongshuApi.qualities(streams).single);
      expect(resolution.lines.single.codec, 'hevc');
    });

    test('the signed query and codec are kept; exact repeats are one address', () {
      final state = _state();
      _editStreams(state, (config) {
        final first = _row(config, 0);
        first['master_url'] = '${first['master_url']}?a=1&a=2&sig=A%2FB';
        (config['h264'] as List<dynamic>).add(first);
        config['h265'] = [first];
      });
      final streams = _streams(state);
      expect(streams, hasLength(5));
      expect(streams.first.url.query, 'a=1&a=2&sig=A%2FB');
      expect(streams.last.codec, 'h265');
    });

    test('at most 32 rows per codec', () {
      final state = _state();
      _editStreams(state, (config) => config['h264'] = List.filled(33, (config['h264'] as List<dynamic>)[0]));
      expect(() => _streams(state), throwsA(isA<ApiChanged>()));
    });

    test('16-3: both codecs are one quality 原画; H.264 lines first, FLV first within each codec', () {
      final state = _state();
      _editStreams(state, (config) {
        final h264 = config['h264'] as List<dynamic>;
        config['h265'] = [
          for (final row in [h264[0], h264[3], h264[1]])
            {...row as Map<String, dynamic>, 'master_url': '${row['master_url']}?codec=hevc'},
        ];
      });
      final streams = _streams(state);
      final qualities = XiaohongshuApi.qualities(streams);
      expect(qualities.map((quality) => (quality.quality, quality.selectionId, quality.sort)), [('原画', 'HD', 0)]);
      final resolution = XiaohongshuApi.resolution(streams, qualities.single);
      expect(resolution.appliedQualityData, 'HD');
      expect(resolution.lines.map((line) => (line.codec, line.format, line.lineId)), [
        ('avc', StreamFormat.flv, 'flv:live-source-play'),
        ('avc', StreamFormat.flv, 'flv:live-source-play-bak-tx'),
        ('avc', StreamFormat.flv, 'flv:live-source-play-hw'),
        ('avc', StreamFormat.hls, 'hls:live-source-play'),
        ('hevc', StreamFormat.flv, 'flv:live-source-play-hw:hevc'),
        ('hevc', StreamFormat.flv, 'flv:live-source-play:hevc'),
        ('hevc', StreamFormat.hls, 'hls:live-source-play:hevc'),
      ]);
      expect(resolution.lines.skip(4).map((line) => line.url), everyElement(endsWith('?codec=hevc')));
    });

    test('several quality types stay apart, in address order, each named by the page', () {
      final state = _state();
      _editStreams(state, (config) {
        final h264 = config['h264'] as List<dynamic>;
        config['h265'] = [
          {...h264[1] as Map<String, dynamic>, 'quality_type': 'SD', 'quality_type_name': '标清'},
        ];
      });
      final streams = _streams(state);
      final qualities = XiaohongshuApi.qualities(streams);
      expect(qualities.map((quality) => (quality.quality, quality.selectionId)), [('原画', 'HD'), ('标清', 'SD')]);
      expect(XiaohongshuApi.resolution(streams, qualities.first).lines, hasLength(4));
      expect(XiaohongshuApi.resolution(streams, qualities.last).lines.single.lineId, 'flv:live-source-play:hevc');
    });

    test('repeated hosts get numbered line ids', () {
      final state = _state();
      _editStreams(state, (config) {
        final first = _row(config, 1);
        (config['h264'] as List<dynamic>).add({...first, 'master_url': '${first['master_url']}?backup=1'});
      });
      final streams = _streams(state);
      final lines = XiaohongshuApi.resolution(streams, XiaohongshuApi.qualities(streams).single).lines;
      expect(lines.map((line) => line.lineId), [
        'flv:live-source-play',
        'flv:live-source-play-bak-tx',
        'flv:live-source-play-hw',
        'flv:live-source-play#2',
        'hls:live-source-play',
      ]);
    });

    test("3.x's quality ids map to the ids now (for M9), and still play", () {
      expect(XiaohongshuApi.legacyQualityIds, {'h264:HD': 'HD', 'h265:HD': 'HD'});
      for (final (legacy, now) in [
        ('h264:HD', 'HD'),
        ('h265:HD', 'HD'),
        (' H264:SD ', 'SD'),
        ('h265:SD', 'SD'),
        ('HD', 'HD'),
        ('h266:HD', 'h266:HD'),
        ('原画 · H264', '原画 · H264'),
      ]) {
        expect(XiaohongshuApi.qualityIdFromLegacy(legacy), now, reason: legacy);
        expect(XiaohongshuApi.qualityIdFromLegacy(now), now, reason: 'applied again: $now');
      }
      final streams = _streams(_state());
      for (final id in ['h264:HD', 'h265:HD', 'HD']) {
        final resolution = XiaohongshuApi.resolution(streams, LivePlayQuality(quality: '原画 · H264', id: id));
        expect(resolution.appliedQualityData, 'HD', reason: id);
        expect(resolution.lines, hasLength(4), reason: id);
      }
    });

    test('a quality the addresses no longer have is StreamUnavailable', () {
      final streams = _streams(_state());
      for (final id in ['h264:SD', 'SD']) {
        expect(
          () => XiaohongshuApi.resolution(streams, LivePlayQuality(quality: '原画', id: id)),
          throwsA(isA<StreamUnavailable>()),
          reason: id,
        );
      }
    });

    group('HTTP status is not a page state', () {
      for (final (status, matcher) in [
        (302, isA<NetworkFailure>()),
        (401, isA<RiskControl>()),
        (403, isA<RiskControl>()),
        (406, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
      ]) {
        test('HTTP $status', () {
          expect(() => XiaohongshuApi.room('', requestedId: _live, status: status), throwsA(matcher));
        });
      }
    });
  });

  group('string-typed fields (the shape the archived spec recorded)', () {
    test('status "2", monetizeType "0", joinLimitTypes "[0]" and an object pullConfig are 3.x\'s live room', () {
      final state = _state();
      final info = _info(state);
      info['status'] = '2';
      info['monetizeType'] = '0';
      info['joinLimitTypes'] = '[0]';
      info['isSportsEvent'] = 'False';
      info['pullConfig'] = jsonDecode(info['pullConfig'] as String);
      final page = _parse(state);
      expect(page.room.isLiveNow, isTrue);
      expect(page.data.access, XiaohongshuAccess.public);
      expect(XiaohongshuApi.playable(page.data), hasLength(4));
      // 3.x refused each of these ("schema"), so a page of this shape never
      // opened there.
    });

    test('ended "3", and list entries written as strings', () {
      final state = _state('S01-room-ended');
      _info(state)
        ..['status'] = '3'
        ..['joinLimitTypes'] = ['0'];
      final page = _parse(state, roomId: _ended);
      expect(page.room.effectiveLiveStatus, LiveStatus.offline);
      expect(page.data.access, XiaohongshuAccess.public);
      final restricted = _state()..['liveStatus'] = 'success';
      _info(restricted)['joinLimitTypes'] = '[0,"2"]';
      expect(_parse(restricted).data.access, XiaohongshuAccess.restricted);
    });
  });

  group("links (3.x's XiaohongshuLink)", () {
    const id = '570341209400361612';
    const dynamicRoom = 'https://www.xiaohongshu.com/livestream/dynpath9oMyTyTC/$id';

    test('room ids, deep links and share pages name a room without a request', () {
      expect(XiaohongshuApi.roomIdFrom(' $id '), id);
      expect(XiaohongshuApi.roomIdFrom('xhsdiscover://live_audience?room_id=$id&source=share'), id);
      expect(XiaohongshuApi.roomIdFrom(dynamicRoom), id);
      expect(XiaohongshuApi.roomIdFrom('主播昵称'), isNull);
      expect(XiaohongshuApi.roomIdFrom('0'), isNull);
      expect(XiaohongshuApi.roomUrl(id).toString(), 'https://www.xiaohongshu.com/livestream/$id');
    });

    test('a deep link names only its room; flvUrl is a preload hint', () {
      expect(
        XiaohongshuApi.deepLinkRoomId(
          'xhsdiscover://live_audience?room_id=$id&source=share&flvUrl=http%3A%2F%2F127.0.0.1%2Fprivate',
        ),
        id,
      );
      expect(XiaohongshuApi.deepLinkRoomId('XHSDISCOVER://LIVE_AUDIENCE?room_id=$id&source=share'), id);
    });

    for (final link in [
      'xhsdiscover://live_audience?room_id=$id',
      'xhsdiscover://live_audience?room_id=$id&source=',
      'xhsdiscover://live_audience?source=a&room_id=$id&source=b',
      'xhsdiscover://live_audience?room_id=$id&host_id=63301151000000002303b082',
    ]) {
      test('16-2: a deep link names its room without a source: $link', () {
        expect(XiaohongshuApi.deepLinkRoomId(link), id);
        expect(XiaohongshuApi.roomIdFrom(link), id);
      });
    }

    for (final link in [
      'xhsdiscover://live_audience?source=share',
      'xhsdiscover://live_audience?room_id=$id&room_id=42&source=share',
      'xhsdiscover://live_audience?room_id=0&source=share',
      'xhsdiscover://live_audience?room_id=&source=share',
      'xhsdiscover://live_audience/path?room_id=$id&source=share',
      'xhsdiscover://live_audience?room_id=$id&source=share#fragment',
      'xhsdiscover://live_audience:8080?room_id=$id&source=share',
      'xhsdiscover://other?room_id=$id&source=share',
      'ftp://xhsdiscover://live_audience?room_id=$id&source=share',
    ]) {
      test('not a room deep link: $link', () {
        expect(XiaohongshuApi.deepLinkRoomId(link), isNull);
        expect(XiaohongshuApi.roomIdFrom(link), isNull);
      });
    }

    for (final url in [
      'https://www.xiaohongshu.com/livestream/$id',
      'https://xiaohongshu.com/livestream/$id',
      'http://www.xiaohongshu.com:80/livestream/$id/',
      'https://www.xiaohongshu.com:443/hina/livestream/$id',
      'https://www.xiaohongshu.com/hina/livestream/$id/123?room_id=42',
      '$dynamicRoom?host_id=42&xsec_token=fixture%3D#ignored',
      'https://www.xiaohongshu.com/livestream/$id?share_id=fixture',
    ]) {
      test('a share page alias names its room: $url', () {
        expect(XiaohongshuApi.webRoomId(url), id);
      });
    }

    for (final url in [
      'https://www.xiaohongshu.com/',
      'https://www.xiaohongshu.com/user/profile/$id',
      'https://www.xiaohongshu.com/explore/$id',
      'https://www.xiaohongshu.com.evil.test/livestream/$id',
      'https://www.xiaohongshu.com:8787/livestream/$id',
      'https://user@www.xiaohongshu.com/livestream/$id',
      'ftp://www.xiaohongshu.com/livestream/$id',
      'https://www.xiaohongshu.com/livestream/$id/.',
      'https://www.xiaohongshu.com/livestream/42/../$id',
      'https://www.xiaohongshu.com/livestream/%35$id',
      r'https://www.xiaohongshu.com/livestream/42\../' + id,
      'https://www.xiaohongshu.com/livestream/dynpathBAD/$id',
      'https://www.xiaohongshu.com/livestream/arbitrary/$id',
      'https://www.xiaohongshu.com/livestream/$id/extra',
      'https://www.xiaohongshu.com/hina/livestream/0/123',
      'https://www.xiaohongshu.com/hina/livestream/$id/123/extra',
      'https://live.bilibili.com/123',
      'https://[broken',
      '',
    ]) {
      test('not a share page: $url', () {
        expect(XiaohongshuApi.webRoomId(url), isNull);
      });
    }

    test('short links are xhslink.com codes only', () {
      expect(XiaohongshuApi.shortLink('https://xhslink.com/m/18ox3lAz'), Uri.parse('https://xhslink.com/m/18ox3lAz'));
      expect(XiaohongshuApi.shortLink('http://xhslink.com/zfknEQ/'), isNotNull);
      for (final url in [
        'https://www.xhslink.com/m/abc',
        'https://xhslink.com.evil.test/m/abc',
        'https://xhslink.com/m/abc/../def',
        'https://xhslink.com:8443/m/abc',
        'ftp://xhslink.com/m/abc',
      ]) {
        expect(XiaohongshuApi.shortLink(url), isNull, reason: url);
      }
    });

    test('E04.2: a code behind a prefix of one to four letters (/o/ of the app shares) is a short link', () {
      expect(XiaohongshuApi.shortLink('https://xhslink.com/o/AbC123'), Uri.parse('https://xhslink.com/o/AbC123'));
      for (final url in [
        'https://xhslink.com/a/fixture',
        'https://xhslink.com/abcd/AbC123/',
        'http://xhslink.com/O/AbC123',
      ]) {
        expect(XiaohongshuApi.shortLink(url), isNotNull, reason: url);
      }
      for (final url in [
        'https://xhslink.com/abcde/xyz',
        'https://xhslink.com/o1/AbC123',
        'https://xhslink.com/o/AbC123/extra',
        'https://xhslink.com/o/m/AbC123',
        'https://example.com/o/AbC123',
        'https://xhslink.com.evil.test/o/AbC123',
      ]) {
        expect(XiaohongshuApi.shortLink(url), isNull, reason: url);
      }
    });

    test('a hop needs a redirect with one plain Location', () {
      final current = Uri.parse('https://xhslink.com/first');
      expect(
        XiaohongshuApi.shortLinkHop(current, status: 302, locations: ['/m/second']),
        Uri.parse('https://xhslink.com/m/second'),
      );
      expect(
        XiaohongshuApi.shortLinkHop(current, status: 307, locations: ['//xhslink.com/m/third']),
        Uri.parse('https://xhslink.com/m/third'),
      );
      expect(XiaohongshuApi.shortLinkHop(current, status: 200, locations: [dynamicRoom]), isNull);
      expect(XiaohongshuApi.shortLinkHop(current, status: 302, locations: [dynamicRoom, dynamicRoom]), isNull);
      expect(XiaohongshuApi.shortLinkHop(current, status: 302, locations: ['  ']), isNull);
      expect(XiaohongshuApi.shortLinkHop(current, status: 302), isNull);
      for (final location in ['/m/first/../second', '/livestream/%35$id', r'/a\b', 'https://[broken']) {
        expect(XiaohongshuApi.shortLinkHop(current, status: 302, locations: [location]), isNull, reason: location);
      }
    });

    test('share texts: deep links not glued to another URL, prose cut off', () {
      expect(XiaohongshuApi.shareTextRoomIds('直播入口：xhsdiscover://live_audience?room_id=$id&source=share，复制'), [id]);
      expect(XiaohongshuApi.shareTextRoomIds('xhsdiscover://live_audience?room_id=$id&source=share).'), [id]);
      expect(
        XiaohongshuApi.shareTextRoomIds(
          'https://example.com/?target=xhsdiscover://live_audience?room_id=$id&source=share '
          'ftp://xhsdiscover://live_audience?room_id=$id&source=share',
        ),
        isEmpty,
      );
      expect(XiaohongshuApi.shareTextRoomIds('看直播 xhsdiscover://live_audience?room_id=$id，复制'), [id], reason: '16-2');
    });
  });
}
