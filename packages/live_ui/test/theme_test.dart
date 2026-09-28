import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
  test('Android names no font family anywhere: the system font, vendor fonts included (principles §2.3)', () {
    final theme = PureTheme.of(Appearance.light, platform: TargetPlatform.android);
    final styles = [
      theme.textTheme.bodyMedium,
      theme.textTheme.titleLarge,
      theme.textTheme.labelMedium,
      theme.primaryTextTheme.bodyMedium,
      theme.appBarTheme.titleTextStyle,
      theme.chipTheme.labelStyle,
      theme.navigationBarTheme.labelTextStyle!.resolve(const {}),
      theme.navigationRailTheme.selectedLabelTextStyle,
    ];
    for (final style in styles) {
      expect(style!.fontFamily, isNull, reason: '$style');
    }
    expect(theme.textTheme.bodyMedium!.fontFamilyFallback, isNotEmpty, reason: 'CJK fallbacks stay');
  });

  test('generated colour tokens match spec/design/tokens.json', () {
    final result = Process.runSync('python3', ['tool/generate_tokens.py', '--check']);
    expect(result.exitCode, 0, reason: 'run python3 packages/live_ui/tool/generate_tokens.py');
  });

  test('themes map the tokens and keep the semantic colours apart from the brand', () {
    final light = PureTheme.of(Appearance.light, platform: TargetPlatform.android);
    final black = PureTheme.of(Appearance.black, platform: TargetPlatform.android);
    expect(light.colorScheme.primary, ColorTokens.light.primary);
    expect(light.colorScheme.brightness, Brightness.light);
    expect(black.colorScheme.surface, const Color(0xFF000000));
    expect(black.colorScheme.primary, ColorTokens.dark.primary);
    expect(LiveThemeTester.of(light).live, FixedColors.live);
    expect(
      PureTheme.of(Appearance.dark, platform: TargetPlatform.windows).textTheme.bodyMedium!.fontFamily,
      'Microsoft YaHei UI',
    );
  });

  test('principles §2.3: text styles carry the language; Traditional Chinese uses JhengHei on Windows', () {
    const hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
    const hans = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
    final traditional = PureTheme.of(Appearance.light, platform: TargetPlatform.windows, locale: hant).textTheme;
    expect(traditional.bodyMedium!.fontFamily, 'Microsoft JhengHei UI');
    expect(traditional.bodyMedium!.fontFamilyFallback!.take(2), ['Microsoft JhengHei UI', 'Microsoft JhengHei']);
    expect(traditional.bodyMedium!.locale, hant);
    final simplified = PureTheme.of(Appearance.light, platform: TargetPlatform.windows, locale: hans).textTheme;
    expect(simplified.titleLarge!.fontFamily, 'Microsoft YaHei UI');
    expect(simplified.titleLarge!.locale, hans);
    // A downloaded font still wins; the Traditional fallbacks stay behind it.
    final custom = PureTheme.tv(
      Appearance.dark,
      platform: TargetPlatform.windows,
      fontFamily: 'Noto Sans TC',
      locale: hant,
    );
    expect(custom.textTheme.bodyMedium!.fontFamily, 'Noto Sans TC');
    expect(custom.textTheme.bodyMedium!.fontFamilyFallback!.first, 'Microsoft JhengHei UI');
    expect(PureTheme.isTraditionalChinese(const Locale('zh', 'TW')), isTrue);
    expect(PureTheme.isTraditionalChinese(const Locale('zh', 'CN')), isFalse);
    expect(PureTheme.isTraditionalChinese(const Locale('en')), isFalse);
  });

  test('principles §2.2: a dynamic seed recolours the roles, keeps error colours and pure black', () {
    const seed = Color(0xFF2EA043);
    final brand = PureTheme.of(Appearance.light);
    final seeded = PureTheme.of(Appearance.light, seed: seed);
    expect(seeded.colorScheme.primary, isNot(brand.colorScheme.primary));
    expect(seeded.colorScheme.error, brand.colorScheme.error);
    final black = PureTheme.of(Appearance.black, seed: seed);
    expect(black.colorScheme.surface, PureTheme.of(Appearance.black).colorScheme.surface);
    expect(black.colorScheme.primary, isNot(PureTheme.of(Appearance.black).colorScheme.primary));
  });

  typeScaleTests();
}

