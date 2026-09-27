import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Installed 3.x apps fetch `assets/version.json` and `assets/releases.json`
/// from the repository root on master, while this app packages its own copies
/// under `legacy/assets/` (docs/adr/0013-legacy-folder.md). A release that
/// updates only one copy would make the update check disagree with the app.
void main() {
  for (final name in ['version.json', 'releases.json']) {
    test('root assets/$name matches the packaged copy', () {
      final published = File('../assets/$name');
      final packaged = File('assets/$name');

      expect(published.existsSync(), isTrue, reason: 'installed apps read ${published.path} from master');
      expect(published.readAsStringSync(), packaged.readAsStringSync());
    });
  }

  test('the update check and release history read the root copies', () {
    final versionUtil = File('lib/common/utils/version_util.dart').readAsStringSync();
    final history = File('lib/modules/about/widgets/release_history_repository.dart').readAsStringSync();

    expect(versionUtil, contains("rawUrl('assets/version.json')"));
    expect(versionUtil, contains("branch: 'master'"));
    expect(history, contains("releaseAssetPath = 'assets/releases.json'"));
  });
}
