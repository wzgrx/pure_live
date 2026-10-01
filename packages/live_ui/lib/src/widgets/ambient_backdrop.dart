import 'package:flutter/material.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/widgets/network_image.dart';

/// The width, in physical pixels, a cover is decoded at for the ambient
/// background: small enough that drawing it large reads as a soft blur.
const int ambientCoverDecodeWidth = 24;

/// The "沉浸背景" behind a portrait picture (3.x
/// `PortraitFullscreenPresentation`, docs/ui/compare/U.2b change 12): 3.x's
/// dark gradient, the room's cover blown up 1.14 times over it, and a 15 %
/// black veil. The cover is decoded once at [ambientCoverDecodeWidth] and
/// drawn large with a smooth filter, which blurs it once; nothing is blurred
/// again per frame (3.x ran a radius-28 blur over the picture every frame).
/// The same backdrop serves the portrait fullscreen, a portrait stream in
/// landscape fullscreen, the wide room and the TV.
class AmbientBackdrop extends StatelessWidget {
  /// Creates the backdrop of [cover] (an address, empty for none).
  const new({required this.cover, super.key});

  /// The room's cover, or its streamer's avatar.
  final String cover;

  @override
  Widget build(BuildContext context) {
    final url = cover.trim();
    return RepaintBoundary(
      child: Stack(
        key: const ValueKey('ambient-backdrop'),
        fit: StackFit.expand,
        children: [
          const DecoratedBox(decoration: BoxDecoration(gradient: OnVideoColors.ambientFallback)),
          if (url.isNotEmpty)
            Transform.scale(
              scale: 1.14,
              child: LiveNetworkImage(
                key: const ValueKey('ambient-backdrop-cover'),
                url: url,
                memCacheWidth: ambientCoverDecodeWidth,
                filterQuality: FilterQuality.medium,
                placeholder: (_) => const SizedBox.shrink(),
                error: (_) => const SizedBox.shrink(),
              ),
            ),
          const ColoredBox(color: OnVideoColors.ambientVeil),
        ],
      ),
    );
  }
}
