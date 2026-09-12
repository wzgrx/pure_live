import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/iptv/models/channel.dart';
import 'package:pure_live/core/iptv/parsers/m3u_parser.dart';

void main() {
  Channel entry(String metadata) {
    final result = M3uParser().parse('#EXTM3U\n#EXTINF:$metadata\nhttps://fixture/live\n', providerId: 'fixture');
    expect(result.errors, isEmpty);
    return result.channels.single;
  }

  test('last quoted TVG attribute before comma is retained', () {
    expect(entry('-1 tvg-id="news",News').tvgId, 'news');
  });
  test('last unquoted attribute stops before display delimiter', () {
    expect(entry('-1 tvg-id=news,News').tvgId, 'news');
  });
  test('unquoted fields stop at whitespace rather than swallowing next keys', () {
    final channel = entry('-1 tvg-id=news tvg-chno=12 group-title=Movies,News');
    expect(channel.tvgId, 'news');
    expect(channel.channelNumber, 12);
    expect(channel.groupTitle, 'Movies');
    expect(channel.streamType, StreamType.vod);
  });
  test('display name retains all commas after metadata delimiter', () {
    expect(entry('-1 tvg-name="Fallback",News, World, HD').name, 'News, World, HD');
  });
  test('quoted commas do not become a display delimiter', () {
    final channel = entry('-1 tvg-name="Fallback, International" tvg-logo="https://fixture/icon,a.png",');
    expect(channel.name, 'Fallback, International');
    expect(channel.tvgLogo, 'https://fixture/icon,a.png');
  });
  test('attribute-looking display text never overrides actual metadata', () {
    final channel = entry('-1 tvg-id="real" group-title="News",News tvg-id="fake" group-title="Movies"');
    expect(channel.tvgId, 'real');
    expect(channel.groupTitle, 'News');
    expect(channel.streamType, StreamType.live);
  });
  test('opposite quote is ordinary content inside an attribute', () {
    final channel = entry('-1 tvg-name="Children\'s News" group-title=Kids,');
    expect(channel.name, "Children's News");
  });
  test('single quoted attributes preserve double quotes and comma', () {
    final channel = entry("-1 tvg-name='News \"World\", HD',Title");
    expect(channel.tvgName, 'News "World", HD');
  });
  test('empty attributes stay empty without consuming their neighbor', () {
    final channel = entry('-1 tvg-id="" tvg-logo="" tvg-name="Fallback",');
    expect(channel.tvgId, isNull);
    expect(channel.tvgLogo, isNull);
    expect(channel.name, 'Fallback');
  });
  test('case and whitespace around equals are tolerated', () {
    final channel = entry('-1 TVG-ID = "news"\tTVG-CHNO = 7,News');
    expect(channel.tvgId, 'news');
    expect(channel.channelNumber, 7);
  });
  test('unquoted URL query retains equals signs', () {
    expect(
      entry('-1 tvg-logo=https://fixture/icon?size=2&key=abc,News').tvgLogo,
      'https://fixture/icon?size=2&key=abc',
    );
  });
  test('a missing display delimiter still permits explicit tvg-name fallback', () {
    expect(entry('-1 tvg-name="Fallback"').name, 'Fallback');
  });
  test('standard entry without attributes remains valid', () {
    expect(entry('-1,News').name, 'News');
  });
  test('duplicate attribute keys use the last value within metadata only', () {
    expect(entry('-1 tvg-id="old" tvg-id="new",News').tvgId, 'new');
  });
  test('EXTGRP begins a persistent group and empty directive clears it', () {
    final result = M3uParser().parse('''#EXTM3U
#EXTINF:-1,One
#EXTGRP:Shared
https://fixture/one
#EXTINF:-1,Two
https://fixture/two
#EXTGRP:
#EXTINF:-1,Three
https://fixture/three
''', providerId: 'fixture');
    expect(result.errors, isEmpty);
    expect(result.channels.map((e) => e.groupTitle), ['Shared', 'Shared', null]);
  });
  test('explicit group-title resets an EXTGRP group for following entries', () {
    final result = M3uParser().parse('''#EXTM3U
#EXTGRP:Shared
#EXTINF:-1 group-title="Own",One
https://fixture/one
#EXTINF:-1,Two
https://fixture/two
''', providerId: 'fixture');
    expect(result.errors, isEmpty);
    expect(result.channels.map((e) => e.groupTitle), ['Own', null]);
  });
  for (final newline in ['\n', '\r\n', '\r']) {
    test('BOM, blank prefix and newline ${newline.codeUnits} preserve entries', () {
      final result = M3uParser().parse(
        [
          '\uFEFF',
          '',
          '#EXTM3U x-tvg-url="https://fixture/epg"',
          '#EXTINF:-1,News',
          '#EXTVLCOPT:program=1',
          'https://fixture/live',
          '',
        ].join(newline),
        providerId: 'fixture',
      );
      expect(result.errors, isEmpty);
      expect(result.channels.single.name, 'News');
    });
  }
  for (final metadata in ['-1 tvg-name="Unclosed,News', "-1 tvg-name='Unclosed,News", '-1 tvg-id="news"broken,News']) {
    test('malformed attribute reports error rather than inventing a channel: $metadata', () {
      final result = M3uParser().parse('#EXTM3U\n#EXTINF:$metadata\nhttps://fixture/live\n', providerId: 'fixture');
      expect(result.hasErrors, isTrue);
      expect(result.channels, isEmpty);
      expect(result.errors.first, contains('Line 2'));
    });
  }
  test('pending entry at EOF reports a truncated stanza', () {
    final result = M3uParser().parse('#EXTM3U\n#EXTINF:-1,News\n', providerId: 'fixture');
    expect(result.hasErrors, isTrue);
    expect(result.errors.single, contains('Line 2'));
  });
  test('new metadata before a URL reports previous truncated stanza', () {
    final result = M3uParser().parse(
      '#EXTM3U\n#EXTINF:-1,Lost\n#EXTINF:-1,News\nhttps://fixture/live\n',
      providerId: 'fixture',
    );
    expect(result.hasErrors, isTrue);
    expect(result.channels.single.name, 'News');
  });
  test('invalid stanza URL reports an error but still parses subsequent valid entry', () {
    final result = M3uParser().parse(
      '#EXTM3U\n#EXTINF:-1,Lost\nnot-a-url\n#EXTINF:-1,News\nhttps://fixture/live',
      providerId: 'fixture',
    );
    expect(result.hasErrors, isTrue);
    expect(result.channels.single.name, 'News');
  });
  test('header prefix impostor is not a valid header', () {
    final result = M3uParser().parse('#EXTM3Ubroken\n#EXTINF:-1,News\nhttps://fixture/live', providerId: 'fixture');
    expect(result.hasErrors, isTrue);
  });
  test('all 120 attribute orders preserve metadata including the final key', () {
    final fields = [
      'tvg-id="news"',
      'tvg-name="News, World"',
      'tvg-logo=https://fixture/icon?a=1',
      'group-title="Series"',
      'tvg-chno=9',
    ];
    Iterable<List<String>> permutations(List<String> values) sync* {
      if (values.isEmpty) {
        yield [];
      } else {
        for (var i = 0; i < values.length; i++) {
          for (final rest in permutations([...values.take(i), ...values.skip(i + 1)])) {
            yield [values[i], ...rest];
          }
        }
      }
    }

    int checked = 0;
    for (final order in permutations(fields)) {
      final channel = entry('-1 ${order.join(' ')},Title, HD');
      expect(channel.tvgId, 'news');
      expect(channel.tvgName, 'News, World');
      expect(channel.tvgLogo, 'https://fixture/icon?a=1');
      expect(channel.channelNumber, 9);
      expect(channel.groupTitle, 'Series');
      expect(channel.streamType, StreamType.series);
      expect(channel.name, 'Title, HD');
      checked++;
    }
    expect(checked, 120);
  });
  test('parser reuse does not leak groups or pending metadata across inputs', () {
    final parser = M3uParser();
    parser.parse('#EXTM3U\n#EXTGRP:Old\n#EXTINF:-1,Pending', providerId: 'old');
    final result = parser.parse('#EXTM3U\n#EXTINF:-1,New\nhttps://fixture/live', providerId: 'new');
    expect(result.errors, isEmpty);
    expect(result.channels.single.groupTitle, isNull);
    expect(result.channels.single.providerId, 'new');
  });
  test('all six supported URL schemes and query commas remain unchanged', () {
    for (final scheme in ['http', 'https', 'rtmp', 'rtsp', 'udp', 'mms']) {
      final url = '$scheme://fixture/live?token=a,b&v=1';
      final result = M3uParser().parse('#EXTM3U\n#EXTINF:-1,News\n$url', providerId: 'fixture');
      expect(result.errors, isEmpty);
      expect(result.channels.single.streamUrl, url);
    }
  });
  test('empty explicit group ends inherited grouping even on a named entry', () {
    final result = M3uParser().parse(
      '#EXTM3U\n#EXTGRP:Old\n#EXTINF:-1 group-title="",News\nhttps://fixture/live',
      providerId: 'fixture',
    );
    expect(result.errors, isEmpty);
    expect(result.channels.single.groupTitle, isNull);
  });
  test('provider catch-up metadata survives playlist parsing', () {
    final channel = entry(
      '-1 catchup="append" catchup-source="&start={utc}&duration={duration}" '
      'catchup-days="3.5" catchup-correction="-2.5",News',
    );

    expect(channel.catchupMode, 'append');
    expect(channel.catchupSource, '&start={utc}&duration={duration}');
    expect(channel.catchupDays, 3.5);
    expect(channel.catchupCorrectionHours, -2.5);
  });
  test('header catch-up defaults are inherited and channel values take precedence', () {
    final result = M3uParser().parse('''#EXTM3U catchup-type="default" catchup-source="https://archive/{utc}" catchup-days="4.5" catchup-correction="1.5"
#EXTINF:-1,One
https://fixture/one
#EXTINF:-1 catchup="append" catchup-source="&start={utc}" catchup-correction="-3",Two
https://fixture/two
''', providerId: 'fixture');

    expect(result.errors, isEmpty);
    expect(result.channels[0].catchupMode, 'default');
    expect(result.channels[0].catchupSource, 'https://archive/{utc}');
    expect(result.channels[0].catchupDays, 4.5);
    expect(result.channels[0].catchupCorrectionHours, 1.5);
    expect(result.channels[1].catchupMode, 'append');
    expect(result.channels[1].catchupSource, '&start={utc}');
    expect(result.channels[1].catchupCorrectionHours, -3);
  });
  test('legacy timeshift and tvg-rec advertise shift windows while zero disables catch-up', () {
    final result = M3uParser().parse('''#EXTM3U
#EXTINF:-1 timeshift="5",One
https://fixture/one
#EXTINF:-1 tvg-rec="2.5",Two
https://fixture/two
#EXTINF:-1 catchup="append" catchup-days="0",Three
https://fixture/three
''', providerId: 'fixture');

    expect(result.errors, isEmpty);
    expect(result.channels[0].catchupMode, 'shift');
    expect(result.channels[0].catchupDays, 5);
    expect(result.channels[1].catchupMode, 'shift');
    expect(result.channels[1].catchupDays, 2.5);
    expect(result.channels[2].catchupMode, 'disabled');
    expect(result.channels[2].catchupDays, 0);
  });
  test('empty input and nameless stanza report errors', () {
    for (final content in ['', '\uFEFF\n\r\n', '#EXTM3U\n#EXTINF:-1,\nhttps://fixture/live']) {
      final result = M3uParser().parse(content, providerId: 'fixture');
      expect(result.hasErrors, isTrue);
      expect(result.channels, isEmpty);
    }
  });
  test('large valid list and long quoted comma values keep every channel', () {
    final title = List.filled(200, 'News,World').join(' ');
    final content = StringBuffer('#EXTM3U\n');
    for (var i = 0; i < 2000; i++) {
      content.write('#EXTINF:-1 tvg-name="$title" tvg-id="$i",Channel $i, HD\nhttps://fixture/$i\n');
    }
    final result = M3uParser().parse(content.toString(), providerId: 'fixture');
    expect(result.errors, isEmpty);
    expect(result.channelCount, 2000);
    expect(result.channels.last.tvgId, '1999');
    expect(result.channels.last.tvgName, title);
    expect(result.channels.last.name, 'Channel 1999, HD');
  });
}
