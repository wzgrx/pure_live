import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

final _now = DateTime.utc(2026, 10);

LivePlayLine _flv(String url, {String? lineId, String? codec, bool cuts = false}) => LivePlayLine(
  url,
  format: StreamFormat.flv,
  lineId: lineId,
  codec: codec,
  lease: cuts ? PlayLease(refreshAt: _now.add(const Duration(minutes: 4)), cutsConnection: true) : null,
);

LivePlayLine _hls(String url, {bool cuts = false}) => LivePlayLine(
  url,
  format: StreamFormat.hls,
  lease: cuts ? PlayLease(refreshAt: _now.add(const Duration(minutes: 4)), cutsConnection: true) : null,
);

void main() {
  group('LineFallback', () {
    final a = _flv('https://a.test/1.flv?sig=1', lineId: 'a');
    final b = _flv('https://b.test/1.flv?sig=1', lineId: 'b');
    final c = _flv('https://c.test/1.flv?sig=1', lineId: 'c');

    test('walks the lines after the current one, skipping failed ones, wrapping around', () {
      final fallback = LineFallback()
        ..select(a)
        ..markFailed(a);
      expect(fallback.next([a, b, c]), b);
      fallback.markFailed(b);
      expect(fallback.next([a, b, c]), c);
      fallback.markFailed(c);
      expect(fallback.hasAvailable([a, b, c]), isFalse);
      expect(fallback.next([a, b, c]), isNull);
    });

    test('a renewed URL of a failed line is still failed (3.x keyed by URL)', () {
      final fallback = LineFallback()..markFailed(a);
      final renewedA = _flv('https://a.test/1.flv?sig=2', lineId: 'a');
      expect(fallback.hasAvailable([renewedA]), isFalse);
      expect(fallback.next([renewedA, b]), b);
    });

    test('a shorter list after a refresh does not run past its end (3.x RangeError)', () {
      final fallback = LineFallback()..select(c);
      expect(fallback.next([a]), a);
    });
  });

  // Ported from 3.x's engine_fallback_manager_test.dart (engines → decoders).
  group('DecoderFallback', () {
    const codec = PlayerException(message: 'decoder failed', type: PlayerErrorType.codec);

    test('the first confirmed terminal decoder failure selects the next mode', () {
      expect(DecoderFallback().fallback(DecoderMode.hardware, codec), DecoderMode.software);
    });

    test('an explicit retry budget keeps the same mode first', () {
      final fallback = DecoderFallback(maxRetryCount: 2);
      expect(fallback.fallback(DecoderMode.hardware, codec), DecoderMode.hardware);
      expect(fallback.fallback(DecoderMode.hardware, codec), DecoderMode.software);
    });

    test('network failures do not fall back; exhausting every mode rethrows', () {
      final fallback = DecoderFallback();
      expect(fallback.shouldFallback(const PlayerException(message: 'x', type: PlayerErrorType.network)), isFalse);
      expect(fallback.fallback(DecoderMode.hardware, codec), DecoderMode.software);
      expect(() => fallback.fallback(DecoderMode.software, codec), throwsA(same(codec)));
    });
  });

  group('PlaybackPlan', () {
    test('"prefer H.264" moves HEVC lines behind, keeping the platform order otherwise', () {
      final resolution = LivePlayUrlResolution.lines([
        _flv('https://x.test/h265.flv', codec: 'hevc'),
        _flv('https://x.test/a.flv', codec: 'avc'),
        _hls('https://x.test/a.m3u8'),
      ]);
      expect(PlaybackPlan.of(resolution).lines.map((line) => line.url), [
        'https://x.test/a.flv',
        'https://x.test/a.m3u8',
        'https://x.test/h265.flv',
      ]);
      expect(PlaybackPlan.of(resolution, preferH264: false).lines.first.codec, 'hevc');
    });

    test('a recipe resolution plans one recipe source without a URL', () {
      final plan = PlaybackPlan.of(LivePlayUrlResolution.owned(input: BigoInputRecipe('12345678')));
      expect(plan.sources.single, isA<RecipeSource>());
      expect(plan.sources.single.url, isNull);
      expect(plan.sources.single.identity, 'bigo:12345678:live');
    });
  });

  group('MediaRoute.of', () {
    const engine = EngineProfile();
    test('FLV with a lease that cuts the connection is spliced only when it can be renewed', () {
      final douyu = _flv('https://hw.test/live.flv?expire=300', cuts: true);
      expect(MediaRoute.of(douyu, engine: engine, canRenew: true), MediaRoute.flvSplice);
      expect(MediaRoute.of(douyu, engine: engine, canRenew: false), MediaRoute.direct);
    });

    test('codec-12 HEVC FLV is rewritten only for an engine that cannot read it', () {
      final kuaishou = _flv('https://ks.test/live.flv', codec: 'hevc');
      final seventeen = _flv('https://pull.17app.co/live.flv');
      expect(MediaRoute.of(kuaishou, engine: engine, canRenew: false), MediaRoute.direct);
      const old = EngineProfile(rewriteLegacyHevcFlv: true);
      expect(MediaRoute.of(kuaishou, engine: old, canRenew: false), MediaRoute.flvRewrite);
      expect(MediaRoute.of(seventeen, engine: old, canRenew: false), MediaRoute.flvRewrite);
      expect(MediaRoute.of(_flv('https://x.test/live.flv'), engine: old, canRenew: false), MediaRoute.direct);
    });

    test('HLS is relayed for a token policy or a renewed cutting lease, else direct', () {
      final url = Uri.parse('https://cdn.test/hls/index.m3u8?token=abc');
      final policy = HlsSourceQueryPolicy.fromSource(url);
      expect(MediaRoute.of(_hls('$url'), engine: engine, canRenew: false, queryPolicy: policy), MediaRoute.hlsRelay);
      expect(
        MediaRoute.of(_hls('https://c.test/m.m3u8', cuts: true), engine: engine, canRenew: true),
        MediaRoute.hlsRelay,
      );
      expect(MediaRoute.of(_hls('https://tc.test/m.m3u8'), engine: engine, canRenew: true), MediaRoute.direct);
    });

    test('G01.4: HLS with a variant selector is relayed (its master is rewritten), FLV is not', () {
      final selector = _Selector();
      expect(
        MediaRoute.of(
          _hls('https://steam.test/master.m3u8'),
          engine: engine,
          canRenew: false,
          variantSelector: selector,
        ),
        MediaRoute.hlsRelay,
      );
      expect(MediaRoute.of(_hls('https://steam.test/master.m3u8'), engine: engine, canRenew: false), MediaRoute.direct);
      expect(
        MediaRoute.of(_flv('https://x.test/live.flv'), engine: engine, canRenew: false, variantSelector: selector),
        MediaRoute.direct,
      );
    });
  });

  group('PlaybackPlan variant selectors (G01.4)', () {
    test("a line's selector comes from the resolution; other lines and recipes have none", () {
      final selector = _Selector();
      const master = 'https://steam.test/master.m3u8';
      final plan = PlaybackPlan.of(
        LivePlayUrlResolution.lines(
          const [
            LivePlayLine(master, format: StreamFormat.hls),
            LivePlayLine('https://other.test/live.m3u8', format: StreamFormat.hls),
          ],
          sourceVariantSelectors: {master: selector},
        ),
      );
      expect(plan.variantSelectorFor(plan.sources.first), same(selector));
      expect(plan.variantSelectorFor(plan.sources.last), isNull);
      expect(
        PlaybackPlan.of(LivePlayUrlResolution.owned(input: BigoInputRecipe('12345678')))
            .variantSelectorFor(RecipeSource(BigoInputRecipe('12345678'))),
        isNull,
      );
    });
  });

  group('MediaOpener', () {
    test('a direct line goes to the engine with its headers and the site proxy', () async {
      final opener = MediaOpener(proxy: const FixedProxyPolicy(perSite: {'twitch': HttpProxyRoute('127.0.0.1', 7897)}));
      const line = LivePlayLine('https://cdn.test/live.m3u8', headers: {'referer': 'https://twitch.tv/'});
      final input = await opener.open(const LineSource(line), site: 'twitch');
      expect(input.route, MediaRoute.direct);
      expect(input.uri.toString(), line.url);
      expect(input.headers, line.headers);
      expect(input.proxyUrl, 'http://127.0.0.1:7897');
      expect(input.private, isFalse);
      await opener.close();
    });

    test('engineProxyUrl brackets IPv6 and never proxies a loopback input', () {
      const policy = FixedProxyPolicy(global: HttpProxyRoute('::1', 7897));
      expect(engineProxyUrl(policy, 'douyu', Uri.parse('https://x.test')), 'http://[::1]:7897');
      expect(engineProxyUrl(policy, 'douyu', Uri.parse('https://x.test'), private: true), '');
      expect(engineProxyUrl(const FixedProxyPolicy(), 'douyu', Uri.parse('https://x.test')), '');
    });

    test('a recipe without an opener is unsupported', () async {
      final opener = MediaOpener(relay: () => throw StateError('no relay needed'));
      await expectLater(
        opener.open(RecipeSource(BigoInputRecipe('12345678')), site: 'bigo'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}

/// A variant selector that selects nothing (G01.4).
final class _Selector implements HlsVariantSelector {
  @override
  HlsMasterSelection selectIn(String text, {required Uri source}) => throw const FormatException('unused');
}
