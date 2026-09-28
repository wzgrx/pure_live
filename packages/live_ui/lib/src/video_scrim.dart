import 'package:flutter/widgets.dart';
import 'package:live_ui/src/metrics.dart';
import 'package:live_ui/src/window_class.dart';

/// The icons of the controls on a picture (spec/design/principles.md §2.6):
/// weight 500, which reads better over a busy frame, and grade 0 in every
/// theme, because the controls on a picture look the same in every theme
/// (white on 60% black, §2.2); white by default.
///
/// Size: [sizeFor]. Icon buttons below take the size and colour too.
class VideoControlIcons extends StatelessWidget {
  /// Gives [child]'s icons the controls' axes at [size].
  const new({required this.child, this.size = Sizes.iconMd, this.color = const Color(0xFFFFFFFF), super.key});

  /// Weight of the controls on a picture.
  static const double weight = 500;

  /// 32 dp in fullscreen and in windows of the expanded width class and
  /// wider, 24 dp in compact and medium windows.
  static double sizeFor(BuildContext context, {required bool fullscreen}) =>
      fullscreen || WidthClass.of(MediaQuery.sizeOf(context).width).atLeast(WidthClass.expanded)
      ? Sizes.iconLg
      : Sizes.iconMd;

  /// Icon size.
  final double size;

  /// Icon colour.
  final Color color;

  /// The controls.
  final Widget child;

  @override
  Widget build(BuildContext context) => IconTheme.merge(
    data: IconThemeData(color: color, size: size, weight: weight, grade: 0, opticalSize: size),
    child: child,
  );
}

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
        const Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: color)),
        ),
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
