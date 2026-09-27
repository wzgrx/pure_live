// v4 Huya parsing against the recorded samples, compared with the legacy
// parser's frozen output. Deviations the spec requires are asserted explicitly.
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  group('S01 bussLive categories', () {
    for (final sample in ['S01-buss1', 'S01-buss2', 'S01-buss8', 'S01-buss3']) {
      test(sample, () {
        final fixture = Fixture.load('huya', sample);
        final id = fixture.url.queryParameters['bussType']!;
        final category = HuyaParse.category(fixture.body, id: id, status: fixture.status);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final areas = (legacy['children'] as List).cast<Map<String, dynamic>>();
        expect(category.id, legacy['id']);
        expect(category.name, legacy['name']);
        // buss2/3/8 write gid as 2165.0; the id stays "2165".
        expect(category.areas.map((a) => a.id), areas.map((a) => a['areaId']));
        expect(category.areas.map((a) => a.name), areas.map((a) => a['areaName']));
        expect(category.areas.map((a) => a.icon.toString()), areas.map((a) => a['areaPic']));
        expect(category.areas.map((a) => a.categoryId).toSet(), {legacy['id']});
      });
    }

    test('top-level order matches legacy getCategores', () {
      expect(HuyaParse.topCategories.map((c) => c.id), ['1', '2', '8', '3']);
      expect(HuyaParse.topCategories.map((c) => c.name), ['网游', '单机', '娱乐', '手游']);
      expect(() => HuyaParse.category('{}', id: '9'), throwsArgumentError);
    });
  });

  void expectCardsMatchLegacy(List<RoomCard> rooms, List<Map<String, dynamic>> legacy) {
    expect(rooms.map((r) => r.ref.roomId), legacy.map((r) => r['roomId']));
    // Legacy keeps surrounding blanks ("海克斯乱斗&云顶  ", "解说元宝 "); v4 trims.
    expect(rooms.map((r) => r.title), legacy.map((r) => decodeHtmlEntities((r['title'] as String).trim())));
    expect(rooms.map((r) => r.anchorName), legacy.map((r) => (r['nick'] as String).trim()));
    expect(rooms.map((r) => r.cover?.toString()), legacy.map((r) => _blankToNull(r['cover'])));
    expect(rooms.map((r) => r.area), legacy.map((r) => _blankToNull(r['area'])));
    // totalCount / game_total_count is popularity, never an online count (§4.3).
    expect(rooms.map((r) => r.audience.popularity), legacy.map((r) => int.parse(r['popularity'] as String)));
    expect(rooms.map((r) => r.audience.online), everyElement(isNull));
    expect(legacy.map((r) => r['audienceMetricType']), everyElement('popularity'));
    expect(rooms.every((r) => r.state == LiveState.live), isTrue);
    expect(legacy.every((r) => r['status'] == true), isTrue);
  }

  group('S02/S03 getLiveListByPage', () {
    // Ends at data.totalPage or on an empty datas, never by the count (§2.3):
    // cold-page1 has 1 room of 120 and totalPage 1; hot pages are full with 5 pages.
    const lastPages = {'S02-last', 'S02-beyond', 'S03-cold-page1', 'S03-cold-page2'};
    for (final sample in [
      'S02-page1',
      'S02-page2',
      'S02-last',
      'S02-beyond',
      'S03-hot-page1',
      'S03-hot-page2',
      'S03-cold-page1',
      'S03-cold-page2',
    ]) {
      test(sample, () {
        final fixture = Fixture.load('huya', sample);
        final page = int.parse(fixture.url.queryParameters['page']!);
        final result = HuyaParse.roomListPage(fixture.body, page: page, status: fixture.status);
        expectCardsMatchLegacy(result.items, ((fixture.legacy as Map)['rooms'] as List).cast());
        expect(result.isLast, lastPages.contains(sample), reason: 'page $page');
        if (!result.isLast) expect(result.next, PageCursor('${page + 1}'));
      });
    }

    test('S02 covers without a query get the thumbnail style, as in legacy', () {
      final fixture = Fixture.load('huya', 'S02-page1');
      final covers = HuyaParse.roomListPage(fixture.body, page: 1).items.map((r) => r.cover.toString());
      expect(covers.where((c) => c.endsWith('?x-oss-process=style/w338_h190&')), isNotEmpty);
    });
  });

  group('S04 getSearchContent', () {
    Page<RoomCard> search(Fixture fixture) {
      final query = fixture.url.queryParameters;
      return HuyaParse.searchPage(
        fixture.body,
        start: int.parse(query['start']!),
        rows: int.parse(query['rows']!),
        status: fixture.status,
      );
    }

    List<Map<String, dynamic>> legacyRooms(Fixture fixture) => ((fixture.legacy as Map)['rooms'] as List).cast();

    for (final (sample, next) in [('S04-results', '20'), ('S04-empty', null), ('S04-fallback', null)]) {
      test(sample, () {
        final fixture = Fixture.load('huya', sample);
        final result = search(fixture);
        expectCardsMatchLegacy(result.items, legacyRooms(fixture));
        // numFound decides the end: 101 after 20 → more; 15 in one page → last.
        expect(result.next?.value, next);
      });
    }

    test('S04-page2 drops the repeated first page (legacy returned 40 rooms, DIAGNOSIS)', () {
      final fixture = Fixture.load('huya', 'S04-page2');
      final legacy = legacyRooms(fixture);
      final firstPage = legacyRooms(Fixture.load('huya', 'S04-results'));
      expect(legacy, hasLength(40));
      expect(legacy.take(20).map((r) => r['roomId']), firstPage.map((r) => r['roomId']));
      final result = search(fixture);
      expectCardsMatchLegacy(result.items, legacy.sublist(20));
      expect(result.next, const PageCursor('40'));
      final page1 = search(Fixture.load('huya', 'S04-results')).items.map((r) => r.ref).toSet();
      expect(result.items.where((r) => page1.contains(r.ref)), isEmpty);
    });
  });

  group('S05/S06 profileRoom detail', () {
    void expectDetailMatchesLegacy(RoomDetail detail, Map<String, dynamic> legacy) {
      expect(detail.ref.roomId, legacy['roomId']);
      expect(detail.card.title, legacy['title']);
      expect(detail.card.anchorName, legacy['nick']);
      expect(detail.avatar?.toString(), _blankToNull(legacy['avatar']));
      expect(detail.card.cover?.toString(), _blankToNull(legacy['cover']));
      expect(detail.card.area, _blankToNull(legacy['area']));
      expect(detail.card.audience, Audience(popularity: int.parse(legacy['popularity'] as String)));
      expect(detail.notice, _blankToNull(legacy['notice']));
      expect(detail.introduction, _blankToNull(legacy['introduction']));
      expect(detail.link.toString(), legacy['link']);
      expect(detail.state == LiveState.live, legacy['status'] == true);
      expect(detail.state == LiveState.replay, legacy['isRecord'] == true);
    }

    for (final sample in ['S05-multicdn', 'S05-xingxiu', 'S05-ratearray']) {
      test('$sample live', () {
        final fixture = Fixture.load('huya', sample);
        final detail = HuyaParse.detail(fixture.body, status: fixture.status);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final room = legacy['getRoomDetail'] as Map<String, dynamic>;
        expectDetailMatchesLegacy(detail, room);
        expect(detail.state, LiveState.live);
        final helpers = legacy['helpers'] as Map<String, dynamic>;
        expect(helpers['parseHuyaLiveStatus'], 'live');
        final audience = helpers['parseRoomAudience'] as Map<String, dynamic>;
        expect(detail.card.audience.popularity, int.parse(audience['popularity'] as String));
        expect(audience['onlineViewers'], '');
        final danmaku = jsonDecode(room['danmakuData'] as String) as Map<String, dynamic>;
        expect(detail.danmakuKeys['uid'], '${danmaku['uid']}');
        if (sample == 'S05-ratearray') {
          // Live without multiLine: legacy lost topSid/subSid (0) and so the
          // headline board (DIAGNOSIS); v4 reads them from baseSteamInfoList (§1).
          expect(danmaku['topSid'], 0);
          expect(detail.danmakuKeys['topSid'], '1319535174649');
          expect(detail.danmakuKeys['subSid'], '1319535174649');
        } else {
          expect(detail.danmakuKeys['topSid'], '${danmaku['topSid']}');
          expect(detail.danmakuKeys['subSid'], '${danmaku['subSid']}');
        }
      });
    }

    test('S06-off offline, with danmaku keys legacy did not provide', () {
      final fixture = Fixture.load('huya', 'S06-off');
      final detail = HuyaParse.detail(fixture.body, status: fixture.status);
      final legacy = fixture.legacy as Map<String, dynamic>;
      for (final entry in ['getRoomDetail', 'getRoomDetailForRecording', 'getRoomDetailForRefresh']) {
        expectDetailMatchesLegacy(detail, (legacy[entry] as Map<String, dynamic>)['value'] as Map<String, dynamic>);
      }
      expect(detail.state, LiveState.offline);
      expect((legacy['helpers'] as Map<String, dynamic>)['isExplicitOfflineState'], isTrue);
      // profileInfo.uid is a string here; chTopId/subChId stand in for the missing stream.
      expect(detail.danmakuKeys, {'uid': '17363578', 'topSid': '17363578', 'subSid': '17363578'});
    });

    test('S06-replay is replay; legacy gave unknown, FormatException and replay (DIAGNOSIS)', () {
      final fixture = Fixture.load('huya', 'S06-replay');
      final legacy = fixture.legacy as Map<String, dynamic>;
      expect(((legacy['getRoomDetail'] as Map)['value'] as Map)['liveStatus'], 3, reason: 'legacy unknown');
      expect((legacy['getRoomDetailForRecording'] as Map)['error'], 'FormatException');
      final detail = HuyaParse.detail(fixture.body, status: fixture.status);
      // §4.2: REPLAY is its own state, with full metadata like getRoomDetailForRefresh.
      expectDetailMatchesLegacy(detail, (legacy['getRoomDetailForRefresh'] as Map)['value'] as Map<String, dynamic>);
      expect(detail.state, LiveState.replay);
    });

    for (final sample in ['S06-notfound', 'S06-alias']) {
      test('$sample status 422 is NotFound (legacy: an unknown room or FormatException)', () {
        final fixture = Fixture.load('huya', sample);
        final legacy = fixture.legacy as Map<String, dynamic>;
        expect(((legacy['getRoomDetail'] as Map)['value'] as Map)['liveStatus'], 3);
        expect((legacy['getRoomDetailForRefresh'] as Map)['error'], 'FormatException');
        expect(fixture.status, 200);
        // §9 / DIAGNOSIS: a missing room answers HTTP 200 with status 422; a
        // letter alias (lpl) cannot be looked up directly either (§1).
        expect(() => HuyaParse.detail(fixture.body, status: fixture.status), throwsA(isA<NotFound>()));
        expect(() => HuyaParse.playData(fixture.body, status: fixture.status), throwsA(isA<NotFound>()));
      });
    }
  });

  group('S05 qualities and lines', () {
    for (final sample in ['S05-multicdn', 'S05-xingxiu']) {
      test('$sample match legacy', () {
        final fixture = Fixture.load('huya', sample);
        final data = HuyaParse.playData(fixture.body, status: fixture.status);
        final legacy = fixture.legacy as Map<String, dynamic>;
        final qualities = (legacy['parsePlayQualities'] as List).cast<Map<String, dynamic>>();
        final parsed = HuyaParse.qualities(data);
        expect(parsed.map((q) => q.id), qualities.map((q) => '${q['id']}'));
        expect(parsed.map((q) => q.label), qualities.map((q) => q['quality']));
        expect(parsed.map((q) => q.rank), qualities.map((q) => q['sort']));

        final lines = HuyaParse.lines(data);
        final legacyLines = ((legacy['data'] as Map)['lines'] as List).cast<Map<String, dynamic>>();
        expect(lines.map((l) => l.cdnType), legacyLines.map((l) => l['cdnType']));
        expect(lines.map((l) => l.format.name), legacyLines.map((l) => l['lineType']));
        expect(lines.map((l) => l.base.toString()), legacyLines.map((l) => l['secureHuyaCdnBase']));
        expect(lines.map((l) => l.streamName), legacyLines.map((l) => l['streamName']));
        expect(lines.map((l) => l.presenterUid), legacyLines.map((l) => l['presenterUid']));
        // FLV carries only sFlvAntiCode, HLS only sHlsAntiCode (§6.1, REG-HUYA-006).
        expect(
          lines.map((l) => l.antiCode),
          legacyLines.map((l) => l[l['lineType'] == 'flv' ? 'flvAntiCode' : 'hlsAntiCode']),
        );
        expect(lines.every((l) => l.needsSigning), isTrue);
        expect(lines.map((l) => l.toString()).join(), isNot(contains('wsSecret')));
      });
    }

    test('S05-multicdn leaves out AL13, which multiLine does not list (§5.2)', () {
      final fixture = Fixture.load('huya', 'S05-multicdn');
      final data = HuyaParse.playData(fixture.body);
      final base = ((data['stream'] as Map)['baseSteamInfoList'] as List).map((b) => (b as Map)['sCdnType']);
      expect(base, contains('AL13'));
      expect(HuyaParse.lines(data).map((l) => l.cdnType), isNot(contains('AL13')));
      // Server order, FLV before HLS (§5.2).
      expect(HuyaParse.lines(data).map((l) => '${l.format.name}:${l.cdnType}'), [
        for (final format in ['flv', 'hls'])
          for (final cdn in ['AL', 'TX', 'HS', 'TX15', 'HS24']) '$format:$cdn',
      ]);
    });

    test('S05-ratearray: rateArray fallback matches legacy; no line is StreamUnavailable', () {
      final fixture = Fixture.load('huya', 'S05-ratearray');
      final data = HuyaParse.playData(fixture.body, status: fixture.status);
      final legacy = fixture.legacy as Map<String, dynamic>;
      final qualities = (legacy['parsePlayQualities'] as List).cast<Map<String, dynamic>>();
      expect(HuyaParse.qualities(data).map((q) => q.id), qualities.map((q) => '${q['id']}'));
      expect(HuyaParse.qualities(data).map((q) => q.label), qualities.map((q) => q['quality']));
      // Legacy returned zero lines silently (DIAGNOSIS); §9 calls it StreamUnavailable.
      expect((legacy['data'] as Map)['lines'], isEmpty);
      expect(() => HuyaParse.lines(data), throwsA(isA<StreamUnavailable>()));
    });

    test('S06 offline and replay rooms offer no stream (§4.2, §6.1)', () {
      for (final sample in ['S06-off', 'S06-replay']) {
        final fixture = Fixture.load('huya', sample);
        expect(
          () => HuyaParse.playData(fixture.body, status: fixture.status),
          throwsA(isA<StreamUnavailable>()),
          reason: sample,
        );
      }
    });

    test('S05-multicdn line assembly: signed query, ratio, headers, unconfirmed quality, native lease', () {
      final fixture = Fixture.load('huya', 'S05-multicdn');
      final data = HuyaParse.playData(fixture.body);
      final line = HuyaParse.lines(data).first;
      final quality = HuyaParse.qualities(data).firstWhere((q) => q.id == '4000');
      expect(() => HuyaParse.mediaUrl(line, antiCode: line.antiCode, quality: quality), throwsArgumentError);
      final signedAt = fixture.capturedAt;
      final wsTime = (signedAt.millisecondsSinceEpoch ~/ 1000 + 60).toRadixString(16);
      final url = HuyaParse.mediaUrl(
        line,
        antiCode: 'wsSecret=s&wsTime=$wsTime&seqid=1&ctype=huya_pc_exe&ver=1&fs=bgct&t=100&u=2',
        quality: quality,
      );
      expect(
        url.toString(),
        'https://al-game.flv.huya.com/src/${line.streamName}.flv'
        '?wsSecret=s&wsTime=$wsTime&seqid=1&ctype=huya_pc_exe&ver=1&fs=bgct&t=100&u=2&codec=264&ratio=4000',
      );
      final token = HuyaParse.tokenWindow('wsTime=$wsTime&ctype=huya_pc_exe', expireTime: 300, receivedAt: signedAt);
      final stream = HuyaParse.streamLine(
        line,
        url: url,
        requested: quality,
        roomId: '660000',
        builtAt: signedAt,
        token: token,
      );
      expect(stream.lineId, 'AL');
      expect(stream.format, StreamFormat.flv);
      expect(stream.requested, quality);
      expect(stream.confirmed, isNull);
      expect(stream.codec, 'avc');
      expect(stream.headers, {
        'user-agent': HuyaParse.mediaUserAgent,
        'origin': 'https://www.huya.com',
        'referer': 'https://www.huya.com/660000',
      });
      // iExpireTime 300 s (NATIVE) is earlier than wsTime + 300 s, so it bounds the lease.
      final invalidAt = signedAt.toUtc().add(const Duration(seconds: 300));
      expect(stream.lease!.cutsConnection, isFalse);
      expect(stream.lease!.expiresAt, invalidAt);
      expect(stream.lease!.refreshAt, invalidAt.subtract(const Duration(seconds: 30)));
    });
  });

  group('rules without samples', () {
    String profile(Object? liveStatus, {Object? stream}) => jsonEncode({
      'status': 200,
      'data': {
        'liveStatus': liveStatus,
        'profileInfo': {'uid': 7, 'nick': 'n', 'profileRoom': 11},
        'liveData': {'introduction': '', 'roomName': 'fallback', 'userCount': 9},
        'stream': ?stream,
      },
    });

    test('liveStatus is trimmed and case-insensitive; an unknown value is an error, never offline', () {
      expect(HuyaParse.detail(profile(' on ')).state, LiveState.live);
      expect(HuyaParse.detail(profile('Replay')).state, LiveState.replay);
      for (final value in ['OFF', 'offline', 'CLOSED']) {
        expect(HuyaParse.detail(profile(value)).state, LiveState.offline, reason: value);
      }
      // §4.2/§9 say "unknown"; ADR 0010 has no unknown state, so it is ApiChanged.
      for (final value in ['PAUSE', null]) {
        expect(() => HuyaParse.detail(profile(value)), throwsA(isA<ApiChanged>()), reason: '$value');
      }
    });

    test('detail: roomName fills an empty title, userCount fills a missing totalCount', () {
      final detail = HuyaParse.detail(profile('ON'));
      expect(detail.card.title, 'fallback');
      expect(detail.card.audience, const Audience(popularity: 9));
      expect(detail.ref, RoomRef('huya', '11'));
    });

    test('ON without stream is StreamUnavailable; HTTP and status failures are typed', () {
      expect(() => HuyaParse.playData(profile('ON')), throwsA(isA<StreamUnavailable>()));
      expect(() => HuyaParse.detail(profile('ON'), status: 502), throwsA(isA<NetworkFailure>()));
      expect(() => HuyaParse.detail(profile('ON'), status: 429), throwsA(isA<RateLimited>()));
      expect(() => HuyaParse.detail('<html>'), throwsA(isA<ApiChanged>()));
      expect(() => HuyaParse.detail('{"status":500,"data":{}}'), throwsA(isA<ApiChanged>()));
      expect(() => HuyaParse.roomListPage('{"status":200,"data":{}}', page: 1), throwsA(isA<ApiChanged>()));
      expect(() => HuyaParse.searchPage('{"response":{}}', start: 0, rows: 20), throwsA(isA<ApiChanged>()));
    });

    test('qualities: bitRateInfo list, blank and negative dropped, first rate wins, source first', () {
      final qualities = HuyaParse.qualities({
        'liveData': {
          'bitRateInfo': [
            {'sDisplayName': '流畅', 'iBitRate': 500},
            {'sDisplayName': ' ', 'iBitRate': 8000},
            {'sDisplayName': '负', 'iBitRate': -1},
            {'sDisplayName': '原画', 'iBitRate': 0},
            {'sDisplayName': '超清', 'iBitRate': 2000},
            {'sDisplayName': '重复超清', 'iBitRate': '2000'},
          ],
        },
      });
      expect(qualities.map((q) => '${q.id}:${q.label}'), ['0:原画', '2000:超清', '500:流畅']);
      final selected = HuyaParse.selectQuality(qualities, const Quality(id: '500', label: 'x', rank: 0));
      expect(selected.label, '流畅');
      expect(HuyaParse.selectQuality(qualities, null).id, '0');
    });

    test('qualities: a broken bitRateInfo falls back to rateArray; nothing at all is one 原画', () {
      final fallback = HuyaParse.qualities({
        'liveData': {'bitRateInfo': '[not json'},
        'stream': {
          'flv': {
            'rateArray': [
              {'sDisplayName': '超清', 'iBitRate': 2000},
            ],
          },
        },
      });
      expect(fallback.map((q) => q.id), ['2000']);
      // REG-HUYA-013: no invented 2000 kbps option.
      expect(HuyaParse.qualities(const {}).map((q) => '${q.id}:${q.label}'), ['0:原画']);
    });

    test('lines: https only for huya.com hosts; presenter UID chain; unmatched CDNs skipped', () {
      final data = {
        'profileInfo': {'uid': '42'},
        'stream': {
          'baseSteamInfoList': [
            {
              'sCdnType': 'AL',
              'sFlvUrl': 'http://al.flv.huya.com/src',
              'sHlsUrl': 'http://al.hls.huya.com.example/src',
              'sStreamName': 's',
              'sFlvAntiCode': 'wsSecret=a&wsTime=1',
              'sHlsAntiCode': 'wsSecret=b&wsTime=1',
              'lPresenterUid': 0,
              'lChannelId': 5,
            },
          ],
          'flv': {
            'multiLine': [
              {'cdnType': 'AL', 'url': 'x'},
              {'cdnType': 'TX', 'url': 'x'},
              {'cdnType': 'AL', 'url': ''},
            ],
          },
          'hls': {
            'multiLine': [
              {'cdnType': 'AL', 'url': 'x'},
            ],
          },
        },
      };
      final lines = HuyaParse.lines(data);
      expect(lines.map((l) => l.base.toString()), [
        'https://al.flv.huya.com/src',
        'http://al.hls.huya.com.example/src',
      ]);
      expect(lines.map((l) => l.antiCode), ['wsSecret=a&wsTime=1', 'wsSecret=b&wsTime=1']);
      expect(lines.map((l) => l.presenterUid), [42, 42]);
      expect(lines.first.needsSigning, isFalse);
    });

    test('media URL: codec kept when present, ratio replaced, source removes ratio', () {
      final line = HuyaLine(
        cdnType: 'TX',
        format: StreamFormat.hls,
        base: Uri.parse('https://tx.hls.huya.com/src/'),
        streamName: 'n',
        antiCode: '',
      );
      const source = Quality(id: '0', label: '原画', rank: 1);
      const hd = Quality(id: '2000', label: '超清', rank: 0);
      final replaced = HuyaParse.mediaUrl(line, antiCode: 'a=1&codec=265&ratio=4000&ratio=500', quality: hd);
      expect(replaced.toString(), 'https://tx.hls.huya.com/src/n.m3u8?a=1&codec=265&ratio=2000');
      final removed = HuyaParse.mediaUrl(line, antiCode: 'a=1&ratio=500', quality: source);
      expect(removed.toString(), 'https://tx.hls.huya.com/src/n.m3u8?a=1&codec=264');
      expect(() => HuyaParse.mediaUrl(line, antiCode: ' ', quality: hd), throwsArgumentError);
    });

    test('rotl64 keeps the high 32 bits (REG-HUYA-008) and round-trips', () {
      const uid = 1400123456789;
      final rotated = HuyaParse.rotateUid(uid);
      expect(rotated >> 32, uid >> 32);
      expect(rotated & 0xFFFFFFFF, (((uid & 0xFFFFFFFF) << 8) | ((uid & 0xFFFFFFFF) >> 24)) & 0xFFFFFFFF);
      expect(HuyaParse.unrotateUid(rotated), uid);
    });

    test('web lease: issued at seqid − UID, 100/125 s, cuts the connection; HLS too', () {
      const uid = 1400123456789;
      final issuedAt = DateTime.utc(2026, 9, 27, 12);
      final seqId = uid + issuedAt.millisecondsSinceEpoch;
      final wsTime = (issuedAt.millisecondsSinceEpoch ~/ 1000 + 86400).toRadixString(16);
      final later = issuedAt.add(const Duration(seconds: 90));
      for (final path in ['live.flv', 'live.m3u8']) {
        final url = Uri.parse(
          'https://al.flv.huya.com/src/$path?wsTime=$wsTime&t=100&ctype=huya_webh5&seqid=$seqId'
          '&u=${HuyaParse.rotateUid(uid)}',
        );
        expect(HuyaParse.isNativeFlv(url), isFalse);
        expect(HuyaParse.signedIssuedAt(url), issuedAt);
        // Built (or read) later: the lease still counts from the issue time (§6.6).
        final lease = HuyaParse.lease(url, builtAt: later)!;
        expect(lease.cutsConnection, isTrue);
        expect(lease.refreshAt, issuedAt.add(const Duration(seconds: 100)));
        expect(lease.expiresAt, issuedAt.add(const Duration(seconds: 125)));
      }
    });

    test('web lease: WAP uses uid; no seqid counts from construction; wsTime and token tighten', () {
      const uid = 1400123456789;
      final issuedAt = DateTime.utc(2026, 9, 27, 12);
      final wsTime = (issuedAt.millisecondsSinceEpoch ~/ 1000 + 3600).toRadixString(16);
      final wap = Uri.parse(
        'https://al.hls.huya.com/src/x.m3u8?wsTime=$wsTime&t=103&seqid=${uid + issuedAt.millisecondsSinceEpoch}&uid=$uid',
      );
      expect(HuyaParse.signedIssuedAt(wap), issuedAt);

      final staticToken = Uri.parse('https://al.flv.huya.com/src/x.flv?wsSecret=legacy&wsTime=$wsTime&t=102');
      expect(HuyaParse.signedIssuedAt(staticToken), isNull);
      final built = HuyaParse.lease(staticToken, builtAt: issuedAt)!;
      expect(built.refreshAt, issuedAt.add(const Duration(seconds: 100)));

      final nearWsTime = (issuedAt.millisecondsSinceEpoch ~/ 1000 - 250).toRadixString(16);
      final closing = Uri.parse('https://al.flv.huya.com/src/x.flv?wsTime=$nearWsTime');
      final tight = HuyaParse.lease(closing, builtAt: issuedAt)!;
      expect(tight.refreshAt, issuedAt.add(const Duration(seconds: 20)));
      expect(tight.expiresAt, issuedAt.add(const Duration(seconds: 50)));

      final token = HuyaTokenWindow(
        refreshAt: issuedAt.add(const Duration(seconds: 10)),
        invalidAt: issuedAt.add(const Duration(seconds: 40)),
      );
      final withToken = HuyaParse.lease(staticToken, builtAt: issuedAt, token: token)!;
      expect(withToken.refreshAt, token.refreshAt);
      expect(withToken.expiresAt, token.invalidAt);

      expect(HuyaParse.lease(Uri.parse('https://cdn.example/x.flv?wsTime=$wsTime'), builtAt: issuedAt), isNull);
    });

    test('native FLV lease: min(wsTime + 300 s, iExpireTime), refresh 30 s before, no cut (REG-HUYA-002)', () {
      final now = DateTime.utc(2026, 9, 27, 12);
      final wsTime = (now.millisecondsSinceEpoch ~/ 1000 + 3600).toRadixString(16);
      final url = Uri.parse('https://tx.flv.huya.com/src/x.flv?wsTime=$wsTime&ctype=huya_pc_exe&t=100');
      expect(HuyaParse.isNativeFlv(url), isTrue);
      expect(
        HuyaParse.isNativeFlv(Uri.parse('https://tx.flv.huya.com.example/src/x.flv?ctype=huya_pc_exe&t=100')),
        isFalse,
      );

      final token = 'wsTime=$wsTime&ctype=huya_pc_exe&t=100';
      final relative = HuyaParse.tokenWindow(token, expireTime: 300, receivedAt: now);
      expect(relative.invalidAt, now.add(const Duration(seconds: 300)));
      final seconds = HuyaParse.tokenWindow(
        token,
        expireTime: now.millisecondsSinceEpoch ~/ 1000 + 90,
        receivedAt: now,
      );
      expect(seconds.invalidAt, now.add(const Duration(seconds: 90)));
      final millis = HuyaParse.tokenWindow(token, expireTime: now.millisecondsSinceEpoch + 60000, receivedAt: now);
      expect(millis.invalidAt, now.add(const Duration(seconds: 60)));
      final noBound = HuyaParse.tokenWindow(token, expireTime: 0, receivedAt: now);
      expect(noBound.invalidAt, now.add(const Duration(seconds: 3900)));
      expect(noBound.refreshAt, now.add(const Duration(seconds: 3870)));

      final lease = HuyaParse.lease(url, builtAt: now, token: relative)!;
      expect(lease.cutsConnection, isFalse);
      expect(lease.expiresAt, relative.invalidAt);
      expect(lease.refreshAt, relative.invalidAt.subtract(const Duration(seconds: 30)));

      for (final bad in ['', 'wsSecret=x', 'wsTime=zz']) {
        expect(() => HuyaParse.tokenWindow(bad, expireTime: 0, receivedAt: now), throwsA(isA<ApiChanged>()));
      }
    });

    test('search: a room repeated inside one response is listed once; unmatched streamers fall back', () {
      final body = jsonEncode({
        'response': {
          '1': {
            'docs': [
              {'uid': 1, 'yyid': 2, 'room_id': 900},
            ],
          },
          '3': {
            'numFound': 3,
            'docs': [
              {'uid': 1, 'yyid': 2, 'room_id': 111, 'game_nick': 'a'},
              {'uid': 3, 'yyid': 4, 'room_id': 222, 'game_nick': 'b'},
              {'uid': 3, 'yyid': 4, 'room_id': 222, 'game_nick': 'b'},
            ],
          },
        },
      });
      final page = HuyaParse.searchPage(body, start: 0, rows: 20);
      expect(page.items.map((r) => r.ref.roomId), ['900', '222']);
      expect(page.isLast, isTrue);
    });
  });
}

/// Legacy writes a missing field as ''; v4 uses null.
String? _blankToNull(Object? value) => value == null || value == '' ? null : value as String;
