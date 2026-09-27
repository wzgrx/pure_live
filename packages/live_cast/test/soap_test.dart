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

    test('SetAVTransportURI: the URL and the DIDL-Lite metadata survive two levels of escaping', () {
      final url = Uri.parse('https://cdn.example.com/live/abc.flv?sign=a&t=1&x="y"');
      const title = '主播 <小明> & "朋友"';
      final media = CastMedia(url: url, title: title);
      final body = soapEnvelope(_avt, 'SetAVTransportURI', {
        'InstanceID': '0',
        'CurrentURI': url.toString(),
        'CurrentURIMetaData': didlLite(media),
      });
      // What the renderer's XML parser sees.
      final action = _find(XmlDocument.parse(body), 'SetAVTransportURI');
      expect(_find(action, 'CurrentURI').innerText, url.toString());
      final metadata = XmlDocument.parse(_find(action, 'CurrentURIMetaData').innerText);
      final item = metadata.rootElement.childElements.single;
      expect(item.getAttribute('restricted'), '1');
      expect(_find(item, 'title').innerText, title);
      expect(_find(item, 'class').innerText, 'object.item.videoItem');
      final res = _find(item, 'res');
      expect(res.getAttribute('protocolInfo'), 'http-get:*:video/x-flv:*');
      expect(res.innerText, url.toString());
    });

    test('protocol info follows the MIME type; long titles are cut; control characters dropped', () {
      final url = Uri.parse('http://cdn.example.com/a.m3u8');
      final hls = didlLite(CastMedia(url: url, title: 'x', mimeType: CastMime.hls));
      expect(hls, contains('protocolInfo="http-get:*:application/vnd.apple.mpegurl:*"'));
      final ts = didlLite(CastMedia(url: url, title: 'x', mimeType: CastMime.mpegTs));
      expect(ts, contains('http-get:*:video/mp2t:*'));
      final long = didlLite(CastMedia(url: url, title: '长' * 200));
      final title = _find(XmlDocument.parse(long), 'title').innerText;
      expect(title.runes.length, maxCastTitleLength);
      expect(title, endsWith('…'));
      expect(escapeXml('a\u0000b\u0007c\td\n'), 'abc\td\n');
    });

    test('MIME types guessed from the path', () {
      expect(CastMime.guess(Uri.parse('http://a/live/x.m3u8?token=1')), CastMime.hls);
      expect(CastMime.guess(Uri.parse('http://a/live/x.FLV')), CastMime.flv);
      expect(CastMime.guess(Uri.parse('http://a/iptv/cctv1.ts')), CastMime.mpegTs);
      expect(CastMime.guess(Uri.parse('http://a/v.mp4')), CastMime.mp4);
      expect(CastMime.guess(Uri.parse('http://a/stream')), CastMime.flv);
      expect(CastMime.guess(Uri.parse('http://a/stream'), fallback: CastMime.hls), CastMime.hls);
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
      expect(() => parseSoapResponse('Play', 404, '<html>Not Found</html>'), throwsA(isA<CastHttpFailure>()));
    });

    test('error codes', () {
      expect(UpnpError.of(714), UpnpError.illegalMimeType);
      expect(UpnpError.of(714).unplayable, isTrue);
      expect(UpnpError.of(705).busy, isTrue);
      expect(UpnpError.of(402).busy, isFalse);
      expect(UpnpError.of(801), UpnpError.unknown);
      expect(UpnpError.of(0), UpnpError.unknown);
    });
  });
}
