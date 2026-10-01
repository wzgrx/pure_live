import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:live_cast/live_cast.dart';

/// Reads a sample description from `test/samples`.
String sample(String name) => File('test/samples/$name').readAsStringSync();

/// One request a [FakeHttp] received.
final class SentRequest {
  new(this.method, this.url, this.headers, this.body, this.timeout);

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String? body;
  final Duration timeout;
}

/// A [CastHttp] that answers from a table, like the real client: errors as
/// [CastFailure]s, statuses returned. An answer may be a [CastHttpResponse],
/// a [CastFailure] to throw, or a function of the request.
final class FakeHttp implements CastHttp {
  new([Map<Uri, Object>? answers]) : answers = answers ?? {};

  final Map<Uri, Object> answers;
  final List<SentRequest> requests = [];

  /// Delay before each answer, on the (fake) clock.
  Duration delay = Duration.zero;

  bool closed = false;

  @override
  Future<CastHttpResponse> send(
    String method,
    Uri url, {
    required Duration timeout,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final request = SentRequest(method, url, headers, body, timeout);
    requests.add(request);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    var answer = answers[url] ?? const CastNetworkFailure('connection refused');
    if (answer is Object Function(SentRequest)) answer = answer(request);
    return switch (answer) {
      final CastHttpResponse response => response,
      final CastFailure failure => throw failure,
      _ => throw StateError('bad fake answer $answer'),
    };
  }

  @override
  void close() => closed = true;
}

/// An [SsdpSocket] whose answers the test injects.
final class FakeSocket implements SsdpSocket {
  new(this.label, {this.sendWorks = true});

  @override
  final String label;

  /// Whether [send] reports success.
  bool sendWorks;

  final List<String> sent = [];
  final StreamController<SsdpDatagram> _datagrams = StreamController<SsdpDatagram>();
  bool closed = false;

  @override
  Stream<SsdpDatagram> get datagrams => _datagrams.stream;

  @override
  bool send(List<int> data) {
    if (closed) throw StateError('send after close');
    sent.add(ascii.decode(data));
    return sendWorks;
  }

  /// Delivers an SSDP answer from [from].
  void answer(String text, {String from = '192.168.1.20'}) {
    if (!closed) _datagrams.add(SsdpDatagram(utf8.encode(text), InternetAddress(from), ssdpPort));
  }

  @override
  void close() {
    closed = true;
    unawaited(_datagrams.close());
  }
}

/// A NOTIFY announcement; [nts] is `ssdp:alive` or `ssdp:byebye`.
String ssdpNotify({required String usn, String? location, String nts = 'ssdp:alive'}) => [
  'NOTIFY * HTTP/1.1',
  'HOST: 239.255.255.250:1900',
  'CACHE-CONTROL: max-age=1800',
  if (location != null) 'LOCATION: $location',
  'NT: $mediaRendererTarget',
  'NTS: $nts',
  'USN: $usn',
  '',
  '',
].join('\r\n');

/// An M-SEARCH answer in the usual layout.
String ssdpAnswer({required String location, required String usn, required String st, String eol = '\r\n'}) => [
  'HTTP/1.1 200 OK',
  'CACHE-CONTROL: max-age=1800',
  'EXT:',
  'LOCATION: $location',
  'SERVER: Linux/4.9 UPnP/1.0 DLNADOC/1.50 Platinum/1.0.5.13',
  'ST: $st',
  'USN: $usn',
  '',
  '',
].join(eol);
