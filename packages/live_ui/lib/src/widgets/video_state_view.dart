import 'dart:async';

import 'package:flutter/material.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/live_colors.dart';
import 'package:live_ui/src/widgets/loading_styles.dart';

/// A button of a [VideoStateView].
@immutable
final class VideoStateAction {
  /// Creates the button.
  const new({required this.label, required this.icon, required this.onPressed, this.key});

  /// The words.
  final String label;

  /// The icon before the words.
  final IconData icon;

  /// What it does; while the returned future runs, the button turns and
  /// does not take another tap ("重试中").
  final FutureOr<void> Function() onPressed;

  /// The button's key (tests).
  final Key? key;
}

/// What the picture shows when it is not simply playing (docs/T05/T05i/T05i.1
/// c2): one component for every state and every layout. From the top: a
/// spinner, an icon or a picture ([leading], the streamer); one sentence
/// ([title]); one reason ([reason]); at most two buttons, the first filled
/// white, the second outlined. Under it, optionally, a dimming of the moving
/// picture ([dim]).
///
/// [compact] (a short picture: portrait 16:9) leaves out the icon but keeps
/// the [leading] picture. Words and the dimming let taps through to the
/// picture (show the controls); only the buttons take them.
class VideoStateView extends StatelessWidget {
  /// Creates the view.
  const new({
    this.title = '',
    this.reason,
    this.icon,
    this.leading,
    this.busy = false,
    this.actions = const [],
    this.dim,
    this.compact = false,
    super.key,
  });

  /// The sentence.
  final String title;

  /// Why, or what to do (smaller).
  final String? reason;

  /// The state's icon (left out when [compact]).
  final IconData? icon;

  /// A picture above the words instead of the icon (the streamer).
  final Widget? leading;

  /// A spinner in the "加载样式" the user chose instead of an icon.
  final bool busy;

  /// At most two buttons; the first is the main one.
  final List<VideoStateAction> actions;

  /// Dims the picture under the state ([OnVideoColors.scrim] or
  /// [OnVideoColors.dimLight]); null leaves it.
  final Color? dim;

  /// A short picture: no icon.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = LiveUiScope.of(context);
    final words = <Widget>[];
    final Widget? head;
    if (busy) {
      head = IgnorePointer(
        key: const ValueKey('video-state-spinner'),
        child: SizedBox.square(
          dimension: compact ? 24 : 32,
          child: Center(
            child: LoadingStyles.build(
              LoadingStyles.normalize(config.loadingStyle),
              color: config.loadingColor ?? OnVideoColors.foreground,
              size: compact ? 24 : 32,
              colors: theme.colorScheme,
            ),
          ),
        ),
      );
    } else if (leading != null) {
      head = leading;
    } else if (icon != null && !compact) {
      head = Icon(icon, key: const ValueKey('video-state-icon'), size: 36, color: OnVideoColors.secondary);
    } else {
      head = null;
    }
    if (title.isNotEmpty) {
      words.add(
        Text(
          title,
          key: const ValueKey('video-state-title'),
          textAlign: TextAlign.center,
          style: busy
              ? theme.textTheme.bodyLarge?.regular.copyWith(
                  color: OnVideoColors.foreground.withValues(alpha: 0.88),
                  shadows: OnVideoColors.shadows,
                )
              : theme.textTheme.titleSmall?.emphasis.copyWith(
                  fontSize: 15,
                  color: OnVideoColors.foreground,
                  shadows: OnVideoColors.shadows,
                ),
        ),
      );
    }
    if (reason case final text? when text.isNotEmpty && text != title) {
      words.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            text,
            key: const ValueKey('video-state-reason'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.regular.copyWith(
              color: OnVideoColors.secondary,
              shadows: OnVideoColors.shadows,
            ),
          ),
        ),
      );
    }
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?head,
        if (words.isNotEmpty) ...[
          SizedBox(height: busy ? 10 : 8),
          IgnorePointer(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(mainAxisSize: MainAxisSize.min, children: words),
            ),
          ),
        ],
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final (index, action) in actions.take(2).indexed) _StateButton(action: action, primary: index == 0),
            ],
          ),
        ],
      ],
    );
    return Stack(
      key: const ValueKey('video-state'),
      fit: StackFit.expand,
      children: [
        if (dim case final color?)
          IgnorePointer(
            child: ColoredBox(key: const ValueKey('video-state-dim'), color: color),
          ),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            physics: const NeverScrollableScrollPhysics(),
            child: content,
          ),
        ),
      ],
    );
  }
}

/// The streamer's picture in a state: a round picture with a light ring.
class VideoStateAvatar extends StatelessWidget {
  /// Creates the picture of [child] at [size].
  const new({required this.child, this.size = 48, super.key});

  /// The picture (an avatar).
  final Widget child;

  /// The diameter.
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey('video-state-avatar'),
    width: size + 4,
    height: size + 4,
    padding: const EdgeInsets.all(2),
    decoration: const BoxDecoration(color: OnVideoColors.avatarRing, shape: BoxShape.circle),
    child: ClipOval(
      child: SizedBox.square(dimension: size, child: child),
    ),
  );
}

class _StateButton extends StatefulWidget {
  const new({required this.action, required this.primary});

  final VideoStateAction action;
  final bool primary;

  @override
  State<_StateButton> createState() => _StateButtonState();
}

class _StateButtonState extends State<_StateButton> {
  bool _busy = false;

  Future<void> _press() async {
    if (_busy) return;
    final result = widget.action.onPressed();
    if (result is! Future<void>) return;
    setState(() => _busy = true);
    try {
      await result;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    final ink = primary ? OnVideoColors.buttonInk : OnVideoColors.foreground;
    final style = Theme.of(context).textTheme.bodyLarge?.emphasis.copyWith(color: ink);
    return Semantics(
      button: true,
      child: Material(
        key: widget.action.key,
        color: primary ? OnVideoColors.foreground : OnVideoColors.buttonFill,
        shape: StadiumBorder(side: primary ? BorderSide.none : const BorderSide(color: OnVideoColors.buttonOutline)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: _busy ? null : () => unawaited(_press()),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: kMinInteractiveDimension),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_busy)
                    SizedBox.square(
                      key: const ValueKey('video-state-button-busy'),
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: ink),
                    )
                  else
                    Icon(widget.action.icon, size: 18, color: ink),
                  const SizedBox(width: 6),
                  Text(widget.action.label, style: style),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
