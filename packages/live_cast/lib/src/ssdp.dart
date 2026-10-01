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

/// Search target that every UPnP device answers.
const String allTarget = 'ssdp:all';

/// Search target of a media renderer device.
const String mediaRendererTarget = 'urn:schemas-upnp-org:device:MediaRenderer:1';

/// Search target of the renderer service a cast needs.
const String avTransportTarget = 'urn:schemas-upnp-org:service:AVTransport:1';

/// The `ST` values sent in search round [round] (0 first), as 3.x
/// (`dlna_dart` 0.1.1 `DLNAManager._sendSearchRequest`) sent them: all three
/// in the first round, then `ssdp:all` every fifth round and MediaRenderer
/// and AVTransport in turn between.
List<String> searchTargetsFor(int round) => switch (round) {
  0 => const [allTarget, mediaRendererTarget, avTransportTarget],
  _ when round % 5 == 0 => const [allTarget],
  _ when round % 5 == 1 || round % 5 == 3 => const [mediaRendererTarget],
  _ => const [avTransportTarget],
};

/// The `MX` of search round [round]: 1 second first, so near devices show
/// quickly, then 3 (3.x).
int searchMxFor(int round) => round == 0 ? 1 : 3;

/// An M-SEARCH request for [searchTarget]; devices answer within [mx]
/// seconds (§1.3.2; MX is clamped to 1–5). Header order as 3.x sent it.
Uint8List mSearchMessage(String searchTarget, {int mx = 3}) => ascii.encode(
  'M-SEARCH * HTTP/1.1\r\n'
  'HOST: 239.255.255.250:1900\r\n'
  'ST: $searchTarget\r\n'
  'MX: ${mx.clamp(1, 5)}\r\n'
  'MAN: "ssdp:discover"\r\n'
  '\r\n',
);

/// What an SSDP message says about a device.
enum SsdpKind {
  /// A unicast `200 OK` answer to an M-SEARCH (§1.3.3).
  response,

  /// A `NOTIFY` with `ssdp:alive` (§1.2.2): the device is there.
  alive,

  /// A `NOTIFY` with `ssdp:byebye` (§1.2.3): the device is leaving.
  byebye,
}

/// An SSDP message about a device: a search answer or an announcement.
@immutable
final class SsdpMessage {
  /// Creates a message.
  const new({required this.kind, required this.usn, this.location, this.target = '', this.server});

  /// Answer, arrival or departure.
  final SsdpKind kind;

  /// Unique service name: `uuid:…` or `uuid:…::urn:…`; may be empty on
  /// cheap devices, which are then known by [location].
  final String usn;

  /// Where the device description is; null only for [SsdpKind.byebye].
  final Uri? location;

  /// The `ST` answered or the `NT` announced.
  final String target;

  /// The `SERVER` header, if any.
  final String? server;

  /// Who the message is about: the device part of [usn] (`uuid:…`),
  /// lower-cased, so one device answering for several targets and on several
  /// interfaces counts once; `location:<url>` when there is no USN.
  String get deviceKey {
    final end = usn.indexOf('::');
    final device = (end < 0 ? usn : usn.substring(0, end)).trim().toLowerCase();
    if (device.isNotEmpty) return device;
    return 'location:$location';
  }

