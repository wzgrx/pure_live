import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live_app/app/version.dart';

void main() {
  test('lib/app/version.dart matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([^\s+]+)\+(\d+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml needs a version with a build number');
    expect(appVersion, match![1], reason: 'update lib/app/version.dart together with pubspec.yaml');
    expect(appBuildNumber, int.parse(match[2]!));
  });
}
