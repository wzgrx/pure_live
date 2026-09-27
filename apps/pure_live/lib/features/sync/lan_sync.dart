import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:live_net/live_net.dart';

/// The LAN sync protocol (store.md §9), wire-compatible with 3.x: HTTP on
/// port 39888, `POST /api/remote-sync/settings` with the pairing code in
/// `x-purelive-pairing`, JSON answers `{code, msg, data}`, no CORS headers.
abstract final class LanSyncProtocol {
  /// Default HTTP port.
  static const port = 39888;

  /// Device information (no pairing code needed).
  static const statusPath = '/api/remote-sync/status';

  /// Where a package is sent.
  static const settingsPath = '/api/remote-sync/settings';

  /// Header carrying the pairing code.
  static const pairingHeader = 'x-purelive-pairing';

  /// Digits in a pairing code.
  static const codeLength = 6;

  /// `type` of a sync package.
  static const syncType = 'pure_live_sync';

  /// Package version sent by v4: `backup` holds a v4 document. Receivers also
  /// accept version 1 (3.x: `settings` holds a v3 export).
  static const packageVersion = 2;

  /// A random pairing code.
  static String newCode([Random? random]) {
    final generator = random ?? Random.secure();
    return List.generate(codeLength, (_) => generator.nextInt(10)).join();
  }

  /// [value] without whitespace.
  static String normalizeCode(String? value) => (value ?? '').replaceAll(RegExp(r'\s'), '');

  /// Compares codes in constant time, so response timing does not leak them.
  static bool codesMatch(String? expected, String? provided) {
    final a = normalizeCode(expected);
    final b = normalizeCode(provided);
    if (a.length != codeLength || b.length != a.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  /// `purelive://<host>:<port>/sync?code=<code>`, the text of the QR code
  /// (3.x devices can scan it).
  static Uri qrUri({required String host, required int port, required String code}) =>
      Uri(scheme: 'purelive', host: host, port: port, path: '/sync', queryParameters: {'code': code});

  /// Reads an address the user typed or pasted: `host`, `host:port`,
  /// `http://host:port` or the QR text (which also carries the code).
  static LanTarget? parseTarget(String text) {
    var value = text.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('purelive:')) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.host.isEmpty) return null;
      final code = normalizeCode(uri.queryParameters['code']);
      return LanTarget(
        uri.host,
        uri.hasPort ? uri.port : port,
        code: code.length == codeLength && int.tryParse(code) != null ? code : null,
      );
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) value = 'http://$value';
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final host = uri.host.trim();
    // IPv4 addresses and host names only; free text is not an address.
    if (!RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$').hasMatch(host)) return null;
    final targetPort = uri.hasPort ? uri.port : port;
    if (targetPort < 1 || targetPort > 65535) return null;
    return LanTarget(host, targetPort);
  }

  /// A v4 sync package around a v4 backup [document].
  static Map<String, Object?> package(Map<String, Object?> document, {LanDevice? from}) => {
    'type': syncType,
    'version': packageVersion,
    'backup': document,
    if (from != null) 'device': from.toJson(),
  };
}

/// Where to send a package.
@immutable
final class LanTarget {
  /// Creates a target.
  const new(this.host, this.port, {this.code});

  /// IPv4 address or host name.
  final String host;

  /// HTTP port.
  final int port;

  /// Pairing code, when the text carried one (QR code).
  final String? code;

  /// URL of [LanSyncProtocol.settingsPath].
  Uri get settingsUrl => Uri(scheme: 'http', host: host, port: port, path: LanSyncProtocol.settingsPath);

  /// URL of [LanSyncProtocol.statusPath].
  Uri get statusUrl => Uri(scheme: 'http', host: host, port: port, path: LanSyncProtocol.statusPath);

  @override
  bool operator ==(Object other) =>
      other is LanTarget && other.host == host && other.port == port && other.code == code;

  @override
  int get hashCode => Object.hash(host, port, code);

  @override
  String toString() => '$host:$port';
}

/// A device taking part in LAN sync.
@immutable
final class LanDevice {
  /// Creates a device.
  const new({required this.id, required this.name, required this.platform, required this.version});

  /// Reads a device; null when [json] is not one.
  static LanDevice? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    String text(String key) => json[key] is String ? json[key]! as String : '';
    final name = text('name');
    if (name.isEmpty) return null;
    return LanDevice(id: text('id'), name: name, platform: text('platform'), version: text('version'));
  }

  /// Stable id of the installation (store.md §9: 3.x `remote_sync_device_id`).
  final String id;

  /// Name shown to the other side.
  final String name;

  /// `android`, `windows`, ...
  final String platform;

  /// App version.
  final String version;

  /// JSON form.
  Map<String, Object?> toJson() => {'id': id, 'name': name, 'platform': platform, 'version': version};
}

/// A package that arrived at the receiver, waiting for the user's decision.
@immutable
final class LanIncoming {
  /// Creates an incoming package.
  const new({required this.document, required this.remoteAddress, this.sender});

  /// The decoded package (`type: pure_live_sync`, version 1 or 2).
  final Map<String, Object?> document;

