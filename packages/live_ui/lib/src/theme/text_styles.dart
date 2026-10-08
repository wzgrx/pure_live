import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The named text styles of 3.x (`AppTextStyles.t13`, `t15Bold`, ...), read
/// from the theme in scope.
///
/// 3.x computed them from `Get.theme` and the font settings singleton; here
/// they come from [Theme.of], whose text theme already carries the font
/// sizes (see `LiveTheme`), so a widget that reads them rebuilds when the
/// theme or the sizes change, and a local [Theme] override is honoured.
///
/// The names keep 3.x's pairs that share a size: `t11`/`t12` are both the
/// small body size, `t15`/`t16` the card title size, `t18`/`t20` the app bar
/// title size.
///
/// ```dart
/// Text(title, style: context.textStyles.t15Bold)
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

  /// [t11], medium.
  TextStyle get t11Medium => t11.copyWith(fontWeight: FontWeight.w500);

  /// [t11], bold.
  TextStyle get t11Bold => t11.copyWith(fontWeight: FontWeight.w700);

  /// [t11], faint hint colour.
  TextStyle get t11Muted => t11.copyWith(color: theme.hintColor.withValues(alpha: 0.6));

  /// [t11], primary colour, semi-bold.
  TextStyle get t11Primary => t11.copyWith(color: _colors.primary, fontWeight: FontWeight.w600);

  /// Small helper text (same size as [t11]).
  TextStyle get t12 => _base.bodySmall ?? const TextStyle();

  /// [t12], medium.
  TextStyle get t12Medium => t12.copyWith(fontWeight: FontWeight.w500);

  /// [t12], bold.
  TextStyle get t12Bold => t12.copyWith(fontWeight: FontWeight.w700);

  /// [t12], hint colour.
  TextStyle get t12Muted => t12.copyWith(color: theme.hintColor);

  /// [t12], primary colour, semi-bold.
  TextStyle get t12Primary => t12.copyWith(color: _colors.primary, fontWeight: FontWeight.w600);

  /// [t12], error colour.
  TextStyle get t12Error => t12.copyWith(color: _colors.error);

  // Body text (bodyMedium).

  /// Body text.
  TextStyle get t13 => _base.bodyMedium ?? const TextStyle();

  /// [t13], medium.
  TextStyle get t13Medium => t13.copyWith(fontWeight: FontWeight.w500);

  /// [t13], semi-bold.
  TextStyle get t13SemiBold => t13.copyWith(fontWeight: FontWeight.w600);

  /// [t13], bold.
  TextStyle get t13Bold => t13.copyWith(fontWeight: FontWeight.w700);

  /// [t13], hint colour.
  TextStyle get t13Muted => t13.copyWith(color: theme.hintColor);

  /// [t13], primary colour.
  TextStyle get t13Primary => t13.copyWith(color: _colors.primary);

  // Emphasised body text (bodyLarge).

  /// Emphasised body text.
  TextStyle get t14 => _base.bodyLarge ?? const TextStyle();

  /// [t14], medium.
  TextStyle get t14Medium => t14.copyWith(fontWeight: FontWeight.w500);

  /// [t14], semi-bold.
  TextStyle get t14SemiBold => t14.copyWith(fontWeight: FontWeight.w600);

  /// [t14], bold.
  TextStyle get t14Bold => t14.copyWith(fontWeight: FontWeight.w700);

  /// [t14], hint colour.
  TextStyle get t14Muted => t14.copyWith(color: theme.hintColor);

  /// [t14], primary colour.
  TextStyle get t14Primary => t14.copyWith(color: _colors.primary);

  // Card titles (titleMedium).

  /// Card titles.
  TextStyle get t15 => _base.titleMedium ?? const TextStyle();

  /// [t15], medium.
  TextStyle get t15Medium => t15.copyWith(fontWeight: FontWeight.w500);

  /// [t15], semi-bold.
  TextStyle get t15SemiBold => t15.copyWith(fontWeight: FontWeight.w600);

  /// [t15], bold.
  TextStyle get t15Bold => t15.copyWith(fontWeight: FontWeight.w700);

  /// [t15], primary colour, semi-bold.
  TextStyle get t15Primary => t15.copyWith(color: _colors.primary, fontWeight: FontWeight.w600);

  /// Card titles (same size as [t15]).
  TextStyle get t16 => _base.titleMedium ?? const TextStyle();

  /// [t16], medium.
  TextStyle get t16Medium => t16.copyWith(fontWeight: FontWeight.w500);

  /// [t16], semi-bold.
  TextStyle get t16SemiBold => t16.copyWith(fontWeight: FontWeight.w600);

  /// [t16], bold.
  TextStyle get t16Bold => t16.copyWith(fontWeight: FontWeight.w700);

  /// [t16], primary colour.
  TextStyle get t16Primary => t16.copyWith(color: _colors.primary);

  // App bar titles (titleLarge).

  /// App bar titles.
  TextStyle get t18 => _base.titleLarge ?? const TextStyle();

  /// [t18], medium.
  TextStyle get t18Medium => t18.copyWith(fontWeight: FontWeight.w500);

  /// [t18], bold.
  TextStyle get t18Bold => t18.copyWith(fontWeight: FontWeight.w700);

  /// App bar titles (same size as [t18]).
  TextStyle get t20 => _base.titleLarge ?? const TextStyle();

  /// [t20], medium.
  TextStyle get t20Medium => t20.copyWith(fontWeight: FontWeight.w500);

  /// [t20], bold.
  TextStyle get t20Bold => t20.copyWith(fontWeight: FontWeight.w700);

  /// Headline: 1.2 × the app bar title size, bold.
  TextStyle get t24Bold => (_base.headlineSmall ?? const TextStyle()).copyWith(fontWeight: FontWeight.w700);

  /// Large headline: 1.6 × the app bar title size, extra bold.
  TextStyle get t32Bold => (_base.headlineLarge ?? const TextStyle()).copyWith(fontWeight: FontWeight.w800);
}

