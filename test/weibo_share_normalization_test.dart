import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/core/site/weibo/weibo_link.dart';

void main() {
  const watch = 'https://weibo.com/l/wblive/p/show/1022:2321325000000000000000';
  for (final suffix in ['/.', '/..']) {
    test('Weibo share punctuation preserves structural suffix $suffix', () {
      final input = '$watch$suffix';
      expect(WeiboLink.parse(input), isNull);
      final extracted = LiveUrlTool.sharedHttpUrls('直播 $input').single;
      expect(extracted, input);
      expect(WeiboLink.parse(extracted), isNull);
    });
  }
  test('Weibo Chinese share prose is separated without truncating the ID colon', () {
    expect(LiveUrlTool.sharedHttpUrls('直播：$watch。打开应用观看').single, watch);
  });

  for (final host in ['weibo.com', 'www.weibo.com']) {
    for (final suffix in ['/..)', '/.。继续观看', '/.?from=share', '/..#section', '/%2e']) {
      test('Weibo extraction keeps invalid route structure on $host: $suffix', () {
        final input = watch.replaceFirst('weibo.com', host) + suffix;
        expect(WeiboLink.parse(input), isNull);
        final extracted = LiveUrlTool.sharedHttpUrls('直播 $input').single;
        expect(WeiboLink.parse(extracted), isNull);
      });
    }
  }

  for (final url in [
    watch,
    watch.replaceFirst('https://weibo.com', 'HTTPS://WWW.WEIBO.COM'),
    watch.replaceFirst('https://weibo.com', 'http://weibo.com:80'),
    watch.replaceFirst('/p/show/', '/m/show/').replaceFirst('1022:', '1022%3a'),
    'https://weibo.com/l/wblive/p/show/1042152:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ]) {
    test('Weibo share punctuation retains exact broadcast identity: $url', () {
      final expectedId = WeiboLink.parse(url);
      expect(expectedId, isNotNull);
      for (final punctuation in ['。打开应用观看', '，复制本条信息', ')', '.']) {
        final extracted = LiveUrlTool.sharedHttpUrls('分享 $url$punctuation').single;
        expect(extracted, url);
        expect(WeiboLink.parse(extracted), expectedId);
      }
    });
  }

  test('Weibo share extraction preserves escaped query spelling', () {
    final url = '$watch?token=a%2Fb%3D%3d&next=%EF%BC%8C%3A#part';
    expect(LiveUrlTool.sharedHttpUrls('分享 $url。打开应用观看').single, url);
    expect(WeiboLink.parse(url), WeiboLink.parse(watch));
  });
}
