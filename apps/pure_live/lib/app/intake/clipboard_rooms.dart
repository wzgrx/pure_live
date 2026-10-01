import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/shared/rooms/room_prompt.dart';
import 'package:pure_live/shared/rooms/share_code.dart';

/// The system clipboard's text (Flutter's clipboard channel); null when
/// there is none or it cannot be read.
Future<String?> readClipboardText() async {
  try {
    return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

/// Looks at the clipboard once the app is up and one second after every
/// return to the front, and offers the room of a share code found there
/// (3.x `DesktopWindowMixin._checkShareCommand` with
/// `ShareCommandHandler.checkClipboard`; M12.5 → F.0a).
///
/// As 3.x: share codes of 3.x and this app only (not links, X2); the same
/// text is offered once per run; the app's own codes are skipped
/// ([OwnClipboardTexts]); "进入房间" opens the room. New: the switch
/// `detectClipboardRooms` (on); with [stamp] (Android) the clipboard is
/// read only after it changed, so Android 12+ does not report "pasted from
/// your clipboard" on every return. One look at a time.
final class ClipboardRoomWatcher {
  /// Creates the watcher.
  new({
    required this.settings,
    required this.prompt,
    required this.open,
    this.read = readClipboardText,
    this.stamp,
    this.resumeDelay = const Duration(seconds: 1),
  });

  /// Longest clipboard text looked at.
  static const int maxText = 4096;

  /// The settings (`detectClipboardRooms`).
  final SettingsStore settings;

  /// Asks the user (U.3d's `showRoomPrompt`).
  final Future<RoomPromptChoice> Function(LiveRoom room) prompt;

  /// Opens the room the user chose.
  final Future<void> Function(LiveRoom room) open;

  /// Reads the clipboard.
  final Future<String?> Function() read;

  /// When the clipboard last changed (-1: empty; null: unknown).
  final Future<int?> Function()? stamp;

  /// The wait after the app comes back (3.x: one second, so the window has
  /// the focus Android needs to read the clipboard).
  final Duration resumeDelay;

  AppLifecycleListener? _lifecycle;
  Timer? _resume;
  Future<void>? _running;
  String? _lastOffered;
  int? _lastStamp;
  bool _disposed = false;

  /// Looks now and after every return to the app.
  void start() {
    if (_disposed || _lifecycle != null) return;
    _lifecycle = AppLifecycleListener(onResume: resumed);
    unawaited(check());
  }

  /// The app came back: looks after [resumeDelay].
  void resumed() {
    _resume?.cancel();
    _resume = Timer(resumeDelay, () => unawaited(check()));
  }

  /// One look at the clipboard (a look already running is joined).
  Future<void> check() => _running ??= _check().whenComplete(() => _running = null);

  Future<void> _check() async {
    try {
      if (_disposed || !settings.get(Settings.detectClipboardRooms)) return;
      final changed = await stamp?.call();
      if (changed != null) {
        if (changed < 0 || changed == _lastStamp) return;
        _lastStamp = changed;
      }
      final text = (await read())?.trim() ?? '';
      if (_disposed || text.isEmpty || text.length > maxText || text == _lastOffered) return;
      if (OwnClipboardTexts.contains(text)) return;
      final room = decodeRoomShareCode(text);
      if (room == null) return;
      _lastOffered = text;
      if (await prompt(room) == RoomPromptChoice.enter && !_disposed) await open(room);
    } on Object catch (error, stack) {
      log('Clipboard check failed', name: 'ClipboardRoomWatcher', error: error, stackTrace: stack);
    }
  }

  /// Stops looking.
  void dispose() {
    _disposed = true;
    _resume?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
