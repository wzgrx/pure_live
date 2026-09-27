import 'package:live_iptv/live_iptv.dart';
import 'package:test/test.dart';

void main() {
  IptvEntry entry(String metadata) {
    final result = M3uParser.parse('#EXTM3U\n#EXTINF:$metadata\nhttps://fixture/live\n');
    expect(result.issues, isEmpty);
    return result.entries.single;
  }

  group('EXTINF attributes', () {
    test('quoted and unquoted values before the display comma', () {
      expect(entry('-1 tvg-id="news",News').tvgId, 'news');
      expect(entry('-1 tvg-id=news,News').tvgId, 'news');
    });

    test('unquoted values stop at whitespace instead of swallowing the next key', () {
      final result = entry('-1 tvg-id=news tvg-logo=https://fixture/n.png group-title=Movies,News');
      expect(result.tvgId, 'news');
      expect(result.logo, 'https://fixture/n.png');
      expect(result.group, 'Movies');
    });

    test('the display name keeps every comma after the metadata', () {
      expect(entry('-1 tvg-name="Fallback",News, World, HD').name, 'News, World, HD');
    });

    test('quoted commas are not the display delimiter', () {
      final result = entry('-1 tvg-name="Fallback, International" tvg-logo="https://fixture/icon,a.png",');
      expect(result.name, 'Fallback, International');
      expect(result.logo, 'https://fixture/icon,a.png');
    });

    test('attribute-looking display text never overrides the metadata', () {
      final result = entry('-1 tvg-id="real" group-title="News",News tvg-id="fake" group-title="Movies"');
      expect(result.tvgId, 'real');
      expect(result.group, 'News');
      expect(result.name, 'News tvg-id="fake" group-title="Movies"');
    });

    test('the other quote is ordinary content', () {
      expect(entry('-1 tvg-name="Children\'s News" group-title=Kids,').name, "Children's News");
      expect(entry("-1 tvg-name='News \"World\", HD',Title").tvgName, 'News "World", HD');
    });

    test('empty attributes stay empty without consuming their neighbour', () {
      final result = entry('-1 tvg-id="" tvg-logo="" tvg-name="Fallback",');
      expect(result.tvgId, isNull);
      expect(result.logo, isNull);
      expect(result.name, 'Fallback');
    });

    test('key case and whitespace around = are tolerated', () {
      expect(entry('-1 TVG-ID = "news"\tGROUP-TITLE = 央视,News').tvgId, 'news');
    });

    test('an unquoted URL keeps its equals signs and ampersands', () {
      expect(entry('-1 tvg-logo=https://fixture/icon?size=2&key=abc,News').logo, 'https://fixture/icon?size=2&key=abc');
    });

    test('a missing display comma falls back to tvg-name', () {
      expect(entry('-1 tvg-name="Fallback"').name, 'Fallback');
      expect(entry('-1,News').name, 'News');
    });

    test('a repeated key keeps its last value; whitespace in names collapses', () {
      expect(entry('-1 tvg-id="old" tvg-id="new",News').tvgId, 'new');
      expect(entry('-1,  CCTV-1   综合 ').name, 'CCTV-1 综合');
    });

    test('all 120 attribute orders keep every value', () {
      final fields = [
        'tvg-id="news"',
        'tvg-name="News, World"',
        'tvg-logo=https://fixture/icon?a=1',
        'group-title="Series"',
        'tvg-chno=9',
      ];
      Iterable<List<String>> orders(List<String> values) sync* {
        if (values.isEmpty) {
          yield [];
          return;
        }
        for (var i = 0; i < values.length; i++) {
          for (final rest in orders([...values.take(i), ...values.skip(i + 1)])) {
            yield [values[i], ...rest];
          }
        }
      }

      var checked = 0;
      for (final order in orders(fields)) {
        final result = entry('-1 ${order.join(' ')},Title, HD');
        expect(result.tvgId, 'news');
        expect(result.tvgName, 'News, World');
        expect(result.logo, 'https://fixture/icon?a=1');
        expect(result.group, 'Series');
        expect(result.name, 'Title, HD');
        checked++;
      }
      expect(checked, 120);
    });

    for (final metadata in [
      '-1 tvg-name="Unclosed,News',
      "-1 tvg-name='Unclosed,News",
      '-1 tvg-id="news"broken,News',
    ]) {
      test('a malformed attribute is an issue, never a half-read channel: $metadata', () {
        final result = M3uParser.parse('#EXTM3U\n#EXTINF:$metadata\nhttps://fixture/live\n');
        expect(result.entries, isEmpty);
        expect(result.issues.single.line, 2);
      });
    }
  });

  group('structure', () {
    test('#EXTGRP starts an inherited group; an empty one clears it', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1,One
#EXTGRP:Shared
https://fixture/one
#EXTINF:-1,Two
https://fixture/two
#EXTGRP:
#EXTINF:-1,Three
https://fixture/three
''');
      expect(result.issues, isEmpty);
      expect(result.entries.map((e) => e.group), ['Shared', 'Shared', '']);
    });

    test("an entry's own group-title, even empty, ends #EXTGRP inheritance", () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTGRP:Shared
#EXTINF:-1 group-title="Own",One
https://fixture/one
#EXTINF:-1,Two
https://fixture/two
#EXTGRP:Old
#EXTINF:-1 group-title="",Three
https://fixture/three
''');
      expect(result.entries.map((e) => e.group), ['Own', '', '']);
    });

    for (final newline in ['\n', '\r\n', '\r']) {
      test('BOM, blank lines and newline ${newline.codeUnits} keep entries and guide URLs', () {
        final result = M3uParser.parse(
          [
            '\uFEFF',
            '',
            '#EXTM3U x-tvg-url="https://epg.fixture/e.xml.gz,https://epg.fixture/backup.xml" url-tvg="https://epg.fixture/e.xml.gz"',
            '#EXTINF:-1,News',
            '#EXTVLCOPT:program=1',
            'https://fixture/live',
            '',
          ].join(newline),
        );
        expect(result.issues, isEmpty);
        expect(result.entries.single.name, 'News');
        expect(result.guideUrls, [
          Uri.parse('https://epg.fixture/e.xml.gz'),
          Uri.parse('https://epg.fixture/backup.xml'),
        ]);
      });
    }

    test('a stanza cut off at the end of the file is an issue', () {
      final result = M3uParser.parse('#EXTM3U\n#EXTINF:-1,News\n');
      expect(result.entries, isEmpty);
      expect(result.issues.single.line, 2);
    });

    test('a new #EXTINF before a URL reports the previous stanza and keeps the next', () {
      final result = M3uParser.parse('#EXTM3U\n#EXTINF:-1,Lost\n#EXTINF:-1,News\nhttps://fixture/live\n');
      expect(result.issues.single.line, 2);
      expect(result.entries.single.name, 'News');
    });

    test('an invalid URL is skipped and the next entry still parses', () {
      final result = M3uParser.parse('#EXTM3U\n#EXTINF:-1,Lost\nnot-a-url\n#EXTINF:-1,News\nhttps://fixture/live');
      expect(result.issues.single.line, 3);
      expect(result.entries.single.name, 'News');
    });

    test('a header impostor, a URL without #EXTINF and a nameless stanza are issues', () {
      expect(M3uParser.parse('#EXTM3Ubroken\n#EXTINF:-1,News\nhttps://fixture/live').issues, isNotEmpty);
      final orphan = M3uParser.parse('#EXTM3U\nhttps://fixture/orphan\n#EXTINF:-1,News\nhttps://fixture/live');
      expect(orphan.issues.single.line, 2);
      expect(orphan.entries.single.name, 'News');
      final nameless = M3uParser.parse('#EXTM3U\n#EXTINF:-1,\nhttps://fixture/live');
      expect(nameless.entries, isEmpty);
      expect(nameless.issues, isNotEmpty);
      expect(M3uParser.parse('').issues.single.reason, 'Playlist is empty');
    });

    test('every playable scheme keeps its URL as written; proprietary ones are rejected', () {
      for (final scheme in ['http', 'https', 'rtmp', 'rtsp', 'rtp', 'udp', 'mms', 'srt']) {
        final url = '$scheme://fixture:1234/live?token=a,b&v=1';
        final result = M3uParser.parse('#EXTM3U\n#EXTINF:-1,News\n$url');
        expect(result.issues, isEmpty, reason: scheme);
        expect(result.entries.single.url, url);
      }
      for (final url in ['p2p://fixture/live', 'proxy://do=live&url=x', 'file:///sdcard/a.ts']) {
        expect(M3uParser.parse('#EXTM3U\n#EXTINF:-1,News\n$url').entries, isEmpty, reason: url);
      }
    });

    test('entries sharing a name stay separate, in file order (they become lines)', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1 tvg-id="CCTV1" group-title="央视",CCTV-1 综合
http://39.134.65.162/PLTV/88888888/224/3221225804/index.m3u8
#EXTINF:-1 tvg-id="CCTV1" group-title="央视",CCTV-1 综合
http://[2409:8087:1a01:df::7005]/ottrrs.hl.chinamobile.com/PLTV/88888888/224/3221226016/index.m3u8
''');
      expect(result.issues, isEmpty);
      expect(result.entries.map((e) => e.name), ['CCTV-1 综合', 'CCTV-1 综合']);
      expect(result.entries.last.url, startsWith('http://[2409:8087:1a01:df::7005]/'));
    });

    test('a large list with long quoted values keeps every entry', () {
      final title = List.filled(200, 'News,World').join(' ');
      final content = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < 2000; i++) {
        content.write('#EXTINF:-1 tvg-name="$title" tvg-id="$i",Channel $i, HD\nhttps://fixture/$i\n');
      }
      final result = M3uParser.parse(content.toString());
      expect(result.issues, isEmpty);
      expect(result.entries, hasLength(2000));
      expect(result.entries.last.tvgId, '1999');
      expect(result.entries.last.tvgName, title);
      expect(result.entries.last.name, 'Channel 1999, HD');
    });
  });

  group('catch-up attributes', () {
    test('entry values', () {
      final result = entry(
        '-1 catchup="append" catchup-source="&start={utc}&duration={duration}" '
        'catchup-days="3.5" catchup-correction="-2.5",News',
      );
      expect(
        result.catchup,
        const IptvCatchup(mode: 'append', source: '&start={utc}&duration={duration}', days: 3.5, correction: -2.5),
      );
    });

    test('header defaults are inherited; entry values win', () {
      final result = M3uParser.parse('''
#EXTM3U catchup-type="default" catchup-source="https://archive/{utc}" catchup-days="4.5" catchup-correction="1.5"
#EXTINF:-1,One
https://fixture/one
#EXTINF:-1 catchup="append" catchup-source="&start={utc}" catchup-correction="-3",Two
https://fixture/two
''');
      expect(result.issues, isEmpty);
      expect(
        result.entries[0].catchup,
        const IptvCatchup(mode: 'default', source: 'https://archive/{utc}', days: 4.5, correction: 1.5),
      );
      expect(
        result.entries[1].catchup,
        const IptvCatchup(mode: 'append', source: '&start={utc}', days: 4.5, correction: -3),
      );
    });

    test('timeshift and tvg-rec are shift windows; zero days or an off mode disable catch-up', () {
      final result = M3uParser.parse(r'''
#EXTM3U
#EXTINF:-1 timeshift="5",One
https://fixture/one
#EXTINF:-1 tvg-rec="2.5",Two
https://fixture/two
#EXTINF:-1 catchup="append" catchup-days="0",Three
https://fixture/three
#EXTINF:-1 catchup="off",Four
https://fixture/four
#EXTINF:-1 catchup-source="?playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}",Five
https://fixture/five
''');
      expect(result.entries.map((e) => e.catchup.mode), ['shift', 'shift', 'disabled', 'disabled', 'default']);
      expect(result.entries[0].catchup.days, 5);
      expect(result.entries[1].catchup.days, 2.5);
      expect(result.entries[2].catchup.isDisabled, isTrue);
      expect(result.entries[4].catchup.source, r'?playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}');
    });

    test('no attributes: no catch-up settings (the playseek rule applies later)', () {
      expect(entry('-1,News').catchup.isEmpty, isTrue);
    });
  });

  group('request headers', () {
    test('#EXTVLCOPT and url|options become headers and leave the URL clean', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTINF:-1,Protected
#EXTVLCOPT:http-user-agent=Directive Agent/1.0
#EXTVLCOPT:http-referrer=https://fixture/guide?id=1
https://fixture/live.m3u8|seekable=1&reconnect_streamed=1&user-agent=URL+Agent%2F2.0&referrer=https%3A%2F%2Ffixture%2Froom%3Fa%3D1%26b%3D2&!x-token=abc%2B%3D
#EXTINF:-1,Plain
https://fixture/plain.m3u8
''');
      expect(result.issues, isEmpty);
      expect(result.entries.first.url, 'https://fixture/live.m3u8');
      expect(result.entries.first.headers, {
        'referer': 'https://fixture/room?a=1&b=2',
        'user-agent': 'URL Agent/2.0',
        'x-token': 'abc+=',
      });
      expect(result.entries.last.headers, isEmpty);
    });

    test('header and EXTINF defaults yield to directives and URL options', () {
      final result = M3uParser.parse('''
#EXTM3U http-user-agent="Header Agent" http-referrer="https://fixture/header"
#EXTINF:-1 http-user-agent="Attribute Agent" http-referrer="https://fixture/attribute",One
#EXTVLCOPT:http-user-agent=Directive Agent
https://fixture/one.m3u8
#EXTINF:-1,Two
https://fixture/two.m3u8|cookies=session%3D42
''');
      expect(result.issues, isEmpty);
      expect(result.entries.first.headers, {'referer': 'https://fixture/attribute', 'user-agent': 'Directive Agent'});
      expect(result.entries.last.headers, {
        'cookie': 'session=42',
        'referer': 'https://fixture/header',
        'user-agent': 'Header Agent',
      });
    });

    test('#EXTHTTP and #KODIPROP headers before or inside a stanza', () {
      final result = M3uParser.parse('''
#EXTM3U
#EXTHTTP:{"Cookie":"session=first","X-Device":"tv"}
#EXTINF:-1,One
https://fixture/one.mpd
#EXTINF:-1,Two
#KODIPROP:inputstream.adaptive.stream_headers=origin=https%3A%2F%2Ffixture&authorization=Bearer%20two
#KODIPROP:inputstream.adaptive.manifest_headers=x-manifest=yes
https://fixture/two.m3u8
''');
      expect(result.issues, isEmpty);
      expect(result.entries.first.headers, {'cookie': 'session=first', 'x-device': 'tv'});
      expect(result.entries.last.headers, {
        'authorization': 'Bearer two',
        'origin': 'https://fixture',
        'x-manifest': 'yes',
      });
    });

    test('a malformed header directive skips its entry instead of keeping partial credentials', () {
      for (final directive in ['#EXTHTTP:{"Cookie":}', '#EXTHTTP:{"Cookie":"session=one","Authorization":42}']) {
        final result = M3uParser.parse(
          '#EXTM3U\n#EXTINF:-1,Broken\n$directive\nhttps://fixture/live.m3u8\n#EXTINF:-1,Next\nhttps://fixture/n',
        );
        expect(result.entries.map((e) => e.name), ['Next'], reason: directive);
        expect(result.issues.first.reason, 'Invalid EXTHTTP header');
      }
    });

    test('malformed URL options reject the stanza instead of requesting an ambiguous URL', () {
      for (final url in ['https://fixture/live.m3u8|Authorization', 'https://fixture/live.m3u8|a=%zz']) {
        final result = M3uParser.parse('#EXTM3U\n#EXTINF:-1,Broken\n$url\n');
        expect(result.entries, isEmpty, reason: url);
        expect(result.issues.single.reason, 'Invalid stream header option');
      }
    });
  });
}
