import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/desktop/close_dialog.dart';
import 'package:pure_live/app/desktop/mini_window.dart';
import 'package:pure_live/app/desktop/shared_data.dart';
import 'package:pure_live/app/desktop/startup_entry.dart';
import 'package:pure_live/app/desktop/title_bar.dart';
import 'package:pure_live/app/desktop/tray.dart';
import 'package:pure_live/app/launch_args.dart';
import 'package:pure_live/app/recording.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

export 'package:pure_live/app/desktop/mini_window.dart' show MiniWindowHost;

/// What the title bar asks of the window (docs/T17/T17a/T17a.1): the
/// shell's window_manager; tests set their own.
abstract interface class WindowControls {
  /// Minimizes the window to the taskbar.
  Future<void> minimize();

  /// Maximizes the window.
  Future<void> maximize();

  /// Gives a maximized window its size back.
  Future<void> restore();

  /// Opens the system's window menu at the pointer (restore, move, size,
  /// minimize, maximize, close; c13).
  Future<void> showSystemMenu();

  /// Moves the window with the pointer that is down.
  Future<void> startDragging();
}

/// What the pages ask of the desktop window (the live room's and
/// multi-view's full screen, the room's mini window, new windows). Without a
/// desktop shell (phones, tests) only [fullScreen] changes and there is no
/// mini window and no new window.
abstract final class DesktopWindow {
  /// Whether the window fills the screen; the title bar hides meanwhile
  /// (3.x `GlobalPlayerState.isWindowFullscreen`).
  static final ValueNotifier<bool> fullScreen = ValueNotifier(false);

  static Future<void> Function({required bool on})? _setFullScreen;

  /// The window's size while the user drags its edge (the title bar shows
  /// it, 3.x `WindowSizeController.isTracking`); null otherwise.
  static final ValueNotifier<Size?> resizing = ValueNotifier(null);

  /// Whether the window is maximized: the title bar's middle button
  /// restores it then (U.13 c3).
  static final ValueNotifier<bool> maximized = ValueNotifier(false);

  /// The title bar's window actions: the shell's, null without a desktop
  /// shell; tests set their own.
  static WindowControls? controls;

  /// The room's desktop mini window (U.2j): the shell's, null without a
  /// desktop shell; tests set their own.
  static MiniWindowHost? miniHost;

  /// Whether the window is the room's mini window now; the title bar hides
  /// meanwhile.
  static final ValueNotifier<bool> mini = ValueNotifier(false);

  /// Whether this window can become a mini window.
  static bool get miniAvailable => miniHost != null;

  /// Starts a new window process: the shell's, null where windows cannot be
  /// opened; tests set their own.
  static Future<void> Function({LiveRoom? room})? newWindowLauncher;

  /// Whether this desktop can open more windows (U.13 c12: the home menu's
  /// "新建独立播放窗口" and the room menu's "在新窗口打开" show where this is
  /// true and the setting [Settings.enableNewWindowPlay] is on).
  static bool get canOpenNewWindow => newWindowLauncher != null;

  /// Whether "open in a new window" is offered with [settings] (c12: both
  /// entries follow the setting).
  static bool offersNewWindow(SettingsStore settings) => canOpenNewWindow && settings.get(Settings.enableNewWindowPlay);

  /// Opens a new window that shares this one's data (c14); [room] plays in
  /// it right away. Says "新窗口启动失败，请重试" and returns false when the
  /// window did not start.
  static Future<bool> openNewWindow({LiveRoom? room}) async {
    final launcher = newWindowLauncher;
    if (launcher == null) return false;
    try {
      await launcher(room: room);
      return true;
    } on Object catch (error, stack) {
      log('New window failed', name: 'Desktop', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('open_new_window_failed'));
      return false;
    }
  }

  /// Shrinks the window to the mini window for a picture of [aspectRatio]
  /// (3.x `WindowHelper.enterPiP`); false when the window system refused.
  static Future<bool> enterMini({required double aspectRatio, required bool onTop}) async {
    final host = miniHost;
    if (host == null || mini.value) return false;
    try {
      await host.enter(aspectRatio: aspectRatio, onTop: onTop);
      mini.value = true;
      return true;
    } on Object catch (error, stack) {
      log('Mini window failed', name: 'Desktop', error: error, stackTrace: stack);
      return false;
    }
  }

