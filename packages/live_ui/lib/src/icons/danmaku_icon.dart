import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Which danmaku picture [DanmakuIcon] shows.
enum DanmakuIconKind {
  /// Danmaku on the video are shown (3.x `danmu_open.svg`).
  on('assets/images/video/danmu_open.svg'),

  /// Danmaku on the video are hidden (3.x `danmu_close.svg`).
  off('assets/images/video/danmu_close.svg'),

  /// The danmaku settings (3.x `danmu_setting.svg`).
  settings('assets/images/video/danmu_setting.svg');

  new(this.asset);

  /// The picture, inside this package.
  final String asset;
}

/// 3.x's danmaku pictures of the video's bottom bar, drawn like an [Icon]:
/// size and colour come from the [IconTheme] unless given, and the theme's
/// first shadow is drawn under the picture (the controls over the video).
class DanmakuIcon extends StatelessWidget {
  /// Creates the picture of [kind].
  const new(this.kind, {this.size, this.color, this.semanticLabel, super.key});

  /// Which picture.
  final DanmakuIconKind kind;

  /// The size; the icon theme's (else 24) by default.
  final double? size;

  /// The colour; the icon theme's by default.
  final Color? color;

  /// What a screen reader says.
  final String? semanticLabel;

  /// The package the pictures are bundled in.
  static const String package = 'live_ui';

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 24;
    final ink = color ?? theme.color ?? const Color(0xFFFFFFFF);
    Widget picture(Color tint) => SvgPicture.asset(
      kind.asset,
      package: package,
      width: side,
      height: side,
      colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
    );
    final shadow = theme.shadows?.firstOrNull;
    return Semantics(
      label: semanticLabel,
      image: semanticLabel != null,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: side,
        child: shadow == null
            // A shadow copy one pixel lower instead of a blur keeps the
            // bar cheap to draw.
            ? picture(ink)
            : Stack(
                children: [
                  Positioned.fill(top: 1, bottom: -1, child: picture(shadow.color)),
                  picture(ink),
                ],
              ),
      ),
    );
  }
}
