import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live_app/core/recording.dart';

void main() {
  test('F-REC-03: streamer names as pinyin folder names', () {
    expect(pinyinFolderName('张大仙'), 'zhangdaxian');
    expect(pinyinFolderName('Uzi乌兹'), 'uziwuzi');
    expect(pinyinFolderName('一条小团团OvO'), 'yitiaoxiaotuantuanovo');
    expect(pinyinFolderName('主播 123'), 'zhubo_123');
    expect(pinyinFolderName('繁體字'), 'fantizi');
    expect(pinyinFolderName('🎮'), 'unknown');
    expect(pinyinFolderName(''), 'unknown');
  });
}
