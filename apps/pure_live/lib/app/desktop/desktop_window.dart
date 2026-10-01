import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/desktop/startup_entry.dart';
import 'package:pure_live/app/desktop/tray.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// What the pages ask of the desktop window (the live room's and
/// multi-view's full screen). Without a desktop shell (phones, tests) only
/// [fullScreen] changes.
abstract final class DesktopWindow {
  /// Whether the window fills the screen; the title bar hides meanwhile
  /// (3.x `GlobalPlayerState.isWindowFullscreen`).
  static final ValueNotifier<bool> fullScreen = ValueNotifier(false);

  static Future<void> Function({required bool on})? _setFullScreen;

  /// Puts the window into ([on]) or out of full screen (3.x `WindowHelper`).
  static Future<void> setFullScreen({required bool on}) async {
    if (fullScreen.value == on) return;
    fullScreen.value = on;
    try {
      await _setFullScreen?.call(on: on);
    } on Object catch (error, stack) {
      log('Full screen failed', name: 'Desktop', error: error, stackTrace: stack);
    }
  }
}

/// The meta key of the main window's last position (`x,y`, logical pixels).
const String windowPositionKey = 'window.position';

/// The Windows window (3.x `DesktopManager`, `DesktopWindowMixin`,
/// `WindowSizeController`): no system title bar (the app draws
/// `DesktopTitleBar`), the size and place of last time, the tray, what the
/// close button does ([Settings.exitChoose], [Settings.dontAskExit]) and the
/// start-up entry ([Settings.enableStartUp]).
final class DesktopShell with WindowListener {
  new _(this._store, {required this.primary});

  final LiveStore _store;

  /// The main window (extra windows have no tray and simply close).
  final bool primary;

  DesktopTray? _tray;
  Timer? _saveTimer;
  StreamSubscription<Setting<Object>>? _settings;
  Future<void>? _closing;

  /// The shell of this window; null before [start] and off Windows.
  static DesktopShell? current;

  /// Smallest window (3.x `WindowSizeController.minWindowWidth/Height`).
  static const Size minimumSize = Size(400, 300);

  /// Sets the window up before the first frame; nothing off Windows.
  static Future<void> start(LiveStore store, {required bool primary}) async {
    if (!Platform.isWindows || current != null) return;
    final shell = current = DesktopShell._(store, primary: primary);
    await shell._start();
  }

  SettingsStore get _prefs => _store.settings;

