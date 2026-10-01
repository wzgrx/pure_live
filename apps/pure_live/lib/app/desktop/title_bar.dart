import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';

/// The streamer of the room [page] shows, for the window's title (U.13
/// c11); null on any other page or when the room has no name yet.
String? roomNameOf(RouteSettings? page) {
  if (page?.name != RoutePath.kLivePlay) return null;
  final room = page?.arguments;
  if (room is! LiveRoom) return null;
  final nick = room.nick.trim();
  return nick.isEmpty ? null : nick;
}

/// The window's name in the taskbar and Alt+Tab: "晚风 - 纯粹直播" in a room,
/// else the app's name (c11).
String nativeWindowTitle(String app, String? room) => room == null ? app : '$room - $app';

/// The window's own title bar (3.x `CustomTitleBar`; docs/ui/compare/U.13):
/// the icon (a click opens the system's window menu, c13), the name with
/// the room's streamer (c11) and the size while the edge is dragged, a drag
/// area (double click maximizes or restores, a right click opens the window
/// menu), and minimize, maximize or restore (c3) and close, each named
/// under the pointer. The ground is the page's surface in both themes and on
/// the splash page (c4).
class DesktopTitleBar extends StatelessWidget {
  /// Creates the bar.
  const new({this.onClose, super.key});

  /// The close button; null asks the desktop shell.
  final Future<void> Function()? onClose;

  /// The bar's height (3.x).
  static const double height = 32;

