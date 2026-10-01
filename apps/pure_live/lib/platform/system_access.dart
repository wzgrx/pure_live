import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// Android's install and local-network permissions (`pure_live/system_access`,
/// 3.x used permission_handler). Off Android every answer is "allowed".
abstract final class SystemAccess {
  static const MethodChannel _channel = MethodChannel('pure_live/system_access');

  /// Replaces the channel calls (tests).
  static Future<Object?> Function(String method)? debugCall;

  static Future<bool> _ask(String method, {required bool fallback}) async {
    final call = debugCall;
    if (call != null) return await call(method) as bool? ?? fallback;
    if (!Platform.isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>(method) ?? fallback;
    } on PlatformException {
      return fallback;
    } on MissingPluginException {
      return fallback;
    }
  }

  /// Whether this app may install packages ("install unknown apps").
  static Future<bool> canInstallPackages() => _ask('canInstallPackages', fallback: true);

  /// Opens the system page that allows installing packages.
  static Future<bool> openInstallSettings() => _ask('openInstallSettings', fallback: false);

  /// Whether sockets to the local network are allowed (Android 17).
  static Future<bool> localNetworkGranted() => _ask('localNetworkGranted', fallback: true);

  /// Asks for local-network access; whether it is granted.
  static Future<bool> requestLocalNetwork() => _ask('requestLocalNetwork', fallback: true);
}

/// Asks for Android 17's local-network permission when a proxy points at the
/// local network (3.x `LocalNetworkAccess.ensureForProxies`): at start and
/// when the proxy settings settle after a change. A refusal is asked again
/// only in a later session; the user is told where to allow it.
final class LocalNetworkGuard {
  /// Creates the guard over the settings.
  new(this._settings, {this.settle = const Duration(seconds: 1)});

  final SettingsStore _settings;

  /// How long the proxy settings must stay unchanged before asking.
  final Duration settle;

  final List<StreamSubscription<Object>> _watches = [];
  Timer? _timer;
  bool _asked = false;

  static const List<Setting<Object>> _proxySettings = [
    Settings.enableAppProxy,
    Settings.appProxyHost,
    Settings.enableProxy,
    Settings.proxyHost,
  ];

  /// Whether an enabled proxy points at the local network.
  bool get needed =>
      (_settings.get(Settings.enableAppProxy) && isLocalNetworkProxyHost(_settings.get(Settings.appProxyHost))) ||
      (_settings.get(Settings.enableProxy) && isLocalNetworkProxyHost(_settings.get(Settings.proxyHost)));

  /// Starts following the proxy settings and checks once.
  void start() {
    if (_watches.isNotEmpty) return;
    for (final setting in _proxySettings) {
      _watches.add(_settings.watch(setting).listen((_) => _schedule()));
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(settle, () => unawaited(ensure()));
  }

  /// Asks when [needed]; whether local sockets are allowed.
  Future<bool> ensure() async {
    if (!needed) return true;
    if (await SystemAccess.localNetworkGranted()) return true;
    if (_asked) return false;
    _asked = true;
    final granted = await SystemAccess.requestLocalNetwork();
    if (!granted) AppNavigator.toast(i18n('local_network_permission_denied'));
    return granted;
  }

  /// Stops following the settings.
  Future<void> dispose() async {
    _timer?.cancel();
    for (final watch in _watches) {
      await watch.cancel();
    }
    _watches.clear();
  }
}
