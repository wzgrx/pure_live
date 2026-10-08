// E06.2 c6 (UPGRADES 26-2): the FC2 control a quality probe opened is
// handed to playback through Fc2ControlPool, by channel, for any tier; one
// nobody takes is closed after 20 s; a newer one of the same channel
// replaces it; closing the pool closes them all. The controls are real
// Fc2LiveControls over a fake socket replaying the recorded control
// answers (fixtures/fc2live/control); the 20 s are an injected timer.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

const _root = '../../fixtures/fc2live/control';

/// The channel of S07-control-hd (tiers 50 and 40 too) and of S04-control.
const _hd = '10200498';
const _live = '62996200';

List<String> _serverFrames(String sample) => [
  for (final line in File('$_root/$sample/frames.jsonl').readAsLinesSync())
    if (line.trim().isNotEmpty)
      if (jsonDecode(line) case {'dir': 'in', 'text': final String text}) text,
];

/// A fake control socket: the recorded server frames, queued.
final class _Socket implements SocketChannel {
  new(List<String> frames) {
    frames.forEach(incoming.add);
  }

  final StreamController<Object?> incoming = StreamController<Object?>();
  bool closed = false;

  @override
  Stream<Object?> get stream => incoming.stream;

  @override
  void add(Object data) {
    if (closed) throw StateError('send failed');
  }

  @override
  Future<void> close([int? code, String? reason]) async => closed = true;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

/// An open control of [channel] (`auto`, as the probe opens it) and its socket.
Future<(Fc2LiveControl, _Socket)> _control(String channel) async {
  final socket = _Socket(_serverFrames(channel == _hd ? 'S07-control-hd' : 'S04-control'));
  final control = await Fc2LiveControl.open(
    Fc2LiveGrant(
      channelId: channel,
      socket: Uri.parse('wss://ws.live.fc2.com/control/channels/$channel'),
      controlToken: 'token',
      orz: 'orz',
    ),
    connector: (endpoint, {required headers, required protocols, required route, required connectTimeout}) async =>
        socket,
  );
  return (control, socket);
}

/// Timers the test fires by hand.
final class _Clock {
  final List<_Timer> timers = [];

  Timer call(Duration duration, void Function() callback) {
    final timer = _Timer(duration, callback);
    timers.add(timer);
    return timer;
  }
}

final class _Timer implements Timer {
  new(this.duration, this._callback);

  final Duration duration;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

/// A transport that must not be asked: a control from the pool needs no
/// request. It records what it was asked and fails.
final class _NoRequests implements LiveHttp {
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    throw TransportFailure(request.site, TransportReason.connect);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    requests.add(request);
    throw TransportFailure(request.site, TransportReason.connect);
  }

  @override
  void close() {}
}

void main() {
  late LoopbackRelay relay;
  setUp(() async => relay = await LoopbackRelay.start());
  tearDown(() => relay.close());

  test("an open takes its channel's probe control, for any tier, without a request", () async {
    final http = _NoRequests();
    final site = Fc2LiveSite(http);
    final pool = Fc2ControlPool(timer: _Clock().call);
    final (control, socket) = await _control(_hd);
    expect(control.requestedQuality, 'auto');
    pool.adopt(control);
    expect(pool.length, 1);

    final opener = Fc2RecipeOpener(site, pool: pool);
    final input = await opener.open(Fc2LiveInputRecipe(_hd, quality: '50'), relay);
    expect(input.relay.line.url, startsWith('https://'));
    expect(Uri.parse(input.relay.line.url).path, '/a/stream/$_hd/51/playlist', reason: "the tier's variant");
    expect(input.relay.line.headers, control.mediaHeaders);
    expect(pool.length, 0);
    expect(http.requests, isEmpty, reason: 'no second grant, no second socket');
    expect(input.isUsable, isTrue);
    await input.close();
    expect((control.isClosed, socket.closed), (true, true), reason: 'the input owned it');
  });

  test('auto plays the master from the same control; another channel opens its own', () async {
    final http = _NoRequests();
    final site = Fc2LiveSite(http);
    final pool = Fc2ControlPool(timer: _Clock().call);
    final (control, _) = await _control(_hd);
    pool.adopt(control);
    final opener = Fc2RecipeOpener(site, pool: pool);
    final input = await opener.open(Fc2LiveInputRecipe(_hd), relay);
    expect(Uri.parse(input.relay.line.url).path, '/a/stream/$_hd/0/master_playlist');
    await input.close();

    // Nothing kept for this channel: the platform is asked for a control.
    await expectLater(opener.open(Fc2LiveInputRecipe(_live, quality: '30'), relay), throwsA(isA<SiteError>()));
    expect(http.requests.map((request) => request.url.path), ['/api/memberApi.php']);
  });

  test('a control nobody takes is closed after 20 s', () async {
    final clock = _Clock();
    final pool = Fc2ControlPool(timer: clock.call);
    expect(pool.unclaimedLifetime, const Duration(seconds: 20));
    final (control, socket) = await _control(_hd);
    pool.adopt(control);
    expect(clock.timers.single.duration, const Duration(seconds: 20));
    expect(control.isClosed, isFalse);
    clock.timers.single.fire();
    await pumpEventQueue();
    expect((pool.length, control.isClosed, socket.closed), (0, true, true));
    expect(pool.take(_hd), isNull);
  });

  test('a newer control of the same channel replaces the one kept; taking stops its clock', () async {
    final clock = _Clock();
    final pool = Fc2ControlPool(timer: clock.call);
    final (first, firstSocket) = await _control(_hd);
    final (second, _) = await _control(_hd);
    pool
      ..adopt(first)
      ..adopt(second);
    await pumpEventQueue();
    expect((first.isClosed, firstSocket.closed), (true, true));
    expect(pool.length, 1);
    // The first one's clock was stopped; it cannot close the second.
    clock.timers.first.fire();
    expect(second.isClosed, isFalse);
    expect(pool.take(_hd), same(second));
    clock.timers.last.fire();
    expect(second.isClosed, isFalse, reason: 'taken: the caller owns it');
    await second.close();
  });

  test('a control that ends while it waits leaves the pool', () async {
    final pool = Fc2ControlPool(timer: _Clock().call);
    final (control, socket) = await _control(_hd);
    pool.adopt(control);
    // The server ends the control (the grant expired).
    await socket.incoming.close();
    await control.done;
    await pumpEventQueue();
    expect(pool.length, 0);
    expect(pool.take(_hd), isNull);
  });

  test('closing the pool closes every control kept (the app ends)', () async {
    final pool = Fc2ControlPool(timer: _Clock().call);
    final (hd, hdSocket) = await _control(_hd);
    final (live, liveSocket) = await _control(_live);
    pool
      ..adopt(hd)
      ..adopt(live);
    expect(pool.length, 2);
    await pool.close();
    expect((pool.length, hd.isClosed, live.isClosed), (0, true, true));
    expect((hdSocket.closed, liveSocket.closed), (true, true));
  });

  test("one pool per adapter: playback's and recording's openers share it", () {
    final site = Fc2LiveSite(_NoRequests());
    expect(Fc2ControlPool.of(site), same(Fc2ControlPool.of(site)));
    expect(Fc2RecipeOpener(site).pool, same(Fc2ControlPool.of(site)));
    expect(Fc2ControlPool.of(Fc2LiveSite(_NoRequests())), isNot(same(Fc2ControlPool.of(site))));
  });
}
