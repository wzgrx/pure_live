// XiaohongshuSite over the recorded share pages and short link (ReplayHttp)
// and synthetic answers: the empty directory, exact search, the room at each
// depth, streams and recovery, links and short links through LinkParser, and
// the error mapping. The cases are ported from 3.x's
// test/xiaohongshu_application_test.dart (adapter part) and
// test/xiaohongshu_share_link_test.dart.
import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _root = '../../fixtures/xiaohongshu';
const _live = '570459564696889177';
const _ended = '570305058583373361';
const _missing = '569865232324657152';

const _userAgent = 'Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/87.0.4280.141 Mobile Safari/537.36';

typedef _Setup = ({XiaohongshuSite site, ReplayHttp http});

_Setup _setup(List<String> samples) {
  final http = ReplayHttp([for (final name in samples) ReplaySample.load('$_root/$name')]);
  return (site: XiaohongshuSite(http), http: http);
}

/// Answers every request with [handler]; records them.
final class _FakeHttp implements LiveHttp {
  new(this.handler);

  Future<LiveResponse> Function(LiveRequest request) handler;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) {
    requests.add(request);
    return handler(request);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    final response = await send(request);
    return LiveStreamedResponse(
      status: response.status,
      body: Stream.value(response.bytes),
      url: response.url,
      headers: response.headers,
    );
  }

  @override
  void close() {}
}

LiveResponse _redirect(int status, String location, LiveRequest request) => LiveResponse(
  status: status,
  bytes: const [],
  url: request.url,
  headers: {
    'location': [location],
  },
);

/// `liveStream` of the recorded live page, to edit (3.x's live.json).
Map<String, dynamic> _state([String sample = 'S01-room-live']) {
  const marker = 'window.__INITIAL_STATE__=';
  final body = Fixture.load('xiaohongshu', sample).body;
  final start = body.indexOf(marker) + marker.length;
  final json = body.substring(start, body.indexOf('</script>', start)).replaceAll(':undefined', ':null');
  return ((jsonDecode(json) as Map<String, dynamic>)['liveStream'] as Map).cast<String, dynamic>();
}

/// The [codec] rows of a decoded `pullConfig`.
List<Map<String, dynamic>> _rows(Map<String, dynamic> config, String codec) =>
    (config[codec] as List<dynamic>).cast<Map<String, dynamic>>();

Map<String, dynamic> _info(Map<String, dynamic> state) =>
    ((state['roomData'] as Map)['roomInfo'] as Map).cast<String, dynamic>();

/// 3.x's application fixture: one live room served by a page it can edit
/// between requests.
final class _Room {
  new([String roomId = _live]) : state = _state() {
    if (roomId != _live) {
      state = jsonDecode(jsonEncode(state).replaceAll(_live, roomId)) as Map<String, dynamic>;
    }
    http = _FakeHttp((request) async {
      expect(request.url.toString(), 'https://www.xiaohongshu.com/livestream/$roomId');
      return LiveResponse(
        status: status,
        bytes: status == 200
            ? utf8.encode('<script>window.__INITIAL_STATE__=${jsonEncode({'liveStream': state})}</script>')
            : const [],
        url: request.url,
      );
    });
    site = XiaohongshuSite(http);
  }

  Map<String, dynamic> state;
  int status = 200;
  late final _FakeHttp http;
  late final XiaohongshuSite site;

  Map<String, dynamic> get info => _info(state);

  void offline() {
    info['status'] = 3;
    state['liveStatus'] = 'end';
  }

  void streams(void Function(Map<String, dynamic> config) edit) {
    final config = jsonDecode(info['pullConfig'] as String) as Map<String, dynamic>;
    edit(config);
    info['pullConfig'] = jsonEncode(config);
  }
}

