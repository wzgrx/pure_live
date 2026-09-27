import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_cast/src/failure.dart';
import 'package:meta/meta.dart';

/// The SSDP multicast group (UPnP Device Architecture 1.1 §1.1.2).
final InternetAddress ssdpGroup = InternetAddress('239.255.255.250');

/// The SSDP port.
const int ssdpPort = 1900;

/// Search target of the renderer service a cast needs.
const String avTransportTarget = 'urn:schemas-upnp-org:service:AVTransport:1';

/// Search target of a media renderer device; some renderers answer only this.
const String mediaRendererTarget = 'urn:schemas-upnp-org:device:MediaRenderer:1';

/// What one search asks for.
const List<String> rendererSearchTargets = [avTransportTarget, mediaRendererTarget];

final RegExp _rendererTarget = RegExp(
  r'^urn:schemas-upnp-org:(service:AVTransport|device:MediaRenderer):\d+$',
  caseSensitive: false,
);

/// Whether [searchTarget] (an `ST` value) names a renderer: AVTransport or
/// MediaRenderer, any version (some devices answer with their own version).
bool isRendererTarget(String searchTarget) => _rendererTarget.hasMatch(searchTarget.trim());

/// An M-SEARCH request for [searchTarget]; devices answer within [mx]
/// seconds (§1.3.2; MX is clamped to 1–5).
Uint8List mSearchMessage(String searchTarget, {int mx = 2}) => ascii.encode(
  'M-SEARCH * HTTP/1.1\r\n'
  'HOST: 239.255.255.250:1900\r\n'
  'MAN: "ssdp:discover"\r\n'
  'MX: ${mx.clamp(1, 5)}\r\n'
  'ST: $searchTarget\r\n'
  '\r\n',
);

/// A unicast answer to an M-SEARCH (§1.3.3).
@immutable
final class SsdpResponse {
  /// Creates a response.
  const new({required this.location, required this.usn, required this.searchTarget, this.server});

  /// Where the device description is.
  final Uri location;

  /// Unique service name: `uuid:…` or `uuid:…::urn:…`.
  final String usn;

  /// The `ST` answered.
  final String searchTarget;

  /// The `SERVER` header, if any.
  final String? server;

  /// The device part of [usn] (`uuid:…`), lower-cased: one device answers
  /// once per search target and interface, all with this id.
  String get deviceId {
    final end = usn.indexOf('::');
    return (end < 0 ? usn : usn.substring(0, end)).trim().toLowerCase();
  }

  /// Parses one datagram; null when it is not a `200 OK` with an HTTP
  /// `LOCATION` and a `USN`. Header names are case-insensitive and lines may
  /// end in LF only (seen on cheap renderers).
  static SsdpResponse? parse(List<int> datagram) {
    final text = utf8.decode(datagram, allowMalformed: true);
    final lines = text.split('\n');
    if (lines.isEmpty || !RegExp(r'^HTTP/1\.[01]\s+200(\s|$)', caseSensitive: false).hasMatch(lines.first.trim())) {
      return null;
    }
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers.putIfAbsent(line.substring(0, colon).trim().toLowerCase(), () => line.substring(colon + 1).trim());
    }
    final location = Uri.tryParse(headers['location'] ?? '');
    final usn = headers['usn'] ?? '';
    if (location == null || !(location.isScheme('http') || location.isScheme('https')) || location.host.isEmpty) {
      return null;
    }
    if (usn.isEmpty) return null;
    return SsdpResponse(location: location, usn: usn, searchTarget: headers['st'] ?? '', server: headers['server']);
  }

  @override
  String toString() => 'SsdpResponse($usn at $location)';
}

/// A datagram received on an [SsdpSocket].
@immutable
final class SsdpDatagram {
  /// Creates a datagram.
  const new(this.data, this.address, this.port);

  /// Payload.
  final List<int> data;

  /// Sender.
  final InternetAddress address;

  /// Sender port.
  final int port;
}

