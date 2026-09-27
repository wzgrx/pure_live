import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ffmpeg_kit_extended_flutter's build hook reads `ffmpeg_kit_extended_config`
/// from the pubspec next to `.dart_tool/package_config.json`. Since the app moved
/// into legacy/ (docs/adr/0013-legacy-folder.md) that is the workspace root. A
/// config left in legacy/pubspec.yaml is ignored and the hook quietly packages
/// its default small build instead of the pinned FFmpeg 9.0.2 bundles.
void main() {
  test('FFmpeg bundle config sits in the workspace root pubspec', () {
    final root = File('../pubspec.yaml').readAsStringSync();
    final app = File('pubspec.yaml').readAsStringSync();

    expect(root, contains('\nworkspace:\n'));
    expect(root, contains('\nffmpeg_kit_extended_config:\n'));
    expect(root, contains('small: false'));
    for (final bundle in [
      'bundle-base-shared-lgpl-release.aar',
      'bundle-base-windows-x86_64-shared-lgpl.zip',
      'bundle-base-linux-x86_64-shared-lgpl.zip',
    ]) {
      expect(root, contains('/releases/download/native-ffmpeg-9.0.2-b1/$bundle'));
    }
    expect(app, isNot(contains('\nffmpeg_kit_extended_config:')));
  });
}
