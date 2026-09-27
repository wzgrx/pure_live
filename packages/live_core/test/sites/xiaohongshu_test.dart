// Xiaohongshu (link-only): share pages, links and the adapter over the
// recorded samples (spec/sites/xiaohongshu.md). No legacy expected values (ADR 0016).
import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _live = '570459564696889177';
const _ended = '570305058583373361';

XiaohongshuSite _site(List<String> samples) =>
    XiaohongshuSite(ReplayHttp.fixtures('../../fixtures/xiaohongshu', samples));

void main() {
  group('§4 share page', () {
    test('S01 live: status "2" as a string, JSON-string pullConfig, FLV and HLS on three CDNs', () {
      final room = XiaohongshuParse.room(Fixture.load('xiaohongshu', 'S01-room-live').body, expectedId: _live);
      expect(room.detail.state, LiveState.live);
      expect(room.detail.card.anchorName, '新华网');
      expect(room.restricted, isFalse, reason: 'joinLimitTypes is the string "[0]"');
      final qualities = XiaohongshuParse.qualities(room.pullConfig!);
      expect(qualities.map((q) => q.label), ['原画']);
      final lines = XiaohongshuParse.lines(room, qualities.first, headers: const {});
      expect(lines.first.format, StreamFormat.flv);
      expect(lines.last.format, StreamFormat.hls);
      expect(lines.where((l) => l.format == StreamFormat.flv), hasLength(3));
      expect(lines.every((l) => l.url.path.contains(_live) && l.codec == 'avc'), isTrue);
    });

    test('S01 ended: offline, no room id, and the recommended next room is ignored', () {
      final room = XiaohongshuParse.room(Fixture.load('xiaohongshu', 'S01-room-ended').body, expectedId: _ended);
      expect(room.detail.state, LiveState.offline);
      expect(room.pullConfig, isNull, reason: 'nextRoomInfo carries another room');
      expect(
        () => XiaohongshuParse.lines(
          room,
          const Quality(id: 'HD', label: '原画', rank: 1),
          headers: const {},
        ),
        throwsA(isA<StreamUnavailable>()),
      );
    });

    test('S01 not found: pageStatus error', () {
      expect(
        () => XiaohongshuParse.room(
          Fixture.load('xiaohongshu', 'S01-room-notfound').body,
          expectedId: '569865232324657152',
        ),
        throwsA(isA<NotFound>()),
      );
    });

    test('state: undefined outside strings only', () {
      const html = 'x<script>window.__INITIAL_STATE__={"a":undefined,"b":"undefined"};</script>';
      expect(XiaohongshuParse.state(html), {'a': null, 'b': 'undefined'});
    });
  });

  group('§1 links', () {
    test('share pages, route variants and deep links', () {
      expect(
        XiaohongshuParse.roomFromUrl(Uri.parse('https://www.xiaohongshu.com/livestream/$_live?share_id=x')),
        _live,
      );
      expect(
        XiaohongshuParse.roomFromUrl(Uri.parse('https://www.xiaohongshu.com/livestream/dynpathAbCd1234/$_live')),
        _live,
      );
      expect(XiaohongshuParse.roomFromUrl(Uri.parse('https://www.xiaohongshu.com/hina/livestream/$_live/abc')), _live);
      expect(
        XiaohongshuParse.roomFromUrl(Uri.parse('xhsdiscover://live_audience?room_id=$_live&source=share_out_of_app')),
        _live,
      );
      expect(XiaohongshuParse.roomFromUrl(Uri.parse('https://www.xiaohongshu.com/explore/abc')), isNull);
      expect(XiaohongshuParse.isShortLink(Uri.parse('https://xhslink.com/m/18ox3lAz')), isTrue);
    });

    test('adapter: ids and share text; an expired short link is unsupported', () async {
      final site = _site(['S02-shortlink-expired']);
      expect(await site.resolve(_live), RoomRef('xiaohongshu', _live));
      expect(
        await site.resolve('【小红书】新华网的直播 https://www.xiaohongshu.com/livestream/$_live 复制本条信息'),
        RoomRef('xiaohongshu', _live),
      );
      await expectLater(site.resolve('看直播 https://xhslink.com/m/18ox3lAz'), throwsA(isA<UnsupportedLink>()));
      expect(await site.resolve('https://www.douyu.com/9999'), isNull);
    });
  });

  test('adapter: detail and streams', () async {
    final site = _site(['S01-room-live']);
    final detail = await site.detail(RoomRef('xiaohongshu', _live));
    final set = await site.streams(detail);
    expect(set.selected.label, '原画');
    expect(set.lines.first.headers['referer'], 'https://www.xiaohongshu.com/');
  });
}
