import 'package:live_core/live_core.dart';
import 'package:test/test.dart';

void main() {
  test("E05.4 c6: 3.x's stand-in names for JD, Kugou and Baidu, nothing else", () {
    expect(legacyPlaceholderNames, {
      SiteIds.jdLive: {'JD Live'},
      SiteIds.kugouLive: {'Kugou Live'},
      SiteIds.baiduLive: {'Baidu Live'},
    });
    for (final id in legacyPlaceholderNames.keys) {
      expect(SiteIds.isSupported(id), isTrue, reason: id);
    }
  });
}
