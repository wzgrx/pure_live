import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// Whether the app runs as a desktop window.
bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// The smallest main window that still lays out as a compact page
/// (principles §5.4). A smaller window is the picture-in-picture window.
const minimumWindowSize = Size(360, 400);

/// The window operations the app uses: window_manager on desktops, a fake in
/// tests. Coordinates are logical pixels.
abstract interface class DesktopWindowOps {
  /// Current bounds.
  Future<Rect> getBounds();

  /// Moves and resizes.
  Future<void> setBounds(Rect bounds);

  /// Whether the window is maximised.
  Future<bool> isMaximized();

  /// Maximises.
  Future<void> maximize();

  /// Leaves the maximised state.
  Future<void> unmaximize();

  /// Whether the window is fullscreen.
  Future<bool> isFullScreen();

  /// Enters or leaves fullscreen.
  Future<void> setFullScreen({required bool fullScreen});

  /// Whether the window stays above others.
  Future<bool> isAlwaysOnTop();

  /// Keeps the window above others or not.
  Future<void> setAlwaysOnTop({required bool alwaysOnTop});

  /// Keeps the aspect ratio while resizing; 0 frees it.
  Future<void> setAspectRatio(double aspectRatio);

  /// Minimum size.
  Future<void> setMinimumSize(Size size);

  /// Hides or shows the system title bar and frame buttons.
  Future<void> setFrameless({required bool frameless});

  /// Starts moving the window with the pointer.
  Future<void> startDragging();

  /// The work area of the screen that shows most of [bounds], if known.
  Future<Rect?> workAreaContaining(Rect bounds);

  /// Whether the window is visible.
  Future<bool> isVisible();

  /// Whether the window is minimised.
  Future<bool> isMinimized();

  /// Shows and restores the window.
  Future<void> show();

  /// Hides the window (it stays in the tray).
  Future<void> hide();

  /// Brings the window to the front.
  Future<void> focus();

  /// Asks the app before closing (window_manager's `onWindowClose`).
  Future<void> setPreventClose({required bool preventClose});

  /// Closes the window and ends the app.
  Future<void> destroy();
}

/// [DesktopWindowOps] over window_manager and screen_retriever.
final class WindowManagerOps implements DesktopWindowOps {
  /// Creates the operations.
  const new();

  @override
  Future<Rect> getBounds() => windowManager.getBounds();

  @override
  Future<void> setBounds(Rect bounds) => windowManager.setBounds(bounds);

  @override
  Future<bool> isMaximized() => windowManager.isMaximized();

  @override
  Future<void> maximize() => windowManager.maximize();

  @override
  Future<void> unmaximize() => windowManager.unmaximize();

  @override
  Future<bool> isFullScreen() => windowManager.isFullScreen();

  @override
  Future<void> setFullScreen({required bool fullScreen}) => windowManager.setFullScreen(fullScreen);

  @override
  Future<bool> isAlwaysOnTop() => windowManager.isAlwaysOnTop();

  @override
  Future<void> setAlwaysOnTop({required bool alwaysOnTop}) => windowManager.setAlwaysOnTop(alwaysOnTop);

  @override
  Future<void> setAspectRatio(double aspectRatio) => windowManager.setAspectRatio(aspectRatio);

  @override
  Future<void> setMinimumSize(Size size) => windowManager.setMinimumSize(size);

  @override
  Future<void> setFrameless({required bool frameless}) => windowManager.setTitleBarStyle(
    frameless ? TitleBarStyle.hidden : TitleBarStyle.normal,
    windowButtonVisibility: !frameless,
  );

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<Rect?> workAreaContaining(Rect bounds) async {
    final areas = await displayWorkAreas();
    Rect? best;
    var bestOverlap = 0.0;
    for (final area in areas) {
      final overlap = area.intersect(bounds);
      final size = overlap.width > 0 && overlap.height > 0 ? overlap.width * overlap.height : 0.0;
      if (best == null || size > bestOverlap) {
        best = area;
        bestOverlap = size;
      }
    }
    return best;
  }

  @override
  Future<bool> isVisible() => windowManager.isVisible();

  @override
  Future<bool> isMinimized() => windowManager.isMinimized();

  @override
  Future<void> show() => windowManager.show();

  @override
  Future<void> hide() => windowManager.hide();

  @override
  Future<void> focus() => windowManager.focus();

  @override
  Future<void> setPreventClose({required bool preventClose}) => windowManager.setPreventClose(preventClose);

  @override
  Future<void> destroy() => windowManager.destroy();
}

/// The main window.
final desktopWindowProvider = Provider<DesktopWindowOps>((ref) => const WindowManagerOps());

