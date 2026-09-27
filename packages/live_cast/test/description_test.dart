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
      expect(device.manufacturer, 'Xiaomi');
      expect(device.modelName, 'Xiaomi MediaRenderer');
      expect(device.host, '192.168.31.120');
      expect(device.avTransport.serviceType, 'urn:schemas-upnp-org:service:AVTransport:1');
      expect(
        device.avTransport.controlUrl.toString(),
        'http://192.168.31.120:49152/dlna/_urn:schemas-upnp-org:service:AVTransport_control',
      );
      expect(
        device.renderingControl!.controlUrl.toString(),
        'http://192.168.31.120:49152/dlna/_urn:schemas-upnp-org:service:RenderingControl_control',
      );
    });

    test('乐播: URLBase wins over LOCATION; a byte-order mark is fine', () {
      final location = Uri.parse('http://192.168.1.105:49153/upnp/desc/dmr.xml');
      final device = parseDeviceDescription('\uFEFF${sample('lebo.xml')}', location)!;
      expect(device.name, '乐播投屏(卧室)');
      expect(device.manufacturer, 'Lebo');
      expect(device.avTransport.controlUrl.toString(), 'http://192.168.1.105:49153/dlna/Render/AVTransport_control');
      expect(
        device.renderingControl!.controlUrl.toString(),
        'http://192.168.1.105:49153/dlna/Render/RenderingControl_control',
      );
      expect(device.location, location);
    });

    test('Kodi: absolute paths against LOCATION; the AVTransport, not the first service', () {
      final location = Uri.parse('http://192.168.1.20:1733/');
      final device = parseDeviceDescription(sample('kodi.xml'), location)!;
      expect(device.name, 'Kodi (LIBREELEC)');
      expect(device.id, 'uuid:0e3b1c9a-5b1f-4c6e-9a8e-3f2d1c0b9a87');
      expect(
        device.avTransport.controlUrl.toString(),
        'http://192.168.1.20:1733/AVTransport/0e3b1c9a-5b1f-4c6e-9a8e-3f2d1c0b9a87/control.xml',
      );
      expect(device.renderingControl!.serviceType, 'urn:schemas-upnp-org:service:RenderingControl:1');
    });
  });

  group('structure', () {
    final location = Uri.parse('http://10.0.0.9:8200/rootDesc.xml');

    String description(String devices, {String urlBase = ''}) =>
        '<?xml version="1.0"?><root xmlns="urn:schemas-upnp-org:device-1-0">$urlBase$devices</root>';

    String service(String type, String control) =>
        '<service><serviceType>$type</serviceType><controlURL>$control</controlURL></service>';

    test('an embedded renderer under a root device', () {
      final text = description(
        [
          '<device><deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>',
          '<friendlyName>Living room box</friendlyName><UDN>uuid:root</UDN>',
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
      expect(device.renderingControl, isNull);
    });

    test('a media server is not a renderer', () {
      final text = description(
        '<device><deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>'
        '<friendlyName>NAS</friendlyName><UDN>uuid:nas</UDN><serviceList>'
        '${service('urn:schemas-upnp-org:service:ContentDirectory:1', '/ctl/ContentDir')}'
        '</serviceList></device>',
      );
      expect(parseDeviceDescription(text, location), isNull);
    });

    test('an AVTransport without a usable control URL is skipped', () {
      final text = description(
        '<device><friendlyName>Broken</friendlyName><UDN>uuid:b</UDN><serviceList>'
        '${service('urn:schemas-upnp-org:service:AVTransport:1', '  ')}'
        '${service('urn:schemas-upnp-org:service:AVTransport:1', 'ftp://10.0.0.9/avt')}'
        '</serviceList></device>',
      );
      expect(parseDeviceDescription(text, location), isNull);
    });

    test('names fall back to the model, then the host; no UDN falls back to the location', () {
      final avt = service('urn:schemas-upnp-org:service:AVTransport:1', 'avt');
      final modelOnly = parseDeviceDescription(
        description('<device><modelName>DMR-100</modelName><serviceList>$avt</serviceList></device>'),
        location,
      )!;
      expect(modelOnly.name, 'DMR-100');
      expect(modelOnly.id, 'location:http://10.0.0.9:8200/rootdesc.xml');
      final bare = parseDeviceDescription(description('<device><serviceList>$avt</serviceList></device>'), location)!;
      expect(bare.name, '10.0.0.9');
    });

    test('an invalid URLBase falls back to LOCATION', () {
      final text = description(
        '<device><UDN>uuid:x</UDN><serviceList>'
        '${service('urn:schemas-upnp-org:service:AVTransport:1', 'avt/control')}'
        '</serviceList></device>',
        urlBase: '<URLBase>not a url</URLBase>',
      );
      expect(
        parseDeviceDescription(text, location)!.avTransport.controlUrl.toString(),
        'http://10.0.0.9:8200/avt/control',
      );
    });

    test('not XML, not a root, no device: protocol failures', () {
      expect(() => parseDeviceDescription('<html><body>404</body>', location), throwsA(isA<CastProtocolFailure>()));
      expect(() => parseDeviceDescription('<html></html>', location), throwsA(isA<CastProtocolFailure>()));
      expect(() => parseDeviceDescription(description(''), location), throwsA(isA<CastProtocolFailure>()));
    });
  });

  group('URL resolution', () {
    final base = Uri.parse('http://192.168.1.5:49152/dev/desc.xml');

    test('absolute, absolute-path and relative references', () {
      expect(resolveDescriptionUrl(base, 'http://192.168.1.5:1234/x').toString(), 'http://192.168.1.5:1234/x');
      expect(resolveDescriptionUrl(base, '/upnp/control').toString(), 'http://192.168.1.5:49152/upnp/control');
      expect(resolveDescriptionUrl(base, 'control').toString(), 'http://192.168.1.5:49152/dev/control');
      expect(resolveDescriptionUrl(base, ' AVT/ctl ').toString(), 'http://192.168.1.5:49152/dev/AVT/ctl');
    });

    test('a colon in the first segment is a path, not a scheme', () {
      expect(
        resolveDescriptionUrl(base, 'urn:schemas-upnp-org:service:AVTransport').toString(),
        'http://192.168.1.5:49152/dev/urn:schemas-upnp-org:service:AVTransport',
      );
    });

    test('empty or non-http references are rejected', () {
      expect(resolveDescriptionUrl(base, ''), isNull);
      expect(resolveDescriptionUrl(base, 'ftp://192.168.1.5/x'), isNull);
    });
  });
}
