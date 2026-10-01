import 'dart:async';

import 'package:pure_live/i18n/i18n.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// The tray icon of the main window (3.x `DesktopTrayService`): a click
/// shows the window, the menu shows or hides it and exits. The native
/// objects are made once and reused (3.x: new items per right-click piled
/// up callbacks).
final class DesktopTray {
  new _(this._icon, this._image, this._menu, this._windowItem, this._exitItem);

  /// Makes the tray icon; throws when the system refuses.
  factory create({
    required Future<void> Function() onShow,
    required Future<void> Function() onHide,
    required Future<void> Function() onExit,
  }) {
    final icon = TrayIcon.create() ?? (throw StateError('No tray icon'));
    final image = ImageAsset.fromAsset('assets/icons/icon.png') ?? (throw StateError('No tray image'));
    final menu = Menu.create() ?? (throw StateError('No tray menu'));
    final windowItem = MenuItem.createWithLabelAndType('', MenuItemType.normal) ?? (throw StateError('No menu item'));
    final exitItem = MenuItem.createWithLabelAndType('', MenuItemType.normal) ?? (throw StateError('No menu item'));
    final tray = DesktopTray._(icon, image, menu, windowItem, exitItem);
    icon
      ..icon = image
      // The menu is relabelled before it opens (the window may have been
      // hidden meanwhile), so it is not opened by the system on release.
      ..setContextMenuTrigger(ContextMenuTrigger.none);
    tray._listeners.add(() {
      final id = icon.addListener((event) {
        if (event is TrayIconClickedEvent) unawaited(onShow());
        if (event is TrayIconRightClickedEvent) unawaited(tray._openMenu());
      });
      return () => icon.removeListener(id);
    }());
    Future<void> toggle() async {
      if (await windowManager.isVisible()) {
        await onHide();
      } else {
        await onShow();
      }
    }

    tray._listeners.add(() {
      final id = windowItem.addListener((event) {
        if (event is MenuItemClickedEvent) unawaited(toggle());
      });
      return () => windowItem.removeListener(id);
    }());
    tray._listeners.add(() {
      final id = exitItem.addListener((event) {
        if (event is MenuItemClickedEvent) unawaited(onExit());
      });
      return () => exitItem.removeListener(id);
    }());
    menu
      ..addItem(windowItem)
      ..addSeparator()
      ..addItem(exitItem);
    icon.setContextMenu(menu);
    tray.relabel();
    if (!icon.setVisible(true)) {
      tray.dispose();
      throw StateError('The tray icon was not shown');
    }
    return tray;
  }

  final TrayIcon _icon;
  final Image _image;
  final Menu _menu;
  final MenuItem _windowItem;
  final MenuItem _exitItem;
  final List<void Function()> _listeners = [];

  /// Updates the words (the language may have changed).
  void relabel({bool visible = true}) {
    _icon.setTooltip(i18nOr('app_name', 'PureLive'));
    _windowItem.label = i18n(visible ? 'hide_window' : 'show_window');
    _exitItem.label = i18n('exit_app');
  }

  Future<void> _openMenu() async {
    relabel(visible: await windowManager.isVisible());
    _icon.openContextMenu();
  }

  /// Removes the icon.
  void dispose() {
    for (final remove in _listeners) {
      remove();
    }
    _listeners.clear();
    _icon
      ..setContextMenu(null)
      ..setVisible(false)
      ..dispose();
    _menu.dispose();
    _windowItem.dispose();
    _exitItem.dispose();
    _image.dispose();
  }
}
