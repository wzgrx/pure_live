import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/proxy.dart';
import 'package:pure_live_app/core/system_proxy.dart';

StreamSet _lines(List<String> urls) {
  const quality = Quality(id: 'o', label: '原画', rank: 1);
  return StreamSet(
    qualities: const [quality],
    selected: quality,
    lines: [
      for (final (index, url) in urls.indexed)
        StreamLine(url: Uri.parse(url), format: StreamFormat.flv, lineId: '$index', requested: quality),
    ],
  );
}

void main() {
  group('F-SET-07: reading the system proxy', () {
    test('Windows ProxyServer: one address or per protocol, https first', () {
      expect(parseWindowsProxy('127.0.0.1:7897'), const SystemProxy('127.0.0.1', 7897));
      expect(
        parseWindowsProxy('http=127.0.0.1:8080;https=127.0.0.1:8443;socks=127.0.0.1:1080'),
        const SystemProxy('127.0.0.1', 8443),
      );
      expect(parseWindowsProxy('http=proxy.lan:3128'), const SystemProxy('proxy.lan', 3128));
      expect(parseWindowsProxy('socks=127.0.0.1:1080'), isNull, reason: 'SOCKS alone is not an HTTP proxy');
      expect(parseWindowsProxy(''), isNull);
      expect(parseWindowsProxy('127.0.0.1:7897', override: 'localhost;<local>;*.lan')!.bypass, [
        'localhost',
        '<local>',
        '*.lan',
      ]);
    });

    test('environment: https_proxy before http_proxy, no_proxy', () {
      expect(
        parseEnvironmentProxy({'http_proxy': 'http://10.0.0.1:3128', 'HTTPS_PROXY': 'http://10.0.0.2:3129'}),
        const SystemProxy('10.0.0.2', 3129),
      );
      final proxy = parseEnvironmentProxy({'http_proxy': '10.0.0.1:3128', 'no_proxy': 'example.com,.lan'})!;
      expect(proxy.bypass, ['example.com', '.lan']);
      expect(parseEnvironmentProxy({}), isNull);
      expect(parseEnvironmentProxy({'http_proxy': 'socks5://10.0.0.1:1080'}), isNull);
    });

    test('bypass rules: loopback, <local>, wildcards and suffixes', () {
      const proxy = SystemProxy('127.0.0.1', 7897, bypass: ['<local>', '*.lan', '.corp', 'example.com', '192.168.*']);
      for (final host in [
        'localhost',
        '127.0.0.1',
        'nas',
        'box.lan',
        'a.corp',
        'corp',
        'example.com',
        'www.example.com',
        '192.168.1.5',
      ]) {
        expect(proxy.bypasses(host), isTrue, reason: host);
      }
      for (final host in ['www.douyu.com', 'example.org', 'lan.com']) {
        expect(proxy.bypasses(host), isFalse, reason: host);
      }
    });
  });

  group('F-SET-07: the proxy in force', () {
    late LiveStore store;
    setUp(() async => store = await LiveStore.inMemory());
    tearDown(() => store.close());

    test('the system proxy is followed while the manual one is off', () async {
      const system = SystemProxy('127.0.0.1', 7897, bypass: ['<local>']);
      final policy = proxyPolicyFrom(store.settings, system: system);
      expect(policy.routeFor('twitch', Uri.parse('https://gql.twitch.tv/')), const HttpProxyRoute('127.0.0.1', 7897));
      expect(policy.routeFor('twitch', Uri.parse('http://nas:5000/')), const DirectRoute());
      expect(proxyUrl(store.settings, system: system), 'http://127.0.0.1:7897');

      await store.settings.set(Settings.followSystemProxy, false);
      expect(
        proxyPolicyFrom(store.settings, system: system).routeFor('twitch', Uri.parse('https://gql.twitch.tv/')),
        const DirectRoute(),
      );
      expect(proxyUrl(store.settings, system: system), isNull);
    });

    test('a manual proxy wins over the system one', () async {
      await store.settings.set(Settings.proxyEnabled, true);
      await store.settings.set(Settings.proxyHost, '10.0.0.9');
      await store.settings.set(Settings.proxyPort, 8888);
      await store.settings.set(Settings.proxyPlatforms, ['twitch']);
      const system = SystemProxy('127.0.0.1', 7897);
      final policy = proxyPolicyFrom(store.settings, system: system);
      expect(policy.routeFor('twitch', Uri.parse('https://gql.twitch.tv/')), const HttpProxyRoute('10.0.0.9', 8888));
      expect(policy.routeFor('douyu', Uri.parse('https://www.douyu.com/')), const DirectRoute());
    });

    test('mpv proxies the noted CDN hosts except bypassed ones', () {
      const system = SystemProxy('127.0.0.1', 7897, bypass: ['*.lan']);
      final hosts = ProxiedHosts(() => system)
        ..note(store.settings, 'twitch', _lines(['https://video.twitch.tv/a.m3u8', 'http://cache.lan/b.flv']));
      expect(hosts.contains(Uri.parse('https://video.twitch.tv/x')), isTrue);
      expect(hosts.contains(Uri.parse('http://cache.lan/x')), isFalse);
    });
  });
}
