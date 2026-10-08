import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/platforms.dart';
import 'package:pure_live/platform/native_http.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every platform of 3.x and IPTV is registered, adapters are kept', () async {
    final services = await testServices();
    addTearDown(services.close);
    // No Android system TLS here: Kick waits for it (UPGRADES X-1).
    expect(services.sites.ids, [
      for (final id in SiteIds.supported)
        if (id != SiteIds.kick) id,
    ]);
    expect(identical(services.sites.of('BiliBili '), services.sites.of(SiteIds.bilibili)), isTrue);
  });

  test('E06.3: YY lists the FLV qualities first, mobile HLS standing in (UPGRADES 6-1)', () async {
    final services = await testServices();
    addTearDown(services.close);
    expect((services.sites.of(SiteIds.yy) as YySite).flvFirst, isTrue);
  });

  test('Kick is registered with its API transport, after CHZZK', () async {
    final services = await testServices();
    addTearDown(services.close);
    final api = NoNetworkHttp();
    final sites = buildSiteRegistry(
      PlatformDeps(
        http: services.http,
        proxy: services.proxy,
        cookies: services.cookies,
        store: services.store,
        kickApi: api,
      ),
    );
    expect(sites.ids, SiteIds.supported.where((id) => id != SiteIds.iptv));
    final kick = sites.of(SiteIds.kick) as KickSite;
    expect(identical(kick.apiHttp, api), isTrue);
    expect(identical(kick.http, services.http), isTrue);
    expect(services.danmaku.connectionFor(SiteIds.kick), isA<KickDanmakuConnection>());
  });

  test('danmaku: every platform with a connection, none for the blocked ones', () async {
    final services = await testServices();
    addTearDown(services.close);
    final danmaku = services.danmaku;
    const without = {
      SiteIds.cc,
      SiteIds.inke,
      SiteIds.xiaohongshu,
      SiteIds.weibo,
      SiteIds.liveMe,
      SiteIds.tiktok,
      SiteIds.iptv,
    };
    expect(danmaku.platforms, [
      for (final id in SiteIds.supported)
        if (!without.contains(id)) id,
    ]);
    expect(danmaku.connectionFor(SiteIds.tiktok), isA<EmptyDanmakuConnection>());
    expect(danmaku.connectionFor(SiteIds.soop), isA<SoopDanmakuConnection>());
    expect(danmaku.connectionFor(SiteIds.niconico), isA<NiconicoDanmakuConnection>());
  });

  test('the proxy follows the app proxy settings at every request', () async {
    final services = await testServices();
    addTearDown(services.close);
    final settings = services.store.settings;
    final url = Uri.parse('https://example.com');
    expect(services.proxy.routeFor('twitch', url), const DirectRoute());
    await settings.set(Settings.appProxyHost, '127.0.0.1');
    await settings.set(Settings.appProxyPort, 7890);
    expect(services.proxy.routeFor('twitch', url), const DirectRoute(), reason: 'switch still off');
    await settings.set(Settings.enableAppProxy, true);
    expect(services.proxy.routeFor('twitch', url), const HttpProxyRoute('127.0.0.1', 7890));
  });

  test("the live room's streams take the playback proxy, never the app proxy (3.x, F.0a)", () async {
    final services = await testServices();
    addTearDown(services.close);
    final settings = services.store.settings;
    final streams = services.mediaOpener.proxy;
    final url = Uri.parse('https://cdn.example.com/live.flv');
    expect(streams, isA<PlaybackProxyPolicy>());
    await settings.setAll({Settings.enableAppProxy: true, Settings.appProxyHost: '127.0.0.1'});
    expect(streams.routeFor('twitch', url), const DirectRoute(), reason: 'playback proxy off: direct (3.x)');
    expect(engineProxyUrl(streams, 'twitch', url), '');
    await settings.setAll({Settings.enableProxy: true, Settings.proxyHost: '10.0.0.2', Settings.proxyPort: 1080});
    expect(streams.routeFor('twitch', url), const HttpProxyRoute('10.0.0.2', 1080));
    expect(engineProxyUrl(streams, 'twitch', url), 'http://10.0.0.2:1080');
    expect(engineProxyUrl(streams, 'twitch', url, private: true), '', reason: 'loopback inputs are never proxied');
    await settings.set(Settings.enableAppProxy, false);
    expect(streams.routeFor('douyu', url), const HttpProxyRoute('10.0.0.2', 1080));
    expect(services.proxy.routeFor('douyu', url), const DirectRoute(), reason: 'the app proxy stays its own');
  });

  test('cookies come from the sealed store and report changes', () async {
    final services = await testServices();
    addTearDown(services.close);
    final changes = services.cookies.changes.first;
    await services.store.secrets.setCookie('douyu', 'acf_uid=1');
    expect(await changes, 'douyu');
    expect(services.cookies.cookieFor('douyu'), 'acf_uid=1');
  });

  test("Douyu's login: LTP0, DID and the save time beside the cookie", () async {
    final services = await testServices();
    addTearDown(services.close);
    final login = StoreDouyuLogin(services.store);
    expect(login.savedAt, isNull);
    final at = DateTime.utc(2026, 10, 1, 12);
    await login.saveRenewed('dy_auth=x', at);
    expect(services.cookies.cookieFor('douyu'), 'dy_auth=x');
    expect(login.savedAt, at);
    await services.store.secrets.write(SecretRefs.douyuLtp0, 'ltp0');
    expect(login.longTermKey, 'ltp0');
  });

  test('the identity move leaves other platforms alone', () async {
    final services = await testServices();
    addTearDown(services.close);
    final resolve = identityResolver(services.sites);
    expect(await resolve(LiveRoom(platform: 'huya', roomId: '1')), isNull);
  });

  group('Android native HTTP', () {
    const channel = MethodChannel('test/native_http');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('only allowed https hosts go through the channel', () async {
      final http = AndroidNativeHttp(proxy: const FixedProxyPolicy(), channel: channel);
      expect(AndroidNativeHttp.allows(Uri.parse('https://gql.twitch.tv/gql')), isTrue);
      expect(AndroidNativeHttp.allows(Uri.parse('http://gql.twitch.tv/gql')), isFalse);
      expect(AndroidNativeHttp.allows(Uri.parse('https://kick.com/api/v2/channels/xqc')), isTrue);
      expect(AndroidNativeHttp.allows(Uri.parse('https://web.kick.com/api/v1/livestreams')), isFalse);
      await expectLater(
        http.send(LiveRequest(site: 'kick', url: Uri.parse('https://example.com/api'))),
        throwsA(isA<TransportFailure>()),
      );
    });

    test('sends method, headers, body and proxy, and reads the answer', () async {
      MethodCall? seen;
      messenger.setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return {
          'status': 200,
          'headers': {
            'Content-Type': ['application/json'],
          },
          'body': Uint8List.fromList('[{"data":{}}]'.codeUnits),
        };
      });
      final http = AndroidNativeHttp(
        proxy: const FixedProxyPolicy(global: HttpProxyRoute('10.0.0.2', 7897)),
        channel: channel,
      );
      final response = await http.send(
        LiveRequest(
          site: 'twitch',
          url: Uri.parse('https://gql.twitch.tv/gql'),
          method: 'POST',
          headers: const {'client-id': 'x'},
          body: '[]'.codeUnits,
        ),
      );
      expect(response.status, 200);
      expect(response.text, '[{"data":{}}]');
      expect(response.headers['content-type'], ['application/json']);
      final args = seen!.arguments as Map<Object?, Object?>;
      expect(args['method'], 'POST');
      expect(args['proxyHost'], '10.0.0.2');
      expect(args['proxyPort'], 7897);
      expect(args['headers'], {'client-id': 'x'});
    });

    test('a platform error is a transport failure', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'failed'));
      final http = AndroidNativeHttp(proxy: const FixedProxyPolicy(), channel: channel);
      await expectLater(
        http.send(LiveRequest(site: 'twitch', url: Uri.parse('https://gql.twitch.tv/gql'))),
        throwsA(isA<TransportFailure>().having((error) => error.reason, 'reason', TransportReason.connect)),
      );
    });
  });

  group('the plain danmaku handshake (UPGRADES B-2, Q03.1)', () {
    test('off by default; on, a connector for the dart:io sockets', () {
      expect(danmakuHandshake(), isNull);
      expect(danmakuHandshake(plain: true), isNotNull);
    });

    test('SOOP, YY and FC2 keep their own handshake; the other 20 sockets take the generic one', () {
      expect(genericDanmakuHandshakeSites, hasLength(20));
      expect(
        genericDanmakuHandshakeSites,
        isNot(anyOf(contains(SiteIds.soop), contains(SiteIds.yy), contains(SiteIds.fc2Live))),
      );
      // No socket of ours to shake hands on.
      for (final site in [
        SiteIds.kuaishou,
        SiteIds.niconico,
        SiteIds.youtube,
        SiteIds.steamBroadcast,
        SiteIds.baiduLive,
      ]) {
        expect(genericDanmakuHandshakeSites, isNot(contains(site)), reason: site);
      }
    });
  });
}