  /// The sender's IP address.
  final String remoteAddress;

  /// What the sender says about itself (v4 senders only).
  final LanDevice? sender;
}

/// The receiving user's decision about a package.
enum LanDecision {
  /// Confirmed and imported.
  applied,

  /// Declined (or not answered in time).
  rejected,

  /// The package is not a backup this app can import.
  invalid,

  /// Importing failed.
  failed,
}

/// Decides about an incoming package; the app shows the dry run and asks the
/// user before anything is written (constitution rule 8).
typedef LanPackageHandler = Future<LanDecision> Function(LanIncoming incoming);

/// Receives sync packages (F-SYNC-01): an HTTP server on the local network
/// that only accepts requests carrying the pairing code shown on this device
/// and hands every package to [handler], which must ask the user. It never
/// writes anything itself.
///
/// Protections: pairing code compared in constant time; the code changes
/// after [maxFailures] wrong attempts and after every decision (one code,
/// one package); one package at a time; body size limit; requests from web
/// pages (with an `Origin` header) are refused and no CORS headers are sent.
final class LanSyncReceiver {
  /// Creates a receiver; [start] opens it.
  new({
    required this.handler,
    required this.device,
    this.preferredPort = LanSyncProtocol.port,
    this.maxBodyBytes = 32 * 1024 * 1024,
    this.maxFailures = 5,
    this.decisionTimeout = const Duration(minutes: 3),
    this.onCodeChanged,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Decides about packages.
  final LanPackageHandler handler;

  /// This device, answered on the status path.
  final LanDevice device;

  /// First port to try; the next 20 are tried when it is taken. 0 picks a
  /// free port (tests).
  final int preferredPort;

  /// Largest accepted package.
  final int maxBodyBytes;

  /// Wrong codes before the code changes.
  final int maxFailures;

  /// How long a package waits for the user.
  final Duration decisionTimeout;

  /// Called with the new code whenever it changes.
  final void Function(String code)? onCodeChanged;

  final Random _random;
  HttpServer? _server;
  String _code = '';
  int _failures = 0;
  bool _pending = false;

  /// The current pairing code.
  String get code => _code;

  /// The port being served, or null when stopped.
  int? get port => _server?.port;

  /// Whether the server is open.
  bool get isRunning => _server != null;

  /// Opens the server on all IPv4 interfaces and returns the port.
  Future<int> start() async {
    if (_server case final server?) return server.port;
    SocketException? lastError;
    final ports = preferredPort == 0 ? [0] : [for (var i = 0; i <= 20; i++) preferredPort + i];
    for (final candidate in ports) {
      try {
        _server = await HttpServer.bind(InternetAddress.anyIPv4, candidate);
        break;
      } on SocketException catch (error) {
        lastError = error;
      }
    }
    final server = _server;
    if (server == null) throw lastError ?? const SocketException('No free port');
    _rotate();
    server.listen((request) => unawaited(_handle(request)), onError: (Object _) {});
    return server.port;
  }

  /// Closes the server; a package waiting for a decision is answered as
  /// rejected.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  void _rotate() {
    _code = LanSyncProtocol.newCode(_random);
    _failures = 0;
    onCodeChanged?.call(_code);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      // A web page in a browser on the same network must not reach this.
      if (request.headers.value('origin') != null) {
        return await _answer(response, HttpStatus.forbidden, 'Web requests are not accepted', reason: 'origin');
      }
      switch (request.uri.path) {
        case LanSyncProtocol.statusPath when request.method == 'GET':
          return await _answer(response, HttpStatus.ok, 'ok', data: {...device.toJson(), 'port': port});
        case LanSyncProtocol.settingsPath:
          return await _receive(request);
        default:
          return await _answer(response, HttpStatus.notFound, 'Not Found');
      }
    } on Object {
      try {
        await _answer(response, HttpStatus.internalServerError, 'Internal Server Error');
      } on Object {
        // The connection is gone.
      }
    }
  }

