import 'package:flutter/widgets.dart';

/// The scrim under a control bar at the top or bottom edge of a picture
/// (spec/design/principles.md §2.2): 60% black behind the bar itself, then a
/// 24 dp fade to nothing towards the middle of the picture. White text on it
/// reads at 5.7:1 on a white frame (55% would give 4.7:1); the fade only
/// softens the edge and never carries text.
///
/// The scrim takes no pointers: gestures between the bar's buttons reach
/// whatever lies under it. A plain colour and a gradient, no blur and no
/// opacity layer (principles §7 rule 1).
class VideoBarScrim extends StatelessWidget {
  /// Puts [child] (the bar, with its safe-area padding inside) on the scrim;
  /// [top] for a bar at the top edge, whose fade runs downwards.
  const new({required this.child, this.top = false, super.key});

  /// 60% black.
  static const Color color = Color(0x99000000);

  /// Length of the fade into the picture.
  static const double fade = 24;

  /// The bar.
  final Widget child;

  /// Whether the bar sits at the top edge.
  final bool top;

  @override
  Widget build(BuildContext context) {
    final bar = Stack(
      children: [
        const Positioned.fill(child: IgnorePointer(child: ColoredBox(color: color))),
        child,
      ],
    );
    final edge = IgnorePointer(
      child: SizedBox(
        height: fade,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: const [color, Color(0x00000000)],
            ),
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: top ? [bar, edge] : [edge, bar],
    );
  }
}
