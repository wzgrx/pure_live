import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pure_live_app/features/system/media_controls.dart';

/// A tray icon event (F-WIN-03).
enum TrayEvent {
  /// Left click on the icon.
  click,

  /// "显示窗口" in the menu.
  show,

  /// "隐藏窗口" in the menu.
  hide,

  /// "退出" in the menu.
  exit,
}

/// The Windows runner's channel `purelive/windows`
/// (`windows/runner/system_bridge.cpp`): forwarded launches, tray icon, SMTC,
/// title bar colour, launch at login and the first show state.
class WindowsNative {
  /// Listens on [channel].
  new([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('purelive/windows') {
    _channel.setMethodCallHandler(_handle);
  }

  final MethodChannel _channel;
  final _forwarded = StreamController<List<String>>.broadcast();
  final _tray = StreamController<TrayEvent>.broadcast();
  final _media = StreamController<MediaCommand>.broadcast();

  /// Arguments of a second launch, forwarded by the runner (F-WIN-01).
  Stream<List<String>> get forwardedArguments => _forwarded.stream;

  /// Tray icon events.
  Stream<TrayEvent> get trayEvents => _tray.stream;

  /// SMTC buttons and media keys.
  Stream<MediaCommand> get mediaCommands => _media.stream;

  Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'forwardedArguments':
        if (call.arguments case final List<Object?> args) _forwarded.add(args.whereType<String>().toList());
      case 'trayEvent':
        final event = TrayEvent.values.asNameMap()[call.arguments];
        if (event != null) _tray.add(event);
      case 'mediaButton':
        final command = MediaCommand.values.asNameMap()[call.arguments];
        if (command != null) _media.add(command);
    }
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Dart listens now; the runner delivers forwarded launches it queued.
  Future<void> ready() => _invoke<void>('ready');

  /// Shows the window maximised when the runner first shows it (F-WIN-06).
  Future<void> setStartMaximized({required bool maximized}) =>
      _invoke<void>('setStartMaximized', {'maximized': maximized});

  /// Dark or light system title bar (principles §5.4).
  Future<void> setTitleBarDark({required bool dark}) => _invoke<void>('setTitleBarDark', {'dark': dark});

  /// Shows the tray icon with its tooltip and menu labels.
  Future<void> showTray({required String tooltip, required String show, required String hide, required String exit}) =>
      _invoke<void>('showTray', {'tooltip': tooltip, 'show': show, 'hide': hide, 'exit': exit});

  /// Removes the tray icon.
  Future<void> hideTray() => _invoke<void>('hideTray');

  /// Adds or removes the `HKCU\…\Run` value [name] for this executable
  /// (F-WIN-05); false when the registry refused.
  Future<bool> setLaunchAtStartup({required String name, required bool enabled}) async =>
      await _invoke<bool>('setLaunchAtStartup', {'name': name, 'enabled': enabled}) ?? false;

  /// Shows [info] in SMTC.
  Future<void> updateMediaControls(MediaInfo info, {required bool playing}) => _invoke<void>('updateMediaControls', {
    'title': info.title,
    'artist': info.artist,
    'album': info.album ?? '',
    'thumbnail': info.artwork?.toString() ?? '',
    'playing': playing,
  });

  /// Clears SMTC.
  Future<void> clearMediaControls() => _invoke<void>('clearMediaControls');
}

/// SMTC as [MediaControls] (F-NEW-12).
final class WindowsMediaControls implements MediaControls {
  /// Uses [native].
  const new(this.native);

  /// The runner channel.
  final WindowsNative native;

  @override
  Stream<MediaCommand> get commands => native.mediaCommands;

  @override
  Future<void> show(MediaInfo info, {required bool playing}) => native.updateMediaControls(info, playing: playing);

  @override
  Future<void> hide() => native.clearMediaControls();
}
