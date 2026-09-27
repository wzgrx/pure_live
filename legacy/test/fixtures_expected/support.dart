// Recorded-sample support for legacy expected values (docs/adr/0009-fixture-format.md).
//
// Samples live in fixtures/<platform>/<sample>/. Tests replay them through the
// production Dio instance (only the network adapter is replaced, so the real
// transformer still decodes the bytes) and compare the legacy parser's output
// with expected.json. PURELIVE_UPDATE_EXPECTED=1 writes expected.json instead;
// review the diff before committing it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/http_client.dart';

class FixtureSample {
  FixtureSample._(this.directory, this.meta);

  factory FixtureSample.load(String platform, String sample) {
    final directory = Directory('../fixtures/$platform/$sample');
    final meta = jsonDecode(File('${directory.path}/meta.json').readAsStringSync()) as Map<String, dynamic>;
    return FixtureSample._(directory, meta);
  }

  final Directory directory;
  final Map<String, dynamic> meta;

  Map<String, dynamic> get _response => meta['response'] as Map<String, dynamic>;

  Uri get url => Uri.parse((meta['request'] as Map<String, dynamic>)['url'] as String);

  int get status => _response['status'] as int;

  String get contentType {
    final value = (_response['headers'] as Map<String, dynamic>)['content-type'];
    return (value is List ? value.first : value)?.toString() ?? 'application/octet-stream';
  }

  File get bodyFile => File('${directory.path}/${meta['body']}');

  Uint8List get bodyBytes => bodyFile.readAsBytesSync();

  dynamic get json => jsonDecode(bodyFile.readAsStringSync());
}

/// Serves recorded samples by URL path; unmatched requests fail the test.
class FixtureAdapter implements HttpClientAdapter {
  FixtureAdapter(this.samples);

  final List<FixtureSample> samples;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requests.add(options);
    final sample = samples.where((sample) => sample.url.path == options.uri.path).firstOrNull;
    if (sample == null) throw StateError('No recorded sample for ${options.method} ${options.uri}');
    return Future.value(
      ResponseBody.fromBytes(
        sample.bodyBytes,
        sample.status,
        headers: {
          Headers.contentTypeHeader: [sample.contentType],
        },
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Replays [samples] through HttpClient.instance.dio for the current test.
FixtureAdapter replay(List<FixtureSample> samples) {
  final dio = HttpClient.instance.dio;
  final previous = dio.httpClientAdapter;
  final adapter = FixtureAdapter(samples);
  dio.httpClientAdapter = adapter;
  addTearDown(() => dio.httpClientAdapter = previous);
  return adapter;
}

/// The fields a v4 adapter must reproduce for a room card or room detail.
Map<String, dynamic> roomProjection(LiveRoom room) {
  final json = room.toJson()
    ..['link'] = room.link
    ..['danmakuData'] = room.danmakuData?.toString();
  json.removeWhere((key, value) => value == null || (value is Map && value.isEmpty) || (value is List && value.isEmpty));
  return json;
}

/// Compares [actual] with the sample's expected.json, or writes it when
/// PURELIVE_UPDATE_EXPECTED=1.
void expectRecorded(FixtureSample sample, String generator, Object? actual) {
  final normalized = jsonDecode(jsonEncode(actual));
  final file = File('${sample.directory.path}/expected.json');
  if (Platform.environment['PURELIVE_UPDATE_EXPECTED'] == '1') {
    file.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'generator': generator, 'value': normalized})}\n',
    );
    return;
  }
  expect(file.existsSync(), isTrue, reason: 'Run once with PURELIVE_UPDATE_EXPECTED=1, review, then commit.');
  final expected = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  expect(expected['generator'], generator);
  expect(normalized, expected['value']);
}
