import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:live_ui/src/theme/live_theme.dart';

/// Which screen size an appearance belongs to (3.x keeps one per size).
enum RoomCardViewport {
  /// Phones.
  mobile,

  /// Tablets and desktop windows.
  desktop,
}

/// Where the platform name shows on a card.
enum RoomCardPlatformBadgeMode {
  /// Beside the title when the card is wide enough.
  automatic,

  /// Always, on the cover.
  always,

  /// Never.
  hidden,
}

/// The card's layout.
enum RoomCardLayout {
  /// 16:9 cover, then avatar, title and streamer.
  cover,

  /// One row without the cover.
  compact,
}

/// The presets of the card settings, with their stored keys.
enum RoomCardPreset {
  /// [RoomCardAppearance.compact].
  compact('compact'),

  /// [RoomCardAppearance.standard].
  standard('normal'),

  /// [RoomCardAppearance.detailed].
  detailed('rich'),

  /// Anything else.
  custom('custom');

  new(this.storageKey);

  /// The stored key.
  final String storageKey;
}

/// How room cards look (3.x `RoomCardAppearance`, from the card settings).
@immutable
final class RoomCardAppearance {
  /// Creates an appearance.
  const new({
    required this.layout,
    required this.showAvatar,
    required this.showAnchorName,
    required this.showPlatformBadge,
    required this.automaticPlatformBadge,
    required this.showAudience,
    required this.showReplayBadge,
    required this.cornerRadius,
  });

  /// The appearance of [preset] ([RoomCardPreset.custom] gives the standard).
  factory fromPreset(RoomCardPreset preset) => switch (preset) {
    RoomCardPreset.compact => compact,
    RoomCardPreset.detailed => detailed,
    RoomCardPreset.standard || RoomCardPreset.custom => standard,
  };

  /// Reads a stored appearance, with 3.x's older keys (`showPlatform`,
  /// `showSubtitle`, `showRecordBadge`, `cardBorderRadius`, `showAsListTile`)
  /// and its repair of the 3.1.4 compact snapshot. Missing or mistyped values
  /// take [fallback]'s; with [strict] (imports) they throw [FormatException].
  factory fromJson(Map<String, dynamic> json, {RoomCardAppearance fallback = standard, bool strict = false}) {
    bool readBool(String currentKey, String legacyKey, {required bool orElse}) {
      final value = json.containsKey(currentKey) ? json[currentKey] : json[legacyKey];
      if (value == null) return orElse;
      if (strict && value is! bool) throw FormatException('$currentKey must be a boolean');
      return value is bool ? value : orElse;
    }

    double readRadius() {
      final value = json['cornerRadius'] ?? json['cardBorderRadius'];
      if (value == null) return fallback.cornerRadius;
      if (strict && value is! num) throw const FormatException('cornerRadius must be numeric');
      if (value is! num) return fallback.cornerRadius;
      if (strict && !value.toDouble().isFinite) throw const FormatException('cornerRadius must be finite');
      return normalizeCornerRadius(value);
    }

    RoomCardLayout readLayout() {
      final value = json['layout'];
      if (value != null) {
        if (strict && value is! String) throw const FormatException('layout must be a string');
        if (value is String) {
          final normalized = value.trim().toLowerCase();
          if (normalized == RoomCardLayout.cover.name) return RoomCardLayout.cover;
          if (normalized == RoomCardLayout.compact.name || normalized == 'list' || normalized == 'listtile') {
            return RoomCardLayout.compact;
          }
          if (strict) throw const FormatException('layout must be cover or compact');
        }
        return fallback.layout;
      }
      final legacy = json['showAsListTile'];
      if (legacy == null) return fallback.layout;
      if (strict && legacy is! bool) throw const FormatException('showAsListTile must be a boolean');
      if (legacy is! bool) return fallback.layout;
      return legacy ? RoomCardLayout.compact : RoomCardLayout.cover;
    }

    final hasExplicitPlatformValue = json.containsKey('showPlatformBadge') || json.containsKey('showPlatform');
    final showPlatformBadge = readBool('showPlatformBadge', 'showPlatform', orElse: fallback.showPlatformBadge);
    final automaticPlatformBadge = json.containsKey('automaticPlatformBadge')
        ? readBool('automaticPlatformBadge', 'automaticPlatformBadge', orElse: fallback.automaticPlatformBadge)
        : !hasExplicitPlatformValue && fallback.automaticPlatformBadge;

    // 3.1.4 stored the compact preset as visibility flags only; the preset key
    // proves the snapshot was not a custom layout, so restore the preset.
    final isBrokenCompactPresetSnapshot =
        fallback.layout == RoomCardLayout.compact &&
        !json.containsKey('layout') &&
        !json.containsKey('showAsListTile') &&
        !readBool('showAvatar', 'showAvatar', orElse: fallback.showAvatar) &&
        !readBool('showAnchorName', 'showSubtitle', orElse: fallback.showAnchorName) &&
        !showPlatformBadge &&
        !automaticPlatformBadge &&
        readBool('showAudience', 'showAudience', orElse: fallback.showAudience) &&
        readBool('showReplayBadge', 'showRecordBadge', orElse: fallback.showReplayBadge) &&
        readRadius() == compact.cornerRadius;
    if (isBrokenCompactPresetSnapshot) return compact;

    return RoomCardAppearance(
      layout: readLayout(),
      showAvatar: readBool('showAvatar', 'showAvatar', orElse: fallback.showAvatar),
      showAnchorName: readBool('showAnchorName', 'showSubtitle', orElse: fallback.showAnchorName),
      showPlatformBadge: showPlatformBadge,
      automaticPlatformBadge: !showPlatformBadge && automaticPlatformBadge,
      showAudience: readBool('showAudience', 'showAudience', orElse: fallback.showAudience),
      showReplayBadge: readBool('showReplayBadge', 'showRecordBadge', orElse: fallback.showReplayBadge),
      cornerRadius: readRadius(),
    );
  }

