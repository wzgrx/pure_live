import 'package:flutter/material.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/widgets/loading_styles.dart';

/// The diameter of the [VideoCentreButton] on a room's picture (64).
const double videoCentreButtonSize = 64;

/// The round button in the middle of a picture (docs/A-界面设计/A07-直播间界面/A07.10-暂停状态/brief.md c2,
/// audit A-01): a white glyph on a 45 % black disc ([OnVideoColors.button],
/// as the mini windows' buttons), so it reads on a bright picture. Paused it
/// is the play mark ([AppIcons.play], what a tap does) and stays on; while
/// the stream waits for data ([busy]) a spinner in the "加载样式" takes the
/// glyph's place on the same disc and taps go through.
///
/// The live room and the in-app floating window draw this same button; the
/// floating window passes its smaller [size] and its other glyphs (pause,
/// retry).
class VideoCentreButton extends StatelessWidget {
  /// Creates the button.
  const new({
    required this.tooltip,
    this.onPressed,
    this.icon = AppIcons.play,
    this.busy = false,
    this.size = videoCentreButtonSize,
    super.key,
  });

  /// What it does (the tooltip and the screen reader's label).
  final String tooltip;

  /// What a tap does; ignored while [busy].
  final VoidCallback? onPressed;

  /// The glyph.
  final IconData icon;

  /// The stream waits for data: a spinner instead of the glyph.
  final bool busy;

  /// The disc's diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    if (busy) {
      final config = LiveUiScope.of(context);
      final spinner = (size * 0.44).roundToDouble();
      return Semantics(
        label: tooltip,
        child: SizedBox.square(
          dimension: size,
          child: DecoratedBox(
            key: const ValueKey('video-centre-busy'),
            decoration: const BoxDecoration(color: OnVideoColors.button, shape: BoxShape.circle),
            child: Center(
              child: SizedBox.square(
                dimension: spinner,
                child: Center(
                  child: LoadingStyles.build(
                    LoadingStyles.normalize(config.loadingStyle),
                    color: config.loadingColor ?? OnVideoColors.foreground,
                    size: spinner,
                    colors: Theme.of(context).colorScheme,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: (size * 0.6).roundToDouble(),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: OnVideoColors.button,
          foregroundColor: OnVideoColors.foreground,
          disabledBackgroundColor: OnVideoColors.button,
          disabledForegroundColor: OnVideoColors.disabled,
          fixedSize: Size.square(size),
          minimumSize: Size.square(size),
        ),
        icon: Icon(icon),
      ),
    );
  }
}
