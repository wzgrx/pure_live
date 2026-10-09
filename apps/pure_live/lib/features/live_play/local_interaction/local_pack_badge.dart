import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';

/// A platform pack's badge (D08.6): the platform's logo ([PlatformLogo],
/// the picture the rest of the app shows for it), its corners rounded as
/// the room cards round theirs; the pack's emoji or two letters ([fallback])
/// only for an id without a logo (the generic pack, a message from before
/// D08.6, which names no platform).
///
/// The same badge in the settings page's chips and preview, the room
/// panel's identity card, the local chat line's chip, the gift banner and
/// the history.
class LocalPackBadge extends StatelessWidget {
  /// Creates the badge of [platform] at [size] × [size], or [fallback] in
  /// [textStyle].
  const new(this.platform, {required this.fallback, required this.size, this.textStyle, this.radius, super.key});

  /// The platform's id, or null (the text then).
  final String? platform;

  /// The words without a logo: the pack's emoji or letters.
  final String fallback;

  /// The logo's width and height.
  final double size;

  /// The style of [fallback].
  final TextStyle? textStyle;

  /// The logo's corner radius; a quarter of [size] when null.
  final double? radius;

  /// Whether [platform] has a logo of its own.
  static bool hasLogo(String? platform) =>
      platform != null && PlatformLogos.ids.contains(platform.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final id = platform;
    if (id == null || !hasLogo(id)) return Text(localEmojiText(fallback), style: localEmojiStyle(textStyle));
    return ClipRRect(
      key: ValueKey('local-pack-logo-${id.trim().toLowerCase()}'),
      borderRadius: BorderRadius.circular(radius ?? size / 4),
      child: PlatformLogo(id, size: size),
    );
  }
}
