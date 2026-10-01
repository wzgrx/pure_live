import 'dart:convert';
import 'dart:typed_data';

import 'package:live_iptv/live_iptv.dart';
import 'package:test/test.dart';

void main() {
  PlaylistParseResult m3u(String content) => const M3uParser().parse(content);

  IptvEntry entry(String metadata) {
    final result = m3u('#EXTM3U\n#EXTINF:$metadata\nhttps://fixture/live\n');
    expect(result.issues, isEmpty);
    return result.entries.single;
  }

  group('M3U attributes (ported from 3.x m3u_parser_test)', () {
    test('quoted and unquoted attributes stop at the display delimiter', () {
      expect(entry('-1 tvg-id="news",News').tvgId, 'news');
      expect(entry('-1 tvg-id=news,News').tvgId, 'news');
      final channel = entry('-1 tvg-id=news tvg-chno=12 group-title=Movies,News');
      expect(channel.channelNumber, 12);
      expect(channel.groupTitle, 'Movies');
      expect(channel.streamType, IptvStreamType.vod);
    });

    test('display name keeps commas and is never scanned for attributes', () {
      expect(entry('-1 tvg-name="Fallback",News, World, HD').name, 'News, World, HD');
      final channel = entry('-1 tvg-id="real" group-title="News",News tvg-id="fake" group-title="Movies"');
      expect(channel.tvgId, 'real');
      expect(channel.groupTitle, 'News');
    });

    test('quoted values hold commas and the other quote', () {
      final channel = entry('-1 tvg-name="Fallback, International" tvg-logo="https://fixture/icon,a.png",');
      expect(channel.name, 'Fallback, International');
      expect(channel.tvgLogo, 'https://fixture/icon,a.png');
      expect(entry("-1 tvg-name='News \"World\", HD',Title").tvgName, 'News "World", HD');
    });

    test('empty, duplicate, upper-case and spaced attributes', () {
      final empty = entry('-1 tvg-id="" tvg-logo="" tvg-name="Fallback",');
      expect(empty.tvgId, isNull);
      expect(empty.name, 'Fallback');
      expect(entry('-1 TVG-ID = "news"\tTVG-CHNO = 7,News').channelNumber, 7);
      expect(entry('-1 tvg-id="old" tvg-id="new",News').tvgId, 'new');
      expect(entry('-1,News').name, 'News');
    });

    test('EXTGRP is inherited until cleared or replaced by group-title', () {
      final result = m3u(
        '#EXTM3U\n#EXTINF:-1,One\n#EXTGRP:Shared\nhttps://f/one\n#EXTINF:-1,Two\nhttps://f/two\n'
        '#EXTGRP:\n#EXTINF:-1,Three\nhttps://f/three\n#EXTGRP:Old\n#EXTINF:-1 group-title="",Four\nhttps://f/four\n',
      );
      expect(result.entries.map((e) => e.groupTitle), ['Shared', 'Shared', null, null]);
    });

    test('BOM, blank lines and every newline style', () {
      for (final newline in ['\n', '\r\n', '\r']) {
        final result = m3u(['\uFEFF', '', '#EXTM3U x-tvg-url="x"', '#EXTINF:-1,News', 'https://f/live'].join(newline));
        expect(result.issues, isEmpty);
        expect(result.entries.single.name, 'News');
      }
    });

    test('catch-up attributes: header defaults, entry values, legacy days, zero disables', () {
      final result = m3u('''
#EXTM3U catchup-type="default" catchup-source="https://archive/{utc}" catchup-days="4.5" catchup-correction="1.5"
#EXTINF:-1,One
https://f/one
#EXTINF:-1 catchup="append" catchup-source="&start={utc}" catchup-correction="-3",Two
https://f/two
#EXTINF:-1 timeshift="5",Three
https://f/three
#EXTINF:-1 catchup="append" catchup-days="0",Four
https://f/four
''');
      final [one, two, three, four] = result.entries;
      expect(
        (one.catchupMode, one.catchupSource, one.catchupDays, one.catchupCorrectionHours),
        ('default', 'https://archive/{utc}', 4.5, 1.5),
      );
      expect((two.catchupMode, two.catchupSource, two.catchupCorrectionHours), ('append', '&start={utc}', -3));
      expect((three.catchupMode, three.catchupDays), ('default', 4.5));
      expect((four.catchupMode, four.catchupDays), ('disabled', 0));
    });

    test('header precedence: header < EXTINF < directives < URL options', () {
      final result = m3u('''
#EXTM3U http-user-agent="Header Agent" http-referrer="https://f/header"
#EXTINF:-1 http-user-agent="Attribute Agent" http-referrer="https://f/attribute",One
#EXTVLCOPT:http-user-agent=Directive Agent
https://f/one.m3u8
#EXTINF:-1,Two
https://f/two.m3u8|seekable=1&user-agent=URL+Agent%2F2.0&!x-token=abc%2B%3D&cookies=session%3D42
''');
      expect(result.entries.first.httpHeaders, {'referer': 'https://f/attribute', 'user-agent': 'Directive Agent'});
      expect(result.entries.last.streamUrl, 'https://f/two.m3u8');
      expect(result.entries.last.httpHeaders, {
        'cookie': 'session=42',
        'referer': 'https://f/header',
        'user-agent': 'URL Agent/2.0',
        'x-token': 'abc+=',
      });
    });

    test('EXTHTTP and KODIPROP in leading and stanza position', () {
      final result = m3u('''
#EXTM3U
#EXTHTTP:{"Cookie":"session=first","X-Device":"tv"}
#EXTINF:-1,One
https://f/one.mpd
#EXTINF:-1,Two
#KODIPROP:inputstream.adaptive.stream_headers=origin=https%3A%2F%2Ff&authorization=Bearer%20two
https://f/two.m3u8
''');
      expect(result.entries.first.httpHeaders, {'cookie': 'session=first', 'x-device': 'tv'});
      expect(result.entries.last.httpHeaders, {'authorization': 'Bearer two', 'origin': 'https://f'});
    });
  });

  group('M3U broken stanzas', () {
    test('a malformed attribute, header directive or URL option skips only its entry', () {
      for (final broken in [
        '#EXTINF:-1 tvg-name="Unclosed,Lost\nhttps://f/lost',
        '#EXTINF:-1,Lost\n#EXTHTTP:{"Cookie":}\nhttps://f/lost',
        '#EXTINF:-1,Lost\n#EXTHTTP:{"Cookie":"a","Authorization":42}\nhttps://f/lost',
        '#EXTHTTP:{"Cookie":}\n#EXTINF:-1,Lost\nhttps://f/lost',
        '#EXTINF:-1,Lost\nhttps://f/lost|Authorization',
        // 3.x let the ArgumentError of a bad percent escape abort the import.
        '#EXTINF:-1,Lost\nhttps://f/lost|x-token=%zz',
        '#EXTINF:-1,Lost\nnot-a-url',
        '#EXTINF:-1,Lost\np2p://f/lost',
        '#EXTINF:-1,\nhttps://f/nameless',
      ]) {
        final result = m3u('#EXTM3U\n$broken\n#EXTINF:-1,News\nhttps://f/live\n');
        expect(result.entries.map((e) => e.name), ['News'], reason: broken);
        expect(result.hasIssues, isTrue, reason: broken);
        expect(result.truncated, isFalse, reason: broken);
      }
    });

    test('a stanza cut off at the end marks the file truncated', () {
      final result = m3u('#EXTM3U\n#EXTINF:-1,News\nhttps://f/live\n#EXTINF:-1,Cut\n');
      expect(result.truncated, isTrue);
      expect(result.issues.single.line, 4);
    });

    test('a missing or impostor header is reported, entries still read', () {
      final result = m3u('#EXTM3Ubroken\n#EXTINF:-1,News\nhttps://f/live');
      expect(result.issues.single.message, 'Missing #EXTM3U header');
      expect(result.entries, hasLength(1));
    });
  });

  group('TXT', () {
    test('genres, notes, multi-source lines and skipped lines', () {
      final result = const TxtParser().parse('''
CCTV-1,http://f/before
央视,#genre#
CCTV-2,http://f/a#rtmp://f/b#bad#http://f/c
更新时间,#genre#
CCTV-3,http://f/three
[note],http://f/note
—sep,http://f/sep
no comma
P2P,p2p://f/p2p
''');
      expect(result.entries.map((e) => (e.name, e.streamUrl, e.groupTitle)), [
        ('CCTV-1', 'http://f/before', 'Uncategorized'),
        ('CCTV-2 (线路1)', 'http://f/a', '央视'),
        ('CCTV-2 (线路2)', 'rtmp://f/b', '央视'),
        ('CCTV-2 (线路3)', 'http://f/c', '央视'),
        ('CCTV-3', 'http://f/three', '央视'),
        ('P2P', 'p2p://f/p2p', '央视'),
      ]);
    });
  });

  group('format and text', () {
    test('detects the format like 3.x URL imports', () {
      expect(detectPlaylistFormat('#EXTM3U\n', path: '/a.txt'), IptvPlaylistFormat.m3u);
      expect(detectPlaylistFormat('a,#genre#\n', path: '/a'), IptvPlaylistFormat.txt);
      expect(detectPlaylistFormat('x', path: '/a.TXT'), IptvPlaylistFormat.txt);
      expect(detectPlaylistFormat('x', path: '/a.m3u8'), IptvPlaylistFormat.m3u);
      expect(detectPlaylistFormat('<html>', path: '/a'), isNull);
    });

    test('UTF-8 with BOM, and non-UTF-8 only through the legacy decoder', () async {
      final bom = Uint8List.fromList([0xef, 0xbb, 0xbf, ...utf8.encode('#EXTM3U')]);
      expect(await decodePlaylistBytes(bom), '#EXTM3U');
      final gbk = Uint8List.fromList([0xd6, 0xd0, 0xce, 0xc4]);
      expect(() => decodePlaylistBytes(gbk), throwsFormatException);
      expect(await decodePlaylistBytes(gbk, legacy: (bytes) => '中文'), '中文');
    });
  });
}