void main() {
  test("3.x's capabilities: a directory notice, no search paging, no danmaku", () {
    final site = XiaohongshuSite(ReplayHttp(const []));
    expect(site.id, 'xiaohongshu');
    expect(site.name, '小红书');
    expect(site, isA<LiveSiteDirectoryPager>());
    expect(site, isA<LiveDirectoryNotice>());
    expect(site.directoryNoticeKey, 'xiaohongshu_directory_scope');
    expect(site, isA<LiveSiteRoomRefresher>());
    expect(site, isA<LiveSiteRecordRoomResolver>());
    expect(site, isA<LivePlayUrlResolver>());
    expect(site, isA<LivePlayRecoveryResolver>());
    expect(site, isA<LiveSiteLinks>());
    expect(site, isNot(isA<LiveCancellableSearch>()));
    expect(site, isNot(isA<LiveSearchPaginationPolicy>()));
    expect(site.getDanmaku(), isA<EmptyDanmaku>(), reason: '3.x had no Xiaohongshu danmaku');
    expect(AudiencePlatformCapability.of('xiaohongshu').supportsConcurrentOnline, isFalse);
  });

  group('directory', () {
    test('empty, without a request, and never another page', () async {
      final setup = _setup(const []);
      final first = await setup.site.getDirectoryPage();
      expect(first.rooms, isEmpty);
      expect(first.hasMore, isFalse);
      expect((await setup.site.getDirectoryPage(page: 2)).hasMore, isFalse);
      expect(await setup.site.getRecommendRooms(), isEmpty);
      expect(await setup.site.getCategories(1, 30), isEmpty);
      expect(await setup.site.getCategoryRooms(const LiveArea(platform: 'xiaohongshu', areaId: '1')), isEmpty);
      expect(setup.http.requests, isEmpty);
    });

    test('cancelled, page 0 or a category are refused (3.x)', () async {
      final site = _setup(const []).site;
      await expectLater(
        site.getDirectoryPage(cancel: CancelToken()..cancel()),
        throwsA(isA<TransportFailure>().having((failure) => failure.reason, 'reason', TransportReason.cancelled)),
      );
      await expectLater(site.getDirectoryPage(page: 0), throwsRangeError);
      await expectLater(
        site.getDirectoryPage(
          category: const LiveArea(platform: 'xiaohongshu', areaId: '1'),
        ),
        throwsArgumentError,
      );
    });

    test("the notice text is 3.x's", () {
      expect(XiaohongshuApi.directoryScope, startsWith('暂无已接入的公开直播目录。'));
    });
  });

  group('rooms', () {
    test("one request with 3.x's headers, no redirect, as xiaohongshu", () async {
      final setup = _setup(['S01-room-live']);
      final room = await setup.site.getRoomDetail(roomId: _live);
      final request = setup.http.requests.single;
      expect(request.url.toString(), 'https://www.xiaohongshu.com/livestream/$_live');
      expect(request.site, 'xiaohongshu', reason: 'the app routes the platform through its proxy');
      expect(request.followRedirects, isFalse, reason: 'the page must be the one asked for');
      expect(request.headers, {'referer': 'https://www.xiaohongshu.com/', 'user-agent': _userAgent});
      expect(room.data, isA<XiaohongshuRoomData>());
      expect(room.danmakuData, isNull);
    });

    for (final (sample, roomId) in [('S01-room-live', _live), ('S01-room-ended', _ended)]) {
      test("$sample: every depth is 3.x's room under the id asked for, one request each", () async {
        final setup = _setup([sample]);
        final legacy = Fixture.load('xiaohongshu', sample).legacy as Map<String, dynamic>;
        final entry = await setup.site.getRoomDetail(roomId: roomId);
        final refresh = await setup.site.getRoomDetailForRefresh(roomId: roomId);
        final recording = await setup.site.getRoomDetailForRecording(roomId: roomId);
        final search = await setup.site.searchRooms(roomId);
        for (final (name, room) in [
          ('getRoomDetail', entry),
          ('getRoomDetailForRefresh', refresh),
          ('getRoomDetailForRecording', recording),
          ('searchRooms(roomId)', search.single),
        ]) {
          final expected = legacy[name] as Map<String, dynamic>;
          expect(expected['requests'], 1, reason: name);
          final answer = expected['value'];
          final legacyRoom = (answer is List ? answer.single : answer) as Map<String, dynamic>;
          final json = {...room.toJson(), 'link': room.link};
          for (final MapEntry(:key, :value) in legacyRoom.entries) {
            expect(json[key] ?? '', value ?? '', reason: '$name $key');
          }
          expect(room.roomId, roomId);
        }
        expect(setup.http.requests, hasLength(4));
        expect(refresh.data, isNull, reason: '3.x refreshed without stream data');
        expect(search.single.data, isNull);
        expect(recording.data, isA<XiaohongshuRoomData>());
        expect(
          await setup.site.getLiveStatus(roomId: roomId),
          (legacy['getLiveStatus'] as Map<String, dynamic>)['value'],
        );
      });
    }

    test('a stored follow merges with the refresh (same identity)', () async {
      final setup = _setup(['S01-room-live']);
      final stored = LiveRoom.fromJson(const {
        'roomId': _live,
        'platform': 'xiaohongshu',
        'title': 'old',
        'liveStatus': 1,
      });
      final merged = stored.mergeFrom(await setup.site.getRoomDetailForRefresh(roomId: _live));
      expect(merged.title, '老片回放《武林外传》');
      expect(merged.isLiveNow, isTrue);
    });

    test('a room id is trimmed; one that is not a room id is NotFound without a request', () async {
      final setup = _setup(['S01-room-live']);
      expect((await setup.site.getRoomDetail(roomId: ' $_live ')).roomId, _live);
      for (final id in ['', '0', 'abc', '123456789012345678901', '12/3']) {
        await expectLater(setup.site.getRoomDetail(roomId: id), throwsA(isA<NotFound>()), reason: id);
      }
      expect(setup.http.requests, hasLength(1));
    });

    test('S01 not found: NotFound at every depth (3.x: an unexplained page error)', () async {
      final setup = _setup(['S01-room-notfound']);
      await expectLater(setup.site.getRoomDetail(roomId: _missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetailForRefresh(roomId: _missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getRoomDetailForRecording(roomId: _missing), throwsA(isA<NotFound>()));
      await expectLater(setup.site.getLiveStatus(roomId: _missing), throwsA(isA<NotFound>()));
    });

    test('a state the page does not name: an unknown room, and getLiveStatus is ApiChanged (3.x)', () async {
      final room = _Room();
      room.info['status'] = 9;
      expect((await room.site.getRoomDetail(roomId: _live)).effectiveLiveStatus, LiveStatus.unknown);
      expect((await room.site.searchRooms(_live)).single.effectiveLiveStatus, LiveStatus.unknown);
      await expectLater(room.site.getLiveStatus(roomId: _live), throwsA(isA<ApiChanged>()));
    });

    test('recording: ended rooms as they are; a room that cannot be played fails (3.x)', () async {
      final room = _Room()..offline();
      expect((await room.site.getRoomDetailForRecording(roomId: _live)).isExplicitlyOfflineNow, isTrue);
      room
        ..info['status'] = 2
        ..state['liveStatus'] = 'success'
        ..info['monetizeType'] = 1;
      final refresh = await room.site.getRoomDetailForRefresh(roomId: _live);
      expect(refresh.isLiveNow, isTrue);
      expect(refresh.notice, contains(XiaohongshuApi.restrictedNotice));
      await expectLater(room.site.getRoomDetailForRecording(roomId: _live), throwsA(isA<NeedsLogin>()));
      room.info
        ..['monetizeType'] = 0
        ..remove('pullConfig');
      await expectLater(room.site.getRoomDetailForRecording(roomId: _live), throwsA(isA<StreamUnavailable>()));
      room.info['status'] = 9;
      await expectLater(room.site.getRoomDetailForRecording(roomId: _live), throwsA(isA<StreamUnavailable>()));
    });

    test('a malformed pull address fails playback and recording, not the room page or the refresh', () async {
      final room = _Room()
        ..streams((config) => _rows(config, 'h264').first['master_url'] = 'http://127.0.0.1/live/x.flv');
      final detail = await room.site.getRoomDetail(roomId: _live);
      expect(detail.isLiveNow, isTrue);
      expect((await room.site.getRoomDetailForRefresh(roomId: _live)).isLiveNow, isTrue);
      await expectLater(room.site.getPlayQualities(detail: detail), throwsA(isA<ApiChanged>()));
      await expectLater(room.site.getRoomDetailForRecording(roomId: _live), throwsA(isA<ApiChanged>()));
    });

    test('HTTP errors keep their kind; transport failures are NetworkFailure; cancellation stays', () async {
      final room = _Room();
      for (final (status, matcher) in [
        (403, isA<RiskControl>()),
        (404, isA<NotFound>()),
        (429, isA<RateLimited>()),
        (503, isA<NetworkFailure>()),
        (302, isA<NetworkFailure>()),
      ]) {
        room.status = status;
        await expectLater(room.site.getRoomDetail(roomId: _live), throwsA(matcher), reason: '$status');
      }
      room.http.handler = (_) async => throw const TransportFailure('xiaohongshu', TransportReason.timeout);
      await expectLater(room.site.getRoomDetail(roomId: _live), throwsA(isA<NetworkFailure>()));
      room.http.handler = (_) async => throw const TransportFailure('xiaohongshu', TransportReason.cancelled);
      await expectLater(room.site.getRoomDetail(roomId: _live), throwsA(isA<TransportFailure>()));
    });
  });

  group('search (exact lookup)', () {
    for (final input in [
      _live,
      ' $_live ',
      'https://www.xiaohongshu.com/livestream/$_live',
      'http://www.xiaohongshu.com/livestream/$_live/?share=fixture',
      'https://xiaohongshu.com/livestream/$_live',
      'https://www.xiaohongshu.com/hina/livestream/$_live',
      'https://www.xiaohongshu.com/hina/livestream/$_live/123',
      'https://www.xiaohongshu.com/livestream/dynpath9oMyTyTC/$_live',
      'xhsdiscover://live_audience?room_id=$_live&source=share_out_of_app',
    ]) {
      test('one room under its broadcast id, one request: $input', () async {
        final room = _Room();
        final found = (await room.site.searchRooms(input)).single;
        expect(found.roomId, _live);
        expect(found.userId, isNull);
        expect(found.data, isNull);
        expect(found.isLiveNow, isTrue);
        expect(found.notice, startsWith(XiaohongshuApi.roomScopeNotice));
        expect(found.onlineViewers, isEmpty);
        expect(found.totalViewers, isEmpty);
        expect(found.audienceValue(preferRealOnline: false, platformEnabled: false), isEmpty);
        expect(await room.site.searchRooms(input, page: 2), isEmpty);
        expect(room.http.requests, hasLength(1));
      });
    }

    test('keywords and prose around a link give nothing without a request (3.x)', () async {
      final room = _Room();
      expect(await room.site.searchRooms('主播昵称'), isEmpty);
      expect(await room.site.searchRooms('看直播 https://www.xiaohongshu.com/livestream/$_live'), isEmpty);
      expect(await room.site.searchRooms(''), isEmpty);
      expect(room.http.requests, isEmpty);
    });

    test('404 gives nothing; other failures are thrown (3.x)', () async {
      final room = _Room()..status = 404;
      expect(await room.site.searchRooms(_live), isEmpty);
      room.status = 403;
      await expectLater(room.site.searchRooms(_live), throwsA(isA<RiskControl>()));
      final missing = _setup(['S01-room-notfound']);
      final legacy = Fixture.load('xiaohongshu', 'S01-room-notfound').legacy as Map<String, dynamic>;
      final thrown = (legacy['searchRooms(roomId)'] as Map<String, dynamic>)['value'] as Map<String, dynamic>;
      expect(thrown['message'], 'Xiaohongshu api', reason: '3.x showed an error');
      await expectLater(missing.site.searchRooms(_missing), throwsA(isA<NotFound>()));
    });

    test('S02 an expired short link: one hop to the home page, no room, no page request', () async {
      final setup = _setup(['S02-shortlink-expired']);
      final legacy = Fixture.load('xiaohongshu', 'S02-shortlink-expired').legacy as Map<String, dynamic>;
      expect(await setup.site.searchRooms('https://xhslink.com/m/18ox3lAz'), isEmpty);
      expect(legacy['searchRooms(shortLink only)'], {'requests': 1, 'value': <Object?>[]});
      final request = setup.http.requests.single;
      expect(request.url.toString(), 'https://xhslink.com/m/18ox3lAz');
      expect(request.followRedirects, isFalse);
      expect(request.site, 'xiaohongshu');
      expect(request.headers['user-agent'], _userAgent);
    });

    test('a short link to a room: the hop, then the room page (share metadata stripped); page 2 is empty', () async {
      const id = '570341209400361612';
      final room = _Room(id);
      final page = room.http.handler;
      room.http.handler = (request) async => request.url.host == 'xhslink.com'
          ? _redirect(
              302,
              'https://www.xiaohongshu.com/livestream/dynpath9oMyTyTC/$id?host_id=42&xsec_token=x',
              request,
            )
          : await page(request);
      final found = await room.site.searchRooms('https://xhslink.com/m/first');
      expect(found.single.roomId, id);
      expect(found.single.data, isNull);
      expect(room.http.requests.map((request) => request.url.toString()), [
        'https://xhslink.com/m/first',
        'https://www.xiaohongshu.com/livestream/$id',
      ]);
      expect(await room.site.searchRooms('https://xhslink.com/m/first', page: 2), isEmpty);
      expect(room.http.requests, hasLength(2));
    });

    test("a short link that fails gives nothing; each hop has 3.x's 12-second limit", () async {
      final http = _FakeHttp((_) async => throw const TransportFailure('xiaohongshu', TransportReason.timeout));
      expect(await XiaohongshuSite(http).searchRooms('https://xhslink.com/m/slow'), isEmpty);
      expect(http.requests.single.timeout, const Duration(seconds: 12));
    });
  });

  group('streams', () {
    test("room entry's stream: 3.x's quality and four lines, without another request", () async {
      final room = _Room();
      final detail = await room.site.getRoomDetail(roomId: _live);
      final qualities = await room.site.getPlayQualities(detail: detail);
      expect(qualities.single.selectionId, 'h264:HD');
      expect(qualities.single.data, isNull);
      final resolution = await room.site.resolvePlayUrls(detail: detail, quality: qualities.single);
      expect(resolution.urls, hasLength(4));
      expect(resolution.urls.first, endsWith('.m3u8'));
      expect(resolution.appliedQualityData, 'h264:HD');
      expect(resolution.lines.first.headers['referer'], 'https://www.xiaohongshu.com/');
      expect(await room.site.getPlayUrls(detail: detail, quality: qualities.single), resolution.urls);
      expect(room.http.requests, hasLength(1));
    });

    test('codec-qualified ids survive a reorder; recovery reads the page again (3.x)', () async {
      final room = _Room()..streams((config) => config['h265'] = [(config['h264'] as List<dynamic>)[0]]);
      final detail = await room.site.getRoomDetail(roomId: _live);
      final qualities = await room.site.getPlayQualities(detail: detail);
      expect(qualities.map((quality) => quality.selectionId), ['h264:HD', 'h265:HD']);
      room.streams((config) {
        config['h264'] = (config['h264'] as List<dynamic>).reversed.toList();
        for (final row in _rows(config, 'h265')) {
          row['master_url'] = '${row['master_url']}?token=renewed';
        }
      });
      final result = await room.site.resolvePlayUrlsForRecovery(detail: detail, quality: qualities.last);
      expect(result.urls.single, endsWith('?token=renewed'));
      expect(result.appliedQualityData, 'h265:HD');
      expect(result.lines.single.codec, 'hevc');
      expect(room.http.requests, hasLength(2));
    });

    test('recovery refuses a room that changed, closed, ended or lost the quality (3.x)', () async {
      final room = _Room();
      final detail = await room.site.getRoomDetail(roomId: _live);
      final quality = (await room.site.getPlayQualities(detail: detail)).single;
      room.info['roomId'] = '123';
      await expectLater(
        room.site.resolvePlayUrlsForRecovery(detail: detail, quality: quality),
        throwsA(isA<ApiChanged>()),
      );
      room.info
        ..['roomId'] = _live
        ..['monetizeType'] = 1;
      await expectLater(
        room.site.resolvePlayUrlsForRecovery(detail: detail, quality: quality),
        throwsA(isA<NeedsLogin>()),
      );
      room.info['monetizeType'] = 0;
      room.offline();
      await expectLater(
        room.site.resolvePlayUrlsForRecovery(detail: detail, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      room
        ..info['status'] = 2
        ..state['liveStatus'] = 'success'
        ..streams((config) {
          for (final row in _rows(config, 'h264')) {
            row['quality_type'] = 'SD';
          }
        });
      await expectLater(
        room.site.resolvePlayUrlsForRecovery(detail: detail, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(room.http.requests, hasLength(5));
    });

    test('an ended room has no stream, without a request (3.x listed no quality)', () async {
      final room = _Room()..offline();
      final detail = await room.site.getRoomDetail(roomId: _live);
      final legacy = Fixture.load('xiaohongshu', 'S01-room-ended').legacy as Map<String, dynamic>;
      expect(legacy['getPlayQualites'], isEmpty);
      await expectLater(room.site.getPlayQualities(detail: detail), throwsA(isA<StreamUnavailable>()));
      const quality = LivePlayQuality(quality: '原画 · H264', id: 'h264:HD');
      await expectLater(room.site.getPlayUrls(detail: detail, quality: quality), throwsA(isA<StreamUnavailable>()));
      await expectLater(
        room.site.resolvePlayUrlsForRecovery(detail: detail, quality: quality),
        throwsA(isA<StreamUnavailable>()),
      );
      expect(room.http.requests, hasLength(1));
    });

    test("a card without the page's data (search, follow) is read first; 3.x failed it", () async {
      final room = _Room();
      final card = (await room.site.searchRooms(_live)).single;
      final qualities = await room.site.getPlayQualities(detail: card);
      expect(qualities.single.selectionId, 'h264:HD');
      expect(room.http.requests, hasLength(2));
      final stale = card.copyWith(
        data: const XiaohongshuRoomData(roomId: '1', live: true, access: XiaohongshuAccess.public),
      );
      expect(await room.site.getPlayUrls(detail: stale, quality: qualities.single), hasLength(4));
      expect(room.http.requests, hasLength(3), reason: "another room's data is not used");
    });

    test('a quality the page does not list, or a room of another platform, is refused', () async {
      final room = _Room();
      final detail = await room.site.getRoomDetail(roomId: _live);
      await expectLater(
        room.site.getPlayUrls(
          detail: detail,
          quality: const LivePlayQuality(id: 'missing', quality: 'HD', data: ['https://evil.test/a.flv']),
        ),
        throwsA(isA<StreamUnavailable>()),
      );
      await expectLater(
        room.site.getPlayQualities(
          detail: LiveRoom(roomId: _live, platform: 'bilibili'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('links', () {
    const id = '570341209400361612';
    const dynamicRoom = 'https://www.xiaohongshu.com/livestream/dynpath9oMyTyTC/$id';

    late _FakeHttp http;
    late LinkParser parser;

    void serve(Future<LiveResponse> Function(LiveRequest request) handler) {
      http = _FakeHttp(handler);
      parser = LinkParser(
        SiteRegistry({'xiaohongshu': () => XiaohongshuSite(http), 'bilibili': () => BilibiliSite(http)}),
        http,
      );
    }

    setUp(() => serve((_) async => throw StateError('No network')));

    test('a deep link in a share text imports only its room, without a request', () async {
      const link = 'xhsdiscover://live_audience?room_id=$id&source=share&flvUrl=http%3A%2F%2F127.0.0.1%2Fprivate';
      expect(parser.containsSupportedLink('直播入口：$link，复制'), isTrue);
      expect(await parser.parse('直播入口：$link，复制'), const RoomLink('xiaohongshu', id));
      expect(http.requests, isEmpty);
    });

    for (final link in [
      'xhsdiscover://live_audience?room_id=$id',
      'xhsdiscover://live_audience?room_id=$id&room_id=42&source=share',
      'xhsdiscover://live_audience?room_id=0&source=share',
      'xhsdiscover://live_audience?room_id=$id&source=',
      'xhsdiscover://live_audience/path?room_id=$id&source=share',
      'xhsdiscover://live_audience?room_id=$id&source=share#fragment',
      'xhsdiscover://other?room_id=$id&source=share',
      'ftp://xhsdiscover://live_audience?room_id=$id&source=share',
      'https://example.com/?target=xhsdiscover://live_audience?room_id=$id&source=share',
    ]) {
      test('not a room deep link: $link', () async {
        expect(parser.containsSupportedLink(link), isFalse);
        expect(await parser.parse(link), isNull);
        expect(http.requests, isEmpty);
      });
    }

    for (final url in [
      dynamicRoom,
      'https://xiaohongshu.com/livestream/$id',
      'http://www.xiaohongshu.com:80/livestream/$id/',
      'https://www.xiaohongshu.com:443/hina/livestream/$id',
      'https://www.xiaohongshu.com/hina/livestream/$id/123?room_id=42',
      '$dynamicRoom?host_id=42&xsec_token=fixture%3D#ignored',
    ]) {
      test('a share page names its room without HTTP: $url', () async {
        expect(parser.containsSupportedLink(url), isTrue);
        expect(await parser.parse(url), const RoomLink('xiaohongshu', id));
        expect(http.requests, isEmpty);
      });
    }

    for (final suffix in ['/.', '/..', '/.。复制', '/..)', '/.?share=fixture']) {
      test('a trailing dot segment is kept and refused: $suffix', () async {
        final url = 'https://www.xiaohongshu.com/livestream/$id$suffix';
        expect(parser.containsSupportedLink(url), isFalse);
        expect(await parser.parse(url), isNull);
        expect(http.requests, isEmpty);
      });
    }

    for (final url in [
      'https://www.xiaohongshu.com.evil.test/livestream/$id',
      'https://www.xiaohongshu.com/user/profile/$id',
      'https://www.xiaohongshu.com/livestream/1/../$id',
      'https://www.xiaohongshu.com/livestream/%35$id',
      'https://www.xiaohongshu.com:8787/livestream/$id',
      'https://user@www.xiaohongshu.com/livestream/$id',
      'https://xhslink.com/a/fixture',
    ]) {
      test('unverified or malformed links stay unrecognised: $url', () async {
        expect(parser.containsSupportedLink(url), isFalse);
        expect(await parser.parse(url), isNull);
        expect(http.requests, isEmpty);
      });
    }

    test("a short link resolves in one hop without fetching the room page; 3.x's headers", () async {
      serve((request) async => _redirect(302, dynamicRoom, request));
      expect(await parser.parse('分享 https://xhslink.com/m/4vYwu2cQpeP，'), const RoomLink('xiaohongshu', id));
      final request = http.requests.single;
      expect(request.followRedirects, isFalse);
      expect(request.headers['user-agent'], _userAgent);
      expect(request.headers['referer'], 'https://www.xiaohongshu.com/');
    });

    for (final status in [301, 302, 303, 307, 308]) {
      test('HTTP $status is a hop', () async {
        serve((request) async => _redirect(status, dynamicRoom, request));
        expect(await parser.parse('http://xhslink.com/zfknEQ'), const RoomLink('xiaohongshu', id));
        expect(http.requests, hasLength(1));
      });
    }

    test('the share prose around a short link', () async {
      serve((request) async => _redirect(302, dynamicRoom, request));
      const text = '小红书，正在直播 😆 https://xhslink.com/m/abc123，复制本条信息，打开【小红书】，直接观看直播！';
      expect(parser.containsSupportedLink(text), isTrue);
      expect(await parser.parse(text), const RoomLink('xiaohongshu', id));
      expect(http.requests.single.url.path, '/m/abc123');
    });

    test('a hop to an app deep link names its room', () async {
      serve((request) async => _redirect(302, 'xhsdiscover://live_audience?room_id=$id&source=share', request));
      expect(await parser.parse('https://xhslink.com/m/abc'), const RoomLink('xiaohongshu', id));
    });

    for (final location in [
      'https://www.xiaohongshu.com/',
      'https://www.xiaohongshu.com/user/profile/$id',
      'https://www.xiaohongshu.com/explore/$id',
      'https://live.bilibili.com/123',
      'http://127.0.0.1/private',
      'http://192.168.1.2:8787/mcp',
      'https://xhslink.com.evil.test/m/abc',
      'https://www.xiaohongshu.com.evil.test/livestream/$id',
      'https://www.xiaohongshu.com:8787/livestream/$id',
      'https://user@www.xiaohongshu.com/livestream/$id',
      'ftp://www.xiaohongshu.com/livestream/$id',
      'https://www.xiaohongshu.com/livestream/$id/.',
      'https://www.xiaohongshu.com/livestream/42/../$id',
      'https://www.xiaohongshu.com/livestream/%35$id',
      r'https://www.xiaohongshu.com/livestream/42\../' + id,
      '/m/first/../second',
      'https://www.xiaohongshu.com/livestream/dynpathBAD/$id',
      'https://www.xiaohongshu.com/livestream/arbitrary/$id',
      'https://www.xiaohongshu.com/hina/livestream/0/123',
      'https://www.xiaohongshu.com/hina/livestream/$id/123/extra',
      'https://[broken',
      '',
    ]) {
      test('a landing that is no room is not fetched, nor handed to other platforms: $location', () async {
        serve((request) async => _redirect(302, location, request));
        expect(await parser.parse('https://xhslink.com/m/abc'), isNull);
        expect(http.requests, hasLength(1));
      });
    }

    for (final status in [200, 204, 400, 404, 429, 500]) {
      test('HTTP $status with a Location is not a redirect', () async {
        serve((request) async => _redirect(status, dynamicRoom, request));
        expect(await parser.parse('https://xhslink.com/m/abc'), isNull);
        expect(http.requests, hasLength(1));
      });
    }

    test('two Location values are ambiguous', () async {
      serve(
        (request) async => LiveResponse(
          status: 302,
          bytes: const [],
          url: request.url,
          headers: const {
            'location': [dynamicRoom, 'https://www.xiaohongshu.com/livestream/123'],
          },
        ),
      );
      expect(await parser.parse('https://xhslink.com/m/abc'), isNull);
      expect(http.requests, hasLength(1));
    });

    test('relative and protocol-relative hops share one budget', () async {
      serve(
        (request) async => _redirect(302, switch (request.url.path) {
          '/first' => '/m/second',
          '/m/second' => '//xhslink.com/m/third',
          _ => dynamicRoom,
        }, request),
      );
      expect(await parser.parse('https://xhslink.com/first'), const RoomLink('xiaohongshu', id));
      expect(http.requests.map((request) => request.url.path), ['/first', '/m/second', '/m/third']);
    });

    test('fragments do not evade the visited check', () async {
      var next = 0;
      serve((request) async => _redirect(302, 'https://xhslink.com/first#${++next}', request));
      expect(await parser.parse('https://xhslink.com/first'), isNull);
      expect(http.requests, hasLength(1));
    });

    test('distinct hops stop at the session budget', () async {
      var next = 0;
      serve((request) async => _redirect(302, 'https://xhslink.com/m/next${++next}', request));
      expect(await parser.parse('https://xhslink.com/first'), isNull);
      expect(http.requests, hasLength(ShortLinkSession.maxRequests));
    });

    test('a failed short link does not hide a later room of another platform', () async {
      serve((request) async => _redirect(307, 'https://www.xiaohongshu.com/', request));
      expect(
        await parser.parse('https://xhslink.com/expired https://live.bilibili.com/123'),
        const RoomLink('bilibili', '123'),
      );
      expect(http.requests, hasLength(1));
    });

    for (final timeout in [false, true]) {
      test('a ${timeout ? 'deadline' : 'cancellation'} prevents a late hop', () async {
        final pending = Completer<LiveResponse>();
        final started = Completer<void>();
        serve((_) {
          started.complete();
          return pending.future;
        });
        final cancel = CancelToken();
        final action = parser.parse(
          'https://xhslink.com/first',
          cancel: cancel,
          timeout: timeout ? const Duration(milliseconds: 30) : const Duration(seconds: 1),
        );
        await started.future;
        if (!timeout) cancel.cancel();
        expect(await action, isNull);
        pending.complete(_redirect(302, 'https://xhslink.com/m/late', LiveRequest(site: 'x', url: Uri())));
        await Future<void>.delayed(Duration.zero);
        expect(http.requests, hasLength(1));
      });
    }
  });
}
