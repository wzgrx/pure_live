import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/tv/tv_theme.dart';

/// The keys that confirm: the remote's OK (`select`), Enter, the gamepad's A
/// and Space (keyboards while testing on a computer).
bool isTvConfirmKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.gameButtonA ||
    key == LogicalKeyboardKey.space;

/// How long OK must be held to count as a long press.
const Duration tvLongPressDelay = Duration(milliseconds: 500);

/// How a focusable answers a key before the default handling; return
/// [KeyEventResult.handled] to keep it (a grid moving by index, a row that
/// opens its options on Right).
typedef TvKeyHandler = KeyEventResult Function(FocusNode node, KeyEvent event);

/// Builds a focusable's content for its focus state.
// The builder shape of pure_live_TV's `TvFocusableBuilder`.
// ignore: avoid_positional_boolean_parameters
typedef TvFocusBuilder = Widget Function(BuildContext context, bool focused);

/// One remote-control target (pure_live_TV `TvFocusable` and `TvFocusStyle`):
/// a focus node, OK as tap, a held OK as long press, and the shared focus
/// look — it grows a little ([scale]), gets an accent ring and, on dark
/// palettes, a soft glow. Gaining focus animates (120 ms), losing it snaps,
/// so a held arrow never leaves a trail of half-lit items.
///
/// Built on Flutter's own focus system (no dpad package): arrows move by
/// geometry through the app's `DirectionalFocusIntent`, widgets with their
/// own rules (grids, lists) step in through [onKey]. Touch and mouse work
/// too: a tap is OK, a long press or right click is the long press.
class TvFocusable extends StatefulWidget {
  /// Creates the target.
  const new({
    required this.builder,
    this.onTap,
    this.onLongPress,
    this.onKey,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.radius = 16,
    this.scale = 1.05,
    this.ring = true,
    this.glow = true,
    super.key,
  });

  /// The content for the focus state.
  final TvFocusBuilder builder;

  /// OK, Enter or a tap.
  final VoidCallback? onTap;

  /// A held OK (at least [tvLongPressDelay]), a long press or a right click.
  final VoidCallback? onLongPress;

  /// Keys before the default handling.
  final TvKeyHandler? onKey;

  /// Focus gained or lost.
  final ValueChanged<bool>? onFocusChange;

  /// The node; one is made when null.
  final FocusNode? focusNode;

  /// Takes the focus when first built.
  final bool autofocus;

  /// The corner radius of the ring and glow, in design pixels.
  final double radius;

  /// How much the target grows when focused (1 for none).
  final double scale;

  /// Draws the accent ring when focused.
  final bool ring;

  /// Draws the glow when focused (dark palettes).
  final bool glow;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  FocusNode? _own;
  bool _focused = false;
  Timer? _hold;
  bool _pressed = false;
  bool _longFired = false;

  FocusNode get _node => widget.focusNode ?? (_own ??= FocusNode(debugLabel: 'TvFocusable'));

