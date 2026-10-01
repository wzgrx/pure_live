import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/pages/remote_receiver/remote_sync_protocol.dart';
import 'package:pure_live/pages/version/app_version.dart';

/// Another device on the network, from its announcement.
@immutable
final class RemoteSyncDevice {
  /// Creates the device.
  const new({
    required this.id,
    required this.name,
    required this.platform,
    required this.ip,
    required this.port,
    required this.lastSeen,
    this.version = '',
  });

  /// Device id.
  final String id;

  /// Shown name.
  final String name;

  /// Operating system.
  final String platform;

  /// App version.
  final String version;

  /// IPv4 address.
  final String ip;

  /// Sync port.
  final int port;

  /// When it was last heard.
  final DateTime lastSeen;

  /// `ip:port`.
  String get address => '$ip:$port';
}

/// Asks the user whether [remoteAddress] may read (`export`) or replace
/// (`import`) this device's settings.
typedef RemoteSyncConfirm = Future<bool> Function(String action, String remoteAddress);

/// The device-sync server and client (3.x `RemoteSyncService`), alive while
/// the page is open.
///
/// - Serves 3.x's endpoints on the first free port from 39888; every
///   settings request needs the pairing code shown here and the user's
///   consent ([confirm]); after [maxWrongCodes] wrong codes the code changes.
/// - Sends this device's settings to another device, or takes its settings,
///   in 3.x's backup layout ([BackupService]); account cookies only with
///   [includeAccounts].
/// - Announces itself and lists other devices over UDP broadcast (port
///   39889); 3.x's mDNS discovery is not here yet.
class RemoteSyncService extends ChangeNotifier {
  /// Creates the service over [store].
  new(this.store, {List<String>? Function()? localIps, this.requestTimeout = const Duration(minutes: 2)})
    : _listIps = localIps;

  /// Settings and backups.
  final LiveStore store;

  /// How long a send or receive waits (the other device asks its user first).
  final Duration requestTimeout;

  final List<String>? Function()? _listIps;

  /// Wrong pairing codes before the code changes.
  static const int maxWrongCodes = 10;

  /// Asks the user about an incoming request; refused without it.
  RemoteSyncConfirm? confirm;

  HttpServer? _server;
  RawDatagramSocket? _discovery;
  Timer? _announceTimer;
  bool _disposed = false;
  bool _starting = false;
  int _wrongCodes = 0;

  /// This device's IPv4 address on the network, or empty.
  String localIp = '';

  /// The server's port.
  int port = RemoteSyncProtocol.defaultHttpPort;

  /// The code another device must give; empty while stopped.
  String pairingCode = '';

  /// Whether account cookies travel (off by default, 3.x).
  bool includeAccounts = false;

  /// Whether a send, receive or incoming import runs.
  bool syncing = false;

  /// Devices heard on the network, newest first.
  final Map<String, RemoteSyncDevice> _devices = {};

  /// Devices heard in the last two minutes.
  List<RemoteSyncDevice> get devices => _devices.values.toList(growable: false);

  /// Whether the server runs.
  bool get running => _server != null;

  /// `ip:port`, or empty.
  String get address => localIp.isEmpty ? '' : '$localIp:$port';

  /// The QR code content, or empty.
  String get qrData => localIp.isEmpty || pairingCode.isEmpty
      ? ''
      : RemoteSyncProtocol.createQrUri(ip: localIp, port: port, code: pairingCode).toString();

  /// This device's sync id (3.x's, kept in the settings).
  String get deviceId {
    final settings = store.settings;
    final existing = settings.get(Settings.remoteSyncDeviceId);
    if (existing.isNotEmpty) return existing;
    final id = '${Platform.operatingSystem}-${DateTime.now().microsecondsSinceEpoch}';
    unawaited(settings.set(Settings.remoteSyncDeviceId, id));
    return id;
  }

  /// This device's name for the others (3.x).
  static String get deviceName => switch (Platform.operatingSystem) {
    'android' => 'PureLive Android',
    'ios' => 'PureLive iPhone',
    'windows' => 'PureLive Windows',
    'macos' => 'PureLive macOS',
    'linux' => 'PureLive Linux',
    _ => 'PureLive',
  };

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Starts serving and announcing; does nothing while running.
  Future<void> start() async {
    if (_disposed || _starting || running) return;
    _starting = true;
    try {
      localIp = await _pickLocalIp();
      HttpServer? server;
      for (
        var candidate = RemoteSyncProtocol.defaultHttpPort;
        candidate < RemoteSyncProtocol.defaultHttpPort + 100;
        candidate++
      ) {
        try {
          server = await HttpServer.bind(InternetAddress.anyIPv4, candidate);
          port = candidate;
          break;
        } on SocketException {
          continue;
        }
      }
      if (server == null) return;
      if (_disposed) {
        await server.close(force: true);
        return;
      }
      _server = server;
      pairingCode = RemoteSyncProtocol.newPairingCode();
      _wrongCodes = 0;
      server.listen((request) => unawaited(handleRequest(request)), onError: (Object _) => unawaited(stop()));
      await _startDiscovery();
    } finally {
      _starting = false;
      _changed();
    }
  }