  /// Default corner radius.
  static const double defaultCornerRadius = 20;

  /// Smallest corner radius.
  static const double minCornerRadius = 0;

  /// Largest corner radius.
  static const double maxCornerRadius = 32;

  /// The compact preset.
  static const compact = RoomCardAppearance(
    layout: RoomCardLayout.compact,
    showAvatar: true,
    showAnchorName: true,
    showPlatformBadge: false,
    automaticPlatformBadge: false,
    showAudience: true,
    showReplayBadge: true,
    cornerRadius: 12,
  );

  /// The standard preset (the default).
  static const standard = RoomCardAppearance(
    layout: RoomCardLayout.cover,
    showAvatar: true,
    showAnchorName: true,
    showPlatformBadge: false,
    automaticPlatformBadge: true,
    showAudience: true,
    showReplayBadge: true,
    cornerRadius: defaultCornerRadius,
  );

  /// The detailed preset.
  static const detailed = RoomCardAppearance(
    layout: RoomCardLayout.cover,
    showAvatar: true,
    showAnchorName: true,
    showPlatformBadge: true,
    automaticPlatformBadge: false,
    showAudience: true,
    showReplayBadge: true,
    cornerRadius: defaultCornerRadius,
  );

  /// Layout.
  final RoomCardLayout layout;

  /// Shows the streamer's avatar.
  final bool showAvatar;

  /// Shows the streamer's name.
  final bool showAnchorName;

  /// Shows the platform on the cover (or in the compact row).
  final bool showPlatformBadge;

  /// Shows the platform beside the title when there is room.
  final bool automaticPlatformBadge;

  /// Shows the audience while live.
  final bool showAudience;

  /// Shows the replay badge.
  final bool showReplayBadge;

  /// Corner radius.
  final double cornerRadius;

  /// The platform badge setting as one value.
  RoomCardPlatformBadgeMode get platformBadgeMode {
    if (automaticPlatformBadge) return RoomCardPlatformBadgeMode.automatic;
    return showPlatformBadge ? RoomCardPlatformBadgeMode.always : RoomCardPlatformBadgeMode.hidden;
  }

  /// The preset equal to [appearance], or [RoomCardPreset.custom].
  static RoomCardPreset presetOf(RoomCardAppearance appearance) {
    if (appearance == compact) return RoomCardPreset.compact;
    if (appearance == standard) return RoomCardPreset.standard;
    if (appearance == detailed) return RoomCardPreset.detailed;
    return RoomCardPreset.custom;
  }

  /// [value] within [minCornerRadius]–[maxCornerRadius]; not finite gives the
  /// default.
  static double normalizeCornerRadius(num value) {
    final converted = value.toDouble();
    if (!converted.isFinite) return defaultCornerRadius;
    return converted.clamp(minCornerRadius, maxCornerRadius);
  }

  /// A copy with the given fields replaced (the radius normalised).
  RoomCardAppearance copyWith({
    RoomCardLayout? layout,
    bool? showAvatar,
    bool? showAnchorName,
    bool? showPlatformBadge,
    bool? automaticPlatformBadge,
    bool? showAudience,
    bool? showReplayBadge,
    double? cornerRadius,
  }) => RoomCardAppearance(
    layout: layout ?? this.layout,
    showAvatar: showAvatar ?? this.showAvatar,
    showAnchorName: showAnchorName ?? this.showAnchorName,
    showPlatformBadge: showPlatformBadge ?? this.showPlatformBadge,
    automaticPlatformBadge: automaticPlatformBadge ?? this.automaticPlatformBadge,
    showAudience: showAudience ?? this.showAudience,
    showReplayBadge: showReplayBadge ?? this.showReplayBadge,
    cornerRadius: normalizeCornerRadius(cornerRadius ?? this.cornerRadius),
  );

