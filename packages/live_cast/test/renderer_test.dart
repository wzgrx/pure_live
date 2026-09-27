import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:live_cast/live_cast.dart';
import 'package:test/test.dart';

import 'fakes.dart';

final Uri _control = Uri.parse('http://192.168.1.20:1733/AVTransport/x/control.xml');

final CastDevice _device = CastDevice(
  id: 'uuid:x',
  name: 'Kodi',
  location: Uri.parse('http://192.168.1.20:1733/'),
  avTransport: CastService(serviceType: 'urn:schemas-upnp-org:service:AVTransport:1', controlUrl: _control),
);

final CastMedia _media = CastMedia(url: Uri.parse('http://cdn.example.com/live/1.flv?a=1&b=2'), title: '主播1 - 标题');

String _ok(String action, [String arguments = '']) => [
  '<?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>',
  '<u:${action}Response xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">$arguments</u:${action}Response>',
  '</s:Body></s:Envelope>',
].join();

String _fault(int code) => [
  '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><detail>',
  '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>$code</errorCode></UPnPError>',
  '</detail></s:Fault></s:Body></s:Envelope>',
].join();

/// The SOAP action of a request, from its header.
String _action(SentRequest request) => request.headers['SOAPAction']!.split('#').last.replaceAll('"', '');

/// A renderer that records calls and fails as scripted.
final class _ScriptedRenderer implements CastRenderer {
  final List<String> calls = [];
  final Map<String, List<CastFailure>> failures = {};

  Future<void> _call(String name) async {
    calls.add(name);
    final queue = failures[name];
    if (queue != null && queue.isNotEmpty) throw queue.removeAt(0);
  }

  @override
  CastDevice get device => _device;

  @override
  Future<void> setMedia(CastMedia media) => _call('set');

  @override
  Future<void> play() => _call('play');

  @override
  Future<void> pause() => _call('pause');

  @override
  Future<void> stop() => _call('stop');

  @override
  Future<TransportInfo> transportInfo() async => const TransportInfo(state: TransportState.playing);
}

void main() {
  group('DlnaRenderer', () {
    test('SetAVTransportURI posts to the control URL with SOAP headers and the metadata', () async {
      final http = FakeHttp({_control: CastHttpResponse(200, _ok('SetAVTransportURI'))});
      await DlnaRenderer(_device, http: http, timeout: const Duration(seconds: 2)).setMedia(_media);
      final request = http.requests.single;
      expect(request.method, 'POST');
      expect(request.url, _control);
      expect(request.timeout, const Duration(seconds: 2));
      expect(request.headers['Content-Type'], 'text/xml; charset="utf-8"');
      expect(_action(request), 'SetAVTransportURI');
      expect(request.body, contains('<InstanceID>0</InstanceID>'));
      expect(request.body, contains('<CurrentURI>http://cdn.example.com/live/1.flv?a=1&amp;b=2</CurrentURI>'));
      expect(request.body, contains('&lt;upnp:class&gt;object.item.videoItem&lt;/upnp:class&gt;'));
    });

    test('Play, Pause and Stop on instance 0', () async {
      final http = FakeHttp({_control: const CastHttpResponse(200, '')});
      final renderer = DlnaRenderer(_device, http: http);
      await renderer.play();
      await renderer.pause();
      await renderer.stop();
      expect(http.requests.map(_action), ['Play', 'Pause', 'Stop']);
      expect(http.requests.first.body, contains('<InstanceID>0</InstanceID><Speed>1</Speed>'));
      expect(http.requests.last.body, contains('<u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'));
    });

    test('GetTransportInfo', () async {
      final http = FakeHttp({
        _control: CastHttpResponse(
          200,
          _ok(
            'GetTransportInfo',
            '<CurrentTransportState>PAUSED_PLAYBACK</CurrentTransportState>'
                '<CurrentTransportStatus>OK</CurrentTransportStatus><CurrentSpeed>1</CurrentSpeed>',
          ),
        ),
      });
      final info = await DlnaRenderer(_device, http: http).transportInfo();
      expect(info, const TransportInfo(state: TransportState.pausedPlayback, status: 'OK', speed: '1'));
      expect(info.failed, isFalse);
      expect(TransportState.parse('no_media_present'), TransportState.noMediaPresent);
      expect(TransportState.parse('CUSTOM'), TransportState.unknown);
      expect(const TransportInfo(state: TransportState.stopped, status: 'ERROR_OCCURRED').failed, isTrue);
    });

    test('UPnP errors, HTTP errors and transport failures reach the caller typed', () async {
      final http = FakeHttp({_control: CastHttpResponse(500, _fault(714))});
      final renderer = DlnaRenderer(_device, http: http);
      await expectLater(
        renderer.setMedia(_media),
        throwsA(isA<UpnpActionFailure>().having((failure) => failure.error, 'error', UpnpError.illegalMimeType)),
      );
      http.answers[_control] = const CastHttpResponse(503, 'busy');
      await expectLater(renderer.play(), throwsA(isA<CastHttpFailure>()));
      http.answers[_control] = const CastTimeoutFailure(Duration(seconds: 6));
      await expectLater(renderer.stop(), throwsA(isA<CastTimeoutFailure>()));
    });
  });

  group('castTo', () {
    test('sets the source, then plays', () async {
      final renderer = _ScriptedRenderer();
      await castTo(renderer, _media);
      expect(renderer.calls, ['set', 'play']);
    });

    test('a busy renderer is stopped and asked once more', () async {
      final renderer = _ScriptedRenderer()
        ..failures['set'] = [const UpnpActionFailure('SetAVTransportURI', 705)]
        ..failures['stop'] = [const UpnpActionFailure('Stop', 701)];
      await castTo(renderer, _media);
      expect(renderer.calls, ['set', 'stop', 'set', 'play']);
    });

    test('a Play refused while loading is retried once after the settle time', () {
      fakeAsync((async) {
        final renderer = _ScriptedRenderer()..failures['play'] = [const UpnpActionFailure('Play', 701)];
        var done = false;
        unawaited(castTo(renderer, _media, settle: const Duration(seconds: 1)).then((_) => done = true));
        async.flushMicrotasks();
        expect(renderer.calls, ['set', 'play']);
        async.elapse(const Duration(milliseconds: 999));
        expect(renderer.calls, ['set', 'play'], reason: 'waits for the renderer to settle');
        async.elapse(const Duration(milliseconds: 1));
        expect(renderer.calls, ['set', 'play', 'play']);
        expect(done, isTrue);
      });
    });

    test('other failures stop the sequence: no Play after a refused source', () async {
      final renderer = _ScriptedRenderer()..failures['set'] = [const UpnpActionFailure('SetAVTransportURI', 716)];
      await expectLater(castTo(renderer, _media), throwsA(isA<UpnpActionFailure>()));
      expect(renderer.calls, ['set']);

      final network = _ScriptedRenderer()..failures['play'] = [const CastNetworkFailure('reset')];
      await expectLater(castTo(network, _media), throwsA(isA<CastNetworkFailure>()));
      expect(network.calls, ['set', 'play']);

      final twice = _ScriptedRenderer()
        ..failures['set'] = [
          const UpnpActionFailure('SetAVTransportURI', 705),
          const UpnpActionFailure('SetAVTransportURI', 705),
        ];
      await expectLater(castTo(twice, _media), throwsA(isA<UpnpActionFailure>()));
      expect(twice.calls, ['set', 'stop', 'set'], reason: 'one retry only');
    });
  });
}