void typeScaleTests() {
  test('principles §2.3: every text style has a line height of at least 1.4 times its size, rounded to even', () {
    for (final (name, theme) in [
      ('phone', PureTheme.of(Appearance.light, platform: TargetPlatform.android)),
      ('windows', PureTheme.of(Appearance.dark, platform: TargetPlatform.windows)),
      ('tv', PureTheme.tv(Appearance.dark, platform: TargetPlatform.android)),
    ]) {
      final text = theme.textTheme;
      final styles = {
        'displayLarge': text.displayLarge,
        'displayMedium': text.displayMedium,
        'displaySmall': text.displaySmall,
        'headlineLarge': text.headlineLarge,
        'headlineMedium': text.headlineMedium,
        'headlineSmall': text.headlineSmall,
        'titleLarge': text.titleLarge,
        'titleMedium': text.titleMedium,
        'titleSmall': text.titleSmall,
        'bodyLarge': text.bodyLarge,
        'bodyMedium': text.bodyMedium,
        'bodySmall': text.bodySmall,
        'labelLarge': text.labelLarge,
        'labelMedium': text.labelMedium,
        'labelSmall': text.labelSmall,
      };
      for (final MapEntry(key: role, value: style) in styles.entries) {
        final size = style!.fontSize!;
        final line = (size * style.height!).round();
        expect(size, greaterThanOrEqualTo(12), reason: '$name $role: 12 sp at least');
        expect(line, greaterThanOrEqualTo(size * 1.4), reason: '$name $role: $size/$line');
        expect(line.isEven, isTrue, reason: '$name $role: $size/$line');
      }
    }
    final phone = PureTheme.of(Appearance.light, platform: TargetPlatform.android).textTheme;
    expect((phone.labelSmall!.fontSize!, (phone.labelSmall!.fontSize! * phone.labelSmall!.height!).round()), (12, 18));
    expect(
      (phone.headlineLarge!.fontSize!, (phone.headlineLarge!.fontSize! * phone.headlineLarge!.height!).round()),
      (32, 46),
    );
  });

  test('numeric adds tabular figures and keeps the size and weight of the text it sits in', () {
    final text = PureTheme.of(Appearance.light, platform: TargetPlatform.android).textTheme;
    final figure = LiveTheme.numeric(text.bodySmall!);
    expect(figure.fontFeatures, [const FontFeature.tabularFigures()]);
    expect(figure.fontWeight, text.bodySmall!.fontWeight);
    expect(figure.fontSize, text.bodySmall!.fontSize);
    expect(LiveTheme.tabularFigures.fontWeight, isNull, reason: 'merges into the surrounding style');
    expect(LiveTheme.tabularFigures.fontSize, isNull);
  });

  test('principles §2.4: inputs and the search box are r2; sliders draw no tick marks', () {
    for (final theme in [
      PureTheme.of(Appearance.light, platform: TargetPlatform.android),
      PureTheme.tv(Appearance.dark, platform: TargetPlatform.android),
    ]) {
      final border = theme.inputDecorationTheme.border! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(Radii.r2));
      final shape = theme.searchBarTheme.shape!.resolve(const {})! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(Radii.r2));
      expect(theme.sliderTheme.tickMarkShape, SliderTickMarkShape.noTickMark);
    }
    final tvFocus = PureTheme.tv(Appearance.dark).inputDecorationTheme.focusedBorder! as OutlineInputBorder;
    expect(tvFocus.borderRadius, BorderRadius.circular(Radii.r2));
  });
}

extension LiveThemeTester on LiveTheme {
  static LiveTheme of(ThemeData theme) => theme.extension<LiveTheme>()!;
}
