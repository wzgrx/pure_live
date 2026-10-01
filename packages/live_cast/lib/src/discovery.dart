import 'dart:async';
import 'dart:collection';

import 'package:live_cast/src/description.dart';
import 'package:live_cast/src/failure.dart';
import 'package:live_cast/src/http.dart';
import 'package:live_cast/src/renderer.dart';
import 'package:live_cast/src/ssdp.dart';

/// A running search for receivers (3.x `DlnaDiscoverySession`).
abstract interface class DlnaDiscoverySession {
  /// Every change of the receiver list, as the whole list in the order the
  /// receivers were found. A receiver missing from a snapshot is gone.
  /// Single subscription; closes when the search stops.
  Stream<List<DlnaCastDevice>> get devices;

  /// Ends the search and closes its sockets. Receivers already listed stay
  /// usable.
  Future<void> stop();
}

/// Starts a search; throws when it cannot start (3.x `DlnaDiscoveryStarter`).
typedef DlnaDiscoveryStarter = Future<DlnaDiscoverySession> Function();

CastHttp? _sharedHttp;

/// Starts a search on the local network, the default [DlnaDiscoveryStarter].
///
/// Throws [CastSearchFailure] when no socket opens or no M-SEARCH can be
/// sent. Receivers talk through [http]; without one, one client shared by
/// every search is used and never closed, so a receiver stays usable after
/// its search has ended (3.x shared one `HttpClient` the same way).
Future<DlnaDiscoverySession> startDlnaDiscovery({
  CastHttp? http,
  SsdpSocketOpener openSockets = openSsdpSockets,
}) async {
  final sockets = await openSockets();
  final session = SsdpDiscovery(sockets, http: http ?? (_sharedHttp ??= IoCastHttp()));
  if (!session.start()) {
    await session.stop();
    throw CastSearchFailure('M-SEARCH not sent on ${sockets.map((socket) => socket.label).join(', ')}');
  }
  return session;
}

/// [DlnaDiscoverySession] over SSDP, with 3.x's search pattern (`dlna_dart`
/// 0.1.1 `DLNAManager`): an M-SEARCH round every [interval] until stopped
/// (targets and MX from [searchTargetsFor] and [searchMxFor], [gap] between
/// the targets of one round), and the announcements heard on port 1900.
///
/// Each device's description is read once per search (3.x read it again for
/// every datagram, dozens of times a minute per device); devices without
/// AVTransport are not listed (3.x listed routers and media servers, and a
/// cast to them failed); one device answering for several targets or on
/// several interfaces is listed once, by UDN (3.x keyed devices by base
/// address). A device is dropped when it says `ssdp:byebye` or has not been
/// heard for [staleAfter] (3.x: 120 seconds).
final class SsdpDiscovery implements DlnaDiscoverySession {
  /// Creates a search over `sockets`; [start] sends the first round.
  new(
    this._sockets, {
    required this._http,
    this.interval = const Duration(seconds: 2),
    this.gap = const Duration(milliseconds: 30),
    this.descriptionTimeout = const Duration(seconds: 10),
    this.staleAfter = const Duration(seconds: 120),
  });

  final List<SsdpSocket> _sockets;
  final CastHttp _http;

  /// Time between search rounds.
  final Duration interval;

  /// Time between the targets of one round.
  final Duration gap;

  /// Limit for reading one description.
  final Duration descriptionTimeout;

  /// How long a device stays listed without being heard.
  final Duration staleAfter;

  final StreamController<List<DlnaCastDevice>> _out = StreamController<List<DlnaCastDevice>>();
  final List<StreamSubscription<SsdpDatagram>> _subscriptions = [];
  final LinkedHashMap<String, DlnaRenderer> _devices = LinkedHashMap();

  /// Device key → renderer id, or null for a device that is not a renderer.
  final Map<String, String?> _known = {};
  final Map<String, int> _lastHeard = {};
  final Map<String, int> _failedRound = {};
  final Set<String> _loading = {};
  Timer? _rounds;
  int _round = 0;
  bool _started = false;
  bool _stopped = false;

  @override
  Stream<List<DlnaCastDevice>> get devices => _out.stream;

  /// Starts listening and sends the first round; false when no socket could
  /// send it. Later calls do nothing and return true.
  bool start() {
    if (_started || _stopped) return !_stopped;
    _started = true;
    for (final socket in _sockets) {
      _subscriptions.add(socket.datagrams.listen(_receive));
    }
    final sent = _sendRound();
    _rounds = Timer.periodic(interval, (_) {
      _sendRound();
      _dropStale();
    });
    return sent;
  }

  bool _sendRound() {
    final round = _round++;
    final targets = searchTargetsFor(round);
    final mx = searchMxFor(round);
    final sent = _send(targets.first, mx);
    for (var index = 1; index < targets.length; index++) {
      final target = targets[index];
      Timer(gap * index, () => _send(target, mx));
    }
    return sent;
  }

  bool _send(String target, int mx) {
    if (_stopped) return false;
    final message = mSearchMessage(target, mx: mx);
    var sent = false;
    for (final socket in _sockets) {
      if (socket.send(message)) sent = true;
    }
    return sent;
  }

  void _receive(SsdpDatagram datagram) {
    if (_stopped) return;
    final message = SsdpMessage.parse(datagram.data);
    if (message == null) return;
    final key = message.deviceKey;
    if (message.kind == SsdpKind.byebye) {
      _forget(key);
      return;
    }
    _lastHeard[key] = _round;
    if (_known.containsKey(key) || _loading.contains(key) || _failedRound[key] == _round) return;
    unawaited(_describe(key, message.location!));
  }

  Future<void> _describe(String key, Uri location) async {
    _loading.add(key);
    try {
      final answer = await _http.send('GET', location, timeout: descriptionTimeout);
      if (!answer.isSuccess) throw CastHttpFailure(answer.statusCode, 'description');
      final device = parseDeviceDescription(answer.body, location);
      if (_stopped) return;
      _known[key] = device?.id;
      if (device != null) {
        _devices[device.id] = DlnaRenderer(device, http: _http);
        _publish();
      }
    } on Exception {
      // Unreachable or unreadable: asked again when the device is heard in a
      // later round. A readable description without AVTransport is not.
      _failedRound[key] = _round;
    } finally {
      _loading.remove(key);
    }
  }

  void _forget(String key) {
    _lastHeard.remove(key);
    _failedRound.remove(key);
    if (!_known.containsKey(key)) return;
    final id = _known.remove(key);
    if (id == null || _known.containsValue(id)) return;
    if (_devices.remove(id) != null) _publish();
  }

  void _dropStale() {
    final limit = (staleAfter.inMicroseconds / interval.inMicroseconds).ceil();
    [
      for (final MapEntry(:key, :value) in _lastHeard.entries)
        if (_round - value > limit) key,
    ].forEach(_forget);
  }

  void _publish() {
    if (!_stopped) _out.add(List<DlnaCastDevice>.unmodifiable(_devices.values));
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _rounds?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    for (final socket in _sockets) {
      socket.close();
    }
    // Not awaited: the done event of a stream nobody listens to never fires.
    unawaited(_out.close());
  }
}
