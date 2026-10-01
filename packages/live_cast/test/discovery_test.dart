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

String _xiaomiAnswer() => ssdpAnswer(
  location: '$_xiaomiLocation',
  usn: '$_xiaomiUuid::$mediaRendererTarget',
  st: mediaRendererTarget,
  eol: '\n',
);

/// A search under test: sockets, HTTP, and the snapshots it delivered.
final class _Run {
  new(this.sockets, this.http);

  final List<FakeSocket> sockets;
  final FakeHttp http;
  final List<List<String>> snapshots = [];
  bool done = false;
  late SsdpDiscovery discovery;

  List<String> get names => snapshots.isEmpty ? const [] : snapshots.last;

  void start() {
    discovery = SsdpDiscovery(sockets, http: http);
    discovery.devices.listen(
      (devices) => snapshots.add([for (final device in devices) device.name]),
      onDone: () => done = true,
    );
    expect(discovery.start(), isTrue);
  }
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
  test('3.x search pattern: three targets with MX 1 at once, then one target every 2 seconds on every interface', () {
    fakeAsync((async) {
      final run = _run(sockets: [FakeSocket('wlan0 192.168.1.5'), FakeSocket('eth0 10.0.0.2')])..start();
      async.elapse(const Duration(milliseconds: 100));
      for (final socket in run.sockets) {
        expect(socket.sent, hasLength(3));
        expect(socket.sent[0], allOf(contains('ST: ssdp:all\r\n'), contains('MX: 1\r\n')));
        expect(socket.sent[1], contains('ST: $mediaRendererTarget\r\n'));
        expect(socket.sent[2], contains('ST: $avTransportTarget\r\n'));
      }
      async.elapse(const Duration(seconds: 2));
      for (final socket in run.sockets) {
        expect(socket.sent, hasLength(4));
        expect(socket.sent[3], allOf(contains('ST: $mediaRendererTarget\r\n'), contains('MX: 3\r\n')));
      }
      unawaited(run.discovery.stop());
      async.flushMicrotasks();
      expect(run.done, isTrue);
      expect(run.sockets.every((socket) => socket.closed), isTrue);
    });
  });

  test('each device is described once, however often it answers (3.x fetched it for every datagram)', () {
    fakeAsync((async) {
      final wifi = FakeSocket('wlan0 192.168.1.5');
      final wired = FakeSocket('eth0 10.0.0.2');
      final run = _run(sockets: [wifi, wired])..start();
      for (var round = 0; round < 5; round++) {
        wifi
          ..answer(_kodiAnswer(avTransportTarget))
          ..answer(_kodiAnswer(mediaRendererTarget))
          ..answer(_kodiAnswer('upnp:rootdevice'));
        wired.answer(_kodiAnswer(avTransportTarget));
        async.elapse(const Duration(seconds: 2));
      }
      wifi.answer(_xiaomiAnswer(), from: '192.168.31.120');
      async.flushMicrotasks();
      expect(run.http.requests.map((request) => request.url), [_kodiLocation, _xiaomiLocation]);
      expect(run.http.requests.first.timeout, const Duration(seconds: 10));
      expect(run.snapshots, [
        ['Kodi (LIBREELEC)'],
        ['Kodi (LIBREELEC)', '客厅的小米电视'],
      ]);
      unawaited(run.discovery.stop());
    });
  });

