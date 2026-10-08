import 'dart:async';

import 'package:live_cli/live_cli.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

import 'fakes.dart';

const _target = PatrolTarget(
  site: 'bilibili',
  name: '哔哩哔哩',
  keyword: '英雄联盟',
  anchors: true,
  fixedRooms: [
    FixedRoom('100', note: '未开播'),
    FixedRoom('101', note: '轮播'),
  ],
  missingRoom: '999',
);

const _quality = LivePlayQuality(quality: '原画', id: 10000);

/// A site where every check passes.
FakeResolverSite _healthy() => FakeResolverSite()
  ..recommend = {
    1: [room('1'), room('2'), room('3')],
    2: [room('4'), room('5')],
  }
  ..categories = [
    LiveCategory(
      id: 'c',
      name: '网游',
      children: const [LiveArea(platform: 'bilibili', areaId: '86', areaName: '英雄联盟')],
    ),
  ]
  ..areaPages = {
    1: [room('11'), room('12')],
    2: [room('13')],
  }
  ..rooms = [room('21'), room('22', status: LiveStatus.offline)]
  ..anchors = [const LiveAnchorItem(roomId: '31', avatar: '', userName: '主播', liveStatus: true)]
  ..details = {
    for (final id in ['1', '2', '3']) id: room(id, link: 'https://live.bilibili.com/$id'),
    '100': room('100', status: LiveStatus.offline),
    '101': room('101', status: LiveStatus.carousel),
  }
  ..qualities = {
    for (final id in ['1', '2', '3']) id: [_quality],
  }
  ..resolutions = {
    for (final id in ['1', '2', '3'])
      id: LivePlayUrlResolution.lines([
        LivePlayLine('https://cdn.example/live/$id.flv?sign=secret', format: StreamFormat.flv),
      ], appliedQualityData: 10000),
  };

