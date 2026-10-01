import 'package:live_cast/live_cast.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

const _avt = 'urn:schemas-upnp-org:service:AVTransport:1';

/// The first element under [parent] with [localName], at any depth.
XmlElement _find(XmlNode parent, String localName) =>
    parent.descendantElements.firstWhere((element) => element.localName == localName);

String _fault(int code, String description) => [
  '<?xml version="1.0"?>',
  '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"',
  ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><s:Fault>',
  '<faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>',
  '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>$code</errorCode>',
  '<errorDescription>$description</errorDescription></UPnPError>',
  '</detail></s:Fault></s:Body></s:Envelope>',
].join();

void main() {
  group('requests', () {
    test('an envelope with the action in the service namespace and arguments in order', () {
      expect(
        soapEnvelope(_avt, 'Play', {'InstanceID': '0', 'Speed': '1'}),
        [
          '<?xml version="1.0" encoding="utf-8"?>',
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"',
          ' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">',
          '<s:Body><u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">',
          '<InstanceID>0</InstanceID><Speed>1</Speed></u:Play></s:Body></s:Envelope>',
        ].join(),
      );
    });

    test('headers: quoted SOAPAction of the service type, XML content type', () {
      expect(soapHeaders(_avt, 'SetAVTransportURI'), {
        'Content-Type': 'text/xml; charset="utf-8"',
        'SOAPAction': '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
      });
    });

    test('SetAVTransportURI: the metadata is an escaped string, not child elements (3.x)', () {
      const url = 'https://cdn.example.com/live/abc.flv?sign=a&t=1&x="y"';
      final body = soapEnvelope(_avt, 'SetAVTransportURI', {
        'InstanceID': '0',
        'CurrentURI': url,
        'CurrentURIMetaData': didlLite(const CastMedia(url: url, title: '主播 <小明> & "朋友"')),
      });
      // What the renderer's XML parser sees.
      final action = _find(XmlDocument.parse(body), 'SetAVTransportURI');
      expect(_find(action, 'CurrentURI').innerText, url);
      final metadataElement = _find(action, 'CurrentURIMetaData');
      expect(metadataElement.childElements, isEmpty);
      final metadata = XmlDocument.parse(metadataElement.innerText);
      final item = metadata.rootElement.childElements.single;
      expect(item.getAttribute('id'), 'id');
      expect(item.getAttribute('parentID'), '0');
      expect(item.getAttribute('restricted'), '0');
      expect(_find(item, 'title').innerText, '主播 <小明> & "朋友"');
      expect(_find(item, 'class').innerText, 'object.item.videoItem');
      final res = _find(item, 'res');
      expect(res.getAttribute('protocolInfo'), 'http-get:*:*:*');
      expect(res.innerText, url);
      expect(item.descendantElements.map((element) => element.localName), isNot(contains('artist')));
      expect(item.descendantElements.map((element) => element.localName), isNot(contains('date')));
    });

    test('an empty title shows the URL, as 3.x did; a MIME type narrows the protocol info', () {
      final metadata = XmlDocument.parse(didlLite(const CastMedia(url: 'http://h/live.m3u8')));
      expect(_find(metadata, 'title').innerText, 'http://h/live.m3u8');
      expect(
        const CastMedia(url: 'http://h/live.flv', mimeType: 'video/x-flv').protocolInfo,
        'http-get:*:video/x-flv:*',
      );
    });

    test('control characters XML does not allow are dropped', () {
      expect(escapeXml('a\u0001b\tc<'), 'ab\tc&lt;');
    });
  });

  group('responses', () {
    test('output arguments by name', () {
      final body = [
        '<?xml version="1.0"?>',
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>',
        '<u:GetTransportInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">',
        '<CurrentTransportState>PLAYING</CurrentTransportState>',
        '<CurrentTransportStatus>OK</CurrentTransportStatus>',
        '<CurrentSpeed>1</CurrentSpeed>',
        '</u:GetTransportInfoResponse></s:Body></s:Envelope>',
      ].join();
      expect(parseSoapResponse('GetTransportInfo', 200, body), {
        'CurrentTransportState': 'PLAYING',
        'CurrentTransportStatus': 'OK',
        'CurrentSpeed': '1',
      });
    });

    test('an empty or odd 200 answer is success with no arguments', () {
      expect(parseSoapResponse('Play', 200, ''), isEmpty);
      expect(parseSoapResponse('Play', 200, 'OK'), isEmpty);
      expect(parseSoapResponse('Play', 204, '<x/>'), isEmpty);
    });

    test('a UPnP error becomes a typed failure', () {
      expect(
        () => parseSoapResponse('SetAVTransportURI', 500, _fault(716, 'Resource not found')),
        throwsA(
          isA<UpnpActionFailure>()
              .having((failure) => failure.action, 'action', 'SetAVTransportURI')
              .having((failure) => failure.code, 'code', 716)
              .having((failure) => failure.error, 'error', UpnpError.resourceNotFound)
              .having((failure) => failure.detail, 'detail', 'Resource not found'),
        ),
      );
      // Some renderers send the fault with status 200.
      expect(
        () => parseSoapResponse('Play', 200, _fault(701, 'Transition not available')),
        throwsA(isA<UpnpActionFailure>().having((failure) => failure.error.busy, 'busy', isTrue)),
      );
    });

    test('a fault without a UPnP error is a protocol failure; a bare error status an HTTP failure', () {
      final fault = [
        '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault>',
        '<faultcode>s:Server</faultcode><faultstring>Internal Error</faultstring>',
        '</s:Fault></s:Body></s:Envelope>',
      ].join();
      expect(() => parseSoapResponse('Play', 500, fault), throwsA(isA<CastProtocolFailure>()));
      expect(
        () => parseSoapResponse('Play', 500, ''),
        throwsA(isA<CastHttpFailure>().having((failure) => failure.statusCode, 'status', 500)),
      );
    });
  });
}
