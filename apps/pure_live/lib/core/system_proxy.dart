import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_net/live_net.dart';

/// The operating system's HTTP proxy (F-SET-07: followed by default, the
/// manual proxy overrides it).
@immutable
final class SystemProxy {
  const new(this.host, this.port, {this.bypass = const []});

  /// Proxy host.
  final String host;

  /// Proxy port.
  final int port;

  /// Hosts that go direct: exact names, `*.suffix` wildcards and `<local>`
  /// (names without a dot), as Windows and `no_proxy` write them.
  final List<String> bypass;

  /// Whether [host] skips the proxy. Loopback always does.
  bool bypasses(String host) {
    final name = host.toLowerCase();
    if (name == 'localhost' || name.startsWith('127.') || name == '::1' || name == '[::1]') return true;
    for (final rule in bypass) {
      final pattern = rule.trim().toLowerCase();
      if (pattern.isEmpty) continue;
      if (pattern == '<local>') {
        if (!name.contains('.')) return true;
      } else if (pattern == '*') {
        return true;
      } else if (pattern.startsWith('*.')) {
        if (name.endsWith(pattern.substring(1))) return true;
      } else if (pattern.startsWith('.')) {
        if (name.endsWith(pattern) || name == pattern.substring(1)) return true;
      } else if (pattern.endsWith('*')) {
        if (name.startsWith(pattern.substring(0, pattern.length - 1))) return true;
      } else if (name == pattern || name.endsWith('.$pattern')) {
        return true;
      }
    }
    return false;
  }

  /// `http://host:port`.
  String get url => 'http://$host:$port';

  @override
  bool operator ==(Object other) =>
      other is SystemProxy && other.host == host && other.port == port && listEquals(other.bypass, bypass);

  @override
  int get hashCode => Object.hash(host, port, Object.hashAll(bypass));

  @override
  String toString() => 'SystemProxy($host:$port)';
}

/// Routes every platform through the system proxy except bypassed hosts. Plain
/// data, so it crosses into the chat worker's isolate.
final class SystemProxyPolicy implements ProxyPolicy {
  const new(this.proxy);

  final SystemProxy proxy;

  @override
  ProxyRoute routeFor(String site, Uri url) =>
      proxy.bypasses(url.host) ? const DirectRoute() : HttpProxyRoute(proxy.host, proxy.port);
}

/// Reads a Windows `ProxyServer` value: `host:port`, or per-protocol
/// `http=host:port;https=host:port;socks=…` (https first, then http; SOCKS
/// alone is not an HTTP proxy).
SystemProxy? parseWindowsProxy(String server, {String override = ''}) {
  final bypass = override.split(';').where((rule) => rule.trim().isNotEmpty).toList();
  String? pick(String value) {
    final entries = {
      for (final part in value.split(';'))
        if (part.contains('='))
          part.substring(0, part.indexOf('=')).trim().toLowerCase(): part.substring(part.indexOf('=') + 1).trim(),
    };
    if (entries.isEmpty) return value.trim();
    return entries['https'] ?? entries['http'];
  }

  final address = pick(server);
  if (address == null || address.isEmpty) return null;
  return _hostPort(address, bypass);
}

