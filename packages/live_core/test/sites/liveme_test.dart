// LiveMe parsing and the adapter over the recorded samples (spec/sites/liveme.md).
// No legacy expected values: the archived app cannot run (ADR 0016).
import 'dart:convert';
import 'dart:math';

import 'package:live_core/live_core.dart';
import 'package:live_net/testing.dart';
import 'package:test/test.dart';

import 'fixture.dart';

const _ignored = {'_time', 'vali', 'lm_s_ts', 'lm_s_str'};

Map<String, dynamic> _json(String sample) => jsonDecode(Fixture.load('liveme', sample).body) as Map<String, dynamic>;

Map<String, dynamic> _video() =>
    (_json('S05-query-live')['data'] as Map<String, dynamic>)['video_info'] as Map<String, dynamic>;

LiveMeSite _site(List<String> samples) => LiveMeSite(
  ReplayHttp.fixtures('../../fixtures/liveme', samples, ignoredQuery: _ignored),
  now: () => Fixture.load('liveme', 'S05-query-live').capturedAt,
  random: Random(1),
);

void main() {
  test('§6.1 signature vector (computed independently with Python hashlib)', () {
    final signed = LiveMeSigner.signAt(
      query: const {'alias': 'liveme', 'tongdun_black_box': '1', 'os': 'web'},
      form: const {
        '_time': '1790529930544',
        'thirdchannel': '6',
        'videoid': '17904580585651396476',
        'area': 'en',
        'vali': 'ABCDlEFGHmJKMNP',
      },
      timestamp: '17905299305440',
    );
    expect(signed.fields['lm_s_str'], '4c71dbf9913b0b4ad7099adfb411b750');
    expect(signed.signature, 'aaa4b40cb4ab6fa268ab712f39f93b6e');
    expect(LiveMeSigner(random: Random(3)).vali(), matches(RegExp(r'^[A-Za-z2-8]{4}l[A-Za-z2-8]{4}m[A-Za-z2-8]{5}$')));
  });

  group('§2.2 featured list', () {
    for (final sample in ['S01-featurelist-p1', 'S01-featurelist-p2']) {
      test(sample, () {
        final data = _json(sample)['data'] as Map<String, dynamic>;
        final rows = (data['video_info'] as List).cast<Map<String, dynamic>>();
        final page = LiveMeParse.featured(Fixture.load('liveme', sample).body, page: 1);
        final expected = rows.where(
          (r) => r['ushortid'] != null && '${r['ispvt']}' != '1' && '${r['livebptype']}' != '7',
        );
        expect(page.items.map((c) => c.ref.roomId), expected.map((r) => r['ushortid']).toSet());
        expect(page.items.every((c) => c.state == LiveState.live), isTrue);
        final first = page.items.first;
        final row = expected.first;
        expect(
          first.audience,
          Audience(
            online: int.parse(row['playnumber'] as String),
            popularity: int.parse(row['heat'] as String),
            cumulative: int.parse(row['watchnumber'] as String),
          ),
        );
        expect(first.cover.toString(), row['videocapture']);
        expect(page.next, const PageCursor('2'), reason: 'next_page == 1');
      });
    }
  });

  group('§3 search', () {
    test('S02 pages of 20 continue although pageSize is 30; the empty page ends', () {
      final page = LiveMeParse.search(Fixture.load('liveme', 'S02-search-p1').body, page: 1);
      expect(page.items, hasLength(20));
      expect(page.next, const PageCursor('2'), reason: 'legacy stopped here because 20 < 30');
      final p2 = LiveMeParse.search(Fixture.load('liveme', 'S02-search-p2').body, page: 2);
      expect(
        p2.items.map((c) => c.ref.roomId).toSet().intersection(page.items.map((c) => c.ref.roomId).toSet()),
        isEmpty,
      );
      final empty = LiveMeParse.search(Fixture.load('liveme', 'S02-search-empty').body, page: 1);
      expect(empty.items, isEmpty);
      expect(empty.isLast, isTrue);
    });

    test('S02 is_live maps to live, anything else to offline', () {
      final rows = ((_json('S02-search-p1')['data'] as Map)['data_info'] as List).cast<Map<String, dynamic>>();
      final page = LiveMeParse.search(Fixture.load('liveme', 'S02-search-p1').body, page: 1);
      for (final (index, card) in page.items.indexed) {
        expect(card.state == LiveState.live, rows[index]['is_live'] == '1');
        expect(card.avatar.toString(), rows[index]['face']);
      }
    });
  });

  group('§4 detail pieces', () {
    test('S03 mapping: live, offline and unknown short ids', () {
      final live = LiveMeParse.mapping(Fixture.load('liveme', 'S03-mapping-live').body);
      expect(live.videoId, _video()['vid']);
      final offline = LiveMeParse.mapping(Fixture.load('liveme', 'S03-mapping-offline').body);
      expect(offline.videoId, isNull);
      expect(
        () => LiveMeParse.mapping(Fixture.load('liveme', 'S03-mapping-notfound').body),
        throwsA(isA<NotFound>()),
        reason: 'status "400" params error',
      );
    });

    test('S04 profile, and "user not exist" as NotFound', () {
      final profile = LiveMeParse.profile(Fixture.load('liveme', 'S04-profile-live').body);
      expect(profile.shortId, _video()['ushortid']);
      expect(() => LiveMeParse.profile(Fixture.load('liveme', 'S04-profile-notfound').body), throwsA(isA<NotFound>()));
    });

    test('S05 live video: qualities, lines and the Wangsu lease', () {
      final video = _video();
      expect(LiveMeParse.state(video), LiveState.live);
      expect(LiveMeParse.qualities(video), [LiveMeParse.source, LiveMeParse.smooth]);
      final lines = LiveMeParse.lines(video, LiveMeParse.source, headers: const {});
      expect(lines.map((l) => l.format), [StreamFormat.flv, StreamFormat.hls]);
      final lease = lines.first.lease!;
      final expiry = int.parse(Uri.parse(video['videosource'] as String).queryParameters['wsABStime']!, radix: 16);
      expect(lease.expiresAt, DateTime.fromMillisecondsSinceEpoch(expiry * 1000, isUtc: true));
      expect(lease.expiresAt!.difference(lease.refreshAt), const Duration(minutes: 10));
      expect(lease.cutsConnection, isFalse);
      final smooth = LiveMeParse.lines(video, LiveMeParse.smooth, headers: const {});
      expect(smooth.single.url.path, endsWith('_360.flv'));
    });

    test('private rooms need an account; an unknown state is ApiChanged', () {
      final private = {..._video(), 'ispvt': '1'};
      expect(() => LiveMeParse.lines(private, LiveMeParse.source, headers: const {}), throwsA(isA<NeedsLogin>()));
      expect(() => LiveMeParse.state({'online': '2'}), throwsA(isA<ApiChanged>()));
      expect(LiveMeParse.state({..._video(), 'status': '1'}), LiveState.offline);
    });
  });

  group('adapter', () {
    test('live detail and streams over the signed query', () async {
      final shortId = _video()['ushortid'] as String;
      final site = _site(['S03-mapping-live', 'S04-profile-live', 'S05-query-live']);
      final detail = await site.detail(RoomRef('liveme', shortId));
      expect(detail.state, LiveState.live);
      expect(detail.card.anchorName, _video()['uname']);
      expect(detail.link, Uri.parse('https://www.liveme.com/livehot/streaming/$shortId'));
      final set = await site.streams(detail);
      expect(set.selected, LiveMeParse.source);
      expect(set.lines.first.headers['referer'], detail.link.toString());
    });

    test('offline detail from the profile only; unknown short id is NotFound', () async {
      final site = _site(['S03-mapping-offline', 'S04-profile-offline', 'S03-mapping-notfound']);
      final detail = await site.detail(RoomRef('liveme', '17709377'));
      expect(detail.state, LiveState.offline);
      await expectLater(site.detail(RoomRef('liveme', '999999999')), throwsA(isA<NotFound>()));
    });

    test('catalog and search', () async {
      final site = _site(['S01-featurelist-p1', 'S02-search-p1']);
      expect(await site.categories(), isEmpty);
      expect((await site.recommended()).items, isNotEmpty);
      expect((await site.search('andre')).items, hasLength(20));
    });

    test('links: short ids, locale pages, share pages', () async {
      final video = _video();
      final site = _site(['S05-query-live']);
      expect(await site.resolve('209683072'), RoomRef('liveme', '209683072'));
      expect(
        await site.resolve('https://www.liveme.com/us/livehot/streaming/209683072?x=1'),
        RoomRef('liveme', '209683072'),
      );
      expect(await site.resolve('看 ${video['shareurl']}'), RoomRef('liveme', video['ushortid'] as String));
      expect(await site.resolve('https://www.liveme.com/livehot'), isNull);
      expect(await site.resolve('https://live.bilibili.com/6'), isNull);
    });
  });
}
