import 'dart:convert';
import 'dart:io';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live_app/app/locale.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// The translation sources (spec/product.md F-APP-06, PLAN §12): a missing
/// translation fails here, not in front of the user. The generated code has
/// no fallback (`fallback_strategy: none`), so a key missing from a locale
/// also fails `dart analyze` once the code is regenerated.
void main() {
  const locales = ['zh-Hans', 'zh-Hant', 'en'];
  final sources = {for (final locale in locales) locale: _leaves(locale)};

  test('F-APP-06: every locale has the same namespaces and keys', () {
    final namespaces = {
      for (final locale in locales)
        locale: Directory('lib/i18n/$locale').listSync().map((file) => file.uri.pathSegments.last).toSet(),
    };
    expect(namespaces['zh-Hant'], namespaces['zh-Hans']);
    expect(namespaces['en'], namespaces['zh-Hans']);
    final base = sources['zh-Hans']!.keys.toSet();
    expect(base.length, greaterThan(1000));
    for (final locale in locales.skip(1)) {
      final keys = sources[locale]!.keys.toSet();
      expect(base.difference(keys), isEmpty, reason: '$locale misses these keys');
      expect(keys.difference(base), isEmpty, reason: '$locale has keys the base locale lacks');
    }
  });

  test('F-APP-06: no text is empty and every plural has its "other" form', () {
    for (final locale in locales) {
      for (final MapEntry(:key, :value) in sources[locale]!.entries) {
        for (final text in _texts(value)) {
          expect(text.trim(), isNotEmpty, reason: '$locale $key');
        }
        if (value is Map) expect(value.containsKey('other'), isTrue, reason: '$locale $key');
      }
    }
  });

  test('F-APP-06: a key has the same placeholders in every locale', () {
    for (final MapEntry(:key, :value) in sources['zh-Hans']!.entries) {
      final expected = _placeholders(value);
      for (final locale in locales.skip(1)) {
        expect(_placeholders(sources[locale]![key]), expected, reason: '$locale $key');
      }
    }
  });

  test('F-APP-06: Traditional Chinese uses traditional characters, English no Chinese', () {
    final simplifiedOnly = RegExp('[$_simplifiedOnly]');
    final han = RegExp('[一-鿿]');
    for (final MapEntry(:key, :value) in sources['zh-Hant']!.entries) {
      if (key.startsWith('settings.languageNames')) continue;
      for (final text in _texts(value)) {
        expect(simplifiedOnly.allMatches(text).map((match) => match[0]), isEmpty, reason: 'zh-Hant $key: $text');
      }
    }
    for (final MapEntry(:key, :value) in sources['en']!.entries) {
      if (key.startsWith('settings.languageNames')) continue;
      for (final text in _texts(value)) {
        expect(han.hasMatch(text), isFalse, reason: 'en $key: $text');
      }
    }
  });

  test('F-APP-06: the generated code matches the sources (run `dart run slang` after editing them)', () {
    final temp = Directory.systemTemp.createTempSync('pure_live_slang');
    addTearDown(() => temp.deleteSync(recursive: true));
    File('slang.yaml').copySync('${temp.path}/slang.yaml');
    for (final locale in locales) {
      Directory('${temp.path}/lib/i18n/$locale').createSync(recursive: true);
      for (final file in Directory('lib/i18n/$locale').listSync().whereType<File>()) {
        file.copySync('${temp.path}/lib/i18n/$locale/${file.uri.pathSegments.last}');
      }
    }
    final packages = File('../../.dart_tool/package_config.json').absolute;
    final config = jsonDecode(packages.readAsStringSync()) as Map<String, Object?>;
    final slang = (config['packages']! as List<Object?>).cast<Map<String, Object?>>().firstWhere(
      (package) => package['name'] == 'slang',
    );
    // rootUri is absolute (pub cache) or relative to the config file.
    final root = packages.uri.resolve('${slang['rootUri']! as String}/');
    final generator = root.resolve('bin/slang.dart').toFilePath();
    final result = Process.runSync('dart', ['--packages=${packages.path}', generator], workingDirectory: temp.path);
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    for (final file in Directory('lib/i18n').listSync().whereType<File>().where((f) => f.path.endsWith('.g.dart'))) {
      final name = file.uri.pathSegments.last;
      expect(
        File('${temp.path}/lib/i18n/$name').readAsStringSync(),
        file.readAsStringSync(),
        reason: '$name is stale: run `dart run slang` in apps/pure_live',
      );
    }
  });

  test('every interface language is one Flutter localizes', () {
    for (final locale in AppLocale.values) {
      expect(kMaterialSupportedLanguages, contains(locale.languageCode));
      expect(GlobalMaterialLocalizations.delegate.isSupported(flutterLocaleOf(locale)), isTrue);
    }
  });
}

