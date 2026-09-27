import 'dart:convert';
import 'dart:io';

import 'package:live_iptv/live_iptv.dart';
import 'package:test/test.dart';

/// An XMLTV excerpt in the shape of the common Chinese guides (e.xml): +0800
/// times, several display names, a programme without `stop`, CDATA, an
/// entity, a lang attribute and an undeclared channel.
const _xmltv = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE tv SYSTEM "xmltv.dtd">
<tv generator-info-name="fixture" source-info-url="https://epg.fixture/">
  <channel id="CCTV1">
    <display-name lang="zh">CCTV-1 综合</display-name>
    <display-name>CCTV1</display-name>
    <icon src="https://epg.fixture/cctv1.png"/>
  </channel>
  <channel id="hunan"><display-name>湖南卫视</display-name></channel>
  <channel id="empty"/>
  <programme start="20260927080000 +0800" stop="20260927090000 +0800" channel="CCTV1" catchup-id="https://vod.fixture/1">
    <title lang="zh">朝闻天下</title>
    <title lang="en">Morning News</title>
    <sub-title>第 1 集</sub-title>
    <desc><![CDATA[新闻 & 资讯]]></desc>
  </programme>
  <programme start="20260927090000 +0800" channel="CCTV1">
    <title>生活圈 &amp; 健康</title>
  </programme>
  <programme start="20260927100000 +0800" stop="20260927110000 +0800" channel="CCTV1">
    <title>新闻30分</title>
  </programme>
  <programme start="20260927100000 +0800" stop="20260927103000 +0800" channel="CCTV1">
    <title>重复的开始时间</title>
  </programme>
  <programme start="20260920100000 +0800" stop="20260920110000 +0800" channel="hunan">
    <title>一周前</title>
  </programme>
  <programme start="20260927200000" stop="20260927210000" channel="undeclared">
    <title>UTC time</title>
  </programme>
  <programme start="bad" stop="20260927210000" channel="hunan"><title>坏时间</title></programme>
  <programme start="20260927200000" stop="20260927210000" channel="hunan"></programme>