void main() {
  test('a healthy platform passes every check but P13 without --danmaku', () async {
    final run = await patrolOf(_healthy(), _target, links: {'https://live.bilibili.com/1': '1'}).run();
    final outcomes = {for (final result in run.results) result.check: result.outcome};
    expect(outcomes.values.where((outcome) => outcome == Outcome.ok), hasLength(12), reason: '${run.toJson()}');
    expect(resultOf(run, CheckId.p13).outcome, Outcome.notRun);
    expect(resultOf(run, CheckId.p13).note, contains('--danmaku'));
    expect(run.hasFailure, isFalse);
  });

  group('P1 recommend', () {
    test('page 2 repeating page 1 fails', () async {
      final site = _healthy()..recommend[2] = [room('1'), room('2'), room('9')];
      final result = resultOf(await patrolOf(site, _target).run(), CheckId.p1);
      expect(result.outcome, Outcome.failed);
      expect(result.note, contains('超过一半'));
    });

    test('an empty first page fails', () async {
      final site = _healthy()..recommend = {};
      expect(resultOf(await patrolOf(site, _target).run(), CheckId.p1).outcome, Outcome.failed);
    });

    test('a card without room id fails', () async {
      final site = _healthy()..recommend[1] = [room(''), room('2')];
      final result = resultOf(await patrolOf(site, _target).run(), CheckId.p1);
      expect(result.outcome, Outcome.failed);
      expect(result.note, contains('没有房间号'));
    });

    test('a small last page that only repeats page 1 passes and says so (17LIVE, E03.18)', () async {
      final site = FakePagerSite()
        ..pages = {
          1: LiveDirectoryPage(rooms: [for (var i = 1; i <= 8; i++) room('$i')], page: 1, hasMore: true),
          2: LiveDirectoryPage(rooms: [room('3')], page: 2, hasMore: false),
        };
      final result = resultOf(await patrolOf(site, _target).run(), CheckId.p1);
      expect(result.outcome, Outcome.ok, reason: result.note);
      expect(result.note, contains('最后一页'));
    });

    test('a last page as large as page 1 and repeating it still fails (a cursor that is ignored)', () async {
      final site = FakePagerSite()
        ..pages = {
          1: LiveDirectoryPage(rooms: [room('1'), room('2')], page: 1, hasMore: true),
          2: LiveDirectoryPage(rooms: [room('1'), room('2')], page: 2, hasMore: false),
        };
      expect(resultOf(await patrolOf(site, _target).run(), CheckId.p1).outcome, Outcome.failed);
    });

    test('a directory pager without more pages passes and says so', () async {
      final site = FakePagerSite()
        ..pages = {
          1: LiveDirectoryPage(rooms: [room('1')], page: 1, hasMore: false),
        };
      final result = resultOf(await patrolOf(site, _target).run(), CheckId.p1);
      expect(result.outcome, Outcome.ok);
      expect(result.note, contains('没有第 2 页'));
    });
  });

  test('P2 fails on a category without areas', () async {
    final site = _healthy()..categories = [LiveCategory(id: 'c', name: '空', children: const [])];
    final run = await patrolOf(site, _target).run();
    expect(resultOf(run, CheckId.p2).outcome, Outcome.failed);
    expect(resultOf(run, CheckId.p3).outcome, Outcome.notRun);
  });

  test('P3 pages the named area and fails when page 2 repeats it', () async {
    final site = _healthy()..areaPages[2] = [room('11'), room('12')];
    final result = resultOf(await patrolOf(site, _target).run(), CheckId.p3);
    expect(result.outcome, Outcome.failed);
    expect(result.note, contains('英雄联盟'));
  });

  test('P4 fails when a live-only search answers offline rooms', () async {
    const target = PatrolTarget(site: 'huya', name: '虎牙', keyword: 'lol', search: SearchKind.liveOnly);
    final result = resultOf(await patrolOf(_healthy(), target).run(), CheckId.p4);
    expect(result.outcome, Outcome.failed);
    expect(result.note, contains('1 个未开播'));
  });

  test('P4 of a room-lookup platform searches the first recommended room id', () async {
    final site = _healthy();
    const target = PatrolTarget(site: 'weibo', name: '微博', search: SearchKind.roomLookup);
    await patrolOf(site, target).run();
    expect(site.keywords, ['1']);
  });

  test('P4 of a room-lookup platform without recommendations looks up its first fixed room (E02.14)', () async {
    final site = _healthy()
      ..details['100'] = room('100', status: LiveStatus.offline)
      ..rooms = [room('100', status: LiveStatus.offline)];
    const target = PatrolTarget(
      site: 'xiaohongshu',
      name: '小红书',
      search: SearchKind.roomLookup,
      fixedRooms: [FixedRoom('100', note: '已结束')],
      unsupported: {CheckId.p1: '没有公开目录', CheckId.p2: '没有分区', CheckId.p3: '没有分区'},
    );
    final run = await patrolOf(site, target).run();
    expect(resultOf(run, CheckId.p1).outcome, Outcome.unsupported);
    expect(site.keywords, ['100']);
    expect(resultOf(run, CheckId.p4).outcome, Outcome.ok);
    expect(resultOf(run, CheckId.p6).outcome, Outcome.notRun, reason: 'no live room reachable anonymously');
  });

  test("Xiaohongshu's object row: no public directory (P1), lookups by its ended room (E02.14)", () {
    final row = patrolTargets.singleWhere((target) => target.site == SiteIds.xiaohongshu);
    expect(row.unsupported.keys, containsAll([CheckId.p1, CheckId.p2, CheckId.p3]));
    expect(row.search, SearchKind.roomLookup);
    expect(row.fixedRooms, isNotEmpty);
  });

  test('P5 is unsupported without streamer search, and listed reasons win', () async {
    const target = PatrolTarget(site: 'x', name: 'x', keyword: 'k', unsupported: {CheckId.p2: '没有分区'});
    final run = await patrolOf(_healthy(), target).run();
    expect(resultOf(run, CheckId.p5).outcome, Outcome.unsupported);
    expect(resultOf(run, CheckId.p2).outcome, Outcome.unsupported);
    expect(resultOf(run, CheckId.p2).note, '没有分区');
  });

  test('P6 skips a room that went offline and fails a room without title on card and detail', () async {
    final site = _healthy()
      ..details['1'] = room('1', status: LiveStatus.offline)
      ..recommend[1] = [room('1'), room('2', title: ''), room('3')]
      ..details['2'] = room('2', title: ' ');
    final result = resultOf(await patrolOf(site, _target).run(), CheckId.p6);
    expect(result.outcome, Outcome.failed);
    expect(result.note, allOf(contains('1 已经offline'), contains('2 缺标题')));
  });

  test('P6 takes a missing title from the card, as the room page does (Kuaishou, A-3)', () async {
    final site = _healthy()
      ..recommend[1] = [room('1', title: '卡片标题'), room('2'), room('3')]
      ..details['1'] = room('1', title: '');
    final result = resultOf(await patrolOf(site, _target).run(), CheckId.p6);
    expect(result.outcome, Outcome.ok);
    expect(result.note, contains('标题取自卡片'));
  });

  test('P6 of a platform that must name the area tries the area page first and reads the detail', () async {
    const target = PatrolTarget(site: 'douyin', name: '抖音', requireArea: true);
    final site = _healthy()
      ..details['11'] = room('11', area: '英雄联盟')
      ..details['12'] = room('12', area: null)
      ..details['13'] = room('13');
    final result = resultOf(await patrolOf(site, target).run(), CheckId.p6);
    expect(result.outcome, Outcome.failed);
    expect(result.note, allOf(contains('11（英雄联盟）'), contains('12 缺分区')));
    expect(result.note, isNot(contains('1 缺')));
  });

  test('a slow platform has its own limit per check', () async {
    const target = PatrolTarget(site: 'kuaishou', name: '快手', checkTimeout: Duration(seconds: 1));
    final site = _healthy()..hang = Completer<List<LiveRoom>>();
    final result = resultOf(await patrolOf(site, target).run(), CheckId.p1);
    expect(result.note, contains('超过 1 秒'));
  });

  test('P6 skips restricted rooms, whose streams need an account', () async {
    final site = _healthy()
      ..details['1'] = LiveRoom(
        roomId: '1',
        platform: 'bilibili',
        title: 't',
        nick: 'n',
        liveStatus: LiveStatus.live,
        restriction: LiveRestriction.needsLogin,
      );
    final run = await patrolOf(site, _target).run();
    expect(resultOf(run, CheckId.p6).note, contains('1 受限（needsLogin，跳过）'));
    expect(resultOf(run, CheckId.p9).note, startsWith('2 '));
  });

  test('P6 fails a start time in the future', () async {
    final site = _healthy()..details['1'] = room('1', startedAt: DateTime.utc(2026, 10, 9));
    expect(resultOf(await patrolOf(site, _target).run(), CheckId.p6).note, contains('开播时间'));
  });

  group('P7 fixed rooms', () {
    test('an unknown state fails', () async {
      final site = _healthy()..details['100'] = room('100', status: LiveStatus.unknown);
      final result = resultOf(await patrolOf(site, _target).run(), CheckId.p7);
      expect(result.outcome, Outcome.failed);
      expect(result.note, contains('状态不对'));
    });

    test('a fixed room that is gone fails', () async {
      final site = _healthy()..details.remove('101');
      final result = resultOf(await patrolOf(site, _target).run(), CheckId.p7);
      expect(result.outcome, Outcome.failed);
      expect(result.note, contains('NotFound'));
    });
  });

  group('P8 missing room', () {
    test('another error kind fails as the wrong kind', () async {
      final site = _healthy()..details['999'] = const ApiChanged('bilibili', 'shape');
      final result = resultOf(await patrolOf(site, _target).run(), CheckId.p8);
      expect(result.outcome, Outcome.failed);
      expect(result.note, contains('错误类型不对'));
    });

    test('an answer without error fails', () async {
      final site = _healthy()..details['999'] = room('999', status: LiveStatus.offline);
      final result = resultOf(await patrolOf(site, _target).run(), CheckId.p8);
      expect(result.outcome, Outcome.failed);
      expect(result.note, contains('应报 NotFound'));
    });
  });

  test('a RiskControl stops the platform: later checks are not run', () async {
    final site = _healthy()..categories = const RiskControl('bilibili', detail: '-352');
    final run = await patrolOf(site, _target).run();
    expect(resultOf(run, CheckId.p1).outcome, Outcome.ok);
    expect(resultOf(run, CheckId.p2).outcome, Outcome.failed);
    expect(resultOf(run, CheckId.p2).note, contains('RiskControl：-352'));
    for (final check in CheckId.values.skip(2)) {
      expect(resultOf(run, check).outcome, Outcome.notRun, reason: check.code);
      expect(resultOf(run, check).note, contains('风控'));
    }
  });

  test('P8 with RiskControl fails as the wrong kind', () async {
    final site = _healthy()..details['999'] = const RiskControl('bilibili');
    final result = resultOf(await patrolOf(site, _target).run(), CheckId.p8);
    expect(result.outcome, Outcome.failed);
    expect(result.note, contains('错误类型不对'));
  });

  group('P9 qualities', () {
    test('a live room the platform says has no stream is skipped, not failed (Douyu streamStatus 0, E01.7)', () async {
      final site = _healthy()..qualityErrors['2'] = const StreamUnavailable('bilibili', 'no stream pushed');
      final run = await patrolOf(site, _target).run();
      final p9 = resultOf(run, CheckId.p9);
      expect(p9.outcome, Outcome.ok, reason: p9.note);
      expect(p9.note, contains('2 没有流'));
      expect(resultOf(run, CheckId.p10).outcome, Outcome.ok);
    });

    test('when no live room has a stream, P9 is not run rather than failed', () async {
      final site = _healthy()
        ..qualityErrors.addAll({
          for (final id in ['1', '2', '3']) id: const StreamUnavailable('bilibili', 'none'),
        });
      expect(resultOf(await patrolOf(site, _target).run(), CheckId.p9).outcome, Outcome.notRun);
    });

    test('repeated names fail', () async {
      final site = _healthy()..qualities['1'] = [_quality, const LivePlayQuality(quality: '原画', id: 1)];
      expect(resultOf(await patrolOf(site, _target).run(), CheckId.p9).note, contains('名字重复'));
    });

    test('no qualities fail', () async {
      final site = _healthy()..qualities['2'] = [];
      expect(resultOf(await patrolOf(site, _target).run(), CheckId.p9).outcome, Outcome.failed);
    });
  });

  group('P10 lines', () {
    test('a recipe passes without opening it', () async {
      final site = _healthy()
        ..resolutions = {
          for (final id in ['1', '2', '3']) id: LivePlayUrlResolution.owned(input: FakeRecipe()),
        };
      final result = resultOf(await patrolOf(site, _target).run(), CheckId.p10);
      expect(result.outcome, Outcome.ok);
      expect(result.note, contains('配方，未打开'));
    });

    test('an HLS line that starts with FLV fails', () async {
      final site = _healthy()
        ..resolutions = {
          for (final id in ['1', '2', '3'])
            id: LivePlayUrlResolution.lines(const [
              LivePlayLine('https://cdn.example/a/b/c.m3u8', format: StreamFormat.hls),
            ]),
        };
      final result = resultOf(await patrolOf(site, _target).run(), CheckId.p10);
      expect(result.outcome, Outcome.failed);
      expect(result.note, contains('开头是FLV'));
      expect(result.note, isNot(contains('c.m3u8')));
    });

    test('an HTTP error fails and the downgrade is written', () async {
      final site = _healthy()
        ..resolutions['1'] = LivePlayUrlResolution.lines(const [
          LivePlayLine('https://cdn.example/live/1.flv', format: StreamFormat.flv),
        ], appliedQualityData: 250);
      final run = await patrolOf(site, _target, head: MediaHead(status: 403, bytes: const [])).run();
      final result = resultOf(run, CheckId.p10);
      expect(result.outcome, Outcome.failed);
      expect(result.note, allOf(contains('HTTP 403'), contains('实际给 250')));
    });
  });

  group('P11 leases', () {
    LivePlayUrlResolution leased(DateTime refreshAt) => LivePlayUrlResolution.lines([
      LivePlayLine(
        'https://cdn.example/live/x.flv',
        format: StreamFormat.flv,
        lease: PlayLease(refreshAt: refreshAt),
      ),
    ]);

    test('a lease due in the future passes with the minutes left', () async {
      final site = _healthy()
        ..resolutions = {
          for (final id in ['1', '2', '3']) id: leased(DateTime.utc(2026, 10, 8, 12, 30)),
        };
      final result = resultOf(await patrolOf(site, _target).run(), CheckId.p11);
      expect(result.outcome, Outcome.ok);
      expect(result.note, contains('30 分钟'));
    });

    test('a lease already due fails', () async {
      final site = _healthy()
        ..resolutions = {
          for (final id in ['1', '2', '3']) id: leased(DateTime.utc(2026, 10, 8, 11)),
        };
      expect(resultOf(await patrolOf(site, _target).run(), CheckId.p11).outcome, Outcome.failed);
    });
  });

  group('P12 links', () {
    test('a link leading to another room fails', () async {
      final run = await patrolOf(_healthy(), _target, links: {'https://live.bilibili.com/1': '2'}).run();
      final result = resultOf(run, CheckId.p12);
      expect(result.outcome, Outcome.failed);
      expect(result.note, contains('应为 1'));
    });

    test('a link naming the room another way passes when its detail is the same room', () async {
      final site = _healthy()..details['key-1'] = room('1');
      final run = await patrolOf(site, _target, links: {'https://live.bilibili.com/1': 'key-1'}).run();
      final result = resultOf(run, CheckId.p12);
      expect(result.outcome, Outcome.ok);
      expect(result.note, contains('详情是同一房间 1'));
    });

    test('the room page is also built from the card id, and ids without one are left out', () async {
      final target = PatrolTarget(
        site: 'niconico',
        name: 'niconico',
        roomLink: (id) => id.startsWith('lv') ? 'https://nico.ms/$id' : null,
      );
      final site = _healthy()
        ..recommend[1] = [room('lv1'), room('lv2'), room('lv3')]
        ..details.addAll({
          for (final n in [1, 2, 3]) 'lv$n': room('user/$n'),
        });
      final run = await patrolOf(site, target, links: {'https://nico.ms/lv1': 'user/1'}).run();
      final result = resultOf(run, CheckId.p12);
      expect(result.outcome, Outcome.ok);
      expect(result.note, contains('房间页（nico.ms）→ user/1'));
    });

    test('case is ignored on platforms whose ids ignore it', () async {
      const target = PatrolTarget(
        site: 'kuaishou',
        name: '快手',
        links: [LinkCase('https://live.kuaishou.com/u/kpl704668133', expected: 'KPL704668133')],
      );
      final run = await patrolOf(
        _healthy(),
        target,
        links: {'https://live.bilibili.com/1': '1', 'https://live.kuaishou.com/u/kpl704668133': 'kpl704668133'},
      ).run();
      expect(resultOf(run, CheckId.p12).outcome, Outcome.ok);
    });
  });

  group('P13 danmaku', () {
    test('a connection that never gets ready fails', () async {
      final run = await patrolOf(
        _healthy(),
        _target,
        links: {'https://live.bilibili.com/1': '1'},
        danmaku: (_, _, _) async => const DanmakuSample(closed: 'connectionFailed'),
        danmakuDuration: const Duration(seconds: 1),
      ).run();
      final result = resultOf(run, CheckId.p13);
      expect(result.outcome, Outcome.failed);
      expect(result.note, contains('没有就绪'));
    });

    test('a ready connection passes with its counts', () async {
      final run = await patrolOf(
        _healthy(),
        _target,
        danmaku: (_, _, _) async => const DanmakuSample(ready: Duration(milliseconds: 200), chats: 7, online: 3),
        danmakuDuration: const Duration(seconds: 1),
      ).run();
      expect(resultOf(run, CheckId.p13).note, contains('聊天 7 条'));
    });
  });

  test('a check that hangs fails after its limit', () async {
    final site = _healthy()..hang = Completer<List<LiveRoom>>();
    final run = await patrolOf(site, _target, checkTimeout: const Duration(seconds: 1)).run();
    expect(resultOf(run, CheckId.p1).outcome, Outcome.failed);
    expect(resultOf(run, CheckId.p1).note, contains('超过 1 秒'));
  });

  test('a skipped platform is not run at all', () async {
    const target = PatrolTarget(site: 'kick', name: 'Kick', skip: '要 Android 原生通道');
    final run = await patrolOf(FakeSite(id: 'kick'), target).run();
    expect(run.results.map((result) => result.outcome).toSet(), {Outcome.notRun});
    expect(run.results.first.note, '要 Android 原生通道');
  });

  test('describeError names the kind, the transport reason and the status', () {
    expect(describeError(const NotFound('douyu', 'room')), 'NotFound：room');
    expect(describeError(const TransportFailure('douyu', TransportReason.tls)), 'TransportFailure tls');
    expect(describeError(const HttpStatusFailure('huya', 403)), 'HTTP 403');
  });
}
