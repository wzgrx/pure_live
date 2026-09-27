import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:live_cast/live_cast.dart';
import 'package:test/test.dart';

import 'fakes.dart';

final Uri _kodiLocation = Uri.parse('http://192.168.1.20:1733/');
final Uri _xiaomiLocation = Uri.parse('http://192.168.31.120:49152/dlna/description.xml');
final Uri _serverLocation = Uri.parse('http://192.168.1.30:8200/rootDesc.xml');

const _kodiUuid = 'uuid:0e3b1c9a-5b1f-4c6e-9a8e-3f2d1c0b9a87';
const _xiaomiUuid = 'uuid:F7CA5454-3F48-4390-8009-4C5EF27F0E07';

String _kodiAnswer(String st) => ssdpAnswer(location: '$_kodiLocation', usn: '$_kodiUuid::$st', st: st);

/// A search under test: sockets, HTTP, and what the stream delivered.
final class _Run {
  new(this.sockets, this.http);

  final List<FakeSocket> sockets;
  final FakeHttp http;
  final List<CastDevice> devices = [];
  final List<Object> errors = [];
  bool done = false;
  late StreamSubscription<CastDevice> subscription;

  void start({Duration timeout = const Duration(seconds: 4), Future<List<SsdpSocket>> Function()? open}) {
    final discovery = CastDiscovery(http: http, openSockets: open ?? () async => sockets, timeout: timeout);
    subscription = discovery.search().listen(devices.add, onError: errors.add, onDone: () => done = true);
  }

  /// Cancels the search, as closing the sheet does.
  Future<void> cancel() => subscription.cancel();
}

_Run _run({List<FakeSocket>? sockets}) => _Run(
  sockets ?? [FakeSocket('wlan0 192.168.1.5')],
  FakeHttp({
    _kodiLocation: CastHttpResponse(200, sample('kodi.xml')),
    _xiaomiLocation: CastHttpResponse(200, sample('xiaomi_tv.xml')),
    _serverLocation: const CastHttpResponse(
      200,
      '<root><device><deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>'
      '<UDN>uuid:nas</UDN></device></root>',
    ),
  }),
);