/// Work areas of every screen (without taskbars), logical pixels.
Future<List<Rect>> displayWorkAreas() async {
  try {
    final displays = await screenRetriever.getAllDisplays();
    return [
      for (final display in displays)
        Rect.fromLTWH(
          display.visiblePosition?.dx ?? 0,
          display.visiblePosition?.dy ?? 0,
          display.visibleSize?.width ?? display.size.width,
          display.visibleSize?.height ?? display.size.height,
        ),
    ];
  } on Object {
    return const [];
  }
}

/// Parses a stored `x,y` window position.
Offset? parseWindowPosition(String value) {
  final parts = value.split(',');
  if (parts.length != 2) return null;
  final x = double.tryParse(parts[0].trim());
  final y = double.tryParse(parts[1].trim());
  if (x == null || y == null || !x.isFinite || !y.isFinite) return null;
  return Offset(x, y);
}

/// The stored form of [position].
String formatWindowPosition(Offset position) => '${position.dx.round()},${position.dy.round()}';

/// [saved] when a window of [size] there keeps enough of its title bar on one
/// of [workAreas] to be grabbed (a screen may have been unplugged); null
/// otherwise, and the window is centred.
Offset? restorablePosition(Offset? saved, Size size, List<Rect> workAreas) {
  if (saved == null) return null;
  final titleBar = Rect.fromLTWH(saved.dx, saved.dy, size.width, 32);
  for (final area in workAreas) {
    final visible = area.intersect(titleBar);
    if (visible.width >= 96 && visible.height >= 16) return saved;
  }
  return null;
}

/// Whether [bounds] are the main window's own: smaller bounds belong to the
/// picture-in-picture window and are not remembered.
bool isMainWindowBounds(Rect bounds) =>
    bounds.width >= minimumWindowSize.width && bounds.height >= minimumWindowSize.height;

/// Restores the last window size, position and maximised state (F-WIN-06),
/// sets the minimum size (principles §5.4) and remembers later changes. A
/// [secondary] window (F-WIN-02) opens centred and remembers nothing, so it
/// does not overwrite the main window's placement. [startMaximized] tells
/// the runner to show the window maximised on its first frame (a window
/// maximised before that would be restored by the first show).
Future<void> initDesktopWindow(
  SettingsStore settings, {
  bool secondary = false,
  Future<void> Function({required bool maximized})? startMaximized,
}) async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(minimumWindowSize);
  final size = Size(settings.get(Settings.windowWidth), settings.get(Settings.windowHeight));
  if (secondary) {
    await windowManager.setSize(size);
    await windowManager.center();
    return;
  }
  final position = restorablePosition(
    parseWindowPosition(settings.get(Settings.windowPosition)),
    size,
    await displayWorkAreas(),
  );
  if (position != null) {
    await windowManager.setBounds(null, position: position, size: size);
  } else {
    await windowManager.setSize(size);
    await windowManager.center();
  }
  if (settings.get(Settings.windowMaximized)) {
    if (startMaximized != null) {
      await startMaximized(maximized: true);
    } else {
      await windowManager.maximize();
    }
  }
  windowManager.addListener(WindowPlacementMemory(settings, const WindowManagerOps()));
}

/// Remembers the main window's size, position and maximised state
/// (F-WIN-06). Maximised, fullscreen, minimised and picture-in-picture
/// bounds are not remembered.
final class WindowPlacementMemory with WindowListener {
  /// Stores into the settings, reading the bounds through the window operations.
  new(this._settings, this._window, {this.debounce = const Duration(milliseconds: 500)});

  final SettingsStore _settings;
  final DesktopWindowOps _window;

  /// How long the window must rest before its bounds are stored.
  final Duration debounce;

  Timer? _timer;

  @override
  void onWindowResized() => _schedule();

  @override
  void onWindowMoved() => _schedule();

  @override
  void onWindowMaximize() => unawaited(_settings.set(Settings.windowMaximized, true));

  @override
  void onWindowUnmaximize() => unawaited(_settings.set(Settings.windowMaximized, false));

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(save()));
  }

  /// Stores the current bounds when they are the main window's normal ones.
  Future<void> save() async {
    _timer?.cancel();
    if (await _window.isFullScreen() || await _window.isMaximized() || await _window.isMinimized()) return;
    final bounds = await _window.getBounds();
    if (!isMainWindowBounds(bounds)) return;
    await _settings.set(Settings.windowWidth, bounds.width);
    await _settings.set(Settings.windowHeight, bounds.height);
    await _settings.set(Settings.windowPosition, formatWindowPosition(bounds.topLeft));
  }
}
