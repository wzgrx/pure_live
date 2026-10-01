import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
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
    expect(services.sites.ids, SiteIds.supported);
    expect(identical(services.sites.of('BiliBili '), services.sites.of(SiteIds.bilibili)), isTrue);
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
      await expectLater(
        http.send(LiveRequest(site: 'kick', url: Uri.parse('https://kick.com/api'))),
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
}
