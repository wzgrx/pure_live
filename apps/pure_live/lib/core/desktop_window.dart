import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:live_store/live_store.dart';
import 'package:window_manager/window_manager.dart';

/// Whether the app runs as a desktop window.
bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Restores the last window size, sets the minimum (principles §5.4:
/// 360 × 400) and remembers new sizes.
Future<void> initDesktopWindow(SettingsStore settings) async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(360, 400));
  await windowManager.setSize(Size(settings.get(Settings.windowWidth), settings.get(Settings.windowHeight)));
  windowManager.addListener(_SizeMemory(settings));
}

final class _SizeMemory with WindowListener {
  new(this._settings);

  final SettingsStore _settings;
  Timer? _debounce;

  @override
  void onWindowResized() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (await windowManager.isFullScreen() || await windowManager.isMaximized()) return;
      final size = await windowManager.getSize();
      await _settings.set(Settings.windowWidth, size.width);
      await _settings.set(Settings.windowHeight, size.height);
    });
  }
}
