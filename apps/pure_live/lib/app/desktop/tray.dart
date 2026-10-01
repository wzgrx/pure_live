import 'dart:async';

import 'package:pure_live/i18n/i18n.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// The rows of the tray menu (3.x `DesktopTrayService`; docs/ui/compare/U.13
/// c9, T4): while recording, "正在录制 N 个直播间" (greyed) and a separator
/// first; then "隐藏窗口 / 显示窗口", a separator and "退出应用".
enum TrayRow {
  /// "正在录制 N 个直播间", not clickable.
  recording,

  /// A line.
  separator,

  /// "隐藏窗口" or "显示窗口".
  window,

  /// "退出应用" (asks first while recording).
  exit,
}

/// The tray menu's rows while [recording] rooms record.
List<TrayRow> trayMenuRows({required int recording}) => [
  if (recording > 0) ...[TrayRow.recording, TrayRow.separator],
  TrayRow.window,
  TrayRow.separator,
  TrayRow.exit,
];

/// The words of [row] ([visible]: the window is showing).
String trayRowLabel(TrayRow row, {required bool visible, required int recording}) => switch (row) {
  TrayRow.recording => i18n('recording_rooms_count', args: {'count': '$recording'}),
  TrayRow.separator => '',
  TrayRow.window => i18n(visible ? 'hide_window' : 'show_window'),
  TrayRow.exit => i18n('exit_app'),
};

/// The tray icon's hint: "纯粹直播", and how many rooms record (T4).
String trayTooltip({required int recording}) =>
    recording > 0 ? i18n('tray_tooltip_recording', args: {'count': '$recording'}) : i18nOr('app_name', 'PureLive');

/// The tray icon of the main window (3.x `DesktopTrayService`): a click
/// shows the window, the menu shows or hides it and exits; while recording
/// the hint and the menu's first row say how many rooms (U.13 c9). The
/// native objects are made once and reused (3.x: new items per right-click
/// piled up callbacks).
final class DesktopTray {
  new _(this._icon, this._image, this._menu, this._recordingItem, this._windowItem, this._exitItem);

  /// Makes the tray icon; throws when the system refuses. [onExit] is the
  /// menu's "退出应用".
  factory create({
    required Future<void> Function() onShow,
    required Future<void> Function() onHide,
    required Future<void> Function() onExit,
  }) {
    final icon = TrayIcon.create() ?? (throw StateError('No tray icon'));
    final image = ImageAsset.fromAsset('assets/icons/icon.png') ?? (throw StateError('No tray image'));
    final menu = Menu.create() ?? (throw StateError('No tray menu'));
    MenuItem item() => MenuItem.createWithLabelAndType('', MenuItemType.normal) ?? (throw StateError('No menu item'));
    final recordingItem = item()..isEnabled = false;
    final windowItem = item();
    final exitItem = item();
    final tray = DesktopTray._(icon, image, menu, recordingItem, windowItem, exitItem);
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
    tray._fill(visible: true);
    icon.setContextMenu(menu);
    if (!icon.setVisible(true)) {
      tray.dispose();
      throw StateError('The tray icon was not shown');
    }
    return tray;
  }

  final TrayIcon _icon;
  final Image _image;
  final Menu _menu;
  final MenuItem _recordingItem;
  final MenuItem _windowItem;
  final MenuItem _exitItem;
  final List<void Function()> _listeners = [];
  int _recording = 0;

  /// Fills the menu with [trayMenuRows] and their words.
  void _fill({required bool visible}) {
    _menu.clear();
    for (final row in trayMenuRows(recording: _recording)) {
      final item = switch (row) {
        TrayRow.recording => _recordingItem,
        TrayRow.window => _windowItem,
        TrayRow.exit => _exitItem,
        TrayRow.separator => null,
      };
      if (item == null) {
        _menu.addSeparator();
      } else {
        item.label = trayRowLabel(row, visible: visible, recording: _recording);
        _menu.addItem(item);
      }
    }
    _icon.setTooltip(trayTooltip(recording: _recording));
  }

  /// How many rooms record: only the hint changes now, the menu when it
  /// opens.
  void setRecording(int count) {
    if (count == _recording) return;
    _recording = count;
    _icon.setTooltip(trayTooltip(recording: count));
  }

  /// Updates the words (the language may have changed).
  void relabel({bool visible = true}) => _fill(visible: visible);

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
    _recordingItem.dispose();
    _windowItem.dispose();
    _exitItem.dispose();
    _image.dispose();
  }
}
