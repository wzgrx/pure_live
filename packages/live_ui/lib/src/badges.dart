import 'package:flutter/material.dart';
import 'package:live_ui/src/metrics.dart';
import 'package:live_ui/src/theme.dart';

/// Platforms that ship a logo in this package; others fall back to a letter tile.
const _logos = {'bilibili', 'douyu', 'huya', 'douyin', 'kuaishou'};

/// A platform's logo, used as is (principles §3.4).
class PlatformLogo extends StatelessWidget {
  /// Creates the logo.
  const new({required this.platformId, this.size = Sizes.logoCard, super.key});

  /// Platform id (`douyu`).
  final String platformId;

  /// Edge length.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.r1),
      child: SizedBox.square(
        dimension: size,
        child: _logos.contains(platformId)
            ? Image.asset(
                'assets/platforms/$platformId.png',
                package: 'live_ui',
                width: size,
                height: size,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
                fit: BoxFit.cover,
              )
            : ColoredBox(
                color: scheme.secondaryContainer,
                child: Center(
                  child: Text(
                    platformId.isEmpty ? '?' : platformId[0].toUpperCase(),
                    style: TextStyle(fontSize: size * 0.6, color: scheme.onSecondaryContainer, height: 1),
                  ),
                ),
              ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final live = LiveTheme.of(context);
    final style = live.numeric.copyWith(color: live.onLive);
    return DecoratedBox(
      decoration: BoxDecoration(color: live.live, borderRadius: BorderRadius.circular(Radii.r1)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s1 + 2, vertical: 1),
        child: Text(duration == null ? '直播' : '直播 $duration', style: style),
      ),
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
    final style = LiveTheme.of(context).numeric.copyWith(color: Colors.white);
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(Radii.r1)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s1 + 2, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFFFF3B30), shape: BoxShape.circle),
              child: SizedBox.square(dimension: 6),
            ),
            const SizedBox(width: Space.s1),
            Text('录制中', style: style),
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
  const new(this.text, {this.recording = false, super.key});

  /// The recording mark for list rows ("录制中").
  const new recording({Key? key}) : this('录制中', recording: true, key: key);

  /// The label.
  final String text;

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
            if (recording) ...[
              DecoratedBox(
                decoration: BoxDecoration(color: scheme.error, shape: BoxShape.circle),
                child: const SizedBox.square(dimension: 6),
              ),
              const SizedBox(width: Space.s1),
            ],
            Text(text, style: style),
          ],
        ),
      ),
    );
  }
}

/// A figure on a cover (audience), on a scrim so it reads on any image.
class CoverLabel extends StatelessWidget {
  /// Creates the label.
  const new(this.text, {this.icon = Icons.person_outline, super.key});

  /// Formatted figure.
  final String text;

  /// Leading icon.
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final style = LiveTheme.of(context).numeric.copyWith(color: Colors.white);
    return DecoratedBox(
      decoration: BoxDecoration(color: const Color(0x99000000), borderRadius: BorderRadius.circular(Radii.r1)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s1 + 2, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 2),
            Text(text, style: style),
          ],
        ),
      ),
    );
  }
}