  test('a media server is not listed nor described again; a failed description is retried next round', () {
    fakeAsync((async) {
      final run = _run()..start();
      final socket = run.sockets.single;
      run.http.answers[_kodiLocation] = const CastNetworkFailure('reset');
      socket
        ..answer(ssdpAnswer(location: '$_serverLocation', usn: 'uuid:nas::upnp:rootdevice', st: allTarget))
        ..answer(_kodiAnswer(avTransportTarget));
      async.flushMicrotasks();
      socket
        ..answer(ssdpAnswer(location: '$_serverLocation', usn: 'uuid:nas', st: allTarget))
        ..answer(_kodiAnswer(mediaRendererTarget));
      async.flushMicrotasks();
      expect(run.http.requests, hasLength(2), reason: 'no retry within the same round');
      expect(run.names, isEmpty);

      run.http.answers[_kodiLocation] = CastHttpResponse(200, sample('kodi.xml'));
      async.elapse(const Duration(seconds: 2));
      socket
        ..answer(ssdpAnswer(location: '$_serverLocation', usn: 'uuid:nas', st: allTarget))
        ..answer(_kodiAnswer(avTransportTarget));
      async.flushMicrotasks();
      expect(run.http.requests.map((request) => request.url), [_serverLocation, _kodiLocation, _kodiLocation]);
      expect(run.names, ['Kodi (LIBREELEC)']);
      unawaited(run.discovery.stop());
    });
  });

  test('announcements list a device; byebye and 120 seconds of silence drop it', () {
    fakeAsync((async) {
      final run = _run()..start();
      final socket = run.sockets.single
        ..answer(ssdpNotify(usn: '$_kodiUuid::$mediaRendererTarget', location: '$_kodiLocation'))
        ..answer(_xiaomiAnswer(), from: '192.168.31.120');
      async.flushMicrotasks();
      expect(run.names, ['Kodi (LIBREELEC)', '客厅的小米电视']);

      socket.answer(ssdpNotify(usn: '$_kodiUuid::$mediaRendererTarget', nts: 'ssdp:byebye'));
      async.flushMicrotasks();
      expect(run.names, ['客厅的小米电视']);

      async.elapse(const Duration(seconds: 118));
      expect(run.names, ['客厅的小米电视']);
      async.elapse(const Duration(seconds: 6));
      expect(run.names, isEmpty);
      unawaited(run.discovery.stop());
    });
  });

  test('stop closes the sockets and the stream; late descriptions are dropped', () {
    fakeAsync((async) {
      final run = _run()..start();
      run.http.delay = const Duration(seconds: 1);
      run.sockets.single.answer(_kodiAnswer(avTransportTarget));
      async.flushMicrotasks();
      unawaited(run.discovery.stop());
      async.elapse(const Duration(seconds: 2));
      expect(run.done, isTrue);
      expect(run.snapshots, isEmpty);
      expect(run.sockets.single.closed, isTrue);
    });
  });

  group('startDlnaDiscovery', () {
    test('fails when no socket opens or nothing can be sent, and closes the sockets', () async {
      await expectLater(
        startDlnaDiscovery(http: FakeHttp(), openSockets: () async => throw const CastSearchFailure('no UDP socket')),
        throwsA(isA<CastSearchFailure>()),
      );
      final mute = FakeSocket('wlan0 192.168.1.5', sendWorks: false);
      await expectLater(
        startDlnaDiscovery(http: FakeHttp(), openSockets: () async => [mute]),
        throwsA(isA<CastSearchFailure>()),
      );
      expect(mute.closed, isTrue);
    });

    test('a listed receiver is a DlnaRenderer that stays usable after the search stops', () async {
      final socket = FakeSocket('wlan0 192.168.1.5');
      final http = FakeHttp({_kodiLocation: CastHttpResponse(200, sample('kodi.xml'))});
      final session = await startDlnaDiscovery(http: http, openSockets: () async => [socket]);
      final first = session.devices.first;
      socket.answer(_kodiAnswer(avTransportTarget));
      final device = (await first).single as DlnaRenderer;
      await session.stop();
      expect(device.id, _kodiUuid);
      expect(device.address, 'http://192.168.1.20:1733');
      http.answers[device.device.avTransport.controlUrl] = const CastHttpResponse(200, '');
      await device.stop();
      expect(http.requests.last.headers['SOAPAction'], '"$avTransportTarget#Stop"');
    });
  });
}
