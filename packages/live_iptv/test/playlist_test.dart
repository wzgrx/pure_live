import 'dart:convert';
import 'dart:io';

import 'package:live_iptv/live_iptv.dart';
import 'package:test/test.dart';

/// A TXT list in the shape Chinese IPTV lists circulate in: update notice,
/// genre lines, `#`-separated and `$`-labelled sources, blank and comment
/// lines, CRLF.
const _txt =
    '更新时间,#genre#\r\n'
    '2026-09-27,https://fixture/notice.mp4\r\n'
    '\r\n'
    '央视频道,#genre#\r\n'
    'CCTV-1 综合,http://39.134.65.162/PLTV/88888888/224/3221225804/index.m3u8\$移动#http://[2409:8087:1a01:df::7005]/cctv1.m3u8\$IPv6\r\n'
    'CCTV-1 综合,http://fixture.backup/cctv1.flv\r\n'
    '// hidden line\r\n'
    'CCTV-5+ 体育赛事,rtmp://fixture/live/cctv5plus\r\n'
    '卫视频道,#GENRE#\r\n'
    '湖南卫视,http://fixture/hunan.m3u8\r\n'
    'broken line without comma\r\n'
    '坏地址,p2p://fixture/abc\r\n'
    '空地址,\r\n';

void main() {
  group('TXT', () {
    test(r'groups, sources split by # and labels after $ removed', () {
      final result = TxtParser.parse(_txt);
      expect(result.format, IptvFormat.txt);
      expect(
        [for (final e in result.entries) (e.group, e.name, e.url)],
        [
          ('更新时间', '2026-09-27', 'https://fixture/notice.mp4'),
          ('央视频道', 'CCTV-1 综合', 'http://39.134.65.162/PLTV/88888888/224/3221225804/index.m3u8'),
          ('央视频道', 'CCTV-1 综合', 'http://[2409:8087:1a01:df::7005]/cctv1.m3u8'),
          ('央视频道', 'CCTV-1 综合', 'http://fixture.backup/cctv1.flv'),
          ('央视频道', 'CCTV-5+ 体育赛事', 'rtmp://fixture/live/cctv5plus'),
          ('卫视频道', '湖南卫视', 'http://fixture/hunan.m3u8'),
        ],
      );
      expect(result.issues.map((issue) => issue.line), [11, 12, 13]);
    });

    test('channels before any genre line have no group; a BOM is ignored', () {
      final result = TxtParser.parse('\uFEFFNews,https://fixture/news\n');
      expect(result.entries.single.group, '');
      expect(result.entries.single.name, 'News');
    });

    test('a dollar sign always starts a label, also after a query', () {
      final result = TxtParser.parse(r'Pay,https://fixture/live?sig=a$电信');
      expect(result.entries.single.url, 'https://fixture/live?sig=a');
    });
  });

  group('JSON', () {
    test('an array of channels with several URL spellings', () {
      final result = JsonPlaylistParser.parse(
        jsonEncode([
          {
            'name': 'CCTV-1',
            'urls': ['https://fixture/a.m3u8', 'https://fixture/b.m3u8'],
            'group': '央视',
            'logo': 'https://fixture/cctv1.png',
            'tvg-id': 'CCTV1',
            'ua': 'Custom/1.0',
          },
          {'title': 'News', 'url': 'https://fixture/n1#https://fixture/n2', 'catchup-days': 3},
          {'name': 'Bad', 'url': 'proxy://x'},
          {'url': 'https://fixture/nameless'},
          'junk',
        ]),
      );
      expect(result.format, IptvFormat.json);
      expect(
        [for (final e in result.entries) (e.name, e.url)],
        [
          ('CCTV-1', 'https://fixture/a.m3u8'),
          ('CCTV-1', 'https://fixture/b.m3u8'),
          ('News', 'https://fixture/n1'),
          ('News', 'https://fixture/n2'),
        ],
      );
      final first = result.entries.first;
      expect(first.group, '央视');
      expect(first.logo, 'https://fixture/cctv1.png');
      expect(first.tvgId, 'CCTV1');
      expect(first.headers, {'user-agent': 'Custom/1.0'});
      expect(result.entries[2].catchup.days, 3);
      expect(result.issues, hasLength(3));
    });

    test('grouped objects, TVBox lives and a guide URL', () {
      final result = JsonPlaylistParser.parse(
        jsonEncode({
          'epg': 'https://epg.fixture/e.xml',
          'groups': [
            {
              'name': '央视',
              'channels': [
                {'name': 'CCTV-2', 'url': 'https://fixture/2'},
              ],
            },
          ],
          'lives': [
            {
              'group': '卫视',
              'channels': [
                {
                  'name': '湖南卫视',
                  'urls': ['https://fixture/hn'],
                },
              ],
            },
            {'name': '远程源', 'type': 0, 'url': 'https://fixture/list.txt'},
          ],
        }),
      );
      expect([for (final e in result.entries) (e.group, e.name)], [('央视', 'CCTV-2'), ('卫视', '湖南卫视')]);
      expect(result.guideUrls, [Uri.parse('https://epg.fixture/e.xml')]);
      expect(result.issues.single.reason, contains('Linked playlist not followed'));
    });
  });

  group('format detection', () {
    test('by content, never by name', () {
      expect(parsePlaylist('\n  #EXTM3U\n#EXTINF:-1,A\nhttps://fixture/a').format, IptvFormat.m3u);
      expect(parsePlaylist('#EXTINF:-1,A\nhttps://fixture/a').format, IptvFormat.m3u);
      expect(parsePlaylist('[{"name":"A","url":"https://fixture/a"}]').format, IptvFormat.json);
      expect(parsePlaylist('A,https://fixture/a').format, IptvFormat.txt);
    });

    test('broken JSON is an issue, not an exception', () {
      final result = parsePlaylist('{"channels": [');
      expect(result.entries, isEmpty);
      expect(result.issues, hasLength(1));
    });

    test('bytes: gzip, UTF-8 BOM and UTF-16 are decoded', () {
      const text = '#EXTM3U\n#EXTINF:-1,央视一套\nhttps://fixture/a\n';
      expect(parsePlaylistBytes(gzip.encode(utf8.encode(text))).entries.single.name, '央视一套');
      expect(parsePlaylistBytes([0xef, 0xbb, 0xbf, ...utf8.encode(text)]).entries.single.name, '央视一套');
      final le = <int>[0xff, 0xfe];
      for (final unit in text.codeUnits) {
        le.addAll([unit & 0xff, unit >> 8]);
      }
      expect(parsePlaylistBytes(le).entries.single.name, '央视一套');
    });
  });
}
