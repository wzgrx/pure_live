import 'package:live_iptv/live_iptv.dart';
import 'package:test/test.dart';

/// Guide channels shaped like the common Chinese guides.
const _guide = [
  IptvGuideChannel(id: 'CCTV1', names: ['CCTV1']),
  IptvGuideChannel(id: 'CCTV10', names: ['CCTV10']),
  IptvGuideChannel(id: 'CCTV4', names: ['CCTV4']),
  IptvGuideChannel(id: 'CCTV4K', names: ['CCTV4K']),
  IptvGuideChannel(id: 'CCTV5', names: ['CCTV5']),
  IptvGuideChannel(id: 'CCTV5+', names: ['CCTV5+']),
  IptvGuideChannel(id: 'hunan', names: ['湖南卫视']),
  IptvGuideChannel(id: 'dragon', names: ['东方卫视', 'Dragon TV']),
  IptvGuideChannel(id: 'news-a', names: ['新闻频道']),
  IptvGuideChannel(id: 'news-b', names: ['新闻']),
  IptvGuideChannel(id: 'dup1', names: ['凤凰中文']),
  IptvGuideChannel(id: 'dup2', names: ['凤凰中文']),
];

void main() {
  final matcher = GuideMatcher(_guide);
  String? match(String name, {String? tvgId, String? tvgName}) =>
      matcher.match(name: name, tvgId: tvgId, tvgName: tvgName);

  test('normalisation', () {
    expect(normalizeChannelName('CCTV-1 综合 HD'), 'cctv1综合');
    expect(normalizeChannelName('ＣＣＴＶ－１（高清）'), 'cctv1');
    expect(normalizeChannelName('CCTV-5+ 体育赛事'), 'cctv5plus体育赛事');
    expect(normalizeChannelName('CCTV1HD'), 'cctv1');
    expect(normalizeChannelName('湖南卫视 高清'), '湖南卫视');
    expect(normalizeChannelName('湖南卫视[1080p]'), '湖南卫视');
    expect(normalizeChannelName('CCTV-4K 超高清'), 'cctv4k');
    expect(normalizeChannelName('Dragon TV FHD'), 'dragontv');
    expect(channelCode('cctv1综合'), 'cctv1');
    expect(channelCode('cctv5plus体育赛事'), 'cctv5plus');
    expect(channelCode('湖南卫视'), isNull);
    expect(channelCode('cctv4k'), isNull);
  });

  test('tvg-id first, case-insensitively', () {
    expect(match('whatever', tvgId: 'cctv10'), 'CCTV10');
    expect(match('CCTV-1', tvgId: 'unknown-id'), 'CCTV1');
  });

  test('names: exact after normalisation, then the channel code', () {
    expect(match('CCTV-1 综合'), 'CCTV1');
    expect(match('CCTV-10 科教'), 'CCTV10');
    expect(match('CCTV-5+ 体育赛事'), 'CCTV5+');
    expect(match('CCTV5 体育'), 'CCTV5');
    expect(match('CCTV-4K'), 'CCTV4K');
    expect(match('湖南卫视 HD'), 'hunan');
    expect(match('Dragon TV'), 'dragon');
    expect(match('随便', tvgName: '东方卫视'), 'dragon');
  });

  test('containment keeps numbers whole and needs a unique answer', () {
    expect(match('湖南卫视国际'), 'hunan');
    // `新闻频道` and `新闻` both normalise to `新闻`: ambiguous.
    expect(match('新闻'), isNull);
    // `cctv1` must not be read as `cctv10` or `cctv1…plus`.
    expect(
      GuideMatcher(const [
        IptvGuideChannel(id: 'x', names: ['CCTV10']),
      ]).match(name: 'CCTV1'),
      isNull,
    );
    expect(
      GuideMatcher(const [
        IptvGuideChannel(id: 'x', names: ['CCTV4K']),
      ]).match(name: 'CCTV4'),
      isNull,
    );
  });

  test('ambiguous answers match nothing, whatever the guide order', () {
    expect(match('凤凰中文'), isNull);
    final reversed = GuideMatcher(_guide.reversed);
    expect(reversed.match(name: '凤凰中文'), isNull);
    expect(reversed.match(name: 'CCTV-1 综合'), 'CCTV1');
    expect(match('完全不认识的频道'), isNull);
  });
}