/// One UDP socket a search sends M-SEARCH from and reads the answers on; a
/// search opens one per IPv4 interface. Tests replace it with a fake.
abstract interface class SsdpSocket {
  /// Interface and address, for diagnostics (`wlan0 192.168.1.5`).
  String get label;

  /// Datagrams received; closes when the socket closes.
  Stream<SsdpDatagram> get datagrams;

  /// Sends [data] to the SSDP group; false when the system refused it.
  bool send(List<int> data);

  /// Closes the socket.
  void close();
}

/// Opens the sockets of one search.
typedef SsdpSocketOpener = Future<List<SsdpSocket>> Function();

/// [SsdpSocket] on a [RawDatagramSocket] bound to one interface address.
///
/// Binding to the interface's address and setting `IP_MULTICAST_IF` makes the
/// M-SEARCH leave through that interface; answers come back unicast to the
/// bound port, so the socket joins no group.
final class IoSsdpSocket implements SsdpSocket {
  new _(this._socket, this.label) {
    _socket
      ..readEventsEnabled = true
      ..writeEventsEnabled = false;
    _subscription = _socket.listen(
      (event) {
        if (event != RawSocketEvent.read) return;
        for (var datagram = _socket.receive(); datagram != null; datagram = _socket.receive()) {
          _datagrams.add(SsdpDatagram(datagram.data, datagram.address, datagram.port));
        }
      },
      onError: (Object _) {
        // A receive error on one interface ends only that socket's answers.
        close();
      },
      onDone: close,
    );
  }

  /// Binds a socket to [address] on an ephemeral port.
  static Future<IoSsdpSocket> bind(InternetAddress address, {String? label}) async {
    final socket = await RawDatagramSocket.bind(address, 0);
    try {
      // §1.1.2: TTL 2 by default.
      socket.multicastHops = 2;
    } on Object {
      // Not supported everywhere; the system default (1) still reaches the LAN.
    }
    if (address.address != InternetAddress.anyIPv4.address) {
      try {
        socket.setRawOption(
          RawSocketOption(RawSocketOption.levelIPv4, RawSocketOption.IPv4MulticastInterface, address.rawAddress),
        );
      } on Object {
        // Linux routes multicast by the bound source address anyway.
      }
    }
    return IoSsdpSocket._(socket, label ?? address.address);
  }

  final RawDatagramSocket _socket;
  final StreamController<SsdpDatagram> _datagrams = StreamController<SsdpDatagram>();
  late final StreamSubscription<RawSocketEvent> _subscription;
  bool _closed = false;

  @override
  final String label;

  /// The bound port, where answers arrive.
  int get port => _socket.port;

  @override
  Stream<SsdpDatagram> get datagrams => _datagrams.stream;

  @override
  bool send(List<int> data) {
    if (_closed) return false;
    try {
      return _socket.send(data, ssdpGroup, ssdpPort) > 0;
    } on SocketException {
      // Network unreachable on this interface.
      return false;
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    unawaited(_subscription.cancel());
    _socket.close();
    unawaited(_datagrams.close());
  }
}

/// Opens one [IoSsdpSocket] per non-loopback IPv4 address, so a search
/// reaches every network the device is on (Wi-Fi, Ethernet, a hotspot).
/// Falls back to one socket on any address when listing or binding fails;
/// throws [CastSearchFailure] when even that fails.
Future<List<SsdpSocket>> openSsdpSockets() async {
  final sockets = <SsdpSocket>[];
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.isLoopback || address.type != InternetAddressType.IPv4) continue;
        try {
          sockets.add(await IoSsdpSocket.bind(address, label: '${interface.name} ${address.address}'));
        } on SocketException {
          // An interface going down while listing; the others still search.
        }
      }
    }
  } on SocketException {
    // Listing is not allowed on some systems; the fallback below still works.
  }
  if (sockets.isNotEmpty) return sockets;
  try {
    return [await IoSsdpSocket.bind(InternetAddress.anyIPv4, label: 'any')];
  } on SocketException catch (error) {
    throw CastSearchFailure('no UDP socket: ${error.message}');
  }
}
