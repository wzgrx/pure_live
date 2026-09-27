import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/desktop_window.dart';
import 'package:pure_live_app/features/system/close_behaviour.dart';
import 'package:pure_live_app/features/system/launch_args.dart';
import 'package:pure_live_app/features/system/windows_native.dart';
import 'package:pure_live_app/i18n/strings.g.dart';
import 'package:window_manager/window_manager.dart';

/// The `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` value of this app.
/// The preview uses its own name so it never touches 3.x's `PureLive` entry;
/// the release that replaces 3.x switches to `PureLive` (ADR 0025).
const autostartValueName = 'PureLiveNext';

/// The Windows shell around the main window: tray icon (F-WIN-03), close
/// behaviour (F-WIN-04), launch at login (F-WIN-05) and launches forwarded by
/// a second start (F-WIN-01). An extra window (F-WIN-02) has no tray, no
/// autostart and quits when closed.
final class WindowsShell with WindowListener {
  /// Creates the shell; [start] wires it up.
  new({
    required this.native,
    required this.window,
    required this.settings,
    required this.secondaryWindow,
    required this.askClose,
    required this.openRoom,
    required this.beforeExit,
  });

  /// The runner channel.
  final WindowsNative native;

  /// The main window.
  final DesktopWindowOps window;

  /// Settings.
  final SettingsStore settings;

  /// This process is an extra window.
  final bool secondaryWindow;

  /// Shows the close dialog; null when dismissed.
  final Future<CloseAnswer?> Function() askClose;

  /// Opens a room page.
  final void Function(RoomRef room) openRoom;

  /// Releases playback before the process ends (SURF-2 order runs in the
  /// player's release).
  final Future<void> Function() beforeExit;

  final _subscriptions = <StreamSubscription<Object?>>[];
  var _exiting = false;

  /// Tray labels.
  static String get trayTooltip => t.app.name;

  /// Starts listening, shows the tray icon and applies the autostart setting;
  /// finally tells the runner to deliver queued forwarded launches.
  Future<void> start() async {
    _subscriptions
      ..add(native.forwardedArguments.listen(onForwardedArguments))
      ..add(native.trayEvents.listen(onTrayEvent));
    await window.setPreventClose(preventClose: true);
    if (!secondaryWindow) {
      await native.showTray(
        tooltip: trayTooltip,
        show: t.system.showWindow,
        hide: t.system.hideWindow,
        exit: t.common.exit,
      );
      await _applyAutostart(settings.get(Settings.launchAtStartup));
      _subscriptions.add(settings.watch(Settings.launchAtStartup).skip(1).listen(_applyAutostart));
    }
    await native.ready();
  }

  Future<void> _applyAutostart(bool enabled) async {
    await native.setLaunchAtStartup(name: autostartValueName, enabled: enabled);
  }

  @override
  void onWindowClose() => unawaited(handleClose());

  /// Applies the close behaviour (F-WIN-04).
  Future<void> handleClose() async {
    switch (closeChoice(
      secondaryWindow: secondaryWindow,
      dontAsk: settings.get(Settings.closeDontAsk),
      action: settings.get(Settings.closeAction),
    )) {
      case CloseChoice.exit:
        await exit();
      case CloseChoice.minimize:
        await window.hide();
      case CloseChoice.ask:
        final answer = await askClose();
        if (answer == null) return;
        if (answer.remember) {
          await settings.set(Settings.closeAction, answer.action);
          await settings.set(Settings.closeDontAsk, true);
        }
        if (answer.action == CloseAction.minimize) {
          await window.hide();
        } else {
          await exit();
        }
    }
  }

  /// Releases playback, removes the tray icon and ends the app.
  Future<void> exit() async {
    if (_exiting) return;
    _exiting = true;
    try {
      await beforeExit().timeout(const Duration(seconds: 3));
    } on Object {
      // Quit anyway.
    }
    await native.hideTray();
    await window.setPreventClose(preventClose: false);
    await window.destroy();
  }

  /// A tray event: a click shows or hides the window.
  void onTrayEvent(TrayEvent event) {
    switch (event) {
      case TrayEvent.click:
        unawaited(_toggle());
      case TrayEvent.show:
        unawaited(_show());
      case TrayEvent.hide:
        unawaited(window.hide());
      case TrayEvent.exit:
        unawaited(exit());
    }
  }

  Future<void> _toggle() async {
    if (await window.isVisible() && !await window.isMinimized()) {
      await window.hide();
    } else {
      await _show();
    }
  }

  Future<void> _show() async {
    await window.show();
    await window.focus();
  }

  /// A second launch: the runner already raised the window; a room argument
  /// opens the room (F-APP-04).
  void onForwardedArguments(List<String> arguments) {
    unawaited(_show());
    final room = LaunchArgs.parse(arguments).openRoom;
    if (room != null) openRoom(room);
  }

  /// Stops listening.
  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
  }
}

/// Keeps the system title bar in step with the app's theme (principles §5.4).
final class TitleBarSync with WidgetsBindingObserver {
  /// Reads the theme through [darkMode] (null: follow the system).
  new(this.native, this.darkMode);

  /// The runner channel.
  final WindowsNative native;

  /// true dark, false light, null follows the system.
  final bool? Function() darkMode;

  bool? _sent;

  /// Sends the current brightness if it changed.
  void update() {
    final forced = darkMode();
    final dark = forced ?? WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    if (dark == _sent) return;
    _sent = dark;
    unawaited(native.setTitleBarDark(dark: dark));
  }

  @override
  void didChangePlatformBrightness() => update();
}