  Future<void> _start() async {
    await windowManager.ensureInitialized();
    final size = Size(_prefs.get(Settings.windowWidth), _prefs.get(Settings.windowHeight));
    final position = primary ? parseWindowPosition(await _store.meta.get(windowPositionKey)) : null;
    final options = WindowOptions(
      size: size,
      minimumSize: minimumSize,
      center: position == null,
      title: i18nOr('app_name', 'PureLive'),
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setPreventClose(true);
      if (position != null && await _onScreen(position, size)) await windowManager.setPosition(position);
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(this);
    DesktopWindow._setFullScreen = ({required on}) => windowManager.setFullScreen(on);
    if (primary) {
      try {
        _tray = DesktopTray.create(onShow: show, onHide: windowManager.hide, onExit: exit);
      } on Object catch (error, stack) {
        // Without a tray, "minimize" minimizes to the taskbar.
        log('Tray failed', name: 'Desktop', error: error, stackTrace: stack);
      }
      _settings = _prefs.changes.listen((setting) {
        if (setting.key != Settings.enableStartUp.key) return;
        unawaited(applyStartupEntry(enabled: _prefs.get(Settings.enableStartUp)));
      });
      if (isReleaseBuild) unawaited(applyStartupEntry(enabled: _prefs.get(Settings.enableStartUp)));
    }
  }

  /// Whether [position] puts most of the window's title row on a display
  /// (a monitor unplugged since last time would hide it).
  Future<bool> _onScreen(Offset position, Size size) async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      final title = Rect.fromLTWH(position.dx + 40, position.dy, math.max(size.width - 80, 40), 32);
      return displays.any((display) {
        final origin = display.visiblePosition ?? Offset.zero;
        final area = origin & (display.visibleSize ?? display.size);
        return area.overlaps(title);
      });
    } on Object {
      return false;
    }
  }

  /// Shows and focuses the window (tray, second launch).
  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Closes the app: saves the window and leaves (3.x
  /// `exitDesktopApplication`).
  Future<void> exit() async {
    await _saveGeometry();
    _tray?.dispose();
    _tray = null;
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  /// The title bar's or the system's close (3.x `handleWindowClose`): an
  /// extra window closes; the main window asks, or does what was chosen.
  Future<void> requestClose() => _closing ??= _close().whenComplete(() => _closing = null);

  Future<void> _close() async {
    if (!primary) {
      await exit();
      return;
    }
    var action = _prefs.get(Settings.exitChoose);
    if (!_prefs.get(Settings.dontAskExit)) {
      final context = AppNavigator.navigatorContext;
      if (context == null) {
        await exit();
        return;
      }
      final choice = await showDialog<({String action, bool remember})>(
        context: context,
        builder: (_) => _CloseDialog(initial: action),
      );
      if (choice == null) return;
      action = choice.action;
      await _prefs.setAll({Settings.exitChoose: action, Settings.dontAskExit: choice.remember});
    }
    try {
      if (action == 'minimize') {
        await (_tray == null ? windowManager.minimize() : windowManager.hide());
      } else {
        await exit();
      }
    } on Object catch (error, stack) {
      log('Window close failed', name: 'Desktop', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('window_close_action_failed'));
    }
  }

  @override
  void onWindowClose() => unawaited(requestClose());

  @override
  void onWindowResized() => _scheduleSave();

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowEnterFullScreen() => DesktopWindow.fullScreen.value = true;

  @override
  void onWindowLeaveFullScreen() => DesktopWindow.fullScreen.value = false;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () => unawaited(_saveGeometry()));
  }

  /// Remembers the normal window's size (3.x) and place (new): not while
  /// maximized, minimized or full screen.
  Future<void> _saveGeometry() async {
    _saveTimer?.cancel();
    try {
      if (await windowManager.isMaximized() ||
          await windowManager.isMinimized() ||
          await windowManager.isFullScreen()) {
        return;
      }
      final bounds = await windowManager.getBounds();
      await _prefs.setAll({
        Settings.windowWidth: bounds.width.clamp(minimumSize.width, 16384).toDouble(),
        Settings.windowHeight: bounds.height.clamp(minimumSize.height, 16384).toDouble(),
      });
      if (primary) await _store.meta.set(windowPositionKey, formatWindowPosition(bounds.topLeft));
    } on Object catch (error, stack) {
      log('Saving the window failed', name: 'Desktop', error: error, stackTrace: stack);
    }
  }

  /// Updates the tray's words (language changes).
  void relabel() => _tray?.relabel();

  /// Stops listening (tests, shutdown).
  Future<void> dispose() async {
    windowManager.removeListener(this);
    _saveTimer?.cancel();
    await _settings?.cancel();
    _tray?.dispose();
    if (identical(current, this)) current = null;
  }
}

/// `x,y` of a stored window position; null when missing or unreadable.
Offset? parseWindowPosition(String? text) {
  final parts = (text ?? '').split(',');
  if (parts.length != 2) return null;
  final x = double.tryParse(parts[0]);
  final y = double.tryParse(parts[1]);
  if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
  return Offset(x, y);
}

/// The stored form of a window position.
String formatWindowPosition(Offset position) => '${position.dx.round()},${position.dy.round()}';

/// Whether this is a release build (the start-up entry is only reconciled at
/// launch there, so development builds never register themselves).
const bool isReleaseBuild = bool.fromEnvironment('dart.vm.product');

/// Asks what the close button does (3.x `_ExitDecisionDialog`).
class _CloseDialog extends StatefulWidget {
  const new({required this.initial});

  final String initial;

  @override
  State<_CloseDialog> createState() => _CloseDialogState();
}

class _CloseDialogState extends State<_CloseDialog> {
  late String _action = widget.initial;
  bool _remember = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(i18n('settings_exit_action')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RadioGroup<String>(
          groupValue: _action,
          onChanged: (value) => setState(() => _action = value ?? _action),
          child: Column(
            children: [
              RadioListTile<String>(
                key: const ValueKey('close-minimize'),
                value: 'minimize',
                title: Text(i18n('settings_exit_action_minimize')),
              ),
              RadioListTile<String>(
                key: const ValueKey('close-exit'),
                value: 'exit',
                title: Text(i18n('settings_exit_action_exit')),
              ),
            ],
          ),
        ),
        CheckboxListTile(
          key: const ValueKey('close-remember'),
          value: _remember,
          onChanged: (value) => setState(() => _remember = value ?? false),
          title: Text(i18n('dont_ask_again')),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(i18n('cancel'))),
      FilledButton(
        key: const ValueKey('close-confirm'),
        onPressed: () => Navigator.pop(context, (action: _action, remember: _remember)),
        child: Text(i18n('confirm')),
      ),
    ],
  );
}
