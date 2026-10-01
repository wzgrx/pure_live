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
