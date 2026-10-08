// Z05.2: the words the adapters write in Chinese, in the interface language.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/platform_texts.dart';

import '../support.dart';

Map<String, Object?> _read(String code) =>
    jsonDecode(File('assets/translations/$code.json').readAsStringSync()) as Map<String, Object?>;

final _cjk = RegExp('[\u3400-\u9fff\uff01-\uff5e]');

/// Every table as (where, Chinese text, key).
List<(String, String, String)> get _entries => [
  for (final MapEntry(:key, :value) in platformLineKeys.entries) ('line', key, value),
  for (final MapEntry(key: platform, value: table) in platformAreaKeys.entries)
    for (final MapEntry(:key, :value) in table.entries) ('area of $platform', key, value),
  for (final MapEntry(:key, :value) in qualityNameKeys.entries) ('quality', key, value),
];

void main() {
  test("every key is in both files, its Chinese text is the adapter's and its English is English", () {
    final zh = _read('zh');
    final en = _read('en');
    for (final (where, text, key) in _entries) {
      expect(zh[key], text, reason: '$where: zh $key');
      expect(en[key], isA<String>(), reason: '$where: en $key');
      expect(_cjk.hasMatch('${en[key]}'), isFalse, reason: '$where: en $key is not English');
    }
    // One key per text, one text per key.
    final keys = [for (final (_, _, key) in _entries) key];
    expect(keys.toSet(), hasLength(keys.length));
  });

  test("the tables cover the adapters' tables of words", () {
    final lines = platformLineKeys.keys.toSet();
    final qualities = qualityNameKeys.keys.toSet();
    Set<String> areas(String platform) => platformAreaKeys[platform]!.keys.toSet();
    Iterable<String> chinese(Iterable<String?> texts) => texts.whereType<String>().where(_cjk.hasMatch);
    expect(lines, containsAll(Fc2LiveApi.noticeText.values));
    expect(lines, containsAll(NiconicoApi.noticeText.values));
    expect(lines, containsAll(MissevanDanmakuProtocol.pkLines.values.toSet()));
    expect(lines, containsAll(MissevanDanmakuProtocol.pkResults.values));
    expect(lines, containsAll(chinese(MissevanDanmakuProtocol.globalPkLines.values)));
    expect(lines, containsAll(MissevanDanmakuProtocol.globalPkResults.values));
    expect(areas(SiteIds.chzzk), containsAll(ChzzkApi.categoryTypeNames.values));
    expect(areas(SiteIds.fc2Live), containsAll(Fc2LiveApi.areaNames.values));
    expect(areas(SiteIds.kick), containsAll(KickApi.categoryNames.values));
    expect(areas(SiteIds.niconico), containsAll(chinese(NiconicoApi.tabNames.values)));
    expect(areas(SiteIds.pandaLive), containsAll(PandaLiveApi.areaNames.values));
    expect(areas(SiteIds.seventeenLive), containsAll(SeventeenLiveApi.regions.values));
    expect(areas(SiteIds.seventeenLive), containsAll([for (final area in SeventeenLiveApi.areas) area.areaName]));
    expect(qualities, containsAll(chinese(TikTokApi.qualityNames.values)));
    expect(qualities, containsAll(chinese(SeventeenLiveApi.qualityNames.values)));
    expect(qualities, containsAll([for (final quality in LiveMeApi.qualityNames.values) quality.name]));
    expect(qualities, containsAll([for (final quality in Fc2LiveApi.tierQualities) quality.quality]));
  });

  test('English shows what the adapters wrote in English, the rest as it is; Chinese is unchanged', () async {
    const own = '主播公告：今晚八点开播';
    const notice = '${PandaLiveApi.adultNotice}\n$own';
    await loadStrings(AppLanguage.en);
    final en = _read('en');
    expect(platformNotice(notice), '${en['pandalive_adult_notice']}\n$own');
    expect(platformNotice(XiaohongshuApi.displayViewersNotice('1.2万')), contains('1.2万'));
    expect(_cjk.hasMatch(platformNotice(XiaohongshuApi.displayViewersNotice('12')).replaceAll('12', '')), isFalse);
    expect(platformNotice(own), own);
    expect(platformAreaName(SiteIds.pandaLive, PandaLiveApi.areaNames['talk']!), en['pandalive_category_talk']);
    // A domestic platform's own area of the same name stays.
    expect(platformAreaName(SiteIds.douyu, PandaLiveApi.areaNames['talk']!), PandaLiveApi.areaNames['talk']);
    expect(platformQualityName('原画'), en['quality_name_original']);
    expect(platformQualityName('原画 · FLV'), '${en['quality_name_original']} · FLV');
    expect(platformQualityName('蓝光4M'), '蓝光4M');

    await loadStrings();
    expect(platformNotice(notice), notice);
    for (final (where, text, _) in _entries) {
      final shown = switch (where) {
        'line' => platformNotice(text),
        'quality' => platformQualityName(text),
        _ => platformAreaName(where.substring('area of '.length), text),
      };
      expect(shown, text, reason: where);
    }
  });
}