  @override
  void dispose() {
    _hold?.cancel();
    _own?.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final custom = widget.onKey?.call(node, event);
    if (custom == KeyEventResult.handled) return custom!;
    if (!isTvConfirmKey(event.logicalKey)) return custom ?? KeyEventResult.ignored;
    if (widget.onTap == null && widget.onLongPress == null) return KeyEventResult.ignored;
    switch (event) {
      case KeyDownEvent():
        if (widget.onLongPress == null) {
          // Nothing to tell apart: act at once.
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        _pressed = true;
        _longFired = false;
        _hold?.cancel();
        _hold = Timer(tvLongPressDelay, () {
          if (!_pressed || !mounted) return;
          _longFired = true;
          widget.onLongPress?.call();
        });
        return KeyEventResult.handled;
      case KeyRepeatEvent():
        // A held key repeats; the timer decides, and a held OK on a plain
        // button does not fire again.
        return KeyEventResult.handled;
      case KeyUpEvent():
        if (!_pressed) return KeyEventResult.ignored;
        _pressed = false;
        _hold?.cancel();
        // The release of a long press never also taps (pure_live_TV
        // `DpadLongPressGate`).
        if (!_longFired) widget.onTap?.call();
        _longFired = false;
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _focusChanged(bool focused) {
    if (!focused) {
      _hold?.cancel();
      _pressed = false;
    }
    setState(() => _focused = focused);
    widget.onFocusChange?.call(focused);
  }

  void _tap() {
    _node.requestFocus();
    widget.onTap?.call();
  }

  void _longPress() {
    _node.requestFocus();
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    final radius = BorderRadius.circular(scale(widget.radius));
    final duration = _focused ? const Duration(milliseconds: 120) : Duration.zero;
    final shadows = _focused && widget.glow
        ? [
            BoxShadow(
              color: palette.focus.withValues(alpha: palette.isLight ? 1 : 0.75),
              blurRadius: palette.isLight ? 0 : scale(18),
              spreadRadius: scale(palette.isLight ? 2 : 1.5),
            ),
          ]
        : const <BoxShadow>[];
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      onFocusChange: _focusChanged,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null ? null : _tap,
        onLongPress: widget.onLongPress == null ? null : _longPress,
        onSecondaryTap: widget.onLongPress == null ? null : _longPress,
        child: AnimatedScale(
          scale: _focused ? widget.scale : 1,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            foregroundDecoration: _focused && widget.ring
                ? BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(color: palette.focus, width: scale(3)),
                  )
                : BoxDecoration(borderRadius: radius),
            decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
            child: widget.builder(context, _focused),
          ),
        ),
      ),
    );
  }
}

/// A pill button of the TV interface: icon and label, filled with the accent
/// when focused, tinted when [selected].
class TvButton extends StatelessWidget {
  /// Creates the button.
  const new({
    required this.label,
    this.icon,
    this.onTap,
    this.onLongPress,
    this.onKey,
    this.focusNode,
    this.autofocus = false,
    this.selected = false,
    this.expand = false,
    this.fontSize = 22,
    super.key,
  });

  /// The text.
  final String label;

  /// The icon before the text.
  final IconData? icon;

  /// OK.
  final VoidCallback? onTap;

  /// A held OK.
  final VoidCallback? onLongPress;

  /// Keys before the default handling.
  final TvKeyHandler? onKey;

  /// The node.
  final FocusNode? focusNode;

  /// Takes the focus when first built.
  final bool autofocus;

  /// Marked as the current choice.
  final bool selected;

  /// Fills the width.
  final bool expand;

  /// The text size in design pixels.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = TvTheme.of(context);
    final scale = TvScale.of(context);
    return TvFocusable(
      focusNode: focusNode,
      autofocus: autofocus,
      onTap: onTap,
      onLongPress: onLongPress,
      onKey: onKey,
      radius: 40,
      builder: (context, focused) {
        final background = focused
            ? palette.focus
            : selected
            ? palette.focus.withValues(alpha: 0.22)
            : palette.card.withValues(alpha: 0.9);
        final foreground = focused ? palette.onFocus : (selected ? palette.focus : palette.text);
        return AnimatedContainer(
          duration: focused ? const Duration(milliseconds: 120) : Duration.zero,
          padding: EdgeInsets.symmetric(horizontal: scale.text(22), vertical: scale.text(10)),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(scale(40))),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: scale.text(fontSize + 4), color: foreground),
                SizedBox(width: scale.text(10)),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: scale.style(fontSize, weight: FontWeight.w600, color: foreground),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Moves the focus into the route on top once it is up: a dialog opened by
/// a page that does not focus anything leaves the remote nowhere until an
/// arrow is pressed. Retries for a few frames while the route comes in.
void tvFocusFirstInRoute({int frames = 3}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final primary = FocusManager.instance.primaryFocus;
    if (primary is FocusScopeNode && primary.traversalDescendants.isNotEmpty) {
      primary.traversalDescendants.first.requestFocus();
      return;
    }
    if (frames > 1) tvFocusFirstInRoute(frames: frames - 1);
  });
}
