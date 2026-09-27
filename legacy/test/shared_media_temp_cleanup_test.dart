import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:pure_live/plugins/file_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('default cleanup uses the application temporary directory', () async {
    final root = await Directory.systemTemp.createTemp('shared-cleanup-platform-');
    final originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(root.path);
    addTearDown(() async {
      PathProviderPlatform.instance = originalPaths;
      if (await root.exists()) await root.delete(recursive: true);
    });
    final file = File('${root.path}/share_handler/fixture-id/original-name.m3u');
    await file.create(recursive: true);

    expect(await FileUtils.cleanupOwnedSharedMediaFile(file), isTrue);
    expect(await file.exists(), isFalse);
  });

  test('owned share-handler file and empty staging directories are removed', () async {
    final root = await Directory.systemTemp.createTemp('shared-cleanup-owned-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final file = File('${root.path}/share_handler/fixture-id/original-name.m3u');
    await file.create(recursive: true);
    await file.writeAsString('#EXTM3U');

    expect(await FileUtils.cleanupOwnedSharedMediaFile(file, temporaryDirectory: root), isTrue);
    expect(await file.exists(), isFalse);
    expect(await Directory('${root.path}/share_handler/fixture-id').exists(), isFalse);
    expect(await Directory('${root.path}/share_handler').exists(), isFalse);
  });

  test('cleanup preserves unrelated and structurally ambiguous temporary files', () async {
    final root = await Directory.systemTemp.createTemp('shared-cleanup-unowned-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final unrelated = File('${root.path}/ordinary/original-name.m3u');
    final nested = File('${root.path}/share_handler/fixture-id/nested/original-name.m3u');
    await unrelated.create(recursive: true);
    await nested.create(recursive: true);

    expect(await FileUtils.cleanupOwnedSharedMediaFile(unrelated, temporaryDirectory: root), isFalse);
    expect(await FileUtils.cleanupOwnedSharedMediaFile(nested, temporaryDirectory: root), isFalse);
    expect(await unrelated.exists(), isTrue);
    expect(await nested.exists(), isTrue);
  });

  test('owned file cleanup keeps a staging directory that still has a sibling', () async {
    final root = await Directory.systemTemp.createTemp('shared-cleanup-sibling-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final owned = File('${root.path}/share_handler/fixture-id/original-name.xml');
    final sibling = File('${root.path}/share_handler/fixture-id/other.xml');
    await owned.create(recursive: true);
    await sibling.writeAsString('<tv/>');

    expect(await FileUtils.cleanupOwnedSharedMediaFile(owned, temporaryDirectory: root), isTrue);
    expect(await owned.exists(), isFalse);
    expect(await sibling.exists(), isTrue);
    expect(await sibling.parent.exists(), isTrue);
  });

  test('shared importers always release plugin-owned temporary input', () {
    final playlistSource = File('lib/core/iptv/services/iptv_import_manager.dart').readAsStringSync();
    final epgSource = File('lib/core/iptv/services/epg_import_manager.dart').readAsStringSync();

    for (final source in [playlistSource, epgSource]) {
      expect(source, contains('finally {'));
      expect(source, contains('FileUtils.cleanupOwnedSharedMediaFile(file)'));
    }
  });
}

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}
