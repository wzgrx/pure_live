import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

String _directive({required bool enabled, required String host, required int port}) =>
    proxyRouteFrom(enabled: enabled, host: host, port: port).directive;

void main() {
  group('proxy settings', () {
    test('normalizes punctuation typed by Chinese input methods', () {
      expect(normalizeProxyHost(' 127。0．0。1 '), '127.0.0.1');
      expect(normalizeProxyHost('［::1］'), '[::1]');
      expect(normalizeProxyHost('127.0.0.1：7897'), '127.0.0.1:7897');
    });

    test('accepts only complete TCP port values', () {
      expect(parseProxyPortInput('1'), 1);
      expect(parseProxyPortInput(' 7897 '), 7897);
      expect(parseProxyPortInput('65535'), 65535);
      expect(parseProxyPortInput(''), isNull);
      expect(parseProxyPortInput('0'), isNull);
      expect(parseProxyPortInput('65536'), isNull);
      expect(parseProxyPortInput('12.5'), isNull);
    });

    test('repairs stored TCP ports with the default', () {
      expect(normalizeStoredProxyPort(1), 1);
      expect(normalizeStoredProxyPort(65535), 65535);
      expect(normalizeStoredProxyPort(0), defaultProxyPort);
      expect(normalizeStoredProxyPort(65536), defaultProxyPort);
      expect(defaultProxyPort, 7897);
    });

    test('builds direct and proxy routes without half-edited values', () {
      expect(_directive(enabled: false, host: '127.0.0.1', port: 7897), 'DIRECT');
      expect(_directive(enabled: true, host: '', port: 7897), 'DIRECT');
      expect(_directive(enabled: true, host: 'localhost', port: 0), 'DIRECT');
      expect(_directive(enabled: true, host: 'localhost', port: 7897), 'PROXY localhost:7897');
      expect(_directive(enabled: true, host: '127。0。0。1', port: 7897), 'PROXY 127.0.0.1:7897');
      expect(_directive(enabled: true, host: '::1', port: 7897), 'PROXY [::1]:7897');
      expect(_directive(enabled: true, host: '[::1]', port: 7897), 'PROXY [::1]:7897');
      expect(proxyRouteFrom(enabled: true, host: '[::1]', port: 7897), const HttpProxyRoute('::1', 7897));
    });

    test('rejects proxy directive injection', () {
      expect(_directive(enabled: true, host: 'localhost; DIRECT', port: 7897), 'DIRECT');
      expect(_directive(enabled: true, host: 'localhost\nDIRECT', port: 7897), 'DIRECT');
      expect(_directive(enabled: true, host: 'localhost\rDIRECT', port: 7897), 'DIRECT');
    });

    test('a fixed policy routes per platform', () {
      const route = HttpProxyRoute('127.0.0.1', 7897);
      const policy = FixedProxyPolicy(perSite: {'twitch': route});
      expect(policy.routeFor('twitch', Uri.parse('https://gql.twitch.tv')), route);
      expect(policy.routeFor('douyu', Uri.parse('https://www.douyu.com')), const DirectRoute());
    });
  });

  group('local network proxies (Android 17 ACCESS_LOCAL_NETWORK)', () {
    test('LAN hosts need local-network access', () {
      for (final host in [
        '192.168.1.238',
        '10.0.0.2',
        '172.16.0.1',
        '172.31.255.254',
        '169.254.10.1',
        'router.lan',
        'nas.local',
        'box.home.arpa',
        '[fd00::1]',
        'fe80::1',
        '192。168。1。2',
      ]) {
        expect(isLocalNetworkProxyHost(host), isTrue, reason: host);
      }
    });

    test('loopback, public and malformed hosts do not', () {
      for (final host in [
        '',
        '127.0.0.1',
        'localhost',
        '::1',
        '172.32.0.1',
        '172.15.0.1',
        '8.8.8.8',
        'proxy.example.com',
        '192.168.1',
        '999.168.1.1',
        // 3.x checked only the first two octets.
        '192.168.1.999',
      ]) {
        expect(isLocalNetworkProxyHost(host), isFalse, reason: host);
      }
    });
  });
}