  /// A copy showing the platform as [mode] says.
  RoomCardAppearance withPlatformBadgeMode(RoomCardPlatformBadgeMode mode) => copyWith(
    showPlatformBadge: mode == RoomCardPlatformBadgeMode.always,
    automaticPlatformBadge: mode == RoomCardPlatformBadgeMode.automatic,
  );

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'layout': layout.name,
    'showAvatar': showAvatar,
    'showAnchorName': showAnchorName,
    'showPlatformBadge': showPlatformBadge,
    'automaticPlatformBadge': automaticPlatformBadge,
    'showAudience': showAudience,
    'showReplayBadge': showReplayBadge,
    'cornerRadius': normalizeCornerRadius(cornerRadius),
  };

  @override
  bool operator ==(Object other) =>
      other is RoomCardAppearance &&
      other.layout == layout &&
      other.showAvatar == showAvatar &&
      other.showAnchorName == showAnchorName &&
      other.showPlatformBadge == showPlatformBadge &&
      other.automaticPlatformBadge == automaticPlatformBadge &&
      other.showAudience == showAudience &&
      other.showReplayBadge == showReplayBadge &&
      other.cornerRadius == cornerRadius;

  @override
  int get hashCode => Object.hash(
    layout,
    showAvatar,
    showAnchorName,
    showPlatformBadge,
    automaticPlatformBadge,
    showAudience,
    showReplayBadge,
    cornerRadius,
  );
}

/// Card geometry shared by `RoomCard` and fixed-extent room grids (3.x
/// `RoomCardLayoutMetrics`), so a grid reserves the height a card takes.
///
/// Give the font settings' [LiveFontSizes]: 3.x measured the text at the
/// default sizes (15/13, dense 13/12) while the card drew it at the user's,
/// so larger font settings overflowed the grid cells.
abstract final class RoomCardLayoutMetrics {
  /// Height of a compact card.
  static double compactHeight({
    required RoomCardAppearance appearance,
    required bool dense,
    bool hasAction = false,
    TextScaler textScaler = TextScaler.noScaling,
    LiveFontSizes fontSizes = const LiveFontSizes(),
  }) {
    final verticalPadding = dense ? 8.0 : 10.0;
    final avatarHeight = appearance.showAvatar ? (dense ? 34.0 : 40.0) : 0.0;
    final minimumInteractiveContent = hasAction || !dense ? 48.0 : 40.0;
    final contentHeight = _textHeight(appearance: appearance, dense: dense, textScaler: textScaler, sizes: fontSizes);
    return math.max(minimumInteractiveContent, math.max(avatarHeight, contentHeight)) + verticalPadding * 2;
  }

  /// Height of a card [itemWidth] wide in a grid.
  static double gridMainAxisExtent({
    required double itemWidth,
    required RoomCardAppearance appearance,
    required bool dense,
    TextScaler textScaler = TextScaler.noScaling,
    LiveFontSizes fontSizes = const LiveFontSizes(),
  }) {
    if (appearance.layout == RoomCardLayout.compact) {
      return compactHeight(appearance: appearance, dense: dense, textScaler: textScaler, fontSizes: fontSizes);
    }
    final baseCaptionHeight = dense ? 72.0 : 84.0;
    final scaledCaptionHeight =
        _textHeight(appearance: appearance, dense: dense, textScaler: textScaler, sizes: fontSizes) +
        (dense ? 16.0 : 20.0);
    final captionHeight = math.max(baseCaptionHeight, scaledCaptionHeight);
    return math.max(0, itemWidth) * 9 / 16 + captionHeight;
  }

  static double _textHeight({
    required RoomCardAppearance appearance,
    required bool dense,
    required TextScaler textScaler,
    required LiveFontSizes sizes,
  }) {
    // The card's styles: title t13/t15, streamer t12/t13 (dense/normal).
    final titleHeight = textScaler.scale(dense ? sizes.bodyMedium : sizes.titleMedium) * 1.2;
    if (!appearance.showAnchorName) return titleHeight;
    final subtitleHeight = textScaler.scale(dense ? sizes.bodySmall : sizes.bodyMedium) * 1.2;
    return titleHeight + (dense ? 2 : 3) + subtitleHeight;
  }
}
