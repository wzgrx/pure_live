import 'dart:convert';
import 'dart:io';

/// A recorded sample under the repository's fixtures/ (docs/adr/0009-fixture-format.md).
class Fixture {
  new _(this.directory, this.meta);

  /// Loads `fixtures/<platform>/<sample>`; tests run from the package directory.
  factory load(String platform, String sample) {
    final directory = Directory('../../fixtures/$platform/$sample');
    final meta = jsonDecode(File('${directory.path}/meta.json').readAsStringSync()) as Map<String, dynamic>;
    return Fixture._(directory, meta);
  }

  final Directory directory;
  final Map<String, dynamic> meta;

  /// Response body as text.
  String get body => File('${directory.path}/${meta['body']}').readAsStringSync();

  /// HTTP status.
  int get status => (meta['response'] as Map<String, dynamic>)['status'] as int;

  /// Request URL.
  Uri get url => Uri.parse((meta['request'] as Map<String, dynamic>)['url'] as String);

  /// When the response was recorded.
  DateTime get capturedAt => DateTime.parse(meta['capturedAt'] as String);

  /// The legacy parser's output (`expected.json` → `value`).
  dynamic get legacy =>
      (jsonDecode(File('${directory.path}/expected.json').readAsStringSync()) as Map<String, dynamic>)['value'];
}
