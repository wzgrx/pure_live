import 'dart:math';

import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

void main() {
  group('HttpHeaderPolicy', () {
    test('canonical names resolve playlist aliases and reject invalid names', () {
      expect(HttpHeaderPolicy.canonicalName(' HTTP-User-Agent '), 'user-agent');
      expect(HttpHeaderPolicy.canonicalName('http-referrer'), 'referer');
      expect(HttpHeaderPolicy.canonicalName('Referrer'), 'referer');
      expect(HttpHeaderPolicy.canonicalName('!Cookies'), 'cookie');
      expect(HttpHeaderPolicy.canonicalName('X-Forwarded-For'), 'x-forwarded-for');
      expect(HttpHeaderPolicy.canonicalName('bad name'), isNull);
      expect(HttpHeaderPolicy.canonicalName(''), isNull);
    });

    test('normalize keeps string entries, cleans control characters and sorts', () {
      final headers = HttpHeaderPolicy.normalize({
        'User-Agent': 'VLC\r\n/3',
        'Referer': ' https://x.test/ ',
        'empty': '  ',
        'bad name': 'x',
        1: 'number key',
        'n': 1,
      });
      expect(headers, {'referer': 'https://x.test/', 'user-agent': 'VLC /3'});
      expect(headers.keys, ['referer', 'user-agent']);
      expect(() => headers['x'] = 'y', throwsUnsupportedError);
      expect(HttpHeaderPolicy.normalize(null), isEmpty);
    });

    test('encode and decode round-trip; unreadable input gives nothing', () {
      final encoded = HttpHeaderPolicy.encode({'Referer': 'https://x.test/', 'User-Agent': 'ua'});
      expect(encoded, '{"referer":"https://x.test/","user-agent":"ua"}');
      expect(HttpHeaderPolicy.decode(encoded), {'referer': 'https://x.test/', 'user-agent': 'ua'});
      expect(HttpHeaderPolicy.encode({'bad name': 'x'}), isNull);
      expect(HttpHeaderPolicy.decode('not json'), isEmpty);
      expect(HttpHeaderPolicy.decode('[1]'), isEmpty);
      expect(HttpHeaderPolicy.decode(null), isEmpty);
    });
  });

  group('BrowserUserAgent', () {
    List<BrowserUserAgent> sample() => [for (var seed = 0; seed < 200; seed++) BrowserUserAgent.random(Random(seed))];

    test('every browser and platform appears, written the way current browsers send it', () {
      final all = sample();
      expect(
        {for (final ua in all) '${ua.browser} ${ua.platform}'},
        {'Chrome macOS', 'Chrome Windows', 'Chrome Linux', 'Edge Windows', 'Safari macOS'},
      );
      for (final ua in all) {
        expect(ua.userAgent, isNot(contains('-')), reason: '3.x wrote "Mac OS X ------"');
        if (ua.platform == 'macOS') expect(ua.userAgent, contains('Intel Mac OS X 10_15_7'));
        if (ua.browser != 'Safari') {
          expect(ua.userAgent, contains('Chrome/${ua.majorVersion}.0.0.0'));
          expect(
            BrowserUserAgent.chromeMajors.followedBy(BrowserUserAgent.edgeMajors),
            contains(int.parse(ua.version)),
          );
        }
        if (ua.browser == 'Edge') expect(ua.userAgent, endsWith('Edg/${ua.version}.0.0.0'));
        if (ua.browser == 'Safari') {
          expect(ua.userAgent, contains('Version/${ua.version} Safari/605.1.15'));
          expect(BrowserUserAgent.safariVersions, contains(ua.version));
        }
      }
    });

    test('client hints match the browser: none for Safari, quoted platform for Chromium', () {
      for (final ua in sample()) {
        final hints = ua.clientHints;
        if (ua.browser == 'Safari') {
          expect(hints, isEmpty);
          continue;
        }
        final brand = ua.browser == 'Edge' ? 'Microsoft Edge' : 'Google Chrome';
        expect(hints['sec-ch-ua'], startsWith('"$brand";v="${ua.majorVersion}", "Chromium";v="${ua.majorVersion}"'));
        expect(hints['sec-ch-ua-mobile'], '?0');
        expect(hints['sec-ch-ua-platform'], '"${ua.platform}"');
        expect(ua.headers['user-agent'], ua.userAgent);
      }
    });
  });
}
