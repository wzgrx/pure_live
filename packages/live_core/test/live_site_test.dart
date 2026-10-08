import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _hd = LivePlayQuality(quality: '高清', id: 250);
const _blue = LivePlayQuality(quality: '蓝光', id: 400);
final LiveRoom _room = LiveRoom(platform: 'fixture', roomId: '1');

/// A site with only the base calls.
final class _PlainSite extends LiveSite {
  @override
  String get id => 'fixture';

  @override
  String get name => 'Fixture';

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async => [
    ' https://a.test/1.flv ',
    '',
    'https://a.test/1.flv',
    'https://b.test/1.flv',
  ];

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async => const [_hd];

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async => [_room];
}

/// A site with every optional capability.
final class _CapableSite extends _PlainSite
    implements LivePlayUrlResolver, LivePlayRecoveryResolver, LiveCancellableSearch, LiveQualityDiscovery {
  final List<String> calls = [];
  Completer<void>? discoveryGate;
  CancelToken? seenCancel;

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    calls.add('resolve');
    return LivePlayUrlResolution(urls: const ['https://c.test/1.flv', 'https://c.test/1.flv'], appliedQualityData: 250);
  }

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    calls.add('recover');
    return LivePlayUrlResolution(urls: const ['https://fresh.test/1.flv']);
  }

  @override
  Future<List<LiveRoom>> searchRoomsCancellable(
    String keyword, {
    int page = 1,
    int pageSize = 30,
    CancelToken? cancel,
  }) async {
    seenCancel = cancel;
    calls.add('search');
    return [_room];
  }

  @override
  Future<List<LivePlayQuality>> discoverPlayQualitiesRaw({required LiveRoom detail, CancelToken? cancel}) async {
    seenCancel = cancel;
    calls.add('discover');
    await discoveryGate?.future;
    return const [_hd, _blue];
  }
}

final class _Recipe implements LiveInputRecipe {
  @override
  String get identity => 'recipe';
}