/// Every translation of [locale] by path (`namespace.key`, map entries as
/// `namespace.key[id]`); a plural is one leaf holding its forms.
Map<String, Object?> _leaves(String locale) {
  final out = <String, Object?>{};
  void walk(String prefix, Object? node) {
    if (node is! Map) {
      out[prefix] = node;
      return;
    }
    for (final MapEntry(key: rawKey, :value) in node.cast<String, Object?>().entries) {
      if (rawKey.startsWith('@')) continue;
      final path = '$prefix.$rawKey';
      if (rawKey.endsWith('(map)')) {
        for (final MapEntry(key: id, value: text) in (value! as Map).cast<String, Object?>().entries) {
          out['$path[$id]'] = text;
        }
      } else if (value is Map && value.keys.every(_pluralForms.contains)) {
        out[path] = value;
      } else {
        walk(path, value);
      }
    }
  }

  for (final file in Directory('lib/i18n/$locale').listSync().whereType<File>()) {
    final namespace = file.uri.pathSegments.last.split('.').first;
    walk(namespace, jsonDecode(file.readAsStringSync()));
  }
  return out;
}

const _pluralForms = {'zero', 'one', 'two', 'few', 'many', 'other'};

Iterable<String> _texts(Object? value) => switch (value) {
  final String text => [text],
  final List<Object?> list => list.isEmpty ? [''] : list.map((item) => '$item'),
  final Map<Object?, Object?> forms => forms.values.map((item) => '$item'),
  _ => [''],
};

Set<String> _placeholders(Object? value) => {
  for (final text in _texts(value))
    for (final match in RegExp(r'(?<!\\)\{([A-Za-z_][A-Za-z0-9_]*)\}').allMatches(text)) match[1]!,
};

/// Characters that exist only in the simplified script, common in interface
/// text; a Traditional Chinese translation never needs them.
const _simplifiedOnly =
    '这设频关载线网录号页链览应讯过时间为说们个来对会动还没让从认删导图话证标题请输择须当优选册码户帐账缓视听声连数据统义显读写击点热门闭无错误败进质画弹检测试换转传运营备复历记组绍产币购买卖价钱键盘'
    '务态签终变亿乐书两临举么亏亚众伤体侦储儿兑党兰兴养内冈况冻净减凤处创别剧劝办励劳势区医华协单卢卫厂厅压厌县参双发叙叶叹吓吗员响哑团园围国圆圣场坏块坚坛垒墙壮壳够头夹夺奋奖妆妈宁宝实宠审宪宽宾寻寿将尔'
    '尘层届岁岂岛岭帅师带帮广庄庆库庙废开异弃张弯归彻径忆忧怀总恋恶惊惧惯愿扑执扩扫扬扰报担拟拥拨挂挡挤挥损捡携摄摆摇敌断旧晋晒晓晕暂术机杀杂权条杨极构枪柜栏树样桥梦楼欢欧残毁毕气汇汉汤沟沪泪泽洁浅济浏浓涂'
    '涨渐温湾湿溃满滚滞滤滨潜灭灯灵灾灿炉炼烂烟烦烧爱爷状犹狭独猎献环现电畅疗疯盏盐监盖矿础确碍礼祸离种积称稳穷窃竞笔简类粮紧纠红约级纪纯纱纲纳纵纷纸纹练细织经结绕绘给络绝继绩续维绿编缘罗罚职联聪肃肠肤肿胀'
    '胆胜脑脚脱脸腾艺节芦苏苹茎荐药莱获萝蓝虑虚虫虽蚀补衬袜装见观规觉触计订讨训议讲论讽访评识诉诊词译诗诚询该详语谁调谈谊谋谎谓谢谨谱负贡财责货贩贫贯费贺资赏赔赖赚赛赞赠赢赵赶跃践踪车轨轮软轻较辆辉边达迁远'
    '违迟适递逻遗邮邻郑酱释针钉钟钢钥钩铁铃铜铝银铺销锁锅锦锻镇镜长闪问闲闷闹阅阔队阳阴阵阶际陆陈险随隐难雾静韩顶项顺顽顾顿预领颗颜额风飞饭饮饰饱饼馆马驱驶驻驾验骑骗鱼鲜鸟鸡鸣鸭鹅麦黄齐齿龙龟';
