import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:live_cast/live_cast.dart';
import 'package:test/test.dart';
import 'package:xml/xml.dart';

import 'fakes.dart';

final Uri _control = Uri.parse('http://192.168.1.20:1733/AVTransport/x/control.xml');

final CastDevice _device = CastDevice(
  id: 'uuid:x',
  name: 'Kodi',
  location: Uri.parse('http://192.168.1.20:1733/'),
  address: 'http://192.168.1.20:1733',
  avTransport: CastService(serviceType: 'urn:schemas-upnp-org:service:AVTransport:2', controlUrl: _control),
);

const _source = 'http://cdn.example.com/live/1.flv?a=1&b=2';

String _ok(String action, [String arguments = '']) => [
  '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>',
  '<u:${action}Response xmlns:u="urn:schemas-upnp-org:service:AVTransport:2">$arguments</u:${action}Response>',
  '</s:Body></s:Envelope>',
].join();

String _fault(int code) => [
  '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><detail>',
  '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>$code</errorCode></UPnPError>',
  '</detail></s:Fault></s:Body></s:Envelope>',
].join();

/// The SOAP action of a request, from its header.
String _action(SentRequest request) => request.headers['SOAPAction']!.split('#').last.replaceAll('"', '');

/// Answers every action from [script] (action → queue of answers), else OK.
FakeHttp _http(Map<String, List<CastHttpResponse>> script) => FakeHttp({
  _control: (SentRequest request) {
    final action = _action(request);
    final queue = script[action];
    if (queue != null && queue.isNotEmpty) return queue.removeAt(0);
    return CastHttpResponse(200, _ok(action));
  },
});

void main() {
  test('setSource posts SetAVTransportURI to the control URL with the advertised service type', () async {
    final http = _http({});
    final renderer = DlnaRenderer(_device, http: http);
    await renderer.setSource(_source);
    final request = http.requests.single;
    expect(request.method, 'POST');
    expect(request.url, _control);
    expect(request.timeout, const Duration(seconds: 15));
    expect(request.headers['SOAPAction'], '"urn:schemas-upnp-org:service:AVTransport:2#SetAVTransportURI"');
    final body = XmlDocument.parse(request.body!);
    final action = body.descendantElements.firstWhere((element) => element.localName == 'SetAVTransportURI');
    expect(action.getElement('InstanceID')!.innerText, '0');
    expect(action.getElement('CurrentURI')!.innerText, _source);
    expect(action.getElement('CurrentURIMetaData')!.innerText, didlLite(const CastMedia(url: _source)));
    expect(renderer.id, 'uuid:x');
    expect(renderer.address, 'http://192.168.1.20:1733');
  });

  test('Play at speed 1, Pause, Stop and GetTransportInfo on instance 0', () async {
    final http = _http({
      'GetTransportInfo': [
        CastHttpResponse(
          200,
          _ok(
            'GetTransportInfo',
            '<CurrentTransportState>PLAYING</CurrentTransportState>'
                '<CurrentTransportStatus>OK</CurrentTransportStatus><CurrentSpeed>1</CurrentSpeed>',
          ),
        ),
      ],
    });
    final renderer = DlnaRenderer(_device, http: http);
    await renderer.play();
    await renderer.pause();
    await renderer.stop();
    final info = await renderer.transportInfo();
    expect(http.requests.map(_action), ['Play', 'Pause', 'Stop', 'GetTransportInfo']);
    expect(http.requests.first.body, contains('<InstanceID>0</InstanceID><Speed>1</Speed>'));
    expect(info, const TransportInfo(state: TransportState.playing, status: 'OK', speed: '1'));
    expect(info.failed, isFalse);
  });

  test('a busy renderer is stopped and asked once more', () async {
    final http = _http({
      'SetAVTransportURI': [CastHttpResponse(500, _fault(705))],
    });
    await DlnaRenderer(_device, http: http).setSource(_source);
    expect(http.requests.map(_action), ['SetAVTransportURI', 'Stop', 'SetAVTransportURI']);
  });

  test('a Play refused while loading is retried once after the settle time', () {
    fakeAsync((async) {
      final http = _http({
        'Play': [CastHttpResponse(500, _fault(701))],
      });
      var done = false;
      unawaited(DlnaRenderer(_device, http: http).play().then((_) => done = true));
      async.elapse(const Duration(milliseconds: 799));
      expect(http.requests.map(_action), ['Play']);
      expect(done, isFalse);
      async.elapse(const Duration(milliseconds: 1));
      expect(http.requests.map(_action), ['Play', 'Play']);
      expect(done, isTrue);
    });
  });

  test('other failures reach the caller typed', () async {
    final http = _http({
      'SetAVTransportURI': [CastHttpResponse(500, _fault(714))],
      'Play': [const CastHttpResponse(404, '')],
    });
    final renderer = DlnaRenderer(_device, http: http);
    await expectLater(
      renderer.setSource(_source),
      throwsA(isA<UpnpActionFailure>().having((failure) => failure.error, 'error', UpnpError.illegalMimeType)),
    );
    await expectLater(renderer.play(), throwsA(isA<CastHttpFailure>()));
    http.answers[_control] = const CastTimeoutFailure(Duration(seconds: 15));
    await expectLater(renderer.pause(), throwsA(isA<CastTimeoutFailure>()));
  });
}
