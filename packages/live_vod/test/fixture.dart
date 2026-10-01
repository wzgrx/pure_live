import 'dart:convert';
import 'dart:io';

/// A recorded sample under fixtures/live_vod (tests run from the package).
final class Fixture {
  new _(this.directory, this.meta);

  /// Loads `fixtures/live_vod/<sample>`.
  factory load(String sample) {
    final directory = Directory('../../fixtures/live_vod/$sample');
    final meta = jsonDecode(File('${directory.path}/meta.json').readAsStringSync()) as Map<String, dynamic>;
    return Fixture._(directory, meta);
  }

  final Directory directory;
  final Map<String, dynamic> meta;

  File get _file => File('${directory.path}/${meta['body']}');

  /// Body as text.
  String get body => _file.readAsStringSync();

  /// Body as bytes.
  List<int> get bytes => _file.readAsBytesSync();

  /// Recorded status.
  int get status => (meta['response'] as Map<String, dynamic>)['status'] as int;

  /// When it was recorded.
  DateTime get capturedAt => DateTime.parse(meta['capturedAt'] as String);
}

/// Fixture root for ReplayHttp.
const String fixtureRoot = '../../fixtures/live_vod';
