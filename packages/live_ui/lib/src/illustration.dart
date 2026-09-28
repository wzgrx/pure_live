import 'package:flutter/material.dart';
import 'package:live_ui/src/tv/tv_scope.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// The empty-state and error pictures (principles §3.3): the brand's TV with
/// antennas, thin lines and one colour plane, no people and no mascot.
///
/// Each picture is an SVG in `assets/illustrations/`, compiled to a
/// vector_graphics binary when assets are built (no XML at run time) and
/// drawn in three placeholder colours: red lines, a green plane and blue
/// knock-outs. [IllustrationView] swaps them for the theme's
/// onSurfaceVariant, primaryContainer and the background, so the pictures
/// follow light, dark, pure black and dynamic colour.
enum Illustration {
  /// 关注为空: an empty screen with a plus.
  followsEmpty('follows_empty'),

  /// 无人开播: a switched-off screen with a moon.
  noneLive('none_live'),

  /// 搜索无结果: a magnifier on the screen.
  noResults('no_results'),

  /// 出错, 平台异常: a warning triangle on the screen.
  error('error'),

  /// 网络错误, 离线: a broken antenna.
  offline('offline'),

  /// 没有录制: a recording dot on the screen.
  noRecordings('no_recordings'),

  /// 没有历史: a clock on the screen.
  noHistory('no_history');

  new(this.file);

  /// File name in `assets/illustrations/`, without `.svg`.
  final String file;

  /// Asset key inside this package.
  String get asset => 'assets/illustrations/$file.svg';
}

/// An [Illustration] at 160 × 120 dp (200 × 150 on TV), coloured from the
/// theme. Decorative: screen readers skip it, the title next to it speaks.
class IllustrationView extends StatelessWidget {
  /// Creates the view.
  const new(this.illustration, {this.width, this.background, super.key});

  /// Which picture.
  final Illustration illustration;

  /// Width; the height is three quarters of it. At most 160 dp (TV 200 dp)
  /// by default.
  final double? width;

  /// The colour behind the picture, for the parts that cover the plane; the
  /// surrounding material's colour by default.
  final Color? background;

  /// Width on phones, tablets and desktops.
  static const double defaultWidth = 160;

  /// Width on TV.
  static const double tvWidth = 200;

  /// The colour matrix that maps the placeholder channels to [line],
  /// [plane] and [knock]. The mapping is linear, so antialiased edges and
  /// channel mixes blend into the matching mix of theme colours.
  static List<double> colorMatrix({required Color line, required Color plane, required Color knock}) => [
    line.r, plane.r, knock.r, 0, 0, //
    line.g, plane.g, knock.g, 0, 0,
    line.b, plane.b, knock.b, 0, 0,
    0, 0, 0, 1, 0,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = this.width ?? (TvScope.of(context).enabled ? tvWidth : defaultWidth);
    final material = Material.maybeOf(context)?.color;
    final knock = background ?? (material != null && material.a == 1 ? material : scheme.surface);
    return VectorGraphic(
      loader: AssetBytesLoader(illustration.asset, packageName: 'live_ui'),
      width: width,
      height: width * 3 / 4,
      excludeFromSemantics: true,
      colorFilter: ColorFilter.matrix(
        colorMatrix(line: scheme.onSurfaceVariant, plane: scheme.primaryContainer, knock: knock),
      ),
    );
  }
}