  /// Gives the window back its size and place; [hidden] hides it first (the
  /// mini window's ✕: the room closes unseen, then [minimize]). False when
  /// the window system refused (3.x "恢复主窗口失败，请重试").
  static Future<bool> exitMini({bool hidden = false}) async {
    final host = miniHost;
    if (host == null || !mini.value) return false;
    try {
      if (hidden) await host.hide();
      await host.exit();
      mini.value = false;
      return true;
    } on Object catch (error, stack) {
      log('Leaving the mini window failed', name: 'Desktop', error: error, stackTrace: stack);
      return false;
    }
  }

  /// Keeps the mini window on top or not; false when the window system
  /// refused.
  static Future<bool> setMiniOnTop({required bool onTop}) async {
    final host = miniHost;
    if (host == null || !mini.value) return false;
    try {
      await host.setOnTop(onTop: onTop);
      return true;
    } on Object catch (error, stack) {
      log('Mini window layer failed', name: 'Desktop', error: error, stackTrace: stack);
      return false;
    }
  }

  /// Minimizes the window to the taskbar.
  static Future<void> minimize() async {
    try {
      await miniHost?.minimize();
    } on Object catch (error, stack) {
      log('Minimize failed', name: 'Desktop', error: error, stackTrace: stack);
    }
  }

  /// Moves the window with the pointer that is down.
  static Future<void> startDragging() async {
    try {
      await miniHost?.startDragging();
    } on Object {
      // The pointer went up before the window system took it.
    }
  }

  /// The child with edges that resize the mini window (3.x
  /// `PureLivePipWidget`); the shell sets it, elsewhere the child as it is.
  static Widget Function(Widget child) resizeArea = (child) => child;

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

/// The meta key of whether the main window was maximized (`1` or `0`; U.13
/// c6).
const String windowMaximizedKey = 'window.maximized';

/// [WindowControls] over window_manager.
final class _WindowManagerControls implements WindowControls {
  const new();

  @override
  Future<void> minimize() => windowManager.minimize();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> restore() => windowManager.unmaximize();

  @override
  Future<void> showSystemMenu() => windowManager.popUpWindowMenu();

  @override
  Future<void> startDragging() async {
    try {
      await windowManager.startDragging();
    } on Object {
      // The pointer went up before the window system took it.
    }
  }
}

/// The desktop window (3.x `DesktopManager`, `DesktopWindowMixin`,
/// `WindowSizeController`; docs/T17/T17a/T17a.1): no system title bar (the
/// app draws [DesktopTitleBar]), the size, place and maximized state of
/// last time (c6), the tray (main window only, c10), what the close button
/// does ([WindowCloser]), the window's name with the room (c11), new
/// windows over the shared data (c12, c14) and the start-up entry
/// ([Settings.enableStartUp]).
final class DesktopShell with WindowListener {
  new _(this._store, {required this.primary, this._recording, this._dataRoot, this._instanceId = ''});

  final LiveStore _store;

  /// The main window (extra windows have no tray and simply close).
  final bool primary;

  final AppRecording? _recording;
  final Directory? _dataRoot;
  final String _instanceId;

  DesktopTray? _tray;
  WindowManagerMiniHost? _mini;
  SharedDataWatch? _shared;
  late final WindowCloser _closer;
  Timer? _saveTimer;
  StreamSubscription<Setting<Object>>? _settings;
  StreamSubscription<int>? _recordings;
  int _activeRecordings = 0;
  String? _title;

  /// The shell of this window; null before [start] and where it does not
  /// run.
  static DesktopShell? current;

  /// Whether the shell runs here. Only Windows for now: the Linux desktop
  /// build is paused (M12.6) and macOS is U.17b. Everything else checks
  /// [current] and the window's abilities, not the platform, so Linux gets
  /// the same title bar, tray and closing once it is on (c2).
  static bool get supported => Platform.isWindows;

  /// Smallest window (UI_PLAN §5.3, U.13 c6; 3.x 400 × 300): it falls to
  /// the phone layout.
  static const Size minimumSize = Size(360, 400);

  /// Sets the window up before the first frame; nothing where the shell does
  /// not run. [dataRoot] is the folder all windows share (c14), [recording]
  /// this window's recorder (the close dialog and the tray count it).
  static Future<void> start(
    LiveStore store, {
    required bool primary,
    AppRecording? recording,
    Directory? dataRoot,
    String instanceId = '',
  }) async {
    if (!supported || current != null) return;
    final shell = current = DesktopShell._(
      store,
      primary: primary,
      recording: recording,
      dataRoot: dataRoot,
      instanceId: instanceId,
    );
    await shell._start();
  }

  SettingsStore get _prefs => _store.settings;

