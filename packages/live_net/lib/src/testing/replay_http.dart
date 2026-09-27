import 'dart:convert';
import 'dart:io';

import 'package:live_net/src/live_http.dart';
import 'package:live_net/src/request.dart';
import 'package:live_net/src/response.dart';

/// One recorded exchange to replay.
final class ReplaySample {
  /// Creates a sample.
  new({
    required this.method,
    required this.url,
    required this.status,
    required this.bytes,
    this.headers = const {},
    this.form,
  });

  /// Loads `<directory>/meta.json` and its body (docs/adr/0009-fixture-format.md).
  factory load(String directory) {
    final meta = jsonDecode(File('$directory/meta.json').readAsStringSync()) as Map<String, dynamic>;
    final request = meta['request'] as Map<String, dynamic>;
    final response = meta['response'] as Map<String, dynamic>;
    return ReplaySample(
      method: request['method'] as String,
      url: Uri.parse(request['url'] as String),
      status: response['status'] as int,
      headers: {
        for (final entry in (response['headers'] as Map<String, dynamic>).entries)
          entry.key.toLowerCase(): entry.value is List
              ? [for (final v in entry.value as List) '$v']
              : ['${entry.value}'],
      },
      bytes: File('$directory/${meta['body']}').readAsBytesSync(),
      form: request['body'] is String ? Uri.splitQueryString(request['body'] as String) : null,
    );
  }

  /// Recorded method.
  final String method;

  /// Recorded URL (signatures scrubbed).
  final Uri url;

  /// Recorded status.
  final int status;

  /// Recorded headers by lower-case name.
  final Map<String, List<String>> headers;

  /// Recorded body.
  final List<int> bytes;

  /// Recorded form fields of a form POST, or null.
  final Map<String, String>? form;
}

/// Replays recorded samples (ADR 0011, rule 5): a request matches a sample by
/// method, host, path, and the query parameters and form fields other than
/// [ignoredQuery] (the signature and session parameters whose recorded
/// values were scrubbed).
/// A request without a sample throws, failing the test.
final class ReplayHttp implements LiveHttp {
  /// Replays [samples].
  new(this.samples, {this.ignoredQuery = const {}});

  /// Loads `<root>/<name>` for every name in [names].
  factory fixtures(String root, List<String> names, {Set<String> ignoredQuery = const {}}) =>
      ReplayHttp([for (final name in names) ReplaySample.load('$root/$name')], ignoredQuery: ignoredQuery);

  /// Samples in match order.
  final List<ReplaySample> samples;

  /// Query parameters left out of matching.
  final Set<String> ignoredQuery;

  /// Every request sent, in order.
  final List<LiveRequest> requests = [];

  Map<String, String> _query(Map<String, String> fields) => {
    for (final entry in fields.entries)
      if (!ignoredQuery.contains(entry.key)) entry.key: entry.value,
  };

  bool _matches(ReplaySample sample, LiveRequest request) {
    if (sample.method.toUpperCase() != request.method.toUpperCase()) return false;
    if (sample.url.host != request.url.host || sample.url.path != request.url.path) return false;
    if (!_same(_query(sample.url.queryParameters), _query(request.url.queryParameters))) return false;
    final form = sample.form;
    if (form == null) return true;
    final body = request.body;
    return body != null && _same(_query(form), _query(Uri.splitQueryString(utf8.decode(body))));
  }

  static bool _same(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    requests.add(request);
    for (final sample in samples) {
      if (_matches(sample, request)) {
        return LiveResponse(status: sample.status, headers: sample.headers, bytes: sample.bytes, url: request.url);
      }
    }
    throw StateError('No recorded sample for ${request.method} ${request.url.replace(query: '')}');
  }

  @override
  void close() {}
}
