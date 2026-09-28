import 'package:flutter/material.dart';
import 'package:live_ui/src/color_tokens.dart';
import 'package:live_ui/src/icons/live_icon.dart';
import 'package:live_ui/src/icons/live_icons.dart';
import 'package:live_ui/src/metrics.dart';
import 'package:live_ui/src/theme.dart';
import 'package:live_ui/src/ui_text.dart';

/// Platforms that ship a logo in this package; others fall back to a letter tile.
const _logos = {
  'bilibili',
  'douyu',
  'huya',
  'douyin',
  'kuaishou',
  'cc',
  'yy',
  'soop',
  'acfun',
  'twitch',
  'chzzk',
  'missevan',
  'kilakila',
  'inke',
  'picarto',
  'twitcasting',
  'showroom',
  'pandalive',
  '17live',
  'liveme',
  'steambroadcast',
  'sixroom',
  'kugoulive',
  'jdlive',
  'baidulive',
  'looklive',
  'weibo',
  'niconico',
  'xiaohongshu',
  'youtube',
  'tiktok',
  'fc2live',
  'bigo',
};

/// A platform's logo, used as is (principles §3.4), on a white r1 tile so
/// it reads the same on light and dark surfaces and on any cover.
///
/// Logos come in three sizes: [Sizes.logoSmall] (on covers and beside small
/// text), [Sizes.logoMedium] (dense rows and tabs) and [Sizes.logoLarge]
/// (leading a row, on a cover placeholder, on TV). The image fills the
/// tile's decoration, so no clip layer is added (principles §7.11).
class PlatformLogo extends StatelessWidget {
  /// Creates the logo.
  const new({required this.platformId, this.size = Sizes.logoSmall, super.key})
    : assert(
        size == Sizes.logoSmall || size == Sizes.logoMedium || size == Sizes.logoLarge,
        'a platform logo is 16, 20 or 24 dp (principles §3.4)',
      );

  /// Platform id (`douyu`).
  final String platformId;

  /// Edge length: 16, 20 or 24.
  final double size;

  /// Whether this package ships a logo for [platformId].
  static bool has(String platformId) => _logos.contains(platformId);

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.r1);
    if (!_logos.contains(platformId)) {
      final scheme = Theme.of(context).colorScheme;
      return DecoratedBox(
        decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: radius),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Text(
              platformId.isEmpty ? '?' : platformId[0].toUpperCase(),
              style: TextStyle(fontSize: size * 0.6, color: scheme.onSecondaryContainer, height: 1),
            ),
          ),
        ),
      );
    }
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FixedColors.logoTile,
        borderRadius: radius,
        image: DecorationImage(
          image: ResizeImage(
            AssetImage('assets/platforms/$platformId.png', package: 'live_ui'),
            width: pixels,
            height: pixels,
          ),
          fit: BoxFit.cover,
        ),
      ),
      child: SizedBox.square(dimension: size),
    );
  }
}

/// The "直播" badge; text plus colour so state never relies on colour alone
/// (principles rule 2).
class LiveBadge extends StatelessWidget {
  /// Creates the badge, optionally with the live duration.
  const new({this.duration, super.key});

  /// Formatted duration shown after the label.
  final String? duration;

  static const _padding = EdgeInsets.symmetric(horizontal: Space.s1 + 2, vertical: 1);

  @override
  Widget build(BuildContext context) {
    final live = LiveTheme.of(context);
    final style = LiveTheme.numeric(Theme.of(context).textTheme.labelMedium!).copyWith(color: live.onLive);
    final words = LiveUiText.current;
    Widget badge(String text) => DecoratedBox(
      decoration: BoxDecoration(color: live.live, borderRadius: BorderRadius.circular(Radii.r1)),
      child: Padding(
        padding: _padding,
        child: Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
    final duration = this.duration;
    if (duration == null) return badge(words.live);
    // Where the badge has no room for both (large text on a narrow card), the
    // duration goes and the word 直播 stays (principles rule 2).
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = words.liveFor(duration);
        if (!constraints.hasBoundedWidth) return badge(full);
        final painter = TextPainter(
          text: TextSpan(text: full, style: DefaultTextStyle.of(context).style.merge(style)),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = painter.width + _padding.horizontal <= constraints.maxWidth;
        painter.dispose();
        return badge(fits ? full : words.live);
      },
    );
  }
}

/// The "录制中" mark of a room the recorder is saving (spec/product.md
/// F-FAV-01): a dot plus text on a scrim, so it reads on any cover and never
/// relies on colour alone (principles rule 2).
class RecordingBadge extends StatelessWidget {
  /// Creates the badge.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium!.copyWith(color: Colors.white);
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(Radii.r1)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s1 + 2, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RecordingDot(),
            const SizedBox(width: Space.s1),
            Text(LiveUiText.current.recording, style: style),
          ],
        ),
      ),
    );
  }
}

/// A short state label beside a name, such as "未支持" or "状态未知": tonal
/// fill and text, no colour-only meaning.
class StatusTag extends StatelessWidget {
  /// Creates the tag; [recording] puts the recording dot before the text.
  const new(String this.text, {this.recording = false, super.key});

  /// The recording mark for list rows ("录制中" in the interface language).
  const new recording({super.key}) : text = null, recording = true;

  /// The label; null for [LiveUiText.recording].
  final String? text;

  /// Whether to show the recording dot.
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall!.copyWith(color: scheme.onSecondaryContainer);
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(Radii.r1)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s1 + 2, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (recording) ...[const RecordingDot(), const SizedBox(width: Space.s1)],
            Text(text ?? LiveUiText.current.recording, style: style),
          ],
        ),
      ),
    );
  }
}

/// A figure on a cover (audience), on a scrim so it reads on any image.
class CoverLabel extends StatelessWidget {
  /// Creates the label.
  const new(this.text, {this.icon = LiveIcons.audience, super.key});

  /// Formatted figure.
  final String text;

  /// Leading icon, sized to the figure beside it.
  final LiveIcons icon;

  @override
  Widget build(BuildContext context) {
    final style = LiveTheme.numeric(Theme.of(context).textTheme.labelMedium!).copyWith(color: Colors.white);
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(Radii.r1)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s1 + 2, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiveIcon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 2),
            Text(text, style: style),
          ],
        ),
      ),
    );
  }
}

/// The solid dot of "录制中" (principles §2.2): the live red in every theme,
/// always next to the word, so recording never relies on colour alone. A
/// button that starts recording shows an outlined circle instead.
class RecordingDot extends StatelessWidget {
  /// Creates the dot.
  const new({this.size = 6, super.key});

  /// Diameter.
  final double size;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(color: FixedColors.live, shape: BoxShape.circle),
    child: SizedBox.square(dimension: size),
  );
}
