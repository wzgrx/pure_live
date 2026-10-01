import 'dart:convert';
import 'dart:io';

import 'package:live_iptv/live_iptv.dart';
import 'package:test/test.dart';

const _xmltv = '''
<tv>
  <channel id="CCTV1"><display-name>CCTV-1 综合</display-name><display-name>CCTV1</display-name><icon src="https://f/1.png"/></channel>
  <channel id="empty"/>
  <programme channel="CCTV1" start="20260927200000 +0800" stop="20260927210000 +08:00" catchup-id="c1">
    <title><![CDATA[新闻 & 联播]]></title><sub-title>S</sub-title><desc>D &amp; E</desc><category>News</category>
  </programme>
  <programme channel="CCTV1" start="202609272100" stop="20260927220000Z"><title>Late</title></programme>
  <programme channel="CCTV1" start="bad" stop="20260927220000"><title>Bad time</title></programme>
  <programme channel="CCTV1" start="20260927220000" stop="20260927230000"></programme>
</tv>''';

void main() {
  group('XMLTV', () {
    test('channels, programmes, CDATA, entities, zones and skipped programmes', () {
      final guide = parseGuide(_xmltv);
      expect(guide.channels.map((c) => (c.id, c.displayNames.join('|'), c.iconUrl)), [
        ('CCTV1', 'CCTV-1 综合|CCTV1', 'https://f/1.png'),
        ('empty', '', null),
      ]);
      final [first, second] = guide.programmes;
      expect(first.title, '新闻 & 联播');
      expect(first.description, 'D & E');
      expect((first.subtitle, first.category, first.catchupId), ('S', 'News', 'c1'));
      expect(first.start, DateTime.utc(2026, 9, 27, 12));
      expect(first.stop, DateTime.utc(2026, 9, 27, 13));
      expect(second.start, DateTime.utc(2026, 9, 27, 21));
      expect(second.stop, DateTime.utc(2026, 9, 27, 22));
    });

    test('malformed XML fails instead of importing half a guide', () {
      expect(() => parseGuide('<tv><channel id="a"></tv>'), throwsFormatException);
    });

    test('gzip is found by its magic bytes and a BOM is dropped', () {
      final bytes = gzip.encode([0xef, 0xbb, 0xbf, ...utf8.encode(_xmltv)]);
      expect(parseGuide(decodeGuideBytes(bytes)).programmes, hasLength(2));
      expect(() => decodeGuideBytes([0x3c, 0xff, 0xfe]), throwsFormatException);
      final latin = latin1.encode('<?xml version="1.0" encoding="ISO-8859-1"?><tv><channel id="é"/></tv>');
      expect(parseGuide(decodeGuideBytes(latin)).channels.single.id, 'é');
    });
  });

  test('JSON guide: aliases, Unix seconds and milliseconds, default duration', () {
    final guide = parseGuide(
      jsonEncode({
        'channels': [
          {'id': 'a', 'displayName': 'A台', 'logo': 'https://f/a.png'},
          {'name': 'B'},
        ],
        'epg': [
          {'channel': 'a', 'name': 'One', 'start': 1790000000, 'end': 1790003600000, 'catchup-id': 'x'},
          {'channelId': 'b', 'title': 'Two', 'startTime': '2026-09-27T12:00:00Z', 'duration': 45},
          {'channelId': 'b', 'title': 'Three', 'time': '1790000000'},
          {'channelId': 'b', 'start': 1790000000},
        ],
      }),
    );
    expect(guide.channels.map((c) => (c.id, c.primaryName, c.iconUrl)), [
      ('a', 'A台', 'https://f/a.png'),
      ('B', 'B', null),
    ]);
    final [one, two, three] = guide.programmes;
    expect(one.start, DateTime.fromMillisecondsSinceEpoch(1790000000000, isUtc: true));
    expect(one.stop, DateTime.fromMillisecondsSinceEpoch(1790003600000, isUtc: true));
    expect(one.catchupId, 'x');
    expect(two.stop.difference(two.start), const Duration(minutes: 45));
    expect(three.start, one.start, reason: '3.x read a digit string as year 179000');
    expect(three.stop.difference(three.start), const Duration(minutes: 30));
  });

  group('matching', () {
    EpgChannel guide(String id, String name) => EpgChannel(sourceId: 's', channelId: id, displayName: name);
    IptvChannel channel(String name, {String? tvgId, String id = 'c'}) => IptvChannel(
      id: id,
      playlistId: 'p',
      entry: IptvEntry(name: name, streamUrl: 'http://f/$id', tvgId: tvgId),
    );

    test('import index: tvg-id, exact name, unique containment, never by row order', () {
      final index = GuideIndex([
        guide('cctv1', 'CCTV-1 综合'),
        guide('cctv13', 'CCTV-13'),
        guide('dup', 'Dup'),
        guide('dup2', 'DUP'),
        guide('blank', '***'),
      ]);
      expect(index.match(channel('x', tvgId: 'CCTV1')), epgChannelKey('s', 'cctv1'));
      expect(index.match(channel('CCTV-13')), epgChannelKey('s', 'cctv13'));
      expect(index.match(channel('dup')), isNull);
      expect(index.match(channel('CCTV')), isNull, reason: 'contained in two names');
      expect(index.match(channel('***')), isNull);
    });

    test('rebuild keeps locked and hand-made mappings and prunes stale automatic ones', () {
      final channels = [channel('CCTV-13', id: 'a'), channel('Nothing', id: 'b'), channel('Mine')];
      final previous = [
        const EpgMapping(channelId: 'b', playlistId: 'p', epgChannelKey: 'old', epgSourceId: 's'),
        const EpgMapping(channelId: 'c', playlistId: 'p', epgChannelKey: 'k', epgSourceId: 's', origin: 'manual'),
      ];
      final result = rebuildMappings(
        playlistId: 'p',
        sourceId: 's',
        channels: channels,
        guideChannels: [guide('cctv13', 'CCTV-13'), guide('mine', 'Mine')],
        previous: previous,
      );
      expect(result.upserts.single.channelId, 'a');
      expect(result.deletes.single.channelId, 'b');
      final none = rebuildMappings(
        playlistId: 'p',
        sourceId: 's',
        channels: channels,
        guideChannels: const [],
        previous: previous,
      );
      expect(none.upserts, isEmpty);
      expect(none.deletes, isEmpty);
    });

    test('room resolution: mapping, tvg-id, perfect name, then fuzzy; empty names never match', () {
      final guides = [guide('1', 'CCTV-1 综合'), guide('11', 'CCTV-11'), guide('blank', '***'), guide('hd', '高清')];
      String? resolve(IptvChannel c, {EpgMapping? mapping}) =>
          resolveGuideChannel(channel: c, sourceId: 's', guideChannels: guides, mapping: mapping);
      expect(resolve(channel('CCTV-1 高清')), epgChannelKey('s', '1'));
      expect(resolve(channel('?', tvgId: 'CCTV11')), isNull);
      expect(resolve(channel('?', tvgId: '11')), epgChannelKey('s', '11'));
      expect(resolve(channel('频道')), isNull, reason: '3.x matched every guide channel');
      const locked = EpgMapping(channelId: 'c', playlistId: 'p', epgChannelKey: 'gone', epgSourceId: 's', locked: true);
      expect(resolve(channel('CCTV-1'), mapping: locked), isNull);
      const raw = EpgMapping(channelId: 'c', playlistId: 'p', epgChannelKey: '11', epgSourceId: 's');
      expect(resolve(channel('CCTV-1'), mapping: raw), epgChannelKey('s', '11'));
      expect(resolveGuideChannel(channel: channel('CCTV-1'), sourceId: '', guideChannels: guides), isNull);
    });

    test('Dice coefficient matches string_similarity', () {
      expect(diceCoefficient('night', 'nacht'), 0.25);
      expect(diceCoefficient('a', 'a'), 1);
      expect(fuzzyScore('cctv 1', 'CCTV-1 综合'), 2);
    });
  });
}
