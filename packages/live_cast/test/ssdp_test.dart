import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_cast/live_cast.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('M-SEARCH', () {
    test('is the UDA request for the target, CRLF lines and a blank line at the end', () {
      expect(
        ascii.decode(mSearchMessage(avTransportTarget)),
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 2\r\n'
        'ST: urn:schemas-upnp-org:service:AVTransport:1\r\n'
        '\r\n',
      );
    });

    test('clamps MX to 1-5 seconds', () {
      expect(ascii.decode(mSearchMessage(mediaRendererTarget, mx: 0)), contains('MX: 1\r\n'));
      expect(ascii.decode(mSearchMessage(mediaRendererTarget, mx: 30)), contains('MX: 5\r\n'));
    });

    test('goes to the SSDP group', () {
      expect(ssdpGroup.address, '239.255.255.250');
      expect(ssdpPort, 1900);
    });
  });

  group('answers', () {
    test('a Kodi (Platinum) answer', () {
      final response = SsdpResponse.parse(
        utf8.encode(
          ssdpAnswer(
            location: 'http://192.168.1.20:1733/',
            usn: 'uuid:0e3b1c9a-5b1f-4c6e-9a8e-3f2d1c0b9a87::urn:schemas-upnp-org:service:AVTransport:1',
            st: avTransportTarget,
          ),
        ),
      )!;
      expect(response.location, Uri.parse('http://192.168.1.20:1733/'));
      expect(response.searchTarget, avTransportTarget);
      expect(response.deviceId, 'uuid:0e3b1c9a-5b1f-4c6e-9a8e-3f2d1c0b9a87');
      expect(response.server, contains('Platinum'));
    });

    test('lower-case headers, LF line ends and an upper-case UUID', () {
      final response = SsdpResponse.parse(
        utf8.encode(
          'HTTP/1.1 200 OK\n'
          'location: http://192.168.31.120:49152/dlna/description.xml\n'
          'st: urn:schemas-upnp-org:device:MediaRenderer:1\n'
          'usn: uuid:F7CA5454-3F48-4390-8009-4C5EF27F0E07::urn:schemas-upnp-org:device:MediaRenderer:1\n'
          '\n',
        ),
      )!;
      expect(response.location.path, '/dlna/description.xml');
      expect(response.deviceId, 'uuid:f7ca5454-3f48-4390-8009-4c5ef27f0e07');
      expect(isRendererTarget(response.searchTarget), isTrue);
    });

    test('a USN without a service part is the device id itself', () {
      final response = SsdpResponse.parse(
        utf8.encode(ssdpAnswer(location: 'http://10.0.0.8/d.xml', usn: 'uuid:abc', st: 'upnp:rootdevice')),
      )!;
      expect(response.deviceId, 'uuid:abc');
      expect(isRendererTarget(response.searchTarget), isFalse);
    });

    test('ignores requests, errors and answers without LOCATION or USN', () {
      expect(SsdpResponse.parse(mSearchMessage(avTransportTarget)), isNull);
      expect(
        SsdpResponse.parse(
          utf8.encode(
            'NOTIFY * HTTP/1.1\r\nLOCATION: http://10.0.0.8/d.xml\r\nNT: $avTransportTarget\r\nUSN: uuid:a\r\n\r\n',
          ),
        ),
        isNull,
      );
      expect(
        SsdpResponse.parse(utf8.encode('HTTP/1.1 404 Not Found\r\nLOCATION: http://a/\r\nUSN: u\r\n\r\n')),
        isNull,
      );
      expect(SsdpResponse.parse(utf8.encode('HTTP/1.1 200 OK\r\nUSN: uuid:a\r\n\r\n')), isNull);
      expect(SsdpResponse.parse(utf8.encode('HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.8/\r\n\r\n')), isNull);
      expect(SsdpResponse.parse(utf8.encode('HTTP/1.1 200 OK\r\nLOCATION: file:///etc/x\r\nUSN: u\r\n\r\n')), isNull);
      expect(SsdpResponse.parse([0xff, 0xfe, 0x00]), isNull);
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
      expect(socket.label, 'lo 127.0.0.1');
      socket.close();
      expect(socket.send([1]), isFalse);
      await closed.future.timeout(const Duration(seconds: 5));
    });

    test('renderer targets: AVTransport and MediaRenderer of any version', () {
      expect(isRendererTarget(avTransportTarget), isTrue);
      expect(isRendererTarget('urn:schemas-upnp-org:service:AVTransport:2'), isTrue);
      expect(isRendererTarget(' URN:SCHEMAS-UPNP-ORG:DEVICE:MEDIARENDERER:1 '), isTrue);
      expect(isRendererTarget('urn:schemas-upnp-org:device:MediaServer:1'), isFalse);
      expect(isRendererTarget('urn:schemas-upnp-org:service:RenderingControl:1'), isFalse);
      expect(isRendererTarget('ssdp:all'), isFalse);
    });
  });
}