  /// A window button's width (3.x).
  static const double buttonWidth = 46;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = colors.onSurface;
    final hover = colors.onSurface.withValues(alpha: 0.08);
    final controls = DesktopWindow.controls;
    final name = TextStyle(fontSize: 13, height: 1.2, fontWeight: FontWeight.w600, color: foreground);
    // Window chrome: the system's font scale does not grow it past 32.
    return MediaQuery.withNoTextScaling(
      child: Material(
        key: const ValueKey('title-bar'),
        color: colors.surface,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              const SizedBox(width: 8),
              _IconButton(
                key: const ValueKey('title-bar-icon'),
                hover: hover,
                onPressed: () => controls?.showSystemMenu(),
              ),
              Expanded(
                child: GestureDetector(
                  key: const ValueKey('title-bar-drag'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => unawaited(controls?.startDragging()),
                  onDoubleTap: () => unawaited(_toggleMaximize(controls)),
                  onSecondaryTapUp: (_) => unawaited(controls?.showSystemMenu()),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Row(
                      children: [
                        Text(i18n('app_name'), style: name, maxLines: 1),
                        // "· 晚风" while a room is open (c11).
                        _RoomName(
                          style: name.copyWith(fontWeight: FontWeight.w400, color: foreground.withValues(alpha: 0.75)),
                        ),
                        // The size while the edge is dragged (3.x).
                        ValueListenableBuilder<Size?>(
                          valueListenable: DesktopWindow.resizing,
                          builder: (context, size, _) => size == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Text(
                                    '[${size.width.round()} × ${size.height.round()}]',
                                    key: const ValueKey('title-bar-size'),
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: foreground.withValues(alpha: 0.6),
                                    ).tabular,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _WindowButton(
                key: const ValueKey('title-bar-minimize'),
                label: i18n('window_button_minimize'),
                icon: AppIcons.windowMinimize,
                color: foreground,
                hover: hover,
                onPressed: () async => await controls?.minimize(),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: DesktopWindow.maximized,
                builder: (context, maximized, _) => _WindowButton(
                  key: const ValueKey('title-bar-maximize'),
                  label: i18n(maximized ? 'window_button_restore' : 'window_button_maximize'),
                  icon: maximized ? AppIcons.windowRestore : AppIcons.windowMaximize,
                  color: foreground,
                  hover: hover,
                  onPressed: () => _toggleMaximize(controls),
                ),
              ),
              _WindowButton(
                key: const ValueKey('title-bar-close'),
                label: i18n('window_button_close'),
                icon: AppIcons.windowClose,
                color: foreground,
                hover: WindowButtonColors.closeHover,
                hoverForeground: WindowButtonColors.onCloseHover,
                onPressed:
                    onClose ??
                    () async {
                      await DesktopShell.current?.requestClose();
                    },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _toggleMaximize(WindowControls? controls) async {
    if (controls == null) return;
    await (DesktopWindow.maximized.value ? controls.restore() : controls.maximize());
  }
}

/// "· 晚风" while a room is the page on top (c11).
class _RoomName extends StatefulWidget {
  const new({required this.style});

  final TextStyle style;

  @override
  State<_RoomName> createState() => _RoomNameState();
}

class _RoomNameState extends State<_RoomName> {
  String? _room = roomNameOf(liveRouteObserver.topPage.value);

  @override
  void initState() {
    super.initState();
    liveRouteObserver.topPage.addListener(_changed);
  }

  @override
  void dispose() {
    liveRouteObserver.topPage.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final room = roomNameOf(liveRouteObserver.topPage.value);
    if (room == _room) return;
    // The navigator below the bar pushes while the frame builds: the bar,
    // already built, follows in the next frame.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _room = roomNameOf(liveRouteObserver.topPage.value));
      });
    } else {
      setState(() => _room = room);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    if (room == null) return const SizedBox.shrink();
    return Flexible(
      child: Text(
        ' · $room',
        key: const ValueKey('title-bar-room'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style,
      ),
    );
  }
}

/// The app icon at the left: a click opens the system's window menu (c13;
/// 3.x opened the project page).
class _IconButton extends StatefulWidget {
  const new({required this.hover, required this.onPressed, super.key});

  final Color hover;
  final VoidCallback onPressed;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: i18n('window_menu'),
    excludeSemantics: true,
    child: MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        onSecondaryTap: widget.onPressed,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? widget.hover : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Image.asset('assets/icons/icon.png', width: 16, height: 16),
        ),
      ),
    ),
  );
}

class _WindowButton extends StatefulWidget {
  const new({
    required this.label,
    required this.icon,
    required this.color,
    required this.hover,
    required this.onPressed,
    this.hoverForeground,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color hover;
  final Color? hoverForeground;
  final Future<void> Function() onPressed;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;
  bool _focused = false;

  Future<void> _run() async {
    try {
      await widget.onPressed();
    } on Object {
      AppNavigator.toast(i18n('window_close_action_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = _focused && FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final button = Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: () => unawaited(_run()),
        onHover: (value) => setState(() => _hovered = value),
        onFocusChange: (value) => setState(() => _focused = value),
        hoverColor: widget.hover.withValues(alpha: 0),
        highlightColor: widget.hover,
        splashFactory: NoSplash.splashFactory,
        child: Container(
          width: DesktopTitleBar.buttonWidth,
          height: DesktopTitleBar.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered || keyboard ? widget.hover : null,
            // A frame while the keyboard is on the button (3.x).
            border: keyboard ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2) : null,
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: _hovered || keyboard ? (widget.hoverForeground ?? widget.color) : widget.color,
          ),
        ),
      ),
    );
    // The name under the pointer (c3); the bar sits beside the Navigator,
    // so [DesktopFrame] gives it an overlay of its own.
    if (Overlay.maybeOf(context) == null) return button;
    return Tooltip(message: widget.label, waitDuration: const Duration(milliseconds: 500), child: button);
  }
}

/// The app with the title bar above it (3.x
/// `DesktopManager.buildWithTitleBar`); [enabled] where the desktop shell
/// runs (it draws the bar on every desktop it runs on, Linux included, c2).
class DesktopFrame extends StatelessWidget {
  /// Creates the frame around [child].
  const new({required this.child, required this.enabled, super.key});

  /// The app.
  final Widget child;

  /// Whether to draw the title bar (the desktop shell runs).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    // No title bar in full screen, nor on the room's mini window (U.2j).
    // The overlay lets the bar show its buttons' names over the page.
    return Overlay.wrap(
      child: ListenableBuilder(
        listenable: Listenable.merge([DesktopWindow.fullScreen, DesktopWindow.mini]),
        builder: (context, _) => Column(
          children: [
            if (!DesktopWindow.fullScreen.value && !DesktopWindow.mini.value) const DesktopTitleBar(),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
