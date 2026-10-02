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

/// The remote's menu key (Android `KEYCODE_MENU`): the same as a held OK
/// (UI_PLAN §5.4, docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件 c10).
bool isTvMenuKey(LogicalKeyboardKey key) => key == LogicalKeyboardKey.contextMenu;

/// How long OK must be held to count as a long press.
const Duration tvLongPressDelay = Duration(milliseconds: 500);

/// How much a focused card, button or tab grows (U.15a c2).
const double tvFocusZoom = 1.05;

/// How much a held OK shrinks the target (pure_live_TV's press, kept by
/// U.15a c1).
const double tvPressScale = 0.97;

/// The width of the focus ring, in canvas pixels (UI_PLAN §5.5).
const double tvFocusRingWidth = 3;

/// How a focusable answers a key before the default handling; return
/// [KeyEventResult.handled] to keep it (a grid moving by index, a row that
/// opens its options on Right).
typedef TvKeyHandler = KeyEventResult Function(FocusNode node, KeyEvent event);

/// Builds a focusable's content for its focus state.
// The builder shape of pure_live_TV's `TvFocusableBuilder`.
// ignore: avoid_positional_boolean_parameters
typedef TvFocusBuilder = Widget Function(BuildContext context, bool focused);

/// One remote-control target with the TV's single focus look
/// (docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件 c2): a near-white 3 px ring outside the target and,
/// for cards, buttons, tabs and menu items ([zoom]), 5 % growth; no glow.
/// Whole rows (settings rows, dialog options, input fields) pass
/// `zoom: false`: growing a full-width row would push it off the screen.
/// Gaining focus animates (120 ms), losing it snaps, so a held arrow never
/// leaves a trail of half-lit items; a held OK shrinks the target a little.
/// The `tvFocusZoom` setting turns the growth off on slow boxes.
///
/// OK is a tap, a held OK (at least [tvLongPressDelay]) or the menu key is
/// the long press, and the release of a long press never also taps.
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
    this.enabled = true,
    this.radius = TvRadius.card,
    this.zoom = true,
    this.ring = true,
    super.key,
  });

  /// The content for the focus state.
  final TvFocusBuilder builder;

  /// OK, Enter or a tap.
  final VoidCallback? onTap;

  /// A held OK, the menu key, a long press or a right click.
  final VoidCallback? onLongPress;

  /// Keys before the default handling.
  final TvKeyHandler? onKey;

  /// Focus gained or lost.
  final ValueChanged<bool>? onFocusChange;

  /// The node; one is made when null.
  final FocusNode? focusNode;

  /// Takes the focus when first built.
  final bool autofocus;

  /// False skips the target when moving the focus (a disabled button).
  final bool enabled;

  /// The corner radius of the ring, in canvas pixels.
  final double radius;

  /// Grows by [tvFocusZoom] when focused (cards, buttons, tabs, menu items).
  final bool zoom;

  /// Draws the focus ring when focused.
  final bool ring;

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

  void _setPressed(bool pressed) {
    if (_pressed == pressed) return;
    if (mounted) setState(() => _pressed = pressed);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final custom = widget.onKey?.call(node, event);
    if (custom == KeyEventResult.handled) return custom!;
    final key = event.logicalKey;
    if (isTvMenuKey(key) && widget.onLongPress != null) {
      if (event is KeyDownEvent) widget.onLongPress?.call();
      return KeyEventResult.handled;
    }
    if (!isTvConfirmKey(key)) return custom ?? KeyEventResult.ignored;
    if (widget.onTap == null && widget.onLongPress == null) return KeyEventResult.ignored;
    switch (event) {
      case KeyDownEvent():
        if (widget.onLongPress == null) {
          // Nothing to tell apart: act at once.
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        _setPressed(true);
        _longFired = false;
        _hold?.cancel();
        _hold = Timer(tvLongPressDelay, () {
          if (!_pressed || !mounted) return;
          _longFired = true;
          _setPressed(false);
          widget.onLongPress?.call();
        });
        return KeyEventResult.handled;
      case KeyRepeatEvent():
        // A held key repeats; the timer decides, and a held OK on a plain
        // button does not fire again.
        return KeyEventResult.handled;
      case KeyUpEvent():
        final fired = _longFired;
        _longFired = false;
        _hold?.cancel();
        if (!_pressed && !fired) return KeyEventResult.ignored;
        _setPressed(false);
        // The release of a long press never also taps (pure_live_TV
        // `DpadLongPressGate`).
        if (!fired) widget.onTap?.call();
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
    final zoom = widget.zoom && TvTheme.zoomOf(context) ? tvFocusZoom : 1.0;
    final target = _focused ? (_pressed ? zoom * tvPressScale : zoom) : (_pressed ? tvPressScale : 1.0);
    final ringOn = _focused && widget.ring;
    final content = widget.builder(context, _focused);
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      skipTraversal: !widget.enabled,
      onKeyEvent: _onKey,
      onFocusChange: _focusChanged,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null || !widget.enabled ? null : _tap,
        onLongPress: widget.onLongPress == null || !widget.enabled ? null : _longPress,
        onSecondaryTap: widget.onLongPress == null || !widget.enabled ? null : _longPress,
        child: AnimatedScale(
          scale: target,
          duration: _focused ? tvFocusDuration : Duration.zero,
          curve: Curves.easeOutCubic,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: ringOn
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(scale.px(widget.radius)),
                    border: Border.all(
                      color: palette.focusRing,
                      width: scale.px(tvFocusRingWidth),
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                  )
                : const BoxDecoration(),
            child: content,
          ),
        ),
      ),
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
