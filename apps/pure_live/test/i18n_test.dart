import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/i18n/i18n.dart';

import 'support.dart';

Map<String, Object?> read(String code) =>
    jsonDecode(File('assets/translations/$code.json').readAsStringSync()) as Map<String, Object?>;

void main() {
  test("3.x's translation files are kept and differ only by four keys", () {
    final zh = read('zh');
    final en = read('en');
    expect(zh.length, greaterThan(2000));
    expect(zh.keys.toSet().difference(en.keys.toSet()), {'count_wan', 'videofit_scaleDown'});
    expect(en.keys.toSet().difference(zh.keys.toSet()), {'count_k', 'double_click_to_exit'});
  });

  test('F.5a: every key the app asks i18n for is translated (old keys were removed)', () {
    final zh = read('zh');
    final en = read('en');
    final pattern = RegExp(r"\bi18n\(\s*'([A-Za-z0-9_.]+)'");
    final missing = <String>{
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart'))
          for (final match in pattern.allMatches(file.readAsStringSync()))
            if (!zh.containsKey(match.group(1)) && !en.containsKey(match.group(1))) '${match.group(1)} (${file.path})',
    };
    expect(missing, isEmpty);
  });

  test('F.5a: the directory and audience notes are words for users, not field names', () {
    final jargon = RegExp(r'\b[a-z]+[A-Z]\w*|\b\w+_\w+');
    for (final code in ['zh', 'en']) {
      for (final MapEntry(:key, :value) in read(code).entries) {
        final note = key.endsWith('_directory_scope') || (key.startsWith('audience_') && key.endsWith('_detail'));
        if (note) expect(jargon.firstMatch('$value')?.group(0), isNull, reason: '$code $key');
      }
    }
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
    // P02: the refresh header's words, set right (U.1c c19: 3.x said "上拉刷新").
    expect(
      [zh.ui.refreshPull, zh.ui.refreshRelease, zh.ui.refreshRefreshing, zh.ui.refreshSucceeded, zh.ui.refreshFailed],
      ['下拉刷新', '松开刷新', '正在刷新...', '刷新成功', '刷新失败'],
    );
    expect(zh.ui.refreshLastTime, '上次刷新时间 {time}');
    final en = await loadStrings(AppLanguage.en);
    expect(en.ui.retry, 'Retry');
    expect(en.ui.refreshPull, 'Pull to refresh');
  });
}