  /// Stops serving and announcing; [start] resumes.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    pairingCode = '';
    _announceTimer?.cancel();
    _announceTimer = null;
    _discovery?.close();
    _discovery = null;
    _devices.clear();
    _changed();
    await server?.close(force: true);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }

  /// The best IPv4 address of this device: private networks first, then
  /// 192.168 over 10 over 172.16/12 (3.x).
  Future<String> _pickLocalIp() async {
    List<String> ips;
    final listed = _listIps?.call();
    if (listed != null) {
      ips = listed;
    } else {
      try {
        final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
        ips = [
          for (final interface in interfaces)
            for (final address in interface.addresses) address.address,
        ];
      } on Object {
        ips = const [];
      }
    }
    final usable = [
      for (final ip in ips)
        if (_ipv4(ip) case final parts? when parts[0] != 127 && !(parts[0] == 169 && parts[1] == 254)) ip,
    ]..sort((a, b) => _priority(b).compareTo(_priority(a)));
    return usable.firstOrNull ?? '';
  }

  static List<int>? _ipv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final values = [for (final part in parts) int.tryParse(part) ?? -1];
    return values.every((value) => value >= 0 && value <= 255) ? values : null;
  }

  static int _priority(String ip) {
    final parts = _ipv4(ip)!;
    if (parts[0] == 192 && parts[1] == 168) return 3;
    if (parts[0] == 10) return 2;
    if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return 1;
    return 0;
  }

  // ---- server ----

  /// Answers one request (public for tests).
  @visibleForTesting
  Future<void> handleRequest(HttpRequest request) async {
    final response = request.response;
    // No CORS headers: a web page on the network must not read the settings.
    response.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    try {
      switch (request.uri.path) {
        case RemoteSyncProtocol.apiStatus:
          if (request.method != 'GET') return await _reply(response, 405, 'Method Not Allowed');
          return await _reply(response, 200, 'ok', {
            'id': deviceId,
            'name': deviceName,
            'platform': Platform.operatingSystem,
            'version': appVersion,
            'ip': localIp,
            'port': port,
          });
        case RemoteSyncProtocol.apiSettings:
          return await _settings(request);
        default:
          return await _reply(response, 404, 'Not Found');
      }
    } on Object {
      try {
        await _reply(response, 500, 'Internal Server Error');
      } on Object {
        // Already answered.
      }
    }
  }

  Future<void> _settings(HttpRequest request) async {
    final response = request.response;
    if (!RemoteSyncProtocol.pairingCodesMatch(pairingCode, request.headers.value(RemoteSyncProtocol.pairingHeader))) {
      // Guessing a 6-digit code takes many tries: a new code stops it.
      if (++_wrongCodes >= maxWrongCodes) {
        _wrongCodes = 0;
        pairingCode = RemoteSyncProtocol.newPairingCode();
        _changed();
      }
      return await _reply(response, 403, 'Pairing code required');
    }
    final action = switch (request.method) {
      'GET' => 'export',
      'POST' => 'import',
      _ => null,
    };
    if (action == null) return await _reply(response, 405, 'Method Not Allowed');
    // Read the body before asking: a bad packet is refused without a prompt.
    Map<String, Object?>? settings;
    if (action == 'import') {
      final body = await utf8.decoder.bind(request).join();
      final packet = body.trim().isEmpty ? null : jsonDecode(body);
      if (packet is! Map || packet['type'] != RemoteSyncProtocol.syncType || packet['settings'] is! Map) {
        return await _reply(response, 400, 'Invalid sync packet');
      }
      settings = (packet['settings']! as Map).cast<String, Object?>();
    }
    final ask = confirm;
    final remote = request.connectionInfo?.remoteAddress.address ?? '';
    var allowed = false;
    try {
      allowed = ask != null && !_disposed && await ask(action, remote);
    } on Object {
      allowed = false;
    }
    if (!allowed) return await _reply(response, 403, 'Rejected on the device');
    if (settings == null) {
      final exported = await BackupService(store).exportAll(includeSensitiveData: includeAccounts);
      return await _reply(response, 200, 'ok', exported);
    }
    syncing = true;
    _changed();
    try {
      await BackupService(store).restoreAll(settings);
      return await _reply(response, 200, 'ok', true);
    } on Object {
      return await _reply(response, 500, 'apply settings failed');
    } finally {
      syncing = false;
      _changed();
    }
  }

  static Future<void> _reply(HttpResponse response, int status, String message, [Object? data = false]) async {
    response
      ..statusCode = status
      ..write(jsonEncode({'code': status, 'msg': message, 'data': data}));
    await response.close();
  }

  // ---- client ----

  /// Sends this device's settings to `ip:port` with [code]; true when the
  /// other device applied them (3.x `syncToAddress`).
  Future<bool> send(String ip, int port, String code) => _busy(() async {
    final settings = await BackupService(store).exportAll(includeSensitiveData: includeAccounts);
    final answer = await _request('POST', ip, port, code, RemoteSyncProtocol.settingsPacket(settings: settings));
    return answer is Map && answer['data'] == true;
  });

  /// Takes the settings of `ip:port` with [code] and applies them here;
  /// true on success (3.x `getRemoteSettings` + import).
  Future<bool> receive(String ip, int port, String code) => _busy(() async {
    final answer = await _request('GET', ip, port, code, null);
    if (answer is! Map || answer['code'] != 200 || answer['data'] is! Map) return false;
    await BackupService(store).restoreAll((answer['data']! as Map).cast<String, Object?>());
    return true;
  });

  Future<bool> _busy(Future<bool> Function() work) async {
    if (_disposed || syncing) return false;
    syncing = true;
    _changed();
    try {
      return await work().timeout(requestTimeout);
    } on Object {
      return false;
    } finally {
      syncing = false;
      _changed();
    }
  }

  Future<Object?> _request(String method, String ip, int port, String code, Object? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.openUrl(
        method,
        Uri(scheme: 'http', host: ip, port: port, path: RemoteSyncProtocol.apiSettings),
      );
      request.headers.set(RemoteSyncProtocol.pairingHeader, RemoteSyncProtocol.normalizePairingCode(code));
      if (body != null) {
        request.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        request.write(jsonEncode(body));
      }
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) return null;
      return jsonDecode(text);
    } finally {
      client.close(force: true);
    }
  }

  // ---- discovery ----

  Future<void> _startDiscovery() async {
    if (localIp.isEmpty) return;
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, RemoteSyncProtocol.discoveryPort);
      if (_disposed || !running) {
        socket.close();
        return;
      }
      socket.broadcastEnabled = true;
      _discovery = socket;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram != null) _heard(datagram);
      });
      _announce();
      _announceTimer = Timer.periodic(const Duration(seconds: 5), (_) => _announce());
    } on Object {
      // Discovery is optional: the QR code and the address still work.
    }
  }

  void _announce() {
    final socket = _discovery;
    if (socket == null) return;
    final packet = utf8.encode(
      jsonEncode(
        RemoteSyncProtocol.discoveryPacket(
          id: deviceId,
          name: deviceName,
          ip: localIp,
          port: port,
          platform: Platform.operatingSystem,
          version: appVersion,
        ),
      ),
    );
    try {
      socket.send(packet, InternetAddress('255.255.255.255'), RemoteSyncProtocol.discoveryPort);
    } on Object {
      // A network without broadcast.
    }
    // Devices not heard for two minutes are gone (3.x).
    final now = DateTime.now();
    final before = _devices.length;
    _devices.removeWhere((_, device) => now.difference(device.lastSeen) > const Duration(minutes: 2));
    if (_devices.length != before) _changed();
  }

  void _heard(Datagram datagram) {
    try {
      final packet = jsonDecode(utf8.decode(datagram.data));
      if (packet is! Map || packet['type'] != RemoteSyncProtocol.discoveryType) return;
      final id = packet['id']?.toString() ?? '';
      if (id.isEmpty || id == deviceId) return;
      final ip = packet['ip']?.toString() ?? datagram.address.address;
      final port = int.tryParse('${packet['port']}') ?? RemoteSyncProtocol.defaultHttpPort;
      if (_ipv4(ip) == null || port < 1 || port > 65535) return;
      _devices[id] = RemoteSyncDevice(
        id: id,
        name: packet['name']?.toString() ?? 'PureLive',
        platform: packet['platform']?.toString() ?? '',
        version: packet['version']?.toString() ?? '',
        ip: ip,
        port: port,
        lastSeen: DateTime.now(),
      );
      _changed();
    } on Object {
      // Not ours.
    }
  }
}
