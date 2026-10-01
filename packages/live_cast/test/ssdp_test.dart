import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_cast/live_cast.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('M-SEARCH', () {
    test('3.x layout: HOST, ST, MX, MAN, CRLF lines and a blank line at the end', () {
      expect(
        ascii.decode(mSearchMessage(avTransportTarget)),
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'ST: urn:schemas-upnp-org:service:AVTransport:1\r\n'
        'MX: 3\r\n'
        'MAN: "ssdp:discover"\r\n'
        '\r\n',
      );
      expect(ascii.decode(mSearchMessage(mediaRendererTarget, mx: 30)), contains('MX: 5\r\n'));
    });

    test('3.x rounds: all three targets with MX 1 first, then ssdp:all every fifth round', () {
      expect(searchTargetsFor(0), [allTarget, mediaRendererTarget, avTransportTarget]);
      expect(searchMxFor(0), 1);
      expect(
        [for (var round = 1; round <= 6; round++) searchTargetsFor(round).single],
        [
          mediaRendererTarget,
          avTransportTarget,
          mediaRendererTarget,
          avTransportTarget,
          allTarget,
          mediaRendererTarget,
        ],
      );
      expect(searchMxFor(1), 3);
    });
  });

  group('messages', () {
    test('a Kodi (Platinum) answer', () {
      final message = SsdpMessage.parse(
        utf8.encode(
          ssdpAnswer(
            location: 'http://192.168.1.20:1733/',
            usn: 'uuid:0e3b1c9a-5b1f-4c6e-9a8e-3f2d1c0b9a87::urn:schemas-upnp-org:service:AVTransport:1',
            st: avTransportTarget,
          ),
        ),
      )!;
      expect(message.kind, SsdpKind.response);
      expect(message.location, Uri.parse('http://192.168.1.20:1733/'));
      expect(message.target, avTransportTarget);
      expect(message.deviceKey, 'uuid:0e3b1c9a-5b1f-4c6e-9a8e-3f2d1c0b9a87');
      expect(message.server, contains('Platinum'));
    });

    test('lower-case headers, LF line ends and an upper-case UUID', () {
      final message = SsdpMessage.parse(
        utf8.encode(
          'HTTP/1.1 200 OK\n'
          'location: http://192.168.31.120:49152/dlna/description.xml\n'
          'st: urn:schemas-upnp-org:device:MediaRenderer:1\n'
          'usn: uuid:F7CA5454-3F48-4390-8009-4C5EF27F0E07::urn:schemas-upnp-org:device:MediaRenderer:1\n'
          '\n',
        ),
      )!;
      expect(message.location!.path, '/dlna/description.xml');
      expect(message.deviceKey, 'uuid:f7ca5454-3f48-4390-8009-4c5ef27f0e07');
    });

    test('announcements: alive with LOCATION, byebye with USN only', () {
      final alive = SsdpMessage.parse(utf8.encode(ssdpNotify(usn: 'uuid:a::x', location: 'http://10.0.0.8/d.xml')))!;
      expect(alive.kind, SsdpKind.alive);
      expect(alive.target, mediaRendererTarget);
      final byebye = SsdpMessage.parse(utf8.encode(ssdpNotify(usn: 'uuid:a::x', nts: 'ssdp:byebye')))!;
      expect(byebye.kind, SsdpKind.byebye);
      expect(byebye.deviceKey, 'uuid:a');
    });

    test('an answer without USN is known by its location (3.x needed only LOCATION)', () {
      final message = SsdpMessage.parse(utf8.encode('HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.8/d.xml\r\n\r\n'))!;
      expect(message.deviceKey, 'location:http://10.0.0.8/d.xml');
    });

    test('ignores requests, errors and answers without an http(s) LOCATION', () {
      expect(SsdpMessage.parse(mSearchMessage(avTransportTarget)), isNull);
      expect(SsdpMessage.parse(utf8.encode('HTTP/1.1 404 Not Found\r\nLOCATION: http://a/\r\nUSN: u\r\n\r\n')), isNull);
      expect(SsdpMessage.parse(utf8.encode('HTTP/1.1 200 OK\r\nUSN: uuid:a\r\n\r\n')), isNull);
      expect(SsdpMessage.parse(utf8.encode('HTTP/1.1 200 OK\r\nLOCATION: file:///etc/x\r\nUSN: u\r\n\r\n')), isNull);
      expect(SsdpMessage.parse(utf8.encode(ssdpNotify(usn: 'uuid:a'))), isNull, reason: 'alive without LOCATION');
      expect(SsdpMessage.parse([0xff, 0xfe, 0x00]), isNull);
    });
  });

  test('an IoSsdpSocket reads unicast answers on its port and closes its stream', () async {
    final socket = await IoSsdpSocket.bind(InternetAddress.loopbackIPv4, label: 'lo 127.0.0.1');
    final sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(sender.close);
    final first = Completer<SsdpDatagram>();
    final closed = Completer<void>();
    final subscription = socket.datagrams.listen(first.complete, onDone: closed.complete);
    addTearDown(subscription.cancel);
    sender.send(utf8.encode('HTTP/1.1 200 OK\r\n\r\n'), InternetAddress.loopbackIPv4, socket.port);
    final datagram = await first.future.timeout(const Duration(seconds: 5));
    expect(utf8.decode(datagram.data), 'HTTP/1.1 200 OK\r\n\r\n');
    expect(datagram.port, sender.port);
    socket.close();
    expect(socket.send([1]), isFalse);
    await closed.future.timeout(const Duration(seconds: 5));
  });
}
