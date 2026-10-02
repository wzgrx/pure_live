import 'package:flutter/material.dart';
import 'package:live_ui/src/widgets/focus_ring.dart';
import 'package:live_ui/src/widgets/network_image.dart';

/// A round avatar (3.x `CommonAvatar`, docs/A-界面设计/A02-组件/A02.1-通用组件 c9): the
/// picture (decoded at its shown size); while it loads a light grey disc;
/// without a picture, or when it fails, the first letter of [fallbackName]
/// on the secondary container, or a person when there is no name either.
///
/// With [onTap] it is a button: darker under the pointer and when pressed,
/// the keyboard focus frame, [tooltip] on hover.
class CommonAvatar extends StatelessWidget {
  /// Creates the avatar.
  const new({
    required this.avatarUrl,
    this.dense = false,
    this.radius,
    this.fallbackName,
    this.onTap,
    this.tooltip,
    super.key,
  });

  /// Picture address (already normalised by the app); null or empty shows
  /// the letter.
  final String? avatarUrl;

  /// The smaller size (radius 17 instead of 20).
  final bool dense;

  /// Radius; overrides [dense].
  final double? radius;

  /// Name whose first letter stands in for the picture.
  final String? fallbackName;

  /// Makes the avatar a button.
  final VoidCallback? onTap;

  /// The button's name (hover, screen readers).
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final r = radius ?? (dense ? 17.0 : 20.0);
    final size = r * 2;
    final url = avatarUrl?.trim() ?? '';
    final scheme = Theme.of(context).colorScheme;

    Widget fallback(BuildContext context) {
      final name = fallbackName?.trim() ?? '';
      return Container(
        key: const ValueKey('avatar-fallback'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.secondaryContainer),
        child: name.isEmpty
            ? Icon(Icons.person_rounded, size: size * 0.6, color: scheme.onSecondaryContainer)
            : Text(
                name.characters.first.toUpperCase(),
                style: TextStyle(
                  fontSize: size * 0.42,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSecondaryContainer,
                ),
              ),
      );
    }

    var avatar = url.isEmpty
        ? fallback(context)
        : SizedBox(
            width: size,
            height: size,
            child: ClipOval(
              child: LiveNetworkImage(
                url: url,
                memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(48, 256),
                placeholder: (context) =>
                    ColoredBox(key: const ValueKey('avatar-loading'), color: scheme.surfaceContainer),
                error: fallback,
              ),
            ),
          );
    final tap = onTap;
    if (tap == null) return avatar;
    avatar = SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          avatar,
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: tap,
                customBorder: const CircleBorder(),
                splashFactory: NoSplash.splashFactory,
                hoverColor: Colors.black.withValues(alpha: 0.10),
                highlightColor: Colors.black.withValues(alpha: 0.18),
                focusColor: Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
    avatar = FocusRing(borderRadius: BorderRadius.circular(r), child: avatar);
    final name = tooltip;
    return name == null ? avatar : Tooltip(message: name, child: avatar);
  }
}
