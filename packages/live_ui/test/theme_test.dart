import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

void main() {
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
}

extension LiveThemeTester on LiveTheme {
  static LiveTheme of(ThemeData theme) => theme.extension<LiveTheme>()!;
}