  Future<void> _receive(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'POST') {
      return await _answer(response, HttpStatus.methodNotAllowed, 'Method Not Allowed');
    }
    if (!LanSyncProtocol.codesMatch(_code, request.headers.value(LanSyncProtocol.pairingHeader))) {
      if (++_failures >= maxFailures) _rotate();
      return await _answer(response, HttpStatus.forbidden, 'Pairing code required', reason: 'pairing');
    }
    if (_pending) return await _answer(response, HttpStatus.conflict, 'Busy', reason: 'busy');
    _pending = true;
    try {
      final body = await _readBody(request);
      if (body == null) return await _answer(response, HttpStatus.requestEntityTooLarge, 'Too large', reason: 'size');
      final Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(body));
      } on FormatException {
        return await _answer(response, HttpStatus.badRequest, 'Invalid request', reason: 'invalid');
      }
      if (decoded is! Map<String, Object?> || decoded['type'] != LanSyncProtocol.syncType) {
        return await _answer(response, HttpStatus.badRequest, 'Invalid sync type', reason: 'invalid');
      }
      final incoming = LanIncoming(
        document: decoded,
        remoteAddress: request.connectionInfo?.remoteAddress.address ?? '',
        sender: LanDevice.fromJson(decoded['device']),
      );
      LanDecision decision;
      try {
        decision = await handler(incoming).timeout(decisionTimeout, onTimeout: () => LanDecision.rejected);
      } on Object {
        decision = LanDecision.failed;
      }
      if (decision == LanDecision.applied || decision == LanDecision.rejected) _rotate();
      return await switch (decision) {
        LanDecision.applied => _answer(response, HttpStatus.ok, 'ok', data: true),
        LanDecision.rejected => _answer(response, HttpStatus.forbidden, 'Rejected on the device', reason: 'rejected'),
        LanDecision.invalid => _answer(response, HttpStatus.badRequest, 'Unsupported backup', reason: 'invalid'),
        LanDecision.failed => _answer(response, HttpStatus.internalServerError, 'Apply failed', reason: 'failed'),
      };
    } finally {
      _pending = false;
    }
  }

  Future<List<int>?> _readBody(HttpRequest request) async {
    if (request.contentLength > maxBodyBytes) return null;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytes.add(chunk);
      if (bytes.length > maxBodyBytes) return null;
    }
    return bytes.takeBytes();
  }

  static Future<void> _answer(HttpResponse response, int status, String message, {Object? data, String? reason}) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
      ..write(jsonEncode({'code': status, 'msg': message, 'data': data ?? false, 'reason': ?reason}));
    await response.close();
  }
}

/// How sending a package ended.
enum LanSendResult {
  /// The other device confirmed and imported it.
  applied,

  /// The pairing code was wrong.
  wrongCode,

  /// The other user declined (or did not answer in time).
  rejected,

  /// The other device is busy with another package.
  busy,

  /// The other device cannot import this package (for example 3.x, which
  /// only accepts 3.x data).
  unsupported,

  /// Nothing answers at the address.
  unreachable,

  /// No answer in time.
  timeout,

  /// The other device failed to import it.
  failed,
}

/// Sends sync packages to a [LanSyncReceiver] (or a 3.x receiver).
final class LanSyncSender {
  /// Sends over [_http], which must not route local addresses through a
  /// proxy; [timeout] covers the other user's confirmation.
  new(this._http, {this.timeout = const Duration(minutes: 4)});

  /// Site id of the requests.
  static const site = 'lan';

  final LiveHttp _http;

  /// Limit for one exchange, the other user's decision included.
  final Duration timeout;

  /// Asks [target] who it is; null when it does not answer like a receiver.
  Future<LanDevice?> status(LanTarget target) async {
    try {
      final response = await _http.send(
        LiveRequest(site: site, url: target.statusUrl, timeout: const Duration(seconds: 5)),
      );
      if (!response.isSuccess) return null;
      final body = jsonDecode(response.text);
      return body is Map<String, Object?> ? LanDevice.fromJson(body['data']) : null;
    } on TransportFailure {
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Sends [package] to [target] with the pairing [code] and waits for the
  /// other device's decision.
  Future<LanSendResult> send(LanTarget target, String code, Map<String, Object?> package) async {
    final LiveResponse response;
    try {
      response = await _http.send(
        LiveRequest(
          site: site,
          url: target.settingsUrl,
          method: 'POST',
          headers: {
            'content-type': 'application/json; charset=utf-8',
            LanSyncProtocol.pairingHeader: LanSyncProtocol.normalizeCode(code),
          },
          body: utf8.encode(jsonEncode(package)),
          followRedirects: false,
          timeout: timeout,
        ),
      );
    } on TransportFailure catch (failure) {
      return failure.reason == TransportReason.timeout ? LanSendResult.timeout : LanSendResult.unreachable;
    }
    Map<String, Object?> body;
    try {
      final decoded = jsonDecode(response.text);
      body = decoded is Map<String, Object?> ? decoded : const {};
    } on FormatException {
      body = const {};
    }
    final reason = body['reason'];
    final message = '${body['msg'] ?? ''}';
    return switch (response.status) {
      200 => body['data'] == true ? LanSendResult.applied : LanSendResult.failed,
      403 when reason == 'pairing' || message.startsWith('Pairing') => LanSendResult.wrongCode,
      403 => LanSendResult.rejected,
      409 => LanSendResult.busy,
      400 || 413 || 405 => LanSendResult.unsupported,
      _ => LanSendResult.failed,
    };
  }
}

/// This device's IPv4 addresses on local networks, private ranges first.
Future<List<String>> localAddresses() async {
  final List<NetworkInterface> interfaces;
  try {
    interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
  } on SocketException {
    return const [];
  }
  final addresses = {
    for (final interface in interfaces)
      for (final address in interface.addresses)
        if (!address.isLoopback && !address.isLinkLocal) address.address,
  }.toList();
  int rank(String address) {
    if (address.startsWith('192.168.')) return 0;
    if (address.startsWith('10.')) return 1;
    final parts = address.split('.');
    final second = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    if (address.startsWith('172.') && second >= 16 && second <= 31) return 2;
    return 3;
  }

  addresses.sort((a, b) => rank(a).compareTo(rank(b)));
  return addresses;
}
