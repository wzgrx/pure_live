import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/global/app_path_manager.dart';
import 'package:pure_live/common/services/settings/cache_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pure-live-cache-scope-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('cache scope contains only app-owned temporary directory names', () {
    expect(CacheStoragePolicy.localDirectoryNames, [AppPathManager.dirImageCache, AppPathManager.dirEmojiCache]);
    expect(CacheStoragePolicy.localDirectoryNames, isNot(contains(AppPathManager.dirRecords)));
    expect(CacheStoragePolicy.localDirectoryNames, isNot(contains(AppPathManager.dirDownload)));
    expect(CacheStoragePolicy.localDirectoryNames, isNot(contains(AppPathManager.dirIptvCache)));
  });

  test('cache copy distinguishes temporary cache from persistent user data', () {
    final english = jsonDecode(File('assets/translations/en.json').readAsStringSync()) as Map<String, dynamic>;
    final chinese = jsonDecode(File('assets/translations/zh.json').readAsStringSync()) as Map<String, dynamic>;

    expect(english['clear_local_cache'], 'Clear Local Cache');
    expect(english['clear_local_cache_desc'], allOf(contains('Recordings'), contains('fonts'), contains('IPTV')));
    expect(chinese['clear_local_cache_desc'], allOf(contains('录制'), contains('字体'), contains('IPTV')));
    expect(english['clear_all_cache'], contains('Recording'));
    expect(chinese['clear_all_cache'], contains('录制'));
  });

  test('size and clear are limited to injected cache roots and preserve persistent user data', () async {
    final cache = Directory('${root.path}/cache')..createSync();
    final records = Directory('${root.path}/records')..createSync();
    final downloads = Directory('${root.path}/downloads')..createSync();
    final iptv = Directory('${root.path}/iptv')..createSync();
    await File('${cache.path}/cover.bin').writeAsBytes(List.filled(1024, 1));
    final recording = await File('${records.path}/record.mp4').writeAsString('recording');
    final font = await File('${downloads.path}/font.ttf').writeAsString('font');
    final playlist = await File('${iptv.path}/playlist.db').writeAsString('iptv');
    var backendClearCalls = 0;
    final controller = CacheController(
      cacheDirectoryResolver: () async => [cache, cache],
      encodedImageCacheClearer: () async {
        backendClearCalls++;
      },
    );

    expect(await controller.getCacheSize(), closeTo(1024 / 1024 / 1024, 0.000001));
    final result = await controller.clearCache();

    expect(result.succeeded, isTrue);
    expect(result.remainingSizeMB, 0);
    expect(backendClearCalls, 1);
    expect(await cache.exists(), isTrue);
    expect(await File('${cache.path}/cover.bin').exists(), isFalse);
    expect(await recording.readAsString(), 'recording');
    expect(await font.readAsString(), 'font');
    expect(await playlist.readAsString(), 'iptv');
    expect(controller.cacheSizeMB.value, 0);
    expect(controller.imageCacheEpoch.value, 1);
  });

  test('a purge failure reports the remaining bytes instead of claiming zero', () async {
    final cache = Directory('${root.path}/locked-cache')..createSync();
    await File('${cache.path}/locked.bin').writeAsBytes(List.filled(2048, 2));
    final controller = CacheController(
      cacheDirectoryResolver: () async => [cache],
      cacheDirectoryPurger: (_) async => false,
      encodedImageCacheClearer: () async {},
    );
    final expectedSize = 2048 / 1024 / 1024;

    expect(await controller.getCacheSize(), closeTo(expectedSize, 0.000001));
    final result = await controller.clearCache();

    expect(result.succeeded, isFalse);
    expect(result.failedOperations, 1);
    expect(result.remainingSizeMB, closeTo(expectedSize, 0.000001));
    expect(controller.cacheSizeMB.value, closeTo(expectedSize, 0.000001));
  });

  test('directory resolution failure retains the last measured size', () async {
    final controller = CacheController(
      cacheDirectoryResolver: () => Future.error(StateError('paths unavailable')),
      encodedImageCacheClearer: () async {},
    );
    controller.cacheSizeMB.value = 7.25;

    final result = await controller.clearCache();

    expect(result.succeeded, isFalse);
    expect(result.failedOperations, 1);
    expect(result.remainingSizeMB, 7.25);
    expect(controller.cacheSizeMB.value, 7.25);
  });

  test('a failed in-flight size scan does not prevent a later clear', () async {
    final cache = Directory('${root.path}/cache')..createSync();
    await File('${cache.path}/cover.bin').writeAsBytes(List.filled(32, 4));
    final firstResolution = Completer<List<Directory>>();
    var resolutionCalls = 0;
    final controller = CacheController(
      cacheDirectoryResolver: () {
        resolutionCalls++;
        return resolutionCalls == 1 ? firstResolution.future : Future.value([cache]);
      },
      encodedImageCacheClearer: () async {},
    );

    final scan = controller.getCacheSize();
    final scanFailure = expectLater(scan, throwsA(isA<StateError>()));
    final clear = controller.clearCache();
    firstResolution.completeError(StateError('first scan failed'));
    await scanFailure;
    final result = await clear;

    expect(result.succeeded, isTrue);
    expect(result.remainingSizeMB, 0);
    expect(resolutionCalls, 2);
    expect(await File('${cache.path}/cover.bin').exists(), isFalse);
  });

  test('duplicate clear calls share one operation and size waits for its result', () async {
    final cache = Directory('${root.path}/cache')..createSync();
    await File('${cache.path}/cover.bin').writeAsBytes(List.filled(64, 3));
    final backendStarted = Completer<void>();
    final releaseBackend = Completer<void>();
    var backendClearCalls = 0;
    final controller = CacheController(
      cacheDirectoryResolver: () async => [cache],
      encodedImageCacheClearer: () async {
        backendClearCalls++;
        backendStarted.complete();
        await releaseBackend.future;
      },
    );

    final first = controller.clearCache();
    final second = controller.clearCache();
    expect(identical(first, second), isTrue);
    expect(controller.isClearing.value, isTrue);
    await backendStarted.future;
    final sizeAfterClear = controller.getCacheSize();
    releaseBackend.complete();

    expect((await first).succeeded, isTrue);
    expect(await second, same(await first));
    expect(await sizeAfterClear, 0);
    expect(backendClearCalls, 1);
    expect(controller.isClearing.value, isFalse);
  });
}
