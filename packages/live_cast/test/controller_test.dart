import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:live_cast/live_cast.dart';
import 'package:test/test.dart';

// Ported from 3.x test/live_dlna_dialog_test.dart: the dialog's logic now
// lives in DlnaCastController, so the widget assertions become state ones.

const _source = 'https://media.example/live.m3u8';

void main() {
  test('DLNA source accepts normalized web URLs and rejects unsafe inputs', () {
    expect(
      normalizeDlnaSource('  https://media.example/live.m3u8?token=fixture  '),
      'https://media.example/live.m3u8?token=fixture',
    );
    for (final value in [
      '',
      'file:///tmp/live.m3u8',
      'rtmp://media.example/live',
      'https:///missing-host',
      'https://user:secret@media.example/live',
      'javascript:alert(1)',
    ]) {
      expect(normalizeDlnaSource(value), isNull, reason: value);
    }
  });

  test('invalid source is terminal and never starts discovery', () async {
    var starts = 0;
    final controller = DlnaCastController(
      'file:///tmp/live.m3u8',
      startDiscovery: () async {
        starts++;
        return _FixtureSession();
      },
    );
    await controller.startSearch();
    expect(starts, 0);
    expect(controller.source, isNull);
    expect(controller.state.status, DlnaCastStatus.invalidSource);
  });

  test('startup is single-flight and timeout stops one session', () {
    fakeAsync((async) {
      final startGate = Completer<DlnaDiscoverySession>();
      final session = _FixtureSession();
      var starts = 0;
      final controller = DlnaCastController(
        _source,
        searchDuration: const Duration(seconds: 1),
        startDiscovery: () {
          starts++;
          return startGate.future;
        },
      );
      final first = controller.startSearch();
      final second = controller.startSearch();
      expect(first, same(second));
      expect(starts, 1);
      expect(controller.state.starting, isTrue);

      startGate.complete(session);
      async.flushMicrotasks();
      expect(controller.state.status, DlnaCastStatus.searching);
      expect(controller.state.starting, isFalse);
      expect(controller.state.searching, isTrue);

      async.elapse(const Duration(seconds: 1));
      expect(controller.state.status, DlnaCastStatus.empty);
      expect(controller.state.searching, isFalse);
      expect(session.stopCalls, 1);
    });
  });

  test('failed discovery shows failed and a later attempt can recover', () async {
    final recovered = _FixtureSession();
    var starts = 0;
    final controller = DlnaCastController(
      _source,
      startDiscovery: () async {
        starts++;
        if (starts == 1) throw StateError('fixture discovery failure');
        return recovered;
      },
    );
    addTearDown(controller.close);
    await controller.startSearch();
    expect(controller.state.status, DlnaCastStatus.failed);

    await controller.startSearch();
    recovered.emit([_FixtureDevice(id: 'receiver-1', name: 'Living room')]);
    expect(starts, 2);
    expect(controller.state.status, DlnaCastStatus.ready);
    expect(controller.state.devices.map((device) => device.id), ['receiver-1']);
  });

  test('device snapshots replace missing receivers instead of retaining stale rows', () async {
    final session = _FixtureSession();
    final controller = DlnaCastController(_source, startDiscovery: () async => session);
    addTearDown(controller.close);
    await controller.startSearch();
    final first = _FixtureDevice(id: 'first', name: 'First receiver');
    final second = _FixtureDevice(id: 'second', name: 'Second receiver');

    session.emit([first, second, _FixtureDevice(id: '  ', name: 'No id')]);
    expect(controller.state.devices.map((device) => device.id), ['first', 'second']);
    session.emit([second]);
    expect(controller.state.devices.map((device) => device.id), ['second']);
  });

  test('refresh releases the prior search and ignores its later snapshots', () async {
    final first = _FixtureSession();
    final second = _FixtureSession();
    var starts = 0;
    final controller = DlnaCastController(_source, startDiscovery: () async => starts++ == 0 ? first : second);
    addTearDown(controller.close);
    await controller.startSearch();
    await controller.startSearch();
    await pumpEventQueue();
    expect(starts, 2);
    expect(first.stopCalls, 1);

    first.emit([_FixtureDevice(id: 'stale', name: 'Stale')]);
    second.emit([_FixtureDevice(id: 'current', name: 'Current')]);
    expect(controller.state.devices.map((device) => device.id), ['current']);
  });

  test('a search failing after receivers were found keeps them with an inline error', () async {
    final session = _FixtureSession();
    final controller = DlnaCastController(_source, startDiscovery: () async => session);
    addTearDown(controller.close);
    await controller.startSearch();
    session
      ..emit([_FixtureDevice(id: 'receiver', name: 'Receiver')])
      ..fail(StateError('socket closed'));
    await pumpEventQueue();
    expect(controller.state.status, DlnaCastStatus.ready);
    expect(controller.state.error, DlnaCastError.searchInterrupted);
    expect(controller.state.searching, isFalse);
  });

  test('cast requests are single-flight and await set-source before play', () async {
    final notices = <DlnaCastNotice>[];
    final session = _FixtureSession();
    final setGate = Completer<void>();
    final playGate = Completer<void>();
    final device = _FixtureDevice(id: 'receiver', name: 'Receiver', setGate: setGate, playGate: playGate);
    final controller = DlnaCastController(_source, startDiscovery: () async => session, onNotice: notices.add);
    addTearDown(controller.close);
    await controller.startSearch();
    session.emit([device]);

    final first = controller.castToDevice('receiver');
    final second = controller.castToDevice('receiver');
    expect(first, same(second));
    await pumpEventQueue();
    expect(device.events, ['set:$_source']);
    expect(controller.state.castingDeviceId, 'receiver');
    expect(controller.state.busy, isTrue);

    setGate.complete();
    await pumpEventQueue();
    expect(device.events, ['set:$_source', 'play']);
    expect(notices, isEmpty);

    playGate.complete();
    await first;
    expect(notices, [DlnaCastNotice.castStarted]);
    expect(controller.state.selectedDeviceId, 'receiver');
    expect(controller.state.castingDeviceId, isNull);
    expect(controller.state.busy, isFalse);
  });

  test('F.5a: the receiver shows "streamer - title" (the URL without either)', () async {
    expect(CastMedia.roomTitle(anchor: ' 主播 ', title: '标题 '), '主播 - 标题');
    expect(CastMedia.roomTitle(anchor: '', title: '标题'), '标题');
    expect(CastMedia.roomTitle(anchor: '主播', title: ' '), '主播');
    expect(CastMedia.roomTitle(anchor: '', title: ''), isEmpty);
    expect(didlLite(const CastMedia(url: _source, title: '主播 - 标题')), contains('<dc:title>主播 - 标题</dc:title>'));

    Future<List<String>> cast(_FixtureDevice device, {String title = ''}) async {
      final session = _FixtureSession();
      final controller = DlnaCastController(_source, title: title, startDiscovery: () async => session);
      addTearDown(controller.close);
      await controller.startSearch();
      session.emit([device]);
      await controller.castToDevice(device.id);
      return device.events;
    }

    // A renderer that takes metadata gets the title with the source.
    expect(await cast(_TitledDevice(), title: '主播 - 标题'), ['media:$_source|主播 - 标题', 'play']);
    // No title: the source alone, as before.
    expect(await cast(_TitledDevice()), ['set:$_source', 'play']);
    // A receiver without metadata support: the source alone.
    expect(
      await cast(
        _FixtureDevice(id: 'plain', name: 'Plain'),
        title: '主播 - 标题',
      ),
      ['set:$_source', 'play'],
    );
  });

  test('switching receivers waits for the previous pause and tolerates its failure', () async {
    final session = _FixtureSession();
    final first = _FixtureDevice(id: 'first', name: 'First');
    final second = _FixtureDevice(id: 'second', name: 'Second');
    final controller = DlnaCastController(_source, startDiscovery: () async => session);
    addTearDown(controller.close);
    await controller.startSearch();
    session.emit([first, second]);

    await controller.castToDevice('first');
    first.pauseError = StateError('fixture receiver left');
    await controller.castToDevice('second');

    expect(first.events, ['set:$_source', 'play', 'pause']);
    expect(second.events, ['set:$_source', 'play']);
    expect(controller.state.selectedDeviceId, 'second');
  });

  test('cast failure stays visible and permits an explicit retry', () async {
    final notices = <DlnaCastNotice>[];
    final session = _FixtureSession();
    final device = _FixtureDevice(id: 'receiver', name: 'Receiver')..setError = StateError('fixture set failure');
    final controller = DlnaCastController(_source, startDiscovery: () async => session, onNotice: notices.add);
    addTearDown(controller.close);
    await controller.startSearch();
    session.emit([device]);

    await controller.castToDevice('receiver');
    expect(controller.state.error, DlnaCastError.castFailed);
    expect(notices, [DlnaCastNotice.castFailed]);

    device.setError = null;
    await controller.castToDevice('receiver');
    expect(notices, [DlnaCastNotice.castFailed, DlnaCastNotice.castStarted]);
    expect(controller.state.error, isNull);
  });

  test('closing during discovery stops the late session without publishing it', () async {
    final gate = Completer<DlnaDiscoverySession>();
    final session = _FixtureSession();
    final controller = DlnaCastController(_source, startDiscovery: () => gate.future);
    final search = controller.startSearch();

    await controller.close();
    gate.complete(session);
    await search;
    expect(session.stopCalls, 1);
    expect(session.hasListener, isFalse);
  });

  test('closing after source assignment suppresses the late play command', () async {
    final session = _FixtureSession();
    final setGate = Completer<void>();
    final device = _FixtureDevice(id: 'receiver', name: 'Receiver', setGate: setGate);
    final controller = DlnaCastController(_source, startDiscovery: () async => session, onNotice: (_) {});
    await controller.startSearch();
    session.emit([device]);
    final cast = controller.castToDevice('receiver');
    await pumpEventQueue();

    await controller.close();
    setGate.complete();
    await cast;
    expect(device.events, ['set:$_source']);
    expect(session.stopCalls, 1);
  });

  test('changes deliver every new state and close with the controller', () async {
    final session = _FixtureSession();
    final controller = DlnaCastController(_source, startDiscovery: () async => session);
    final states = <DlnaCastStatus>[];
    final done = Completer<void>();
    controller.changes.listen((state) => states.add(state.status), onDone: done.complete);
    await controller.startSearch();
    session.emit([_FixtureDevice(id: 'receiver', name: 'Receiver')]);
    await controller.close();
    await done.future;
    expect(states, [DlnaCastStatus.searching, DlnaCastStatus.searching, DlnaCastStatus.ready]);
  });
}

