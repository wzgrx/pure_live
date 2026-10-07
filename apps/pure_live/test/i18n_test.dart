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

  test('A01.4 c3: status page titles have no full stop; their explanations are sentences with one', () {
    final zh = read('zh');
    final en = read('en');
    final titles = <String>{
      for (final key in zh.keys)
        if (key.endsWith('_empty_title')) key,
    };
    final explanations = <String>{'status_empty_subtitle'};
    final call = RegExp(r'AppStatusView(?:\.\w+)?\(');
    final title = RegExp(r"(?<!sub)title:\s*i18n\(\s*'([a-z0-9_]+)'");
    final subtitle = RegExp(r"subtitle:\s*i18n\(\s*'([a-z0-9_]+)'");
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in call.allMatches(source)) {
        // The call's arguments, up to its closing bracket.
        var depth = 1;
        var end = match.end;
        while (end < source.length && depth > 0) {
          final char = source[end++];
          if (char == '(') depth++;
          if (char == ')') depth--;
        }
        final arguments = source.substring(match.end, end);
        titles.addAll(title.allMatches(arguments).map((found) => found.group(1)!));
        explanations.addAll(subtitle.allMatches(arguments).map((found) => found.group(1)!));
      }
    }
    expect(titles, containsAll(['tags_empty_title', 'empty_favorite_title', 'search_no_results']));
    expect(explanations, containsAll(['empty_favorite_subtitle', 'search_start_desc']));
    for (final key in titles) {
      expect('${zh[key]}', isNot(endsWith('。')), reason: 'zh $key');
      expect('${en[key]}', isNot(endsWith('.')), reason: 'en $key');
    }
    for (final key in explanations) {
      expect('${zh[key]}', anyOf(endsWith('。'), endsWith('？'), endsWith('！')), reason: 'zh $key');
      expect('${en[key]}', anyOf(endsWith('.'), endsWith('?'), endsWith('!')), reason: 'en $key');
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
