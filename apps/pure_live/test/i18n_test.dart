import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/i18n/i18n.dart';

import 'support.dart';

void main() {
  test("3.x's translation files are kept and differ only by four keys", () {
    Map<String, Object?> read(String code) =>
        jsonDecode(File('assets/translations/$code.json').readAsStringSync()) as Map<String, Object?>;
    final zh = read('zh');
    final en = read('en');
    expect(zh.length, greaterThan(2000));
    expect(zh.keys.toSet().difference(en.keys.toSet()), {'count_wan', 'videofit_scaleDown'});
    expect(en.keys.toSet().difference(zh.keys.toSet()), {'count_k', 'double_click_to_exit'});
  });

  test('i18n reads the current language, fills named arguments and falls back', () async {
    await loadStrings();
    expect(i18n('favorites_title'), '关注');
    expect(i18n('auto_close_time', args: {'time': '5'}), '自动关闭时间: 5分钟');
    // Missing in Chinese: the English text instead of the raw key (3.x showed the key).
    expect(i18n('double_click_to_exit'), isNot('double_click_to_exit'));
    expect(i18n('no_such_key'), 'no_such_key');
    expect(i18nOr('no_such_key', 'fallback'), 'fallback');
    expect(i18nExists('menu'), isTrue);

    await loadStrings(AppLanguage.en);
    expect(i18n('favorites_title'), isNot('关注'));
    expect(i18n('count_wan'), isNotEmpty);
  });

  test('the language: the stored choice, else the device, else Chinese', () {
    expect(AppLanguage.resolve(stored: 'English', preferred: const [Locale('zh')]), AppLanguage.en);
    expect(AppLanguage.resolve(stored: '简体中文', preferred: const [Locale('en', 'US')]), AppLanguage.zh);
    // Never chosen: 3.x's easy_localization followed the device.
    expect(AppLanguage.resolve(stored: null, preferred: const [Locale('en', 'US')]), AppLanguage.en);
    expect(AppLanguage.resolve(stored: null, preferred: const [Locale('ja'), Locale('zh', 'TW')]), AppLanguage.zh);
    expect(AppLanguage.resolve(stored: null, preferred: const [Locale('ja')]), AppLanguage.zh);
    expect(AppLanguage.resolve(stored: 'Klingon', preferred: const [Locale('en')]), AppLanguage.en);
  });

  test("the shared widgets' words come from 3.x's keys", () async {
    final zh = await loadStrings();
    expect(zh.ui.retry, '重新加载');
    expect(zh.ui.emptyTitle, '暂无数据');
    final en = await loadStrings(AppLanguage.en);
    expect(en.ui.retry, 'Retry');
  });
}