  Future<void> _start() async {
    await windowManager.ensureInitialized();
    final size = Size(
      _prefs.get(Settings.windowWidth).clamp(minimumSize.width, double.infinity),
      _prefs.get(Settings.windowHeight).clamp(minimumSize.height, double.infinity),
    );
    final position = primary ? parseWindowPosition(await _store.meta.get(windowPositionKey)) : null;
    final maximize = primary && await _store.meta.get(windowMaximizedKey) == '1';
    final options = WindowOptions(
      size: size,
      minimumSize: minimumSize,
      center: position == null,
      title: i18nOr('app_name', 'PureLive'),
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setPreventClose(true);
      if (position != null) {
        // A monitor unplugged since last time: back to the middle (c6).
        if (await _onScreen(position, size)) {
          await windowManager.setPosition(position);
        } else {
          await windowManager.center();
        }
      }
      if (maximize) await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
    DesktopWindow.maximized.value = maximize;
    windowManager.addListener(this);
    DesktopWindow._setFullScreen = ({required on}) => windowManager.setFullScreen(on);
    DesktopWindow.controls = const _WindowManagerControls();
    DesktopWindow.miniHost = _mini = WindowManagerMiniHost(_prefs, normalMinimum: minimumSize);
    DesktopWindow.resizeArea = (child) => DragToResizeArea(child: child);
    DesktopWindow.newWindowLauncher = startWindowProcess;
    _closer = WindowCloser(
      settings: _prefs,
      primary: primary,
      hasTray: () => _tray != null,
      recordings: () => _activeRecordings,
      ask: _ask,
      hide: windowManager.hide,
      minimize: windowManager.minimize,
      exit: exit,
      show: show,
      failed: () => AppNavigator.toast(i18n('window_close_action_failed')),
    );
    final recording = _recording;
    if (recording != null) {
      _activeRecordings = recording.activeCount;
      _recordings = recording.activeCounts.listen((count) {
        _activeRecordings = count;
        _tray?.setRecording(count);
      });
    }
    liveRouteObserver.topPage.addListener(_retitle);
    if (_dataRoot case final root?) _shared = SharedDataWatch(_store, root)..start();
    if (primary) {
      try {
        _tray = DesktopTray.create(onShow: show, onHide: windowManager.hide, onExit: _closer.exitFromTray)
          ..setRecording(_activeRecordings);
      } on Object catch (error, stack) {
        // Without a tray, "minimize" minimizes to the taskbar (c7).
        log('Tray failed', name: 'Desktop', error: error, stackTrace: stack);
      }
      _settings = _prefs.changes.listen((setting) {
        if (setting.key != Settings.enableStartUp.key) return;
        unawaited(_applyStartup());
      });
      if (isReleaseBuild) unawaited(_applyStartup());
    }
  }

  /// Whether [position] puts most of the window's title row on a display.
  Future<bool> _onScreen(Offset position, Size size) async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      return titleRowOnScreen(position, size, [
        for (final display in displays)
          (display.visiblePosition ?? Offset.zero) & (display.visibleSize ?? display.size),
      ]);
    } on Object {
      return false;
    }
  }

  /// The start-up entry for the settings row (3.x `StartupController`'s
  /// "applying" and "failed" texts).
  static final ValueNotifier<StartupEntryState> startupState = ValueNotifier(StartupEntryState.idle);

  Future<void> _applyStartup() async {
    startupState.value = StartupEntryState.applying;
    final applied = await applyStartupEntry(enabled: _prefs.get(Settings.enableStartUp));
    startupState.value = applied ? StartupEntryState.idle : StartupEntryState.failed;
  }

  /// Gives the window [size] now (3.x applied the window size setting at
  /// once); a maximized or full-screen window is restored first. False when
  /// the window manager refused.
  Future<bool> resize(Size size) async {
    try {
      if (await windowManager.isFullScreen()) await windowManager.setFullScreen(false);
      if (await windowManager.isMaximized()) await windowManager.unmaximize();
      await windowManager.setSize(size);
      return true;
    } on Object catch (error, stack) {
      log('Window size not applied', name: 'Desktop', error: error, stackTrace: stack);
      return false;
    }
  }

