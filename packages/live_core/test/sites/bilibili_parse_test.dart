// v4 Bilibili parsing against the recorded samples, compared with the legacy
// parser's frozen output. Deviations the spec (or DIAGNOSIS "样本录制中发现的
// 问题") requires are asserted explicitly.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  Fixture sample(String name) => Fixture.load('bilibili', name);

  test('S01 categories match legacy ids, names, parent ids and icons', () {
    final fixture = sample('S01-guest');
    final categories = BilibiliParse.categories(fixture.body, status: fixture.status);
    final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
    expect(categories.map((c) => c.id), legacy.map((c) => c['id']));
    expect(categories.map((c) => c.name), legacy.map((c) => c['name']));
    for (final (index, category) in categories.indexed) {
      final areas = (legacy[index]['children'] as List).cast<Map<String, dynamic>>();
      expect(category.areas.map((a) => a.id), areas.map((a) => a['areaId']));
      expect(category.areas.map((a) => a.name), areas.map((a) => a['areaName']));
      expect(category.areas.map((a) => a.categoryId), areas.map((a) => a['areaType']));
      expect(category.areas.map((a) => a.icon?.toString()), areas.map((a) => a['areaPic']));
    }
  });

  test('S02 second/getList -352 is RiskControl (legacy double-wrapped an Exception)', () {
    for (final name in ['S02-risk352', 'S02-signed-risk352']) {
      final fixture = sample(name);
      // DIAGNOSIS: "-352 被包成两层异常"; §9 / REG-BILIBILI-006: a typed RiskControl.
      final thrown = (fixture.legacy as Map<String, dynamic>)['throws'] as Map<String, dynamic>;
      expect(thrown['message'], startsWith('Exception: Exception:'), reason: name);
      expect(
        () => BilibiliParse.areaRoomsPage(fixture.body, page: 1, status: fixture.status),
        throwsA(isA<RiskControl>()),
        reason: name,
      );
    }
  });

  void expectCardsMatchLegacy(List<RoomCard> rooms, List<Map<String, dynamic>> legacy) {
    expect(rooms.map((r) => r.ref.roomId), legacy.map((r) => r['roomId']));
    expect(rooms.map((r) => r.title), legacy.map((r) => r['title']));
    expect(rooms.map((r) => r.anchorName), legacy.map((r) => r['nick']));
    expect(rooms.map((r) => r.area), legacy.map((r) => r['area']));
    expect(rooms.map((r) => r.audience.popularity), legacy.map((r) => int.parse(r['popularity'] as String)));
    expect(rooms.map((r) => r.state == LiveState.live), legacy.map((r) => r['status']));
    // `online` is popularity, never an online count (§4.4, REG-BILIBILI-014).
    expect(rooms.every((r) => r.audience.online == null), isTrue);
  }

  group('S03/S04 recommend', () {
    for (final name in ['S03-page1', 'S03-out-of-range', 'S04-page1']) {
      test('$name matches legacy', () {
        final fixture = sample(name);
        final page = int.parse(fixture.url.queryParameters['page']!);
        final result = BilibiliParse.recommendPage(fixture.body, page: page, status: fixture.status);
        final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
        expectCardsMatchLegacy(result.items, legacy);
        expect(result.items.map((r) => r.cover?.toString()), legacy.map((r) => r['cover']));
        // `face` is the streamer's avatar; the 3.3.x bridge shows it on legacy cards.
        expect(result.items.map((r) => r.avatar?.toString() ?? ''), legacy.map((r) => r['avatar']));
        // Neither endpoint reports an end: only the empty page is the last one.
        expect(result.isLast, legacy.isEmpty);
      });
    }

    test('watched_show "N人看过" is cumulative; "N人气" (switch false) only repeats popularity', () {
      // Legacy dropped watched_show (totalViewers ''); ADR 0010 rule 3 keeps the measure.
      for (final name in ['S03-page1', 'S04-page1']) {
        final fixture = sample(name);
        final rooms = BilibiliParse.recommendPage(fixture.body, page: 1).items;
        final data = (jsonDecode(fixture.body) as Map)['data'];
        final raw = [
          for (final item in (data is Map ? data['recommend_room_list'] : data) as List) item as Map<String, dynamic>,
        ];
        for (final room in rooms) {
          final item = raw.firstWhere((i) => '${i['roomid']}' == room.ref.roomId);
          final show = item['watched_show'] as Map<String, dynamic>;
          expect(room.audience.cumulative, show['switch'] == true ? show['num'] : null, reason: room.ref.key);
          expect(room.audience.popularity, item['online'], reason: room.ref.key);
        }
        expect((fixture.legacy as List).every((r) => (r as Map)['totalViewers'] == ''), isTrue);
      }
      // The two S03 rooms with "N人气" have no cumulative figure.
      final ranked = BilibiliParse.recommendPage(sample('S03-page1').body, page: 1).items;
      expect(ranked.take(2).map((r) => r.audience.cumulative), [null, null]);
      expect(ranked.skip(2).every((r) => r.audience.cumulative != null), isTrue);
    });
  });

  group('S05 search', () {
    RoomCard? byId(List<RoomCard> rooms, int id) => rooms.where((r) => r.ref.roomId == '$id').firstOrNull;

    for (final name in ['S05-live-results', 'S05-no-buvid3']) {
      test('$name live_room entries match legacy, live_user entries follow', () {
        final fixture = sample(name);
        final result = BilibiliParse.searchPage(fixture.body, page: 1, status: fixture.status);
        final legacy = (fixture.legacy as List).cast<Map<String, dynamic>>();
        final rooms = result.items.take(legacy.length).toList();
        expectCardsMatchLegacy(rooms, legacy);
        final raw = (((jsonDecode(fixture.body) as Map)['data'] as Map)['result'] as Map)['live_room'] as List;
        for (final (index, room) in rooms.indexed) {
          final item = raw[index] as Map<String, dynamic>;
          // DIAGNOSIS: legacy used the keyframe `cover`; the room cover is `user_cover`.
          expect(legacy[index]['cover'], 'https:${item['cover']}@400w.jpg');
          expect(room.cover.toString(), 'https:${item['user_cover']}@400w.jpg');
          expect(room.followers, item['attentions']);
          expect(room.liveSince, DateTime.parse('${(item['live_time'] as String).replaceFirst(' ', 'T')}+08:00'));
        }
        // DIAGNOSIS: legacy ignored `live_user`; v4 appends the streamers not
        // already listed, with their room state (2 is replay, §4.3).
        final users = result.items.skip(legacy.length).toList();
        expect(users.map((r) => r.ref.roomId), ['5440', '22462095', '20006', '22647871', '6243413', '7297527']);
        expect(users.map((r) => r.state), [
          LiveState.replay,
          LiveState.replay,
          LiveState.offline,
          LiveState.offline,
          LiveState.offline,
          LiveState.offline,
        ]);
        expect(byId(users, 5440)!.anchorName, '哔哩哔哩直播');
        expect(byId(users, 5440)!.area, '颜值');
        expect(users.every((r) => r.title.isEmpty && r.cover == null && r.audience.isEmpty), isTrue);
        // pageinfo.live_room.numPages is 1: this is the last page (legacy
        // asked for page 2 and stopped on its empty live_room, S05-out-of-range).
        expect(result.isLast, isTrue);
      });
    }

    test('S05-out-of-range page 2 is empty: the repeated live_user entries are not listed again', () {
      final fixture = sample('S05-out-of-range');
      expect(fixture.url.queryParameters['page'], '2');
      final result = BilibiliParse.searchPage(fixture.body, page: 2, status: fixture.status);
      expect(fixture.legacy, isEmpty);
      final users = (((jsonDecode(fixture.body) as Map)['data'] as Map)['result'] as Map)['live_user'] as List;
      expect(users, hasLength(6), reason: 'the platform repeats page 1 streamers on every page');
      expect(result.items, isEmpty);
      expect(result.isLast, isTrue);
    });

    test('S05-no-results is an empty last page', () {
      final fixture = sample('S05-no-results');
      final result = BilibiliParse.searchPage(fixture.body, page: 1, status: fixture.status);
      expect(fixture.legacy, isEmpty);
      expect(result.items, isEmpty);
      expect(result.isLast, isTrue);
    });
  });

  group('S06 getInfoByRoom', () {
    for (final name in ['S06-live', 'S06-offline', 'S06-replay', 'S06-short-id', 'S06-short-id-long']) {
      test('$name matches legacy', () {
        final fixture = sample(name);
        final detail = BilibiliParse.detail(fixture.body, status: fixture.status);
        final expected = fixture.legacy as Map<String, dynamic>;
        final legacy = expected['getRoomDetailForRefresh'] as Map<String, dynamic>;
        final longId = '${expected['parseRoomInfoResponse.room_info.room_id']}';
        // §1.1: the ref is the long id whatever was requested (legacy kept the input, "6").
        expect(detail.ref, RoomRef('bilibili', longId));
        expect(detail.link.toString(), 'https://live.bilibili.com/$longId');
        expect(detail.danmakuKeys, {'roomId': longId});
        if (name == 'S06-short-id') {
          expect(fixture.url.queryParameters['room_id'], '6');
          expect(legacy['roomId'], '6');
          expect(legacy['link'], 'https://live.bilibili.com/6');
          expect(longId, '7734200');
        } else {
          expect(legacy['roomId'], longId);
          expect(legacy['link'], detail.link.toString());
        }
        expect(detail.card.title, legacy['title']);
        expect(detail.card.anchorName, legacy['nick']);
        expect(detail.avatar?.toString(), legacy['avatar']);
        expect(detail.card.cover?.toString(), legacy['cover']);
        expect(detail.card.area, legacy['area']);
        expect(detail.card.audience.popularity, int.parse(legacy['popularity'] as String));
        expect(detail.card.audience.online, isNull);
        expect(detail.state == LiveState.live, legacy['status']);
        // §4.3: live_status 2 is replay; legacy called it offline.
        if (name == 'S06-replay') {
          expect(detail.state, LiveState.replay);
          expect(legacy['status'], isFalse);
          // The recording shows HTML in `description`; legacy kept the tags.
          expect(legacy['introduction'], '<p>凡人线下嘉年华</p>');
          expect(detail.introduction, '凡人线下嘉年华');
        } else {
          expect(detail.introduction, _blankToNull(legacy['introduction']));
        }
        expect(detail.notice, _blankToNull(legacy['notice']));
        final data = (jsonDecode(fixture.body) as Map)['data'] as Map<String, dynamic>;
        final room = data['room_info'] as Map<String, dynamic>;
        final show = data['watched_show'] as Map<String, dynamic>;
        // Legacy had no cumulative measure; watched_show "N人看过" is one (ADR 0010 rule 3).
        expect(
          detail.card.audience.cumulative,
          show['switch'] == true && detail.state != LiveState.offline ? show['num'] : null,
        );
        expect(
          detail.card.liveSince,
          detail.state == LiveState.live
              ? DateTime.fromMillisecondsSinceEpoch((room['live_start_time'] as int) * 1000, isUtc: true)
              : null,
        );
      });
    }

    test('S06-short-id and S06-short-id-long are the same room', () {
      final short = BilibiliParse.detail(sample('S06-short-id').body);
      final long = BilibiliParse.detail(sample('S06-short-id-long').body);
      expect(short.ref, long.ref);
    });

    test('S06-not-found (19002000, HTTP 200) is NotFound; legacy threw StateError', () {
      final fixture = sample('S06-not-found');
      final legacy = (fixture.legacy as Map<String, dynamic>)['getRoomDetailForRefresh'] as Map<String, dynamic>;
      expect((legacy['throws'] as Map)['type'], 'StateError');
      expect(fixture.status, 200);
      expect(() => BilibiliParse.detail(fixture.body, status: fixture.status), throwsA(isA<NotFound>()));
    });

    test('S06-risk352 is RiskControl; legacy threw StateError after one WBI refresh', () {
      final fixture = sample('S06-risk352');
      final legacy = fixture.legacy as Map<String, dynamic>;
      expect(((legacy['parseRoomInfoResponse'] as Map)['throws'] as Map)['type'], 'StateError');
      expect((legacy['requests'] as Map)['/xlive/web-room/v1/index/getInfoByRoom'], 2);
      expect(() => BilibiliParse.detail(fixture.body, status: fixture.status), throwsA(isA<RiskControl>()));
    });
  });

  group('S07 getRoomPlayInfo', () {
    // The long id each play sample belongs to (S06 details).
    const longIds = {
      'S07-guest-qn0': '42062',
      'S07-guest-qn10000': '42062',
      'S07-hevc-qn10000': '42062',
      'S07-short-id': '7734200',
      'S07-short-id-long': '7734200',
    };

    for (final MapEntry(key: name, value: roomId) in longIds.entries) {
      test('$name qualities, confirmed qn, lines, headers and lease', () {
        final fixture = sample(name);
        final data = BilibiliParse.playData(fixture.body, status: fixture.status);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final qn = legacy['requestedQn'] as int;
        expect(fixture.url.queryParameters['qn'], '$qn');

        final legacyQualities = (legacy['parsePlayQualities'] as List).cast<Map<String, dynamic>>();
        final qualities = BilibiliParse.qualities(data);
        expect(qualities.map((q) => q.id), legacyQualities.map((q) => '${q['id']}'));
        expect(qualities.map((q) => q.label), legacyQualities.map((q) => q['quality']));
        expect(qualities.map((q) => q.rank), legacyQualities.map((q) => q['sort']));

        final requested = qn == 0 ? null : qualities.firstWhere((q) => q.id == '$qn');
        final set = BilibiliParse.streams(
          data,
          roomId: roomId,
          issuedAt: fixture.capturedAt,
          requested: requested,
          cookie: 'buvid3=x;buvid4=y;',
        );
        final resolution = legacy['parsePlayUrlResolution'] as Map<String, dynamic>;
        final applied = '${resolution['appliedQualityData']}';
        expect(resolution['qualityUnconfirmed'], isFalse);
        expect(set.qualities, qualities);
        // REG-BILIBILI-001: the guest asked for 10000 and got 250; each line says so.
        expect(set.lines.every((l) => l.confirmed?.id == applied), isTrue);
        expect(set.lines.every((l) => l.requested.id == (qn == 0 ? applied : '$qn')), isTrue);
        expect(set.selected.id, qn == 0 ? applied : '$qn');
        expect(set.lines.first.effective.label, '超清');

        final legacyUrls = (resolution['urls'] as List).cast<String>();
        final avcUrls = _codecUrls(fixture.body, 'avc');
        if (name == 'S07-hevc-qn10000') {
          // Recording note: legacy mixed AVC and HEVC lines in one list; v4
          // keeps the first candidate's codec (AVC, §5.2 rule 4) only.
          expect(legacyUrls.any((u) => !avcUrls.contains(u)), isTrue);
          expect(set.lines.map((l) => l.url.toString()), legacyUrls.where(avcUrls.contains));
        } else {
          expect(set.lines.map((l) => l.url.toString()), legacyUrls);
        }
        expect(set.lines.every((l) => l.codec == 'avc'), isTrue);
        expect(set.lines.map((l) => l.format).toSet(), {StreamFormat.flv, StreamFormat.hls});
        expect(set.lines.first.format, StreamFormat.flv);
        // §5.3: line id = host + protocol + format + codec, unique in a set.
        expect(set.lines.map((l) => l.lineId).toSet(), hasLength(set.lines.length));
        expect(set.lines.first.lineId, '${set.lines.first.url.host}|http_stream|flv|avc');

        for (final line in set.lines) {
          // §6.3: media headers with the long id, even when the request used the short one.
          expect(line.headers, {
            'user-agent': BilibiliParse.userAgent,
            'origin': 'https://live.bilibili.com',
            'referer': 'https://live.bilibili.com/$roomId',
            'cookie': 'buvid3=x;buvid4=y;',
          });
          // §6.5: `expires` is issue time + 1 h; prefetch 60 s before, no cut.
          final expires = int.parse(line.url.queryParameters['expires']!);
          final lease = line.lease!;
          expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true));
          expect(lease.expiresAt!.difference(fixture.capturedAt).inSeconds, inInclusiveRange(3599, 3601));
          expect(lease.expiresAt!.difference(lease.refreshAt), BilibiliParse.leaseLead);
          expect(lease.cutsConnection, isFalse);
        }
      });
    }

    test('S07-short-id: the play API accepts short id 6 and answers for 7734200', () {
      final fixture = sample('S07-short-id');
      expect(fixture.url.queryParameters['room_id'], '6');
      expect(BilibiliParse.playData(fixture.body)['room_id'], 7734200);
    });

    test('S07-offline and S07-replay (playurl_info null) are StreamUnavailable; legacy threw FormatException', () {
      for (final name in ['S07-offline', 'S07-replay']) {
        final fixture = sample(name);
        final legacy = fixture.legacy as Map<String, dynamic>;
        expect(((legacy['parsePlayUrlResolution'] as Map)['throws'] as Map)['type'], 'FormatException');
        expect(
          () => BilibiliParse.playData(fixture.body, status: fixture.status),
          throwsA(isA<StreamUnavailable>()),
          reason: name,
        );
      }
    });
  });

  group('session samples', () {
    test('S09 getDanmuInfo token and endpoints match legacy; guest uid is 0', () {
      final fixture = sample('S09-guest');
      final legacy = (fixture.legacy as Map<String, dynamic>)['danmakuArgs'] as Map<String, dynamic>;
      final info = BilibiliSession.danmakuInfo(fixture.body, status: fixture.status);
      expect(info.token, legacy['token']);
      expect(info.servers.map((s) => s.toString()), legacy['serverUrls']);
      expect(BilibiliSession.danmakuUid(cookie: '', storedUid: 0), legacy['uid']);
    });

    test('S10 finger/spi buvid, cookie and API headers match legacy', () {
      final fixture = sample('S10-guest');
      final legacy = fixture.legacy as Map<String, dynamic>;
      final buvid = BilibiliSession.buvid(fixture.body, status: fixture.status);
      expect({'b_3': buvid.buvid3, 'b_4': buvid.buvid4}, legacy['getBuvid']);
      final cookie = BilibiliSession.cookie(buvid3: buvid.buvid3, buvid4: buvid.buvid4);
      expect(BilibiliSession.apiHeaders(cookie), legacy['getHeader']);
    });

    test('S11 nav WBI keys (code -101 still carries them) and mixin key match legacy', () {
      final fixture = sample('S11-guest');
      expect((jsonDecode(fixture.body) as Map)['code'], -101);
      final legacy = fixture.legacy as Map<String, dynamic>;
      final keys = BilibiliSession.wbiKeys(fixture.body, status: fixture.status);
      expect(keys.imgKey, legacy['imgKey']);
      expect(keys.subKey, legacy['subKey']);
      expect(BilibiliSession.mixinKey(keys.imgKey, keys.subKey), legacy['mixinKey']);
    });

    test('S12 access id matches legacy', () {
      final fixture = sample('S12-guest');
      expect(BilibiliSession.accessId(fixture.body), (fixture.legacy as Map<String, dynamic>)['getAccessId']);
    });

    test('S15 QR generate and polls match legacy', () {
      final generate = sample('S15-generate');
      final legacy = generate.legacy as Map<String, dynamic>;
      final code = BilibiliSession.qrCode(generate.body, status: generate.status);
      expect(code.key, legacy['qrcodeKey']);
      expect(code.url.toString(), legacy['qrcodeUrl']);
      for (final (name, state, legacyState) in [
        ('S15-poll-86101', BilibiliQrState.waiting, 'unscanned'),
        ('S15-poll-86038', BilibiliQrState.expired, 'expired'),
      ]) {
        final poll = sample(name);
        expect((poll.legacy as Map<String, dynamic>)['status'], legacyState);
        expect(BilibiliSession.qrPoll(poll.body, status: poll.status), state, reason: name);
      }
    });

    test('S16 account -101 is NeedsLogin (legacy: logged out, "login expired" notice)', () {
      final fixture = sample('S16-no-cookie');
      final legacy = fixture.legacy as Map<String, dynamic>;
      expect(legacy['logined'], isFalse);
      expect(legacy['notices'], ['bilibili_login_expired']);
      expect(() => BilibiliSession.account(fixture.body, status: fixture.status), throwsA(isA<NeedsLogin>()));
    });
  });

  group('rules without samples', () {
    String envelope(Object? data, {int code = 0}) => jsonEncode({'code': code, 'message': 'm', 'data': data});

    Map<String, dynamic> areaRoom(int id, int online) => {
      'roomid': id,
      'title': 'T$id &amp; co',
      'uname': 'U$id',
      'cover': '//i0.hdslb.com/c$id.jpg',
      'face': 'https://i0.hdslb.com/f.jpg',
      'online': online,
      'area_name': '英雄联盟',
    };

    test('§2.2 area rooms: live, sorted by popularity then id, has_more ends the page', () {
      final page = BilibiliParse.areaRoomsPage(
        envelope({
          'list': [areaRoom(30, 5), areaRoom(20, 9), areaRoom(10, 5), areaRoom(0, 99)],
          'has_more': 1,
        }),
        page: 3,
      );
      expect(page.items.map((r) => r.ref.roomId), ['20', '10', '30']);
      expect(page.items.first.title, 'T20 & co');
      expect(page.items.first.cover.toString(), 'https://i0.hdslb.com/c20.jpg@400w.jpg');
      expect(page.items.first.area, '英雄联盟');
      expect(page.items.every((r) => r.state == LiveState.live), isTrue);
      expect(page.next, const PageCursor('4'));
      final last = BilibiliParse.areaRoomsPage(
        envelope({
          'list': [areaRoom(1, 1)],
          'has_more': 0,
        }),
        page: 1,
      );
      expect(last.isLast, isTrue, reason: 'has_more 0 ends even a non-empty page');
      final noFlag = BilibiliParse.areaRoomsPage(
        envelope({
          'list': [areaRoom(1, 1)],
        }),
        page: 1,
      );
      expect(noFlag.isLast, isFalse, reason: 'without has_more only an empty page ends');
      expect(BilibiliParse.areaRoomsPage(envelope({'list': <Object>[]}), page: 2).isLast, isTrue);
    });

    test('§9 envelope: 412 / -412 RateLimited, -101 NeedsLogin, 5xx NetworkFailure, others ApiChanged', () {
      final ok = envelope(<Object>[]);
      expect(() => BilibiliParse.categories('<html>412</html>', status: 412), throwsA(isA<RateLimited>()));
      expect(() => BilibiliParse.categories(envelope(null, code: -412)), throwsA(isA<RateLimited>()));
      expect(() => BilibiliParse.categories(envelope(null, code: -352)), throwsA(isA<RiskControl>()));
      expect(() => BilibiliParse.categories(envelope(null, code: -101)), throwsA(isA<NeedsLogin>()));
      expect(() => BilibiliParse.categories(ok, status: 502), throwsA(isA<NetworkFailure>()));
      expect(() => BilibiliParse.categories(envelope(null, code: -400)), throwsA(isA<ApiChanged>()));
      expect(() => BilibiliParse.categories('<html></html>'), throwsA(isA<ApiChanged>()));
      expect(() => BilibiliParse.categories(ok, status: 404), throwsA(isA<ApiChanged>()));
      expect(BilibiliParse.categories(ok), isEmpty);
      // §2.3: a rejected recommend request is an error, never an empty list.
      expect(() => BilibiliParse.recommendPage(envelope(null, code: -400), page: 1), throwsA(isA<ApiChanged>()));
      // -404 is NotFound only for a room detail.
      expect(() => BilibiliParse.detail(envelope(null, code: -404)), throwsA(isA<NotFound>()));
      expect(() => BilibiliParse.searchPage(envelope(null, code: -404), page: 1), throwsA(isA<ApiChanged>()));
    });

    Map<String, dynamic> roomInfo(Object? liveStatus) => {
      'room_info': {
        'room_id': 7734200,
        'short_id': 6,
        'title': 'a &amp; b',
        'cover': '//i0.hdslb.com/c.jpg',
        'description': '<p>one &lt;two&gt;</p><p><br></p><p>three</p>',
        'live_status': liveStatus,
        'live_start_time': 0,
        'area_name': 'x',
        'online': 1,
      },
      'anchor_info': {
        'base_info': {'uname': 'u', 'face': '//i0.hdslb.com/f.jpg'},
      },
      'news_info': {'content': '公告 &amp; 通知'},
    };

    test('§4 detail: string live_status, HTML description, notice, structure errors', () {
      // REG-BILIBILI-019: "1" is live.
      final live = BilibiliParse.detail(envelope(roomInfo('1')));
      expect(live.state, LiveState.live);
      expect(live.ref.roomId, '7734200');
      expect(live.card.title, 'a & b');
      expect(live.card.cover.toString(), 'https://i0.hdslb.com/c.jpg');
      expect(live.avatar.toString(), 'https://i0.hdslb.com/f.jpg@100w.jpg');
      expect(live.introduction, 'one <two>\n\nthree');
      expect(live.notice, '公告 & 通知');
      expect(live.card.liveSince, isNull, reason: 'live_start_time 0 is not a start time');
      expect(BilibiliParse.detail(envelope(roomInfo('2'))).state, LiveState.replay);
      // ADR 0010 rule 2: no "unknown" state.
      expect(() => BilibiliParse.detail(envelope(roomInfo(3))), throwsA(isA<ApiChanged>()));
      expect(() => BilibiliParse.detail(envelope(roomInfo(null))), throwsA(isA<ApiChanged>()));
      expect(
        () => BilibiliParse.detail(envelope({'room_info': roomInfo(1)['room_info']})),
        throwsA(isA<ApiChanged>()),
        reason: 'anchor_info missing',
      );
      expect(() => BilibiliParse.detail(envelope(null, code: 60004)), throwsA(isA<NotFound>()));
    });

    test('§3 search: string live_status, entities, missing result', () {
      final page = BilibiliParse.searchPage(
        envelope({
          'result': {
            'live_room': [
              {
                'roomid': 1,
                'title': '<em class="keyword">A</em> &amp; B',
                'uname': 'x',
                'live_status': '1',
                'cover': '//k.jpg',
                'user_cover': '',
                'online': 3,
                'live_time': '0000-00-00 00:00:00',
              },
            ],
          },
        }),
        page: 1,
      );
      expect(page.items.single.title, 'A & B');
      expect(page.items.single.state, LiveState.live);
      expect(page.items.single.cover.toString(), 'https://k.jpg@400w.jpg', reason: 'no user_cover: keyframe');
      expect(page.items.single.liveSince, isNull);
      expect(page.isLast, isFalse, reason: 'no pageinfo: only an empty live_room page ends');
      final empty = BilibiliParse.searchPage(envelope({'page': 1}), page: 1);
      expect(empty.items, isEmpty);
      expect(empty.isLast, isTrue);
    });

    Map<String, dynamic> codec(String name, int current, List<int> accept, List<String> hosts, {String? base}) => {
      'codec_name': name,
      'current_qn': current,
      'accept_qn': accept,
      'base_url': base ?? '/live-bvc/$name-$current.flv?',
      'url_info': [
        for (final host in hosts) {'host': host, 'extra': 'expires=2000000000&qn=$current', 'stream_ttl': 0},
      ],
    };

    Map<String, dynamic> play(List<Map<String, dynamic>> streams, {List<Object>? names}) => {
      'room_id': 1,
      'live_status': 1,
      'playurl_info': {
        'playurl': {
          'g_qn_desc':
              names ??
              [
                {'qn': 15000, 'desc': '2K'},
                {'qn': 10000, 'desc': '原画P'},
              ],
          'stream': streams,
        },
      },
    };

    Map<String, dynamic> stream(String protocol, String format, List<Map<String, dynamic>> codecs) => {
      'protocol_name': protocol,
      'format': [
        {'format_name': format, 'codec': codecs},
      ],
    };

    final issued = DateTime.utc(2033, 5, 18);

    test('§5.1 labels: fixed table first, then g_qn_desc, then "清晰度 {qn}"', () {
      final data = play([
        stream('http_stream', 'flv', [
          codec('avc', 250, [15000, 10000, 12345, 250, 0, -1], ['https://a.test']),
        ]),
      ]);
      expect(BilibiliParse.qualities(data).map((q) => (q.id, q.label, q.rank)), [
        ('15000', '2K', 15000),
        ('12345', '清晰度 12345', 12345),
        ('10000', '原画', 10000),
        ('250', '超清', 250),
      ]);
    });

    test('§5.2 a qn only HEVC serves gives an HEVC-only set', () {
      final data = play([
        stream('http_stream', 'flv', [
          codec('avc', 10000, [10000], ['https://a.test']),
          codec('hevc', 20000, [20000, 10000], ['https://b.test']),
        ]),
        stream('http_hls', 'ts', [
          codec('avc', 10000, [10000], ['https://c.test'], base: '/a.m3u8?'),
          codec('hevc', 20000, [20000], ['https://d.test'], base: '/h.m3u8?'),
        ]),
      ]);
      const uhd = Quality(id: '20000', label: '4K', rank: 20000);
      final set = BilibiliParse.streams(data, roomId: '1', issuedAt: issued, requested: uhd);
      expect(set.lines.map((l) => l.url.host), ['b.test', 'd.test']);
      expect(set.lines.map((l) => l.codec).toSet(), {'hevc'});
      expect(set.lines.map((l) => l.format), [StreamFormat.flv, StreamFormat.hls]);
      expect(set.lines.every((l) => l.confirmed == uhd), isTrue);
      // Asking for 10000 on the same response keeps AVC.
      const source = Quality(id: '10000', label: '原画', rank: 10000);
      final avc = BilibiliParse.streams(data, roomId: '1', issuedAt: issued, requested: source);
      expect(avc.lines.map((l) => l.url.host), ['a.test', 'c.test']);
    });

    test('§5.2 order: mcdn hosts last; non-http hosts dropped; duplicates removed; no current_qn is unconfirmed', () {
      final data = play([
        stream('http_stream', 'flv', [
          codec('avc', 250, [250], ['https://x.mcdn.test', 'https://b.test', 'rtmp://r.test', 'https://b.test']),
        ]),
      ]);
      final set = BilibiliParse.streams(data, roomId: '1', issuedAt: issued);
      expect(set.lines.map((l) => l.url.host), ['b.test', 'x.mcdn.test']);
      expect(set.selected.id, '250', reason: 'qn=0: the server default is what was selected');

      final unconfirmed = play([
        stream('http_stream', 'flv', [
          {
            'codec_name': 'avc',
            'accept_qn': [400],
            'base_url': '/x.flv?',
            'url_info': [
              {'host': 'https://a.test', 'extra': ''},
            ],
          },
        ]),
      ]);
      const blue = Quality(id: '400', label: '蓝光', rank: 400);
      final line = BilibiliParse.streams(unconfirmed, roomId: '1', issuedAt: issued, requested: blue).lines.single;
      expect(line.confirmed, isNull);
      expect(line.effective, blue);
      expect(line.lease, isNull, reason: 'no expires');
    });

    test('§6 play errors: playurl missing is ApiChanged, no line is StreamUnavailable', () {
      final noPlayurl = envelope({'playurl_info': <String, Object>{}});
      expect(() => BilibiliParse.playData(noPlayurl), throwsA(isA<ApiChanged>()));
      final noLines = play([
        stream('http_stream', 'flv', [
          codec('avc', 250, [250], ['rtmp://r.test']),
        ]),
      ]);
      expect(() => BilibiliParse.streams(noLines, roomId: '1', issuedAt: issued), throwsA(isA<StreamUnavailable>()));
    });

    test('§6.5 lease: past expiry is none; short lifetimes renew a quarter before', () {
      final expired = Uri.parse('https://a.test/x.flv?expires=1000');
      expect(BilibiliParse.lease(expired, issued), isNull);
      final short = Uri.parse('https://a.test/x.flv?len=0&expires=${issued.millisecondsSinceEpoch ~/ 1000 + 100}');
      final lease = BilibiliParse.lease(short, issued)!;
      expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(seconds: 25));
      expect(lease.cutsConnection, isFalse);
    });

    test('§6.3 media headers: no cookie header without a cookie, never authority', () {
      expect(BilibiliParse.mediaHeaders('42062'), {
        'user-agent': BilibiliParse.userAgent,
        'origin': 'https://live.bilibili.com',
        'referer': 'https://live.bilibili.com/42062',
      });
    });

    test("§6.4 WBI string to sign: sorted, wts added, !'()* removed, spaces as %20", () {
      // The public test vector (same keys as S11): md5 of this string is
      // 8f6f2b5b3d485fe1886cec6a0be8c5d4.
      final query = BilibiliSession.wbiQuery({'foo': '114', 'bar': '514', 'zab': '1919810'}, wts: 1702204169);
      expect(query, 'bar=514&foo=114&wts=1702204169&zab=1919810');
      expect(
        BilibiliSession.mixinKey('7cd084941338484aae1ad9425b84077c', '4932caff0ff746eab6f01bf08b70ac45'),
        'ea1db124af3c7062474693fa704f4ff8',
      );
      expect(BilibiliSession.wbiQuery({'k': "a b!'()*/中"}, wts: 1), 'k=a%20b%2F%E4%B8%AD&wts=1');
      expect(() => BilibiliSession.mixinKey('short', 'keys'), throwsA(isA<ApiChanged>()));
      expect(() => BilibiliSession.wbiKeys(jsonEncode({'code': -352})), throwsA(isA<RiskControl>()));
    });

    test('§8.1 cookie: login cookie kept, buvid appended only when missing', () {
      expect(BilibiliSession.cookie(buvid3: 'b3', buvid4: 'b4'), 'buvid3=b3;buvid4=b4;');
      expect(
        BilibiliSession.cookie(buvid3: 'b3', buvid4: 'b4', loginCookie: 'SESSDATA=s; buvid3=mine'),
        'SESSDATA=s; buvid3=mine',
      );
      expect(
        BilibiliSession.cookie(buvid3: 'b3', buvid4: 'b4', loginCookie: 'SESSDATA=s;'),
        'SESSDATA=s;buvid3=b3;buvid4=b4;',
      );
    });

    test('§8.2 danmaku uid: DedeUserID from the same cookie, then the stored uid', () {
      expect(BilibiliSession.danmakuUid(cookie: 'a=1; dedeuserid=42; b=2', storedUid: 7), 42);
      expect(BilibiliSession.danmakuUid(cookie: 'SESSDATA=s', storedUid: 7), 7);
      expect(BilibiliSession.danmakuUid(cookie: 'SESSDATA=s', storedUid: 0), 0);
      expect(BilibiliSession.danmakuUid(cookie: ' ', storedUid: 7), 0);
    });

    test('§7.1 danmaku endpoints: 443 omitted, missing port is 443, no duplicates; empty token fails', () {
      final info = BilibiliSession.danmakuInfo(
        envelope({
          'token': 't',
          'host_list': [
            {'host': 'a.test', 'wss_port': 443},
            {'host': 'b.test'},
            {'host': 'a.test', 'wss_port': 443},
            {'host': 'c.test', 'wss_port': 2245},
          ],
        }),
      );
      expect(info.servers.map((s) => s.toString()), [
        'wss://broadcastlv.chat.bilibili.com/sub',
        'wss://a.test/sub',
        'wss://b.test/sub',
        'wss://c.test:2245/sub',
      ]);
      expect(() => BilibiliSession.danmakuInfo(envelope({'token': ''})), throwsA(isA<ApiChanged>()));
    });

    test('§8.3 QR: 86090 scanned, 0 confirmed, other codes fail; the QR URL must be https', () {
      String poll(int code) => envelope({'code': code, 'message': 'm'});
      expect(BilibiliSession.qrPoll(poll(86090)), BilibiliQrState.scanned);
      expect(BilibiliSession.qrPoll(poll(0)), BilibiliQrState.confirmed);
      expect(() => BilibiliSession.qrPoll(poll(86000)), throwsA(isA<ApiChanged>()));
      expect(
        () => BilibiliSession.qrCode(envelope({'qrcode_key': 'k', 'url': 'http://a.test/'})),
        throwsA(isA<ApiChanged>()),
      );
    });

    test('§8.2 account: signed in with uname and mid', () {
      final account = BilibiliSession.account(envelope({'mid': 9, 'uname': 'n'}));
      expect(account.uid, 9);
      expect(account.name, 'n');
    });
  });
}

/// The play URLs of every [codec] entry in a getRoomPlayInfo body.
Set<String> _codecUrls(String body, String codec) {
  final playurl = (((jsonDecode(body) as Map)['data'] as Map)['playurl_info'] as Map)['playurl'] as Map;
  return {
    for (final stream in playurl['stream'] as List)
      for (final format in (stream as Map)['format'] as List)
        for (final entry in (format as Map)['codec'] as List)
          if ((entry as Map)['codec_name'] == codec)
            for (final info in entry['url_info'] as List)
              '${(info as Map)['host']}${entry['base_url']}${info['extra']}',
  };
}

/// Legacy writes a missing field as ''; v4 uses null.
String? _blankToNull(Object? value) => value == null || value == '' ? null : value as String;
