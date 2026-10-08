import 'package:flutter/material.dart';

/// The named text styles of 3.x (`AppTextStyles.t13`, `t15SemiBold`, ...),
/// read from the theme in scope.
///
/// 3.x computed them from `Get.theme` and the font settings singleton; here
/// they come from [Theme.of], whose text theme already carries the font
/// sizes (see `LiveTheme`), so a widget that reads them rebuilds when the
/// theme or the sizes change, and a local [Theme] override is honoured.
///
/// The names keep 3.x's pairs that share a size: `t11`/`t12` are both the
/// small body size, `t15`/`t16` the card title size, `t18`/`t20` the app bar
/// title size. Weights are 400 and 600 only (UI.md §8.2, A01.2): 3.x's
/// `*Medium` (500) and `*Bold` (700, 800) are gone; use the plain style or
/// its `*SemiBold` / `.emphasis` form.
///
/// ```dart
/// Text(title, style: context.textStyles.t15SemiBold)
/// ```
@immutable
final class AppTextStyles {
  /// Styles of [theme].
  const new(this.theme);

  /// Styles of the theme in scope.
  factory of(BuildContext context) => AppTextStyles(Theme.of(context));

  /// The theme the styles come from.
  final ThemeData theme;

  TextTheme get _base => theme.textTheme;
  ColorScheme get _colors => theme.colorScheme;

  // Small helper text (bodySmall).

  /// Small helper text.
  TextStyle get t11 => _base.bodySmall ?? const TextStyle();

  /// [t11], faint hint colour.
  TextStyle get t11Muted => t11.copyWith(color: theme.hintColor.withValues(alpha: 0.6));

  /// [t11], primary colour, semi-bold.
  TextStyle get t11Primary => t11.copyWith(color: _colors.primary, fontWeight: FontWeight.w600);

  /// Small helper text (same size as [t11]).
  TextStyle get t12 => _base.bodySmall ?? const TextStyle();

  /// [t12], hint colour.
  TextStyle get t12Muted => t12.copyWith(color: theme.hintColor);

  /// [t12], primary colour, semi-bold.
  TextStyle get t12Primary => t12.copyWith(color: _colors.primary, fontWeight: FontWeight.w600);

  /// [t12], error colour.
  TextStyle get t12Error => t12.copyWith(color: _colors.error);

  // Body text (bodyMedium).

  /// Body text.
  TextStyle get t13 => _base.bodyMedium ?? const TextStyle();

  /// [t13], semi-bold.
  TextStyle get t13SemiBold => t13.copyWith(fontWeight: FontWeight.w600);

  /// [t13], hint colour.
  TextStyle get t13Muted => t13.copyWith(color: theme.hintColor);

  /// [t13], primary colour.
  TextStyle get t13Primary => t13.copyWith(color: _colors.primary);

  // Emphasised body text (bodyLarge).

  /// Emphasised body text.
  TextStyle get t14 => _base.bodyLarge ?? const TextStyle();

  /// [t14], semi-bold.
  TextStyle get t14SemiBold => t14.copyWith(fontWeight: FontWeight.w600);

  /// [t14], hint colour.
  TextStyle get t14Muted => t14.copyWith(color: theme.hintColor);

  /// [t14], primary colour.
  TextStyle get t14Primary => t14.copyWith(color: _colors.primary);

  // Card titles (titleMedium).

  /// Card titles.
  TextStyle get t15 => _base.titleMedium ?? const TextStyle();

  /// [t15], semi-bold.
  TextStyle get t15SemiBold => t15.copyWith(fontWeight: FontWeight.w600);

  /// [t15], primary colour, semi-bold.
  TextStyle get t15Primary => t15.copyWith(color: _colors.primary, fontWeight: FontWeight.w600);

  /// Card titles (same size as [t15]).
  TextStyle get t16 => _base.titleMedium ?? const TextStyle();

  /// [t16], semi-bold.
  TextStyle get t16SemiBold => t16.copyWith(fontWeight: FontWeight.w600);

  /// [t16], primary colour.
  TextStyle get t16Primary => t16.copyWith(color: _colors.primary);

  // App bar titles (titleLarge).

  /// App bar titles.
  TextStyle get t18 => _base.titleLarge ?? const TextStyle();

  /// App bar titles (same size as [t18]).
  TextStyle get t20 => _base.titleLarge ?? const TextStyle();
}

/// `context.textStyles.t13`: the [AppTextStyles] of the theme in scope.
extension AppTextStylesContext on BuildContext {
  /// The named text styles of the theme in scope.
  AppTextStyles get textStyles => AppTextStyles.of(this);
}

/// The system's text size times the app's "文字大小" (U.6b C-5): 3.x
/// replaced the system size with its own factor, so a larger system font did
/// nothing inside the app. Keeps the system's (possibly non-linear) curve.
final class AppTextScaler extends TextScaler {
  /// [system] scaled by [factor].
  const new(this.system, this.factor);

  /// The platform's scaler (`MediaQuery.textScalerOf`).
  final TextScaler system;

  /// The app's factor (`textScaleFactor`, 0.5–2).
  final double factor;

  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;

  @override
  // The interface still requires it; it is the linear equivalent.
  // ignore: deprecated_member_use
  double get textScaleFactor => system.textScaleFactor * factor;

  @override
  bool operator ==(Object other) => other is AppTextScaler && other.system == system && other.factor == factor;

  @override
  int get hashCode => Object.hash(system, factor);
}