  /// Shows and focuses the window (tray, second launch).
  Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  /// Closes this window's app: stops its recordings (what was recorded is
  /// kept), saves the window and leaves (3.x `exitDesktopApplication`).
  Future<void> exit() async {
    await _saveGeometry();
    try {
      await _recording?.dispose().timeout(const Duration(seconds: 3));
    } on Object catch (error, stack) {
      log('Recording stop failed', name: 'Desktop', error: error, stackTrace: stack);
    }
    // An extra window's own task list is not read again (a new window gets
    // a new id).
    if (!primary) await _forget(recorderTasksKeyFor(_instanceId));
    _tray?.dispose();
    _tray = null;
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  Future<void> _forget(String key) async {
    try {
      await _store.meta.set(key, null);
    } on Object {
      // Left behind; nothing reads it.
    }
  }

  /// The title bar's or the system's close ([WindowCloser.close]).
  Future<void> requestClose() => _closer.close();

  Future<CloseChoice?> _ask({
    required bool tray,
    required int recording,
    required bool askRemember,
    required bool remember,
  }) async {
    final context = AppNavigator.navigatorContext;
    // Nothing to ask on: leave, as before.
    if (context == null) return (action: CloseAction.exit, remember: remember);
    return await showCloseWindowDialog(
      context,
      tray: tray,
      recording: recording,
      askRemember: askRemember,
      remember: remember,
    );
  }

  /// The window's name follows the room on top (c11).
  void _retitle() {
    final title = nativeWindowTitle(i18nOr('app_name', 'PureLive'), roomNameOf(liveRouteObserver.topPage.value));
    if (title == _title) return;
    _title = title;
    unawaited(windowManager.setTitle(title).catchError((Object _) {}));
  }

  @override
  void onWindowClose() => unawaited(requestClose());

  @override
  void onWindowResized() {
    DesktopWindow.resizing.value = null;
    _scheduleSave();
  }

  @override
  void onWindowResize() => unawaited(
    windowManager.getSize().then((size) => DesktopWindow.resizing.value = size, onError: (Object _) => null),
  );

  @override
  void onWindowMoved() => _scheduleSave();

  @override
  void onWindowMaximize() => _maximizedChanged(maximized: true);

  @override
  void onWindowUnmaximize() => _maximizedChanged(maximized: false);

  void _maximizedChanged({required bool maximized}) {
    DesktopWindow.maximized.value = maximized;
    // The mini window un-maximizes on its way in; that is not the user's.
    if (primary && !DesktopWindow.mini.value) unawaited(_remember(windowMaximizedKey, maximized ? '1' : '0'));
  }

  Future<void> _remember(String key, String value) async {
    try {
      await _store.meta.set(key, value);
    } on Object catch (error, stack) {
      log('Saving the window failed', name: 'Desktop', error: error, stackTrace: stack);
    }
  }

  @override
  void onWindowFocus() => _shared?.check();

  @override
  void onWindowEnterFullScreen() => DesktopWindow.fullScreen.value = true;

  @override
  void onWindowLeaveFullScreen() => DesktopWindow.fullScreen.value = false;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () => unawaited(_saveGeometry()));
  }

  /// Remembers the main window's normal size (3.x) and place (new): not
  /// while maximized, minimized or full screen. An extra window remembers
  /// nothing (the data is shared, c14). The mini window remembers its own
  /// (`rememberPipPosition`, U.2j).
  Future<void> _saveGeometry() async {
    _saveTimer?.cancel();
    if (DesktopWindow.mini.value) {
      await _mini?.saveGeometry();
      return;
    }
    if (!primary) return;
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
      await _store.meta.set(windowPositionKey, formatWindowPosition(bounds.topLeft));
    } on Object catch (error, stack) {
      log('Saving the window failed', name: 'Desktop', error: error, stackTrace: stack);
    }
  }

  /// Updates the tray's and the window's words (the language changed).
  void relabel() {
    _tray?.relabel();
    _title = null;
    _retitle();
  }

  /// Stops listening (tests, shutdown).
  Future<void> dispose() async {
    windowManager.removeListener(this);
    liveRouteObserver.topPage.removeListener(_retitle);
    _saveTimer?.cancel();
    await _settings?.cancel();
    await _recordings?.cancel();
    await _shared?.dispose();
    _tray?.dispose();
    if (identical(DesktopWindow.miniHost, _mini)) {
      DesktopWindow.miniHost = null;
      DesktopWindow.resizeArea = (child) => child;
      DesktopWindow.controls = null;
      DesktopWindow.newWindowLauncher = null;
    }
    if (identical(current, this)) current = null;
  }
}

/// Whether a window at [position] of [size] has most of its title row on
/// one of [displays] (work areas): a monitor unplugged since last time
/// would hide it (U.13 c6).
bool titleRowOnScreen(Offset position, Size size, List<Rect> displays) {
  final title = Rect.fromLTWH(position.dx + 40, position.dy, (size.width - 80).clamp(40, double.infinity), 32);
  return displays.any((area) => area.overlaps(title));
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

/// The state of the Windows start-up entry.
enum StartupEntryState {
  /// Nothing pending; the entry follows the setting.
  idle,

  /// Being written.
  applying,

  /// The last write failed.
  failed,
}
