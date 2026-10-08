import 'dart:math';

/// The LAN sync wire format, unchanged from 3.x
/// (`remote_sync_protocol.dart`), so 3.x and v4 devices sync both ways:
/// `GET /api/remote-sync/status`, `GET`/`POST /api/remote-sync/settings`
/// with the pairing code header, settings in 3.x's backup layout.
abstract final class RemoteSyncProtocol {
  /// First port tried by the server.
  static const int defaultHttpPort = 39888;

  /// UDP port of the discovery announcements.
  static const int discoveryPort = 39889;

  /// `type` of a discovery announcement.
  static const String discoveryType = 'pure_live_discovery';

  /// `type` of a settings packet.
  static const String syncType = 'pure_live_sync';

  /// Device information.
  static const String apiStatus = '/api/remote-sync/status';

  /// Settings: GET reads them, POST replaces them.
  static const String apiSettings = '/api/remote-sync/settings';

  /// The header with the pairing code shown on the target device; settings
  /// hold login cookies, so being on the same network is not enough.
  static const String pairingHeader = 'x-purelive-pairing';

  /// Digits of a pairing code.
  static const int pairingCodeLength = 6;

  /// A new random pairing code.
  static String newPairingCode([Random? random]) {
    final generator = random ?? Random.secure();
    return List.generate(pairingCodeLength, (_) => generator.nextInt(10)).join();
  }

  /// [value] without white space.
  static String normalizePairingCode(String? value) => (value ?? '').replaceAll(RegExp(r'\s'), '');

  /// Compares codes in constant time, so timing does not leak the code.
  static bool pairingCodesMatch(String? expected, String? provided) {
    final a = normalizePairingCode(expected);
    final b = normalizePairingCode(provided);
    if (a.length != pairingCodeLength || b.length != a.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// The QR code content: `purelive://<ip>:<port>/sync?code=<code>`.
  static Uri createQrUri({required String ip, required int port, required String code}) =>
      Uri(scheme: 'purelive', host: ip, port: port, path: '/sync', queryParameters: {'code': code});

  /// A discovery announcement.
  static Map<String, Object?> discoveryPacket({
    required String id,
    required String name,
    required String ip,
    required int port,
    required String platform,
    required String version,
  }) => {
    'type': discoveryType,
    'id': id,
    'name': name,
    'ip': ip,
    'port': port,
    'platform': platform,
    'version': version,
  };

  /// The key of the status answer that lists the parts a device takes on
  /// their own (new in v4, docs/J-设置和数据/J05-设备同步/J05.1-同步前勾选内容):
  /// only such a device gets a packet with some parts left out. 3.x (and
  /// upstream pure_live, and v4 before it) resets every section a packet
  /// lacks to its defaults, or may, so they always get everything.
  static const String partsKey = 'syncParts';

  /// The body of a settings POST; [sections] lists the sections [settings]
  /// keeps when some were left out (upstream pure_live `9483ccf03`'s optional
  /// field, same name and meaning); without it the packet is the whole
  /// backup, as 3.x sends it.
  static Map<String, Object?> settingsPacket({required Map<String, Object?> settings, List<String>? sections}) => {
    'type': syncType,
    'version': 1,
    'settings': settings,
    'sections': ?sections,
  };

  /// The `sections` of a settings packet: null when it has none (a whole
  /// backup) or when it is not a list of names.
  static List<String>? sectionsOf(Map<Object?, Object?> packet) {
    final sections = packet['sections'];
    if (sections is! List || sections.isEmpty) return null;
    final names = sections.whereType<String>().toList(growable: false);
    return names.length == sections.length ? names : null;
  }

  /// Whether a status answer's [data] says the device takes parts on their
  /// own ([partsKey]).
  static bool takesParts(Object? data) => data is Map && data[partsKey] is List;

  /// An address typed by the user (`192.168.1.2`, `192.168.1.2:39888`,
  /// `http://…`): IPv4 addresses and host names only; null otherwise.
  static ({String ip, int port})? parseHttpAddress(String value) {
    var text = value.trim();
    if (text.isEmpty) return null;
    if (!text.startsWith('http://') && !text.startsWith('https://')) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    final host = uri.host.trim();
    if (!RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$').hasMatch(host)) return null;
    final port = uri.hasPort ? uri.port : defaultHttpPort;
    if (port < 1 || port > 65535) return null;
    return (ip: host, port: port);
  }

  /// A sync QR code or a typed address; the code is null for an address.
  static ({String ip, int port, String? code})? parseQr(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('purelive:')) {
      final uri = Uri.tryParse(text);
      if (uri == null || uri.host.isEmpty || !uri.hasPort) return null;
      final code = normalizePairingCode(uri.queryParameters['code']);
      return (ip: uri.host, port: uri.port, code: code.length == pairingCodeLength ? code : null);
    }
    final address = parseHttpAddress(text);
    return address == null ? null : (ip: address.ip, port: address.port, code: null);
  }
}