/// Reads `https_proxy` / `http_proxy` (and `no_proxy`) as curl does.
SystemProxy? parseEnvironmentProxy(Map<String, String> environment) {
  String? value(String name) => environment[name] ?? environment[name.toUpperCase()];
  final raw = value('https_proxy') ?? value('http_proxy');
  if (raw == null || raw.trim().isEmpty) return null;
  final bypass = (value('no_proxy') ?? '').split(',').where((rule) => rule.trim().isNotEmpty).toList();
  final uri = Uri.tryParse(raw.contains('://') ? raw.trim() : 'http://${raw.trim()}');
  if (uri == null || uri.host.isEmpty || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
  return SystemProxy(uri.host, uri.hasPort ? uri.port : 80, bypass: bypass);
}

SystemProxy? _hostPort(String address, List<String> bypass) {
  final uri = Uri.tryParse(address.contains('://') ? address : 'http://$address');
  if (uri == null || uri.host.isEmpty) return null;
  return SystemProxy(uri.host, uri.hasPort ? uri.port : 80, bypass: bypass);
}

const _channel = MethodChannel('purelive/net');

/// The system proxy now, or null for none (or when it cannot be read).
Future<SystemProxy?> readSystemProxy() async {
  try {
    if (Platform.isWindows) return _WindowsInternetSettings.read();
    if (Platform.isAndroid) {
      final value = await _channel.invokeMapMethod<String, Object?>('systemProxy');
      final host = value?['host'];
      final port = value?['port'];
      if (host is! String || host.isEmpty || port is! int || port <= 0) return null;
      final exclusions = value?['exclusions'];
      return SystemProxy(host, port, bypass: exclusions is List ? [for (final item in exclusions) '$item'] : const []);
    }
    return parseEnvironmentProxy(Platform.environment);
  } on Object {
    // No channel (tests, other shells) or an unreadable registry: direct.
    return null;
  }
}

/// The system proxy, read at start-up and again whenever the app comes back
/// to the foreground (proxies change with networks and proxy tools).
class SystemProxyNotifier extends Notifier<SystemProxy?> {
  @override
  SystemProxy? build() {
    unawaited(refresh());
    try {
      final lifecycle = AppLifecycleListener(onResume: () => unawaited(refresh()));
      ref.onDispose(lifecycle.dispose);
    } on Object {
      // No widgets binding (unit tests): read once.
    }
    return null;
  }

  /// Reads the system proxy again.
  Future<void> refresh() async {
    final proxy = await readSystemProxy();
    if (ref.mounted && proxy != state) state = proxy;
  }
}

/// The operating system's proxy, or null.
final systemProxyProvider = NotifierProvider<SystemProxyNotifier, SystemProxy?>(SystemProxyNotifier.new);

typedef _RegGetValueNative = Int32 Function(
  IntPtr key,
  Pointer<Utf16> subKey,
  Pointer<Utf16> value,
  Uint32 flags,
  Pointer<Uint32> type,
  Pointer<Void> data,
  Pointer<Uint32> size,
);
typedef _RegGetValueDart = int Function(
  int key,
  Pointer<Utf16> subKey,
  Pointer<Utf16> value,
  int flags,
  Pointer<Uint32> type,
  Pointer<Void> data,
  Pointer<Uint32> size,
);

/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`, the
/// proxy Windows' settings and proxy tools write (WinINet).
abstract final class _WindowsInternetSettings {
  static const _currentUser = 0x80000001;
  static const _dword = 0x00000010;
  static const _string = 0x00000002;
  static const _path = r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  static SystemProxy? read() {
    final get = DynamicLibrary.open('advapi32.dll')
        .lookupFunction<_RegGetValueNative, _RegGetValueDart>('RegGetValueW');
    return using((arena) {
      final path = _path.toNativeUtf16(allocator: arena);
      final size = arena<Uint32>();
      int? dword(String name) {
        final data = arena<Uint32>();
        size.value = 4;
        final status = get(
          _currentUser,
          path,
          name.toNativeUtf16(allocator: arena),
          _dword,
          nullptr,
          data.cast(),
          size,
        );
        return status == 0 ? data.value : null;
      }

      String? text(String name) {
        final value = name.toNativeUtf16(allocator: arena);
        size.value = 0;
        if (get(_currentUser, path, value, _string, nullptr, nullptr, size) != 0 || size.value == 0) return null;
        final data = arena<Uint8>(size.value);
        if (get(_currentUser, path, value, _string, nullptr, data.cast(), size) != 0) return null;
        return data.cast<Utf16>().toDartString();
      }

      if (dword('ProxyEnable') != 1) return null;
      final server = text('ProxyServer');
      if (server == null || server.trim().isEmpty) return null;
      return parseWindowsProxy(server, override: text('ProxyOverride') ?? '');
    });
  }
}