  /// Parses one datagram; null for anything else (another control point's
  /// M-SEARCH, an error status, an answer without an http(s) `LOCATION`).
  /// Header names are case-insensitive and lines may end in LF only (seen on
  /// cheap renderers).
  static SsdpMessage? parse(List<int> datagram) {
    final text = utf8.decode(datagram, allowMalformed: true);
    final lines = text.split('\n');
    final start = lines.first.trim();
    final SsdpKind? kind;
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers.putIfAbsent(line.substring(0, colon).trim().toLowerCase(), () => line.substring(colon + 1).trim());
    }
    if (RegExp(r'^HTTP/1\.[01]\s+200(\s|$)', caseSensitive: false).hasMatch(start)) {
      kind = SsdpKind.response;
    } else if (RegExp(r'^NOTIFY\s', caseSensitive: false).hasMatch(start)) {
      kind = switch (headers['nts']?.toLowerCase()) {
        'ssdp:alive' => SsdpKind.alive,
        'ssdp:byebye' => SsdpKind.byebye,
        _ => null,
      };
    } else {
      kind = null;
    }
    if (kind == null) return null;
    final usn = headers['usn'] ?? '';
    final target = headers[kind == SsdpKind.response ? 'st' : 'nt'] ?? '';
    if (kind == SsdpKind.byebye) {
      return usn.isEmpty ? null : SsdpMessage(kind: kind, usn: usn, target: target);
    }
    final location = Uri.tryParse(headers['location'] ?? '');
    if (location == null || !(location.isScheme('http') || location.isScheme('https')) || location.host.isEmpty) {
      return null;
    }
    return SsdpMessage(kind: kind, usn: usn, location: location, target: target, server: headers['server']);
  }

  @override
  String toString() => 'SsdpMessage(${kind.name}, $deviceKey${location == null ? '' : ' at $location'})';
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

/// One UDP socket of a search: a search socket sends M-SEARCH and reads the
/// unicast answers; the listener on port 1900 only reads announcements.
/// Tests replace it with a fake.
abstract interface class SsdpSocket {
  /// Interface and address, for diagnostics (`wlan0 192.168.1.5`).
  String get label;

  /// Datagrams received; closes when the socket closes.
  Stream<SsdpDatagram> get datagrams;

  /// Sends [data] to the SSDP group; false when the system refused it or
  /// the socket only listens.
  bool send(List<int> data);

  /// Closes the socket.
  void close();
}

/// Opens the sockets of one search.
typedef SsdpSocketOpener = Future<List<SsdpSocket>> Function();

/// [SsdpSocket] on a [RawDatagramSocket].
final class IoSsdpSocket implements SsdpSocket {
  new _(this._socket, this.label, {required this._sends}) {
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

  /// A search socket bound to [address] on an ephemeral port.
  ///
  /// Binding to the interface's address and setting `IP_MULTICAST_IF` makes
  /// the M-SEARCH leave through that interface; answers come back unicast to
  /// the bound port. 3.x sent from one socket on the any-address, so with a
  /// VPN up the search left through the VPN and found nothing.
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
    return IoSsdpSocket._(socket, label ?? address.address, sends: true);
  }

  /// The listener for announcements: port 1900, joined to the group on each
  /// of [interfaces] (or the default one), as 3.x listened.
  static Future<IoSsdpSocket> listen(List<NetworkInterface> interfaces) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, ssdpPort);
    var joined = false;
    for (final interface in interfaces) {
      try {
        socket.joinMulticast(ssdpGroup, interface);
        joined = true;
      } on Object {
        // An interface without multicast; the others still hear.
      }
    }
    if (!joined) {
      try {
        socket.joinMulticast(ssdpGroup);
      } on Object {
        socket.close();
        rethrow;
      }
    }
    return IoSsdpSocket._(socket, 'listen :$ssdpPort', sends: false);
  }

  final RawDatagramSocket _socket;
  final bool _sends;
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
    if (_closed || !_sends) return false;
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

/// Opens one search socket per non-loopback IPv4 address, so a search reaches
/// every network the device is on (Wi-Fi, Ethernet, a hotspot), plus the
/// announcement listener on port 1900 when the port is free. Falls back to
/// one search socket on the any-address when listing or binding fails;
/// throws [CastSearchFailure] when even that fails.
Future<List<SsdpSocket>> openSsdpSockets() async {
  final sockets = <SsdpSocket>[];
  var interfaces = <NetworkInterface>[];
  try {
    interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
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
  if (sockets.isEmpty) {
    try {
      sockets.add(await IoSsdpSocket.bind(InternetAddress.anyIPv4, label: 'any'));
    } on SocketException catch (error) {
      throw CastSearchFailure('no UDP socket: ${error.message}');
    }
  }
  try {
    sockets.add(await IoSsdpSocket.listen(interfaces));
  } on Object {
    // Port 1900 is taken (a system SSDP service) or multicast is refused;
    // the search answers alone find every renderer that answers M-SEARCH.
  }
  return sockets;
}
