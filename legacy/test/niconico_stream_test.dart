import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/niconico/niconico_stream.dart';
import 'package:pure_live/core/site/niconico/niconico_watch.dart';

Map<String, dynamic> fixture() =>
    jsonDecode(File('test/fixtures/niconico/stream.json').readAsStringSync()) as Map<String, dynamic>;
Matcher get schema => throwsA(isA<NiconicoException>().having((e) => e.kind, 'kind', NiconicoFailure.schema));
final origin = Uri.parse('https://livedelivery.dlive.nicovideo.jp');

void main() {
  test('observed six declared choices and thirteen path cookies stay separate', () {
    final grant = NiconicoStream.parse(fixture());
    expect(grant.availableQualities, [
      'abr',
      'super_high',
      '1.5Mbps480p30fps',
      '480kbps288p30fps',
      'audio_high',
      'audio_only',
    ]);
    expect(grant.retainedCookieCount, 13);
    expect(
      grant.cookieHeaderFor(grant.uri),
      'CloudFront-Policy=fixture-1; CloudFront-Signature=fixture-2; CloudFront-Key-Pair-Id=fixture-3',
    );
    expect(grant.cookieHeaderFor(origin.resolve('/hls/segments/fixture-program/video/a.ts')), contains('fixture-4'));
    expect(grant.cookieHeaderFor(origin.resolve('/hls/segments/fixture-program/audio/a.ts')), contains('fixture-7'));
    expect(
      grant.cookieHeaderFor(origin.resolve('/hls/keys/fixture-program/fixture-session/key')),
      startsWith('CloudFront-Policy=fixture-10'),
    );
    expect(
      grant.cookieHeaderFor(origin.resolve('/hls/keys/fixture-program/fixture-session/key')),
      endsWith('session=fixture-0'),
    );
    expect(() => grant.availableQualities.clear(), throwsUnsupportedError);
    grant.close();
  });
  test('credentials stay on exact HTTPS media origin and separator-bounded path', () {
    final grant = NiconicoStream.parse(fixture());
    for (final target in [
      'http://livedelivery.dlive.nicovideo.jp/hls/keys/fixture-program/key',
      'https://livedelivery.dlive.nicovideo.jp:8443/hls/keys/fixture-program/key',
      'https://other.nicovideo.jp/hls/keys/fixture-program/key',
      'https://child.livedelivery.dlive.nicovideo.jp/hls/keys/fixture-program/key',
      'https://livedelivery.dlive.nicovideo.jp/hls/keys/fixture-program-extra/key',
      'https://livedelivery.dlive.nicovideo.jp/HLS/keys/fixture-program/key',
      'https://user@livedelivery.dlive.nicovideo.jp/hls/keys/fixture-program/key',
      'https://livedelivery.dlive.nicovideo.jp/hls/keys/fixture-program/key#fragment',
    ]) {
      expect(grant.cookieHeaderFor(Uri.parse(target)), isNull, reason: target);
    }
    grant.close();
  });
  test('HTTP-date expiry is honored and close revokes previously returned grants', () {
    var now = DateTime.utc(2026, 9, 10);
    final data = fixture();
    data['cookies'][0]['expires'] = HttpDate.format(now.add(const Duration(seconds: 1)));
    final grant = NiconicoStream.parse(data, now: () => now);
    final key = origin.resolve('/hls/keys/fixture-program/key');
    expect(grant.cookieHeaderFor(key), 'session=fixture-0');
    now = now.add(const Duration(seconds: 1));
    expect(grant.cookieHeaderFor(key), isNull);
    grant.close();
    expect(grant.retainedCookieCount, 0);
    expect(grant.isActive, isFalse);
    expect(() => grant.cookieHeaderFor(grant.uri), throwsA(isA<NiconicoException>()));
    expect(grant.toString(), isNot(contains('fixture-')));
  });
  for (final field in [
    'protocol',
    'quality',
    'qualities',
    'duplicate-quality',
    'missing-cookies',
    'cookie-count',
    'cookie-size',
    'aggregate',
    'duplicate-cookie',
  ]) {
    test('reject malformed or over-budget $field atomically', () {
      final data = fixture();
      switch (field) {
        case 'protocol':
          data['protocol'] = 'dash';
        case 'quality':
          data['quality'] = 'unknown';
        case 'qualities':
          data['availableQualities'] = [42];
        case 'duplicate-quality':
          data['availableQualities'] = ['abr', 'abr'];
        case 'missing-cookies':
          data.remove('cookies');
        case 'cookie-count':
          data['cookies'] = List.filled(65, data['cookies'][0]);
        case 'cookie-size':
          data['cookies'][0]['value'] = 'x' * 5000;
        case 'aggregate':
          for (final cookie in data['cookies']) {
            cookie['value'] = 'x' * 2000;
          }
        case 'duplicate-cookie':
          data['cookies'].add(<String, dynamic>{...data['cookies'][0] as Map<String, dynamic>});
      }
      expect(() => NiconicoStream.parse(data), schema);
    });
  }
  for (final spec in [
    ('domain', 'evil.test'),
    ('secure', false),
    ('path', '/'),
    ('path', '/hls/key;inject=x'),
    ('name', 'bad name'),
    ('name', '__Host-domain-not-allowed'),
    ('value', 'v; injected=x'),
    ('value', 'v\r\nHeader: x'),
    ('expires', 'bad-date'),
    ('expires', 42),
  ]) {
    test('reject cookie ${spec.$1}=${spec.$2}', () {
      final data = fixture();
      data['cookies'].last[spec.$1] = spec.$2;
      expect(() => NiconicoStream.parse(data), schema);
    });
  }
  for (final uri in [
    'http://livedelivery.dlive.nicovideo.jp/hls/playlists/a/master.m3u8',
    'https://evil.test/hls/playlists/a/master.m3u8',
    'https://user@livedelivery.dlive.nicovideo.jp/hls/playlists/a/master.m3u8',
    'https://livedelivery.dlive.nicovideo.jp:8443/hls/playlists/a/master.m3u8',
    'https://livedelivery.dlive.nicovideo.jp/hls/playlists/a/../master.m3u8',
    'https://livedelivery.dlive.nicovideo.jp/hls/playlists/a/master.m3u8#token',
  ]) {
    test('reject unverified media target $uri', () {
      final data = fixture()..['uri'] = uri;
      expect(() => NiconicoStream.parse(data), schema);
    });
  }
}