void main() {
  group('play URLs', () {
    test('a plain site: URLs are cleaned and the requested quality is assumed applied', () async {
      final resolution = await _PlainSite().resolvePlayUrls(detail: _room, quality: _hd);
      expect(resolution.urls, ['https://a.test/1.flv', 'https://b.test/1.flv']);
      expect(resolution.appliedQualityData, 250);
      expect(resolution.lineCount, 2);
    });

    test('a resolver confirms the applied quality; recovery asks for fresh URLs', () async {
      final site = _CapableSite();
      final resolution = await site.resolvePlayUrls(detail: _room, quality: _blue);
      expect(resolution.urls, ['https://c.test/1.flv']);
      final shown = resolveAppliedPlayQuality(qualities: const [_hd, _blue], requested: _blue, resolution: resolution);
      expect(shown.quality, '高清', reason: 'the platform applied 250');
      expect(shown.isPlaybackUnconfirmed, isFalse);
      expect((await site.resolvePlayUrlsForRecovery(detail: _room, quality: _hd)).urls, ['https://fresh.test/1.flv']);
      expect(site.calls, ['resolve', 'recover']);
      expect((await _PlainSite().resolvePlayUrlsForRecovery(detail: _room, quality: _hd)).urls, hasLength(2));
    });

    test('an unconfirmed or unknown applied id marks the requested quality unconfirmed', () {
      final unknown = resolveAppliedPlayQuality(
        qualities: const [_hd],
        requested: _hd,
        resolution: LivePlayUrlResolution(urls: const ['u'], appliedQualityData: 9999),
      );
      expect(unknown.quality, '高清');
      expect(unknown.isPlaybackUnconfirmed, isTrue);
      final missing = resolveAppliedPlayQuality(
        qualities: const [_hd],
        requested: _hd,
        resolution: LivePlayUrlResolution(urls: const ['u'], qualityUnconfirmed: true),
      );
      expect(missing.isPlaybackUnconfirmed, isTrue);
      expect(_hd.withPlaybackUnconfirmed(unconfirmed: false), same(_hd));
    });

    test('G01.3: the codec hint is not part of the identity and survives marking unconfirmed', () {
      const hevc = LivePlayQuality(quality: '原画', id: 'origin', codec: 'hevc');
      const plain = LivePlayQuality(quality: '原画', id: 'origin');
      expect(hevc.selectionId, plain.selectionId);
      expect(const LivePlayQuality(quality: '原画', codec: 'hevc').selectionId, '原画');
      expect(plain.codec, isNull);
      final unconfirmed = hevc.withPlaybackUnconfirmed(unconfirmed: true);
      expect((unconfirmed.codec, unconfirmed.isPlaybackUnconfirmed, unconfirmed.id), ('hevc', true, 'origin'));
    });

    group('C01.4: the served quality', () {
      const original = LivePlayQuality(quality: '原画', id: 10000);
      const hd = LivePlayQuality(quality: '超清', id: 250);

      test('a confirmed id in the list is that option', () {
        final served = resolveServedPlayQuality(
          platform: 'bilibili',
          qualities: const [original, hd],
          requested: original,
          resolution: LivePlayUrlResolution(urls: const ['u'], appliedQualityData: 250),
        );
        expect(served, same(hd));
      });

      test("a confirmed id outside the list is named by the platform's codes and is confirmed", () {
        final served = resolveServedPlayQuality(
          platform: 'bilibili',
          qualities: const [original],
          requested: original,
          resolution: LivePlayUrlResolution(urls: const ['u'], appliedQualityData: 250),
        );
        expect((served.quality, served.id, served.data, served.isPlaybackUnconfirmed), ('超清', 250, 250, false));
        expect(served.selectionId, 250);
      });

      test('a quality the platform did not confirm stays the request, unconfirmed', () {
        final missing = resolveServedPlayQuality(
          platform: 'bilibili',
          qualities: const [original],
          requested: original,
          resolution: LivePlayUrlResolution(urls: const ['u'], qualityUnconfirmed: true),
        );
        expect((missing.quality, missing.isPlaybackUnconfirmed), ('原画', true));
        final odd = resolveServedPlayQuality(
          platform: 'bilibili',
          qualities: const [original],
          requested: original,
          resolution: LivePlayUrlResolution(urls: const ['u'], appliedQualityData: 250, qualityUnconfirmed: true),
        );
        expect((odd.quality, odd.isPlaybackUnconfirmed), ('原画', true));
        final blank = resolveServedPlayQuality(
          platform: 'bilibili',
          qualities: const [original],
          requested: original,
          resolution: LivePlayUrlResolution(urls: const ['u'], appliedQualityData: ' '),
        );
        expect((blank.quality, blank.isPlaybackUnconfirmed), ('原画', true));
      });

      test('a quality the platform switched to and named is that quality (11-1)', () {
        const switched = LivePlayQuality(quality: '1080p 60fps', id: 'new');
        final served = resolveServedPlayQuality(
          platform: 'youtube',
          qualities: const [original],
          requested: original,
          resolution: LivePlayUrlResolution(urls: const ['u'], appliedQualityData: 'new', appliedQuality: switched),
        );
        expect(served, same(switched));
      });
    });

    test('11-1: a quality the platform switched to and named is shown confirmed; normalizing keeps it', () {
      const switched = LivePlayQuality(quality: '1080p 60fps', id: 'new');
      final resolution = LivePlayUrlResolution(
        urls: const ['u', 'u'],
        appliedQualityData: 'new',
        appliedQuality: switched,
        start: const Duration(seconds: 754),
      );
      final shown = resolveAppliedPlayQuality(qualities: const [_hd], requested: _hd, resolution: resolution);
      expect((shown.quality, shown.isPlaybackUnconfirmed), ('1080p 60fps', false));
      final normalized = resolution.normalized();
      expect(normalized.urls, ['u']);
      expect((normalized.appliedQuality, normalized.start), (switched, const Duration(seconds: 754)));
      // A named quality whose id is not the confirmed one is not trusted.
      final odd = resolveAppliedPlayQuality(
        qualities: const [_hd],
        requested: _hd,
        resolution: LivePlayUrlResolution(urls: const ['u'], appliedQualityData: 'other', appliedQuality: switched),
      );
      expect((odd.quality, odd.isPlaybackUnconfirmed), ('高清', true));
      // A known id still wins over the named quality.
      final known = resolveAppliedPlayQuality(
        qualities: const [_hd],
        requested: _hd,
        resolution: LivePlayUrlResolution(
          urls: const ['u'],
          appliedQualityData: _hd.selectionId,
          appliedQuality: switched,
        ),
      );
      expect(known, same(_hd));
    });

    test('source policies must belong to exactly the resolved URLs', () {
      const url = 'https://cdn.test/live/a/master.m3u8?token=t';
      final policy = HlsSourceQueryPolicy.fromSource(Uri.parse(url));
      final resolution = LivePlayUrlResolution.withSourcePolicies(
        urls: const [url, url],
        sourceQueryPolicies: {url: policy},
      );
      expect(resolution.urls, [url]);
      expect(resolution.sourceQueryPolicies.keys, [url]);
      expect(
        () => LivePlayUrlResolution.withSourcePolicies(
          urls: const ['https://other.test/x.m3u8'],
          sourceQueryPolicies: {url: policy},
        ),
        throwsFormatException,
      );
    });

    test('an owned input counts as one line and has no URLs', () {
      final resolution = LivePlayUrlResolution.owned(input: _Recipe());
      expect(resolution.urls, isEmpty);
      expect(resolution.lineCount, 1);
      expect(resolution.hasSources, isTrue);
      expect(resolution.normalized(), same(resolution));
    });
  });

  group('cancellation', () {
    test('search forwards the token where the adapter can, and a cancelled token fails first', () async {
      final site = _CapableSite();
      final token = CancelToken();
      expect(await site.searchRoomsWithCancellation('x', cancel: token), [_room]);
      expect(site.seenCancel, same(token));
      expect(await _PlainSite().searchRoomsWithCancellation('x'), [_room]);
      token.cancel();
      await expectLater(
        site.searchRoomsWithCancellation('x', cancel: token),
        throwsA(isA<TransportFailure>().having((f) => f.reason, 'reason', TransportReason.cancelled)),
      );
    });

    test('a discovery scope cancels running discoveries and close waits for their cleanup', () async {
      final site = _CapableSite()..discoveryGate = Completer<void>();
      final scope = LiveQualityDiscoveryScope();
      final running = scope.discover(site, _room);
      await Future<void>.delayed(Duration.zero);
      var closed = false;
      final closing = scope.close().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse, reason: 'the discovery still holds its session');
      site.discoveryGate!.complete();
      await expectLater(running, throwsA(isA<TransportFailure>()), reason: 'a cancelled result is not passed on');
      await closing;
      expect(closed, isTrue);
      expect(() => scope.checkActive('fixture'), throwsA(isA<TransportFailure>()));
    });

    test('a plain site discovers through its qualities', () async {
      expect(await LiveQualityDiscoveryScope().discover(_PlainSite(), _room), [_hd]);
    });
  });

  test('base calls have harmless defaults', () async {
    final site = _BareSite();
    expect(await site.getCategories(1, 20), isEmpty);
    expect(await site.searchAnchors('x'), isEmpty);
    expect(await site.getCategoryRooms(const LiveArea()), isEmpty);
    expect(await site.getRecommendRooms(), isEmpty);
    expect(await site.getLiveStatus(roomId: '1'), isFalse);
    expect(await site.getSuperChatMessage(roomId: '1'), isEmpty);
    final danmaku = site.getDanmaku()..onMessage = (_) {};
    expect(danmaku, isA<EmptyDanmaku>());
    expect(danmaku.heartbeatTime, 60000);
    await danmaku.stop();
    expect(danmaku.onMessage, isNull, reason: 'stop drops the callbacks');
    expect(danmaku.isConnected, isFalse);
  });

  test('super chats: only Bilibili, Huya and Douyu have them (3.x)', () {
    expect(_BareSite().hasSuperChats, isFalse);
    expect(superChatPlatforms, {SiteIds.bilibili, SiteIds.huya, SiteIds.douyu});
    for (final id in [SiteIds.bilibili, SiteIds.huya, SiteIds.douyu]) {
      expect(_IdSite(id).hasSuperChats, isTrue, reason: id);
    }
    for (final id in [SiteIds.douyin, SiteIds.kuaishou, SiteIds.cc, SiteIds.twitch, SiteIds.iptv]) {
      expect(_IdSite(id).hasSuperChats, isFalse, reason: id);
    }
  });

  test('a directory page is unmodifiable', () {
    final page = LiveDirectoryPage(rooms: [_room], page: 1, hasMore: true, nextCursor: 'c2');
    expect(() => page.rooms.add(_room), throwsUnsupportedError);
  });
}

final class _BareSite extends LiveSite {
  @override
  String get id => 'bare';

  @override
  String get name => 'Bare';
}

/// A site that is only an id.
final class _IdSite extends LiveSite {
  new(this.id);

  @override
  final String id;

  @override
  String get name => id;
}