/// `context.textStyles.t13`: the [AppTextStyles] of the theme in scope.
extension AppTextStylesContext on BuildContext {
  /// The named text styles of the theme in scope.
  AppTextStyles get textStyles => AppTextStyles.of(this);
}

/// The most the app's text grows: the system's text size and the app's
/// "文字大小" together (A04.1, research V03.2 §3.3 D3). Both at 2× once came
/// to about 4×, and pages could not hold their words; 3.x also stopped at
/// 2× (its factor replaced the system's).
const double appTextScaleLimit = 2;

/// The system's text size times the app's "文字大小" (U.6b C-5): 3.x
/// replaced the system size with its own factor, so a larger system font did
/// nothing inside the app. Keeps the system's (possibly non-linear) curve,
/// and never grows a font more than [maxScale] times ([appTextScaleLimit]).
/// The picture's controls keep their own lower limit (1.3).
final class AppTextScaler extends TextScaler {
  /// [system] scaled by [factor], at most [maxScale] times.
  const new(this.system, this.factor, {this.maxScale = appTextScaleLimit});

  /// The platform's scaler (`MediaQuery.textScalerOf`).
  final TextScaler system;

  /// The app's factor (`textScaleFactor`, 0.5–2).
  final double factor;

  /// The most a font grows, both factors together.
  final double maxScale;

  @override
  double scale(double fontSize) => math.min(system.scale(fontSize) * factor, fontSize * maxScale);

  @override
  // The interface still requires it; it is the linear equivalent.
  // ignore: deprecated_member_use
  double get textScaleFactor => math.min(system.textScaleFactor * factor, maxScale);

  @override
  bool operator ==(Object other) =>
      other is AppTextScaler && other.system == system && other.factor == factor && other.maxScale == maxScale;

  @override
  int get hashCode => Object.hash(system, factor, maxScale);
}