class _FixtureSession implements DlnaDiscoverySession {
  final _controller = StreamController<List<DlnaCastDevice>>.broadcast(sync: true);
  int stopCalls = 0;

  @override
  Stream<List<DlnaCastDevice>> get devices => _controller.stream;

  bool get hasListener => _controller.hasListener;

  void emit(List<DlnaCastDevice> devices) => _controller.add(devices);

  void fail(Object error) => _controller.addError(error);

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

class _FixtureDevice implements DlnaCastDevice {
  new({required this.id, required this.name, this.setGate, this.playGate});

  @override
  final String id;
  @override
  final String name;
  @override
  String get address => 'http://192.168.1.2:49152';
  final Completer<void>? setGate;
  final Completer<void>? playGate;
  Error? setError;
  Error? pauseError;
  final events = <String>[];

  @override
  Future<void> pause() async {
    events.add('pause');
    final error = pauseError;
    if (error != null) throw error;
  }

  @override
  Future<void> setSource(String source) async {
    events.add('set:$source');
    final error = setError;
    if (error != null) throw error;
    await setGate?.future;
  }

  @override
  Future<void> play() async {
    events.add('play');
    await playGate?.future;
  }

  @override
  Future<void> stop() async => events.add('stop');

  @override
  Future<TransportInfo> transportInfo() async => const TransportInfo(state: TransportState.playing);
}

/// A receiver that also takes the metadata (`DlnaRenderer` does).
class _TitledDevice extends _FixtureDevice implements CastMediaTarget {
  new() : super(id: 'titled', name: 'Titled');

  @override
  Future<void> setMedia(CastMedia media) async => events.add('media:${media.url}|${media.title}');
}
