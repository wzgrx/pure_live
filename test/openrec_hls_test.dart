import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/openrec/openrec_api.dart';
import 'package:pure_live/core/site/openrec/openrec_hls.dart';
import 'package:pure_live/core/site/openrec/openrec_link.dart';

String _fixture(String name) => File('test/fixtures/openrec/$name.m3u8').readAsStringSync();
const _source = OpenrecMedia('hls', 'https://dfixture.cloudfront.net/session/master.m3u8');
Matcher _failure(OpenrecFailure value) => throwsA(isA<OpenrecException>().having((e) => e.kind, 'kind', value));

void main() {
  test('captured master exposes five declared renditions without splitting CODECS commas', () {
    final qualities = parseOpenrecHls(_fixture('master'), _source);
    expect(qualities.map((q) => q.label), ['720p 60fps', '720p 30fps', '540p 30fps', '360p 30fps', '144p 30fps']);
    expect(qualities.first.urls.single, 'https://dfixture.cloudfront.net/session/chunklist_source/chunklist-live.m3u8');
    expect(qualities.first.id, contains('avc1.640020,mp4a.40.2'));
    expect(qualities.first.rank, 5000000);
    expect(() => qualities.clear(), throwsUnsupportedError);
    expect(() => qualities.first.urls.clear(), throwsUnsupportedError);
  });
  test('public and low latency families retain declared geometry and separate identity', () {
    final public = parseOpenrecHls(_fixture('public-master'), OpenrecMedia('public-hls', _source.url));
    final low = parseOpenrecHls(_fixture('low-latency-master'), OpenrecMedia('low-latency-hls', _source.url));
    expect(public.single.label, '360p 30fps');
    expect(low.single.label, '720p 60fps');
    expect(low.single.urls.single, 'https://ull01.openrec.tv/fixture-stream/source/chunklist.m3u8');
    expect(low.single.id, isNot(parseOpenrecHls(_fixture('master'), _source).first.id));
  });
  test('renewal changes URLs and bandwidth without changing known quality IDs', () {
    final old = parseOpenrecHls(_fixture('master'), _source);
    final next = parseOpenrecHls(
      _fixture('master').replaceAll('5000000', '5100000'),
      const OpenrecMedia('hls', 'https://dnext.cloudfront.net/renewed/master.m3u8'),
    );
    expect(next.map((q) => q.id), old.map((q) => q.id));
    expect(next.first.urls, isNot(old.first.urls));
  });
  test('duplicate rendition IDs group distinct lines and discard exact duplicate URLs', () {
    const one = '#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=640x360,FRAME-RATE=30\na.m3u8\n';
    final result = parseOpenrecHls('#EXTM3U\n$one$one${one.replaceAll('a.m3u8', 'b.m3u8')}', _source);
    expect(result, hasLength(1));
    expect(result.single.urls, hasLength(2));
  });
  test('external audio keeps the master rather than losing audio in a naked child', () {
    const text =
        '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="Audio",URI="audio.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=1000,RESOLUTION=640x360,AUDIO="aac"\nvideo.m3u8\n';
    final result = parseOpenrecHls(text, _source).single;
    expect(result.id, 'hls:auto');
    expect(result.urls, [_source.url]);
  });
  test('captured rolling media list remains automatic and is not treated as a master variant', () {
    final result = parseOpenrecHls(_fixture('media-playlist'), _source).single;
    expect(result.label, 'HLS Auto');
    expect(result.urls, [_source.url]);
  });
  test('ended and VOD lists are unavailable live media, not owner-offline evidence', () {
    for (final tag in ['#EXT-X-ENDLIST', '#EXT-X-PLAYLIST-TYPE:VOD']) {
      expect(
        () => parseOpenrecHls('${_fixture('media-playlist')}\n$tag', _source),
        _failure(OpenrecFailure.mediaUnavailable),
      );
    }
  });
  test('encrypted manifests are explicit pending modes rather than silent trial/clear rewrites', () {
    expect(
      () => parseOpenrecHls('#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key"\n#EXTINF:2,\na.ts', _source),
      _failure(OpenrecFailure.restricted),
    );
  });
  test('malformed attributes, dangling URLs, mixed lists and invalid metadata fail', () {
    for (final text in [
      '<html>403</html>',
      '#EXTM3U',
      '#EXTM3U\nstray.m3u8',
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1',
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,BANDWIDTH=2\na.m3u8',
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=0\na.m3u8',
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=bad\na.m3u8',
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,FRAME-RATE=NaN\na.m3u8',
      '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,garbage\na.m3u8',
      '#EXTM3U\n#EXTINF:2,',
      '${_fixture('master')}\n#EXTINF:2,\na.ts',
    ]) {
      expect(() => parseOpenrecHls(text, _source), _failure(OpenrecFailure.schema), reason: text);
    }
  });
  test('every variant, rendition and segment authority is validated', () {
    for (final url in [
      'file:///a.m3u8',
      'https://user@dfixture.cloudfront.net/a.m3u8',
      'https://dfixture.cloudfront.net.evil.test/a.m3u8',
      'https://127.0.0.1/a.m3u8',
    ]) {
      expect(
        () => parseOpenrecHls('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\n$url', _source),
        _failure(OpenrecFailure.schema),
      );
      expect(() => parseOpenrecHls('#EXTM3U\n#EXTINF:2,\n$url', _source), _failure(OpenrecFailure.schema));
      expect(
        () => parseOpenrecHls(
          '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,URI="$url"\n#EXT-X-STREAM-INF:BANDWIDTH=1\na.m3u8',
          _source,
        ),
        _failure(OpenrecFailure.schema),
      );
    }
  });
  test('master budget and unknown source families are bounded', () {
    expect(
      () => parseOpenrecHls('#EXTM3U\n${'中' * (OpenrecApi.responseLimit ~/ 3 + 1)}', _source),
      _failure(OpenrecFailure.schema),
    );
    expect(
      () => parseOpenrecHls(_fixture('master'), OpenrecMedia('trial', _source.url)),
      _failure(OpenrecFailure.schema),
    );
  });
  test('canonical room key pins numeric identity and preserves case', () {
    final key = OpenrecRoomKey.create('Fixture_Owner', 100);
    expect(key.value, 'Fixture_Owner@100');
    expect(OpenrecRoomKey.parse(key.value).channelId, 'Fixture_Owner');
    expect(key.url, 'https://www.mellow-fan.com/user/Fixture_Owner');
    for (final value in [
      'Fixture_Owner',
      'Fixture_Owner@0',
      'Fixture_Owner@01',
      'Fixture_Owner@100@101',
      '../owner@100',
      'owner@9007199254740992',
    ]) {
      expect(() => OpenrecRoomKey.parse(value), _failure(OpenrecFailure.identity));
    }
  });
  test('official old/new channel and live/movie links preserve public ID case', () {
    for (final host in ['www.openrec.tv', 'openrec.tv', 'www.mellow-fan.com', 'mellow-fan.com']) {
      expect(OpenrecLink.parse('https://$host/user/Fixture_Owner')!.kind, OpenrecLinkKind.channel);
      for (final path in ['live', 'movie']) {
        final link = OpenrecLink.parse('https://$host/$path/fixture1234/?utm_source=fixture#share');
        expect(link!.id, 'fixture1234');
        expect(link.kind, OpenrecLinkKind.movie);
      }
    }
  });
  test('nearby hosts, credentials, encoded traversal and non-room paths are rejected', () {
    for (final url in [
      'https://www.mellow-fan.com.evil.test/user/Owner',
      'https://x@www.mellow-fan.com/user/Owner',
      'https://www.mellow-fan.com:8787/user/Owner',
      'https://public.mellow-fan.com/user/Owner',
      'https://www.mellow-fan.com/search/Owner',
      'https://www.mellow-fan.com/user/%4fwner',
      'https://www.mellow-fan.com/a/../user/Owner',
      'https://www.mellow-fan.com/user/Owner/extra',
      'ftp://www.mellow-fan.com/user/Owner',
    ]) {
      expect(OpenrecLink.parse(url), isNull, reason: url);
    }
  });
}
