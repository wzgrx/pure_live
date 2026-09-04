import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart' as flutter;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as material;
import 'package:pure_live/common/styles/dynamic_color_adapter.dart';

void main() {
  test('dynamic color adapter preserves every Material 3 color role', () {
    final source = material.ColorScheme.fromSeed(
      seedColor: const flutter.Color(0xff6750a4),
      brightness: flutter.Brightness.dark,
    );
    final expected = source.harmonized();

    final actual = toFlutterColorScheme(source);

    expect(actual.brightness, expected.brightness);
    expect(actual.primary, expected.primary);
    expect(actual.onPrimary, expected.onPrimary);
    expect(actual.primaryContainer, expected.primaryContainer);
    expect(actual.onPrimaryContainer, expected.onPrimaryContainer);
    expect(actual.primaryFixed, expected.primaryFixed);
    expect(actual.primaryFixedDim, expected.primaryFixedDim);
    expect(actual.onPrimaryFixed, expected.onPrimaryFixed);
    expect(actual.onPrimaryFixedVariant, expected.onPrimaryFixedVariant);
    expect(actual.secondary, expected.secondary);
    expect(actual.onSecondary, expected.onSecondary);
    expect(actual.secondaryContainer, expected.secondaryContainer);
    expect(actual.onSecondaryContainer, expected.onSecondaryContainer);
    expect(actual.secondaryFixed, expected.secondaryFixed);
    expect(actual.secondaryFixedDim, expected.secondaryFixedDim);
    expect(actual.onSecondaryFixed, expected.onSecondaryFixed);
    expect(actual.onSecondaryFixedVariant, expected.onSecondaryFixedVariant);
    expect(actual.tertiary, expected.tertiary);
    expect(actual.onTertiary, expected.onTertiary);
    expect(actual.tertiaryContainer, expected.tertiaryContainer);
    expect(actual.onTertiaryContainer, expected.onTertiaryContainer);
    expect(actual.tertiaryFixed, expected.tertiaryFixed);
    expect(actual.tertiaryFixedDim, expected.tertiaryFixedDim);
    expect(actual.onTertiaryFixed, expected.onTertiaryFixed);
    expect(actual.onTertiaryFixedVariant, expected.onTertiaryFixedVariant);
    expect(actual.error, expected.error);
    expect(actual.onError, expected.onError);
    expect(actual.errorContainer, expected.errorContainer);
    expect(actual.onErrorContainer, expected.onErrorContainer);
    expect(actual.surface, expected.surface);
    expect(actual.onSurface, expected.onSurface);
    expect(actual.surfaceDim, expected.surfaceDim);
    expect(actual.surfaceBright, expected.surfaceBright);
    expect(actual.surfaceContainerLowest, expected.surfaceContainerLowest);
    expect(actual.surfaceContainerLow, expected.surfaceContainerLow);
    expect(actual.surfaceContainer, expected.surfaceContainer);
    expect(actual.surfaceContainerHigh, expected.surfaceContainerHigh);
    expect(actual.surfaceContainerHighest, expected.surfaceContainerHighest);
    expect(actual.onSurfaceVariant, expected.onSurfaceVariant);
    expect(actual.outline, expected.outline);
    expect(actual.outlineVariant, expected.outlineVariant);
    expect(actual.shadow, expected.shadow);
    expect(actual.scrim, expected.scrim);
    expect(actual.inverseSurface, expected.inverseSurface);
    expect(actual.onInverseSurface, expected.onInverseSurface);
    expect(actual.inversePrimary, expected.inversePrimary);
    expect(actual.surfaceTint, expected.surfaceTint);
  });

  test('reverse adapter preserves every Flutter Material 3 color role', () {
    final source = flutter.ColorScheme.fromSeed(
      seedColor: const flutter.Color(0xff006c4c),
      brightness: flutter.Brightness.dark,
    );

    final actual = toMaterialUiColorScheme(source);

    expect(actual.brightness, source.brightness);
    expect(actual.primary, source.primary);
    expect(actual.onPrimary, source.onPrimary);
    expect(actual.primaryContainer, source.primaryContainer);
    expect(actual.onPrimaryContainer, source.onPrimaryContainer);
    expect(actual.primaryFixed, source.primaryFixed);
    expect(actual.primaryFixedDim, source.primaryFixedDim);
    expect(actual.onPrimaryFixed, source.onPrimaryFixed);
    expect(actual.onPrimaryFixedVariant, source.onPrimaryFixedVariant);
    expect(actual.secondary, source.secondary);
    expect(actual.onSecondary, source.onSecondary);
    expect(actual.secondaryContainer, source.secondaryContainer);
    expect(actual.onSecondaryContainer, source.onSecondaryContainer);
    expect(actual.secondaryFixed, source.secondaryFixed);
    expect(actual.secondaryFixedDim, source.secondaryFixedDim);
    expect(actual.onSecondaryFixed, source.onSecondaryFixed);
    expect(actual.onSecondaryFixedVariant, source.onSecondaryFixedVariant);
    expect(actual.tertiary, source.tertiary);
    expect(actual.onTertiary, source.onTertiary);
    expect(actual.tertiaryContainer, source.tertiaryContainer);
    expect(actual.onTertiaryContainer, source.onTertiaryContainer);
    expect(actual.tertiaryFixed, source.tertiaryFixed);
    expect(actual.tertiaryFixedDim, source.tertiaryFixedDim);
    expect(actual.onTertiaryFixed, source.onTertiaryFixed);
    expect(actual.onTertiaryFixedVariant, source.onTertiaryFixedVariant);
    expect(actual.error, source.error);
    expect(actual.onError, source.onError);
    expect(actual.errorContainer, source.errorContainer);
    expect(actual.onErrorContainer, source.onErrorContainer);
    expect(actual.surface, source.surface);
    expect(actual.onSurface, source.onSurface);
    expect(actual.surfaceDim, source.surfaceDim);
    expect(actual.surfaceBright, source.surfaceBright);
    expect(actual.surfaceContainerLowest, source.surfaceContainerLowest);
    expect(actual.surfaceContainerLow, source.surfaceContainerLow);
    expect(actual.surfaceContainer, source.surfaceContainer);
    expect(actual.surfaceContainerHigh, source.surfaceContainerHigh);
    expect(actual.surfaceContainerHighest, source.surfaceContainerHighest);
    expect(actual.onSurfaceVariant, source.onSurfaceVariant);
    expect(actual.outline, source.outline);
    expect(actual.outlineVariant, source.outlineVariant);
    expect(actual.shadow, source.shadow);
    expect(actual.scrim, source.scrim);
    expect(actual.inverseSurface, source.inverseSurface);
    expect(actual.onInverseSurface, source.onInverseSurface);
    expect(actual.inversePrimary, source.inversePrimary);
    expect(actual.surfaceTint, source.surfaceTint);
  });
}
