import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/version/update_feed.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:window_manager/window_manager.dart';

/// The window's own title bar on Windows (3.x `CustomTitleBar`): the icon and
/// name (opens the project page), a drag area, minimize, maximize/restore
/// and close (which follows the close setting). Hidden in full screen.
class DesktopTitleBar extends StatelessWidget {
  /// Creates the bar.
  const new({this.onClose, super.key});

  /// The close button; null asks the desktop shell.
  final Future<void> Function()? onClose;

  /// The bar's height (3.x).
  static const double height = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final foreground = dark ? Colors.white.withValues(alpha: 0.75) : Colors.black87;
    final hover = dark ? Colors.white.withValues(alpha: 0.08) : theme.colorScheme.primary.withValues(alpha: 0.08);
    final colors = theme.colorScheme;
    return ValueListenableBuilder<String>(
      valueListenable: liveRouteObserver.currentRoute,
      builder: (context, route, bar) => DecoratedBox(
        // On the splash page the bar continues its gradient (3.x).
        decoration: route == RoutePath.kSplash
            ? BoxDecoration(
                gradient: LinearGradient(
                  colors: dark
                      ? [colors.surface, colors.surfaceContainer]
                      : [colors.surface, colors.primaryContainer.withValues(alpha: 0.6)],
                ),
              )
            : BoxDecoration(color: dark ? Colors.black : theme.scaffoldBackgroundColor),
        child: bar,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              Expanded(
                child: DragToMoveArea(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      key: const ValueKey('title-bar-project'),
                      onTap: () => unawaited(AppNavigator.openExternal(projectUrl)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/icons/icon.png', width: 16, height: 16),
                            const SizedBox(width: 6),
                            Text(
                              i18n('app_name'),
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: foreground),
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
                                        style: TextStyle(fontSize: 12, color: foreground.withValues(alpha: 0.6)),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _WindowButton(
                key: const ValueKey('title-bar-minimize'),
                label: i18n('window_minimize'),
                icon: Icons.remove,
                color: foreground,
                hover: hover,
                onPressed: windowManager.minimize,
              ),
              _WindowButton(
                key: const ValueKey('title-bar-maximize'),
                label: i18n('window_maximize_restore'),
                icon: Icons.crop_square,
                color: foreground,
                hover: hover,
                onPressed: () async {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
              ),
              _WindowButton(
                key: const ValueKey('title-bar-close'),
                label: i18n('window_close'),
                icon: Icons.close,
                color: foreground,
                hover: const Color(0xFFE81123),
                hoverColor: Colors.white,
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
}

class _WindowButton extends StatefulWidget {
  const new({
    required this.label,
    required this.icon,
    required this.color,
    required this.hover,
    required this.onPressed,
    this.hoverColor,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color hover;
  final Color? hoverColor;
  final Future<void> Function() onPressed;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  Future<void> _run() async {
    try {
      await widget.onPressed();
    } on Object {
      AppNavigator.toast(i18n('window_close_action_failed'));
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    excludeSemantics: true,
    // The bar sits beside the Navigator, outside its Overlay: no Tooltip.
    child: InkWell(
      onTap: () => unawaited(_run()),
      onHover: (value) => setState(() => _hovered = value),
      child: Container(
        width: 46,
        height: DesktopTitleBar.height,
        color: _hovered ? widget.hover : Colors.transparent,
        alignment: Alignment.center,
        child: Icon(widget.icon, size: 16, color: _hovered ? (widget.hoverColor ?? widget.color) : widget.color),
      ),
    ),
  );
}

/// The app with the title bar above it on Windows (3.x
/// `DesktopManager.buildWithTitleBar`); [enabled] is false elsewhere.
class DesktopFrame extends StatelessWidget {
  /// Creates the frame around [child].
  const new({required this.child, required this.enabled, super.key});

  /// The app.
  final Widget child;

  /// Whether to draw the title bar (Windows with the desktop shell).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: DesktopWindow.fullScreen,
      builder: (context, fullScreen, _) => Column(
        children: [
          if (!fullScreen) const DesktopTitleBar(),
          Expanded(child: child),
        ],
      ),
    );
  }
}
