import 'package:flutter/material.dart';
import 'package:live_ui/src/widgets/network_image.dart';

/// A round avatar (3.x `CommonAvatar`): the picture, or the first letter of
/// [fallbackName] on a grey disc when there is no picture or it fails.
class CommonAvatar extends StatelessWidget {
  /// Creates the avatar.
  const new({required this.avatarUrl, this.dense = false, this.radius, this.fallbackName, super.key});

  /// Picture address (already normalised by the app); null or empty shows
  /// the letter.
  final String? avatarUrl;

  /// The smaller size (radius 17 instead of 20).
  final bool dense;

  /// Radius; overrides [dense].
  final double? radius;

  /// Name whose first letter stands in for the picture.
  final String? fallbackName;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? (dense ? 17.0 : 20.0);
    final size = r * 2;
    final url = avatarUrl?.trim() ?? '';

    Widget fallback(BuildContext context) {
      final name = fallbackName ?? '';
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).disabledColor.withAlpha(80)),
        child: Text(
          name.isEmpty ? '' : name.characters.first.toUpperCase(),
          style: TextStyle(fontSize: r * 0.8, fontWeight: FontWeight.bold),
        ),
      );
    }

    if (url.isEmpty) return fallback(context);
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: LiveNetworkImage(
          url: url,
          memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(48, 256),
          placeholder: (context) => ColoredBox(color: Theme.of(context).disabledColor.withValues(alpha: 0.2)),
          error: fallback,
        ),
      ),
    );
  }
}
