import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/io_client.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;

/// The platform name image requests are routed under
/// ([ProxyPolicy.routeFor]); the app proxy does not tell platforms apart.
const String imageProxySite = 'image';

/// The disk cache of covers, avatars and emoticons (3.x
/// `CustomImageCacheManager.key`, `pureLiveImagesV2`): its database name and
/// its folder under the temporary directory. Not flutter_cache_manager's
/// default (`libCachedImageData`), whose client ignores the app proxy.
const String appImageCacheKey = 'pureLiveImages';

/// The folder of [appImageCacheKey] under [temporary] (flutter_cache_manager's
/// `IOFileSystem` layout).
Directory appImageCacheFolder(Directory temporary) => Directory(p.join(temporary.path, appImageCacheKey));

/// The image downloads' client (3.x `CustomImageCacheManager._createManager`):
/// the app proxy of [proxy], read at each new connection so a changed
/// setting applies to the next image without a new client; idle
/// connections close after 30 s. The directive is [ProxyRoute.directive]
/// as is: Android resolves anything else in it as a host name.
HttpClient imageHttpClient(ProxyPolicy proxy) => HttpClient()
  ..idleTimeout = const Duration(seconds: 30)
  ..findProxy = (url) => proxy.routeFor(imageProxySite, url).directive;

/// flutter_cache_manager's download service over [imageHttpClient].
FileService imageFileService(ProxyPolicy proxy) => HttpFileService(httpClient: IOClient(imageHttpClient(proxy)));

/// The image cache's rules (3.x): 30 minutes before a file is asked for
/// again, at most 320 files, downloads through [proxy]. [repo] and
/// [fileSystem] replace the on-disk ones in tests.
Config appImageCacheConfig(ProxyPolicy proxy, {CacheInfoRepository? repo, FileSystem? fileSystem}) {
  const stalePeriod = Duration(minutes: 30);
  const maxNrOfCacheObjects = 320;
  final fileService = imageFileService(proxy);
  if (repo == null || fileSystem == null) {
    return Config(
      appImageCacheKey,
      stalePeriod: stalePeriod,
      maxNrOfCacheObjects: maxNrOfCacheObjects,
      fileService: fileService,
    );
  }
  return Config(
    appImageCacheKey,
    stalePeriod: stalePeriod,
    maxNrOfCacheObjects: maxNrOfCacheObjects,
    repo: repo,
    fileSystem: fileSystem,
    fileService: fileService,
  );
}

/// The app's image cache manager (Q02.1): live_ui's covers and avatars
/// (`LiveUiConfig.imageCacheManager`), the flying danmaku's emoticons and
/// the data page's clearing all use it.
abstract final class AppImageCache {
  /// The manager; null until [install] (tests and widgets outside the app
  /// fall back to their defaults).
  static BaseCacheManager? manager;

  /// The meta key set once flutter_cache_manager's default cache, which
  /// earlier versions filled, was emptied.
  static const String legacyClearedKey = 'images.legacyCacheCleared';

  /// The manager, created from [config] the first time.
  static BaseCacheManager install(Config Function() config) => manager ??= CacheManager(config());

  /// Empties the old default cache with [clearLegacy] unless [meta] says it
  /// was done; a failure is tried again at the next start.
  static Future<void> clearLegacyOnce(MetaStore meta, Future<void> Function() clearLegacy) async {
    if (await meta.get(legacyClearedKey) != null) return;
    try {
      await clearLegacy();
      await meta.set(legacyClearedKey, '1');
    } on Object {
      // Left for the next start.
    }
  }
}