void main() {
  test('sends both targets on every interface, and again after a second', () {
    fakeAsync((async) {
      final run = _run(sockets: [FakeSocket('wlan0 192.168.1.5'), FakeSocket('eth0 10.0.0.2')])..start();
      async.flushMicrotasks();
      for (final socket in run.sockets) {
        expect(socket.sent, hasLength(2));
        expect(socket.sent[0], contains('ST: urn:schemas-upnp-org:service:AVTransport:1\r\n'));
        expect(socket.sent[1], contains('ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'));
        expect(socket.sent[0], contains('MX: 2\r\n'));
      }
      async.elapse(const Duration(seconds: 1));
      for (final socket in run.sockets) {
        expect(socket.sent, hasLength(4));
      }
      async.elapse(const Duration(seconds: 3));
      expect(run.done, isTrue);
      expect(run.sockets.every((socket) => socket.closed), isTrue);
      expect(run.devices, isEmpty);
      expect(run.errors, isEmpty);
    });
  });

  test('emits renderers once, deduplicated by USN across targets and interfaces', () {
    fakeAsync((async) {
      final wifi = FakeSocket('wlan0 192.168.1.5');
      final wired = FakeSocket('eth0 10.0.0.2');
      final run = _run(sockets: [wifi, wired])..start();
      async.flushMicrotasks();
      wifi
        ..answer(_kodiAnswer(avTransportTarget))
        ..answer(_kodiAnswer(mediaRendererTarget));
      wired.answer(_kodiAnswer(avTransportTarget));
      wifi.answer(
        ssdpAnswer(
          location: '$_xiaomiLocation',
          usn: '$_xiaomiUuid::urn:schemas-upnp-org:device:MediaRenderer:1',
          st: mediaRendererTarget,
          eol: '\n',
        ),
        from: '192.168.31.120',
      );
      async.flushMicrotasks();
      expect(run.devices.map((device) => device.name), ['Kodi (LIBREELEC)', '客厅的小米电视']);
      expect(run.http.requests.map((request) => request.url), [_kodiLocation, _xiaomiLocation]);
      expect(run.http.requests.first.method, 'GET');
      expect(run.http.requests.first.timeout, const Duration(seconds: 3));
      async.elapse(const Duration(seconds: 4));
      expect(run.done, isTrue);
      expect(run.devices, hasLength(2));
    });
  });

  test('skips media servers, non-renderer targets and devices whose description fails', () {
    fakeAsync((async) {
      final run = _run()..start();
      async.flushMicrotasks();
      final socket = run.sockets.single
        ..answer(ssdpAnswer(location: '$_serverLocation', usn: 'uuid:nas::$avTransportTarget', st: avTransportTarget))
        ..answer(ssdpAnswer(location: '$_kodiLocation', usn: 'uuid:other', st: 'upnp:rootdevice'))
        ..answer(ssdpAnswer(location: 'http://192.168.1.99/gone.xml', usn: 'uuid:gone', st: avTransportTarget))
        ..answer('garbage');
      async.flushMicrotasks();
      expect(run.http.requests.map((request) => request.url.host), ['192.168.1.30', '192.168.1.99']);
      socket.answer(_kodiAnswer(avTransportTarget));
      async.flushMicrotasks();
      expect(run.devices.map((device) => device.id), [_kodiUuid]);
      expect(run.errors, isEmpty);
    });
  });

  test('a failed description is tried again on a later answer; a readable non-renderer is not', () {
    fakeAsync((async) {
      var kodiCalls = 0;
      final run = _run()..start();
      run.http.answers[_kodiLocation] = (_) =>
          ++kodiCalls == 1 ? const CastTimeoutFailure(Duration(seconds: 3)) : CastHttpResponse(200, sample('kodi.xml'));
      async.flushMicrotasks();
      final server = ssdpAnswer(
        location: '$_serverLocation',
        usn: 'uuid:nas::$avTransportTarget',
        st: avTransportTarget,
      );
      final socket = run.sockets.single
        ..answer(_kodiAnswer(avTransportTarget))
        ..answer(server);
      async.flushMicrotasks();
      expect(run.devices, isEmpty);
      socket
        ..answer(_kodiAnswer(mediaRendererTarget))
        ..answer(server);
      async.flushMicrotasks();
      expect(run.devices.map((device) => device.id), [_kodiUuid]);
      expect(kodiCalls, 2);
      expect(run.http.requests.where((request) => request.url == _serverLocation), hasLength(1));
    });
  });

  test('answers after the deadline are ignored; a description still loading finishes first', () {
    fakeAsync((async) {
      final run = _run()
        ..http.delay = const Duration(milliseconds: 500)
        ..start(timeout: const Duration(seconds: 2));
      async.elapse(const Duration(milliseconds: 1900));
      run.sockets.single.answer(_kodiAnswer(avTransportTarget));
      async.elapse(const Duration(milliseconds: 100));
      expect(run.done, isFalse, reason: 'the Kodi description is loading');
      expect(run.sockets.single.closed, isTrue, reason: 'no more answers are read');
      async.elapse(const Duration(milliseconds: 400));
      expect(run.devices.map((device) => device.name), ['Kodi (LIBREELEC)']);
      expect(run.done, isTrue);
    });
  });

  test('cancelling ends the search at once: sockets closed, late descriptions dropped', () {
    fakeAsync((async) {
      final run = _run()
        ..http.delay = const Duration(milliseconds: 300)
        ..start();
      async.flushMicrotasks();
      run.sockets.single.answer(_kodiAnswer(avTransportTarget));
      async.flushMicrotasks();
      unawaited(run.cancel());
      async.flushMicrotasks();
      expect(run.sockets.single.closed, isTrue);
      async.elapse(const Duration(seconds: 5));
      expect(run.devices, isEmpty);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('cancelling while the sockets open closes them when they arrive', () {
    fakeAsync((async) {
      final opening = Completer<List<SsdpSocket>>();
      final run = _run()..start(open: () => opening.future);
      unawaited(run.cancel());
      opening.complete(run.sockets);
      async.flushMicrotasks();
      expect(run.sockets.single.closed, isTrue);
      expect(run.sockets.single.sent, isEmpty);
    });
  });

  test('a timeout of 8 seconds asks for MX 4 and listens 8 seconds', () {
    fakeAsync((async) {
      final run = _run()..start(timeout: const Duration(seconds: 8));
      async.flushMicrotasks();
      expect(run.sockets.single.sent.first, contains('MX: 4\r\n'));
      async.elapse(const Duration(seconds: 7));
      expect(run.done, isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(run.done, isTrue);
    });
  });

  test('fails when no socket opens, there is no interface, or nothing can be sent', () {
    fakeAsync((async) {
      final refused = _run()..start(open: () async => throw const CastSearchFailure('no UDP socket'));
      final empty = _run()..start(open: () async => []);
      final unsent = _run(sockets: [FakeSocket('wlan0', sendWorks: false), FakeSocket('eth0', sendWorks: false)])
        ..start();
      final broken = _run()..start(open: () async => throw StateError('boom'));
      async.flushMicrotasks();
      for (final run in [refused, empty, unsent, broken]) {
        expect(run.errors.single, isA<CastSearchFailure>());
        expect(run.done, isTrue);
      }
      expect(unsent.sockets.every((socket) => socket.closed), isTrue);
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('one interface that cannot send does not fail the search', () {
    fakeAsync((async) {
      final run = _run(sockets: [FakeSocket('tun0', sendWorks: false), FakeSocket('wlan0')])..start();
      async.flushMicrotasks();
      run.sockets.last.answer(_kodiAnswer(avTransportTarget));
      async.elapse(const Duration(seconds: 4));
      expect(run.errors, isEmpty);
      expect(run.devices, hasLength(1));
      expect(run.done, isTrue);
    });
  });
}
