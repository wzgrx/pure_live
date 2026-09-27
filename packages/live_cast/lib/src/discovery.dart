import 'dart:async';

import 'package:live_cast/src/description.dart';
import 'package:live_cast/src/failure.dart';
import 'package:live_cast/src/http.dart';
import 'package:live_cast/src/ssdp.dart';

/// Finds DLNA renderers on the local network (F-CAST-01): SSDP M-SEARCH for
/// AVTransport and MediaRenderer on every IPv4 interface, then each new
/// device's description.
final class CastDiscovery {
  /// Creates a discovery. `http` reads descriptions; `openSockets` opens the
  /// sockets of one search ([openSsdpSockets] by default).
  new({
    required this._http,
    this._openSockets = openSsdpSockets,
    this.timeout = const Duration(seconds: 4),
    this.resendAfter = const Duration(seconds: 1),
    this.descriptionTimeout = const Duration(seconds: 3),
    this.searchTargets = rendererSearchTargets,
  });

  final CastHttp _http;
  final SsdpSocketOpener _openSockets;

  /// How long answers are collected.
  final Duration timeout;

  /// When the M-SEARCH is sent a second time (UDP may drop the first);
  /// not resent when this is not shorter than [timeout].
  final Duration resendAfter;

  /// Limit for reading one description.
  final Duration descriptionTimeout;

  /// The `ST` values searched.
  final List<String> searchTargets;

  /// Searches once.
  ///
  /// Emits each renderer once, as soon as its description is read; one device
  /// answering for several targets or on several interfaces counts once (by
  /// the device part of its USN, then by its UDN). Answers stop after
  /// [timeout]; the stream closes when the descriptions still loading have
  /// finished. Devices whose description fails or has no AVTransport are
  /// skipped. The stream fails with [CastSearchFailure] when no socket opens
  /// or no M-SEARCH can be sent. Cancelling the subscription ends the search
  /// and closes its sockets at once.
  Stream<CastDevice> search() {
    late final _Search run;
    final controller = StreamController<CastDevice>(
      onListen: () => unawaited(run.start()),
      onCancel: () => run.cancel(),
    );
    run = _Search(this, controller);
    return controller.stream;
  }
}

final class _Search {
  new(this._owner, this._out);

  final CastDiscovery _owner;
  final StreamController<CastDevice> _out;
  final List<SsdpSocket> _sockets = [];
  final List<StreamSubscription<SsdpDatagram>> _subscriptions = [];
  final Set<String> _answered = {};
  final Set<String> _emitted = {};
  Timer? _resend;
  Timer? _deadline;
  int _loading = 0;
  bool _listening = false;
  bool _done = false;

  Future<void> start() async {
    final List<SsdpSocket> sockets;
    try {
      sockets = await _owner._openSockets();
    } on Object catch (error) {
      _fail(error is CastSearchFailure ? error : CastSearchFailure('$error'));
      return;
    }
    if (_done) {
      for (final socket in sockets) {
        socket.close();
      }
      return;
    }
    if (sockets.isEmpty) {
      _fail(const CastSearchFailure('no network interface'));
      return;
    }
    _sockets.addAll(sockets);
    _listening = true;
    for (final socket in sockets) {
      _subscriptions.add(socket.datagrams.listen(_receive));
    }
    if (!_sendAll()) {
      _fail(CastSearchFailure('M-SEARCH not sent on ${sockets.map((socket) => socket.label).join(', ')}'));
      return;
    }
    if (_owner.resendAfter < _owner.timeout) _resend = Timer(_owner.resendAfter, _sendAll);
    _deadline = Timer(_owner.timeout, _stopListening);
  }

  /// Sends every target on every socket; true when at least one went out.
  bool _sendAll() {
    final mx = (_owner.timeout.inSeconds ~/ 2).clamp(1, 5);
    var sent = false;
    for (final target in _owner.searchTargets) {
      final message = mSearchMessage(target, mx: mx);
      for (final socket in _sockets) {
        if (socket.send(message)) sent = true;
      }
    }
    return sent;
  }

  void _receive(SsdpDatagram datagram) {
    if (!_listening) return;
    final response = SsdpResponse.parse(datagram.data);
    if (response == null || !isRendererTarget(response.searchTarget)) return;
    if (!_answered.add(response.deviceId)) return;
    unawaited(_describe(response));
  }

  Future<void> _describe(SsdpResponse response) async {
    _loading++;
    try {
      final answer = await _owner._http.send('GET', response.location, timeout: _owner.descriptionTimeout);
      if (_done || !answer.isSuccess) return;
      final device = parseDeviceDescription(answer.body, response.location);
      if (device != null && !_done && _emitted.add(device.id)) _out.add(device);
    } on Exception {
      // Unreachable or not a renderer description: skip this device.
    } finally {
      _loading--;
      if (!_listening && _loading == 0) _finish();
    }
  }

  void _stopListening() {
    _listening = false;
    _resend?.cancel();
    _closeSockets();
    if (_loading == 0) _finish();
  }

  void _closeSockets() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    for (final socket in _sockets) {
      socket.close();
    }
    _sockets.clear();
  }

  void _fail(CastSearchFailure failure) {
    if (_done) return;
    _out.addError(failure);
    _stopListening();
    _finish();
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _resend?.cancel();
    _deadline?.cancel();
    unawaited(_out.close());
  }

  void cancel() {
    _listening = false;
    _finish();
    _closeSockets();
  }
}