</tv>
''';

void main() {
  final from = DateTime.utc(2026, 9, 25);
  final to = DateTime.utc(2026, 9, 29);

  group('XMLTV', () {
    final guide = XmltvParser.parse(_xmltv, from: from, to: to);

    test('channels keep every display name and the icon; undeclared ids are added', () {
      expect(guide.channels.map((c) => c.id), ['CCTV1', 'hunan', 'empty', 'undeclared']);
      expect(guide.channels.first.names, ['CCTV-1 综合', 'CCTV1']);
      expect(guide.channels.first.icon, 'https://epg.fixture/cctv1.png');
    });

    test('programmes: zones, first title, CDATA, entities, missing stop, duplicates', () {
      final cctv1 = guide.programmes.where((p) => p.channelId == 'CCTV1').toList();
      expect(cctv1.map((p) => p.title), ['朝闻天下', '生活圈 & 健康', '新闻30分']);
      expect(cctv1.first.start, DateTime.utc(2026, 9, 27));
      expect(cctv1.first.stop, DateTime.utc(2026, 9, 27, 1));
      expect(cctv1.first.subtitle, '第 1 集');
      expect(cctv1.first.description, '新闻 & 资讯');
      expect(cctv1.first.catchupId, 'https://vod.fixture/1');
      // No stop: ends at the next programme.
      expect(cctv1[1].stop, DateTime.utc(2026, 9, 27, 2));
      final utc = guide.programmes.singleWhere((p) => p.channelId == 'undeclared');
      expect(utc.start, DateTime.utc(2026, 9, 27, 20));
    });

    test('the window drops old programmes; bad items are counted as issues', () {
      expect(guide.programmes.any((p) => p.title == '一周前'), isFalse);
      expect(guide.programmes.any((p) => p.title == '坏时间'), isFalse);
      expect(guide.issues.map((i) => i.reason), containsAll(['Programme with an invalid time', 'Duplicate programme']));
    });

    test('malformed markup is skipped, the rest still parses', () {
      final broken = XmltvParser.parse(
        '<tv><channel id="a"><display-name>A</display-name></channel><<<bad> '
        '<programme start="20260927080000 +0000" stop="20260927090000 +0000" channel="a"><title>T</title></programme></tv>',
      );
      expect(broken.channels.map((c) => c.id), contains('a'));
      expect(broken.programmes.single.title, 'T');
    });

    test('time formats', () {
      expect(parseXmltvTime('20260927200000 +0800'), DateTime.utc(2026, 9, 27, 12));
      expect(parseXmltvTime('20260927200000-0330'), DateTime.utc(2026, 9, 27, 23, 30));
      expect(parseXmltvTime('20260927200000 +08:00'), DateTime.utc(2026, 9, 27, 12));
      expect(parseXmltvTime('202609272000'), DateTime.utc(2026, 9, 27, 20));
      expect(parseXmltvTime('20260927200000Z'), DateTime.utc(2026, 9, 27, 20));
      expect(parseXmltvTime('20261327200000'), isNull);
      expect(parseXmltvTime(''), isNull);
    });

    test('gzip bytes (.xml.gz) are unpacked and the keep window applies', () {
      final bytes = gzip.encode(utf8.encode(_xmltv));
      final parsed = parseGuideBytes(bytes, now: DateTime.utc(2026, 9, 27, 12));
      expect(parsed.programmes.map((p) => p.title), containsAll(['朝闻天下', 'UTC time']));
      expect(parsed.programmes.any((p) => p.title == '一周前'), isFalse);
    });
  });

  group('JSON guide', () {
    test('channels and programmes with mixed time spellings', () {
      final guide = JsonGuideParser.parse(
        jsonEncode({
          'channels': [
            {'id': 'cctv1', 'name': 'CCTV1', 'icon': 'https://epg.fixture/1.png'},
            {
              'id': 'cctv2',
              'names': ['CCTV-2 财经', 'CCTV2'],
            },
          ],
          'programmes': [
            {'channel': 'cctv1', 'title': 'Seconds', 'start': 1790438400, 'stop': 1790442000},
            {'channelId': 'cctv1', 'title': 'Millis', 'start': 1790442000000, 'end': '1790445600000'},
            {'channel': 'cctv2', 'title': 'ISO', 'start': '2026-09-27T08:00:00+08:00', 'duration': 45},
            {'channel': 'cctv2', 'title': 'XMLTV', 'start': '20260927010000 +0000', 'stop': '20260927020000 +0000'},
            {'channel': 'cctv2', 'start': 1790438400},
          ],
        }),
      );
      expect(guide.channels.map((c) => c.id), ['cctv1', 'cctv2']);
      expect(guide.channels[1].names, ['CCTV-2 财经', 'CCTV2']);
      final byTitle = {for (final p in guide.programmes) p.title: p};
      expect(byTitle['Seconds']!.start, DateTime.utc(2026, 9, 26, 16));
      expect(byTitle['Millis']!.stop, DateTime.utc(2026, 9, 26, 18));
      expect(byTitle['ISO']!.start, DateTime.utc(2026, 9, 27));
      expect(byTitle['ISO']!.stop, DateTime.utc(2026, 9, 27, 0, 45));
      expect(byTitle['XMLTV']!.start, DateTime.utc(2026, 9, 27, 1));
      expect(guide.issues.single.reason, 'Programme without a title');
    });

    test('a DIYP day uses local clock times and wraps past midnight', () {
      final guide = JsonGuideParser.parse(
        jsonEncode({
          'channel_name': 'CCTV1',
          'date': '2026-09-27',
          'epg_data': [
            {'start': '08:00', 'end': '09:00', 'title': '朝闻天下', 'desc': '新闻'},
            {'start': '23:30', 'end': '00:00', 'title': '午夜'},
          ],
        }),
        local: (wall) => wall.subtract(const Duration(hours: 8)),
      );
      expect(guide.channels.single.names, ['CCTV1']);
      expect(guide.programmes.first.start, DateTime.utc(2026, 9, 27));
      expect(guide.programmes.first.description, '新闻');
      expect(guide.programmes.last.stop, DateTime.utc(2026, 9, 27, 16));
    });

    test('format detection', () {
      expect(parseGuide('  <tv></tv>').channels, isEmpty);
      expect(parseGuide('{"channels": []}').channels, isEmpty);
      expect(() => parseGuide('CCTV1,08:00,朝闻天下'), throwsFormatException);
    });
  });
}
