import 'package:live_cast/live_cast.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  group('vendor descriptions', () {
    test('Xiaomi TV: relative control URLs whose first segment has a colon', () {
      final location = Uri.parse('http://192.168.31.120:49152/dlna/description.xml');
      final device = parseDeviceDescription(sample('xiaomi_tv.xml'), location)!;
      expect(device.name, '客厅的小米电视');
      expect(device.id, 'uuid:f7ca5454-3f48-4390-8009-4c5ef27f0e07');
      expect(device.address, 'http://192.168.31.120:49152', reason: 'no URLBase: the origin, as 3.x showed');
      expect(device.avTransport.serviceType, 'urn:schemas-upnp-org:service:AVTransport:1');
      expect(
        device.avTransport.controlUrl.toString(),
        'http://192.168.31.120:49152/dlna/_urn:schemas-upnp-org:service:AVTransport_control',
      );
    });

    test('乐播: URLBase wins over LOCATION and is the address shown; a byte-order mark is fine', () {
      final location = Uri.parse('http://192.168.1.105:49153/upnp/desc/dmr.xml');
      final device = parseDeviceDescription('﻿${sample('lebo.xml')}', location)!;
      expect(device.name, '乐播投屏(卧室)');
      expect(device.address, 'http://192.168.1.105:49153');
      expect(device.avTransport.controlUrl.toString(), 'http://192.168.1.105:49153/dlna/Render/AVTransport_control');
    });

    test('Kodi: absolute paths against LOCATION; the AVTransport, not the first service', () {
      final location = Uri.parse('http://192.168.1.20:1733/');
      final device = parseDeviceDescription(sample('kodi.xml'), location)!;
      expect(device.name, 'Kodi (LIBREELEC)');
      expect(
        device.avTransport.controlUrl.toString(),
        'http://192.168.1.20:1733/AVTransport/0e3b1c9a-5b1f-4c6e-9a8e-3f2d1c0b9a87/control.xml',
      );
    });
  });

  group('3.x problems', () {
    final location = Uri.parse('http://10.0.0.9:8200/rootDesc.xml');

    String description(String devices, {String urlBase = ''}) =>
        '<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0">$urlBase$devices</root>';

    String service(String type, String control) =>
        '<service><serviceType>$type</serviceType><controlURL>$control</controlURL></service>';

    test('an embedded renderer under a root device is found (3.x read only the first serviceList)', () {
      final text = description(
        [
          '<device><deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>',
          '<friendlyName>Living room box</friendlyName><UDN>uuid:root</UDN>',
          '<serviceList>${service('urn:schemas-upnp-org:service:Layer3Forwarding:1', '/l3f')}</serviceList>',
          '<deviceList><device><deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>',
          '<friendlyName> </friendlyName><UDN>uuid:Renderer</UDN>',
          '<serviceList>${service('urn:schemas-upnp-org:service:AVTransport:2', '/avt')}</serviceList>',
          '</device></deviceList></device>',
        ].join(),
      );
      final device = parseDeviceDescription(text, location)!;
      expect(device.id, 'uuid:renderer');
      expect(device.name, 'Living room box', reason: 'a blank embedded name falls back to the root name');
      expect(device.avTransport.serviceType, 'urn:schemas-upnp-org:service:AVTransport:2');
      expect(device.avTransport.controlUrl.toString(), 'http://10.0.0.9:8200/avt');
    });

    test('a media server or router is not listed (3.x listed it and the cast failed)', () {
      final text = description(
        '<device><deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>'
        '<friendlyName>NAS</friendlyName><UDN>uuid:nas</UDN><serviceList>'
        '${service('urn:schemas-upnp-org:service:ContentDirectory:1', '/ctl/ContentDir')}'
        '</serviceList></device>',
      );
      expect(parseDeviceDescription(text, location), isNull);
    });

    test('a renderer without friendlyName is kept with an empty name (3.x dropped it)', () {
      final device = parseDeviceDescription(
        description(
          '<device><UDN>uuid:x</UDN><serviceList>'
          '${service('urn:schemas-upnp-org:service:AVTransport:1', 'avt')}</serviceList></device>',
        ),
        location,
      )!;
      expect(device.name, isEmpty);
      expect(device.id, 'uuid:x');
    });

    test('an absolute control URL is used as given (3.x appended it to the base)', () {
      final device = parseDeviceDescription(
        description(
          '<device><UDN>uuid:x</UDN><serviceList>'
          '${service('urn:schemas-upnp-org:service:AVTransport:1', 'http://10.0.0.9:9000/AVTransport/ctl')}'
          '</serviceList></device>',
        ),
        location,
      )!;
      expect(device.avTransport.controlUrl.toString(), 'http://10.0.0.9:9000/AVTransport/ctl');
    });

    test('not XML, not a root, no device: protocol failures', () {
      expect(() => parseDeviceDescription('<html><body>404</body>', location), throwsA(isA<CastProtocolFailure>()));
      expect(() => parseDeviceDescription(description(''), location), throwsA(isA<CastProtocolFailure>()));
    });
  });

  group('URL resolution', () {
    final base = Uri.parse('http://192.168.1.5:49152/dev/desc.xml');

    test('absolute, absolute-path and relative references', () {
      expect(resolveDescriptionUrl(base, 'http://192.168.1.5:1234/x').toString(), 'http://192.168.1.5:1234/x');
      expect(resolveDescriptionUrl(base, '/upnp/control').toString(), 'http://192.168.1.5:49152/upnp/control');
      expect(resolveDescriptionUrl(base, 'control').toString(), 'http://192.168.1.5:49152/dev/control');
    });

    test('empty or non-http references are rejected', () {
      expect(resolveDescriptionUrl(base, ''), isNull);
      expect(resolveDescriptionUrl(base, 'ftp://192.168.1.5/x'), isNull);
    });
  });
}
