import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/image_cache.dart';
import 'package:pure_live/app/platforms.dart';
import 'package:pure_live/app/services.dart';

import 'support.dart';

/// Real sockets inside the test binding, which otherwise answers every
/// `HttpClient` request with 400.
final class _RealHttp extends HttpOverrides;

/// A loopback server that answers every request with three bytes and keeps the
/// request lines it saw: an absolute URI when it was used as a proxy.
final class _Server {
  new _(this._server) {
    _server.listen((request) async {
      seen.add('${request.method} ${request.uri}');
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType('image', 'png')
        ..add(const [1, 2, 3]);
      await request.response.close();
    });
  }

  static Future<_Server> start() async => _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final List<String> seen = [];

  int get port => _server.port;

  Future<void> close() => _server.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('images follow the app proxy, read at each new connection (Q02.1)', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      final proxy = await _Server.start();
      final direct = await _Server.start();
      addTearDown(proxy.close);
      addTearDown(direct.close);
      final service = imageFileService(SettingsProxyPolicy(store.settings));

      await store.settings.setAll({
        Settings.enableAppProxy: true,
        Settings.appProxyHost: '127.0.0.1',
        Settings.appProxyPort: proxy.port,
      });
      final proxied = await service.get('http://covers.example/a.jpg');
      expect(proxied.statusCode, 200);
      expect(await proxied.content.expand((bytes) => bytes).toList(), [1, 2, 3]);
      expect(proxy.seen, ['GET http://covers.example/a.jpg'], reason: 'asked of the proxy, by absolute URI');

      await store.settings.set(Settings.enableAppProxy, false);
      await (await service.get('http://127.0.0.1:${direct.port}/b.jpg')).content.drain<void>();
      expect(direct.seen, ['GET /b.jpg'], reason: 'off: straight to the image host');

      // A half-typed address stays direct (proxyRouteFrom).
      await store.settings.setAll({Settings.enableAppProxy: true, Settings.appProxyHost: ''});
      await (await service.get('http://localhost:${direct.port}/c.jpg')).content.drain<void>();
      expect(direct.seen.last, 'GET /c.jpg');
      expect(proxy.seen, hasLength(1));
    }, _RealHttp());
  });

  test("the cache follows 3.x's rules under a key of its own", () {
    final config = appImageCacheConfig(
      const _NoProxy(),
      repo: NonStoringObjectProvider(),
      fileSystem: MemoryCacheSystem(),
    );
    expect(config.cacheKey, appImageCacheKey);
    expect(appImageCacheKey, isNot('libCachedImageData'), reason: "not flutter_cache_manager's default");
    expect(config.stalePeriod, const Duration(minutes: 30));
    expect(config.maxNrOfCacheObjects, 320);
    expect(config.fileService, isA<HttpFileService>());
    // flutter_cache_manager keeps the files in <temp>/<key> (IOFileSystem).
    expect(appImageCacheFolder(Directory('/tmp/x')).path, p.join('/tmp/x', appImageCacheKey));
  });

  test("one manager; flutter_cache_manager's old default cache is emptied once", () async {
    final store = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(store.close);
    final previous = AppImageCache.manager;
    addTearDown(() => AppImageCache.manager = previous);
    var legacy = 0;
    Config memory() =>
        appImageCacheConfig(const _NoProxy(), repo: NonStoringObjectProvider(), fileSystem: MemoryCacheSystem());

    AppImageCache.manager = null;
    final manager = AppImageCache.install(memory);
    expect(AppImageCache.manager, same(manager));
    expect(AppImageCache.install(memory), same(manager), reason: 'one manager');

    await AppImageCache.clearLegacyOnce(store.meta, () async => legacy++);
    expect(legacy, 1);
    await AppImageCache.clearLegacyOnce(store.meta, () async => legacy++);
    expect(legacy, 1, reason: 'remembered in the meta table');

    final failing = await LiveStore.memory(cipher: FakeCipher());
    addTearDown(failing.close);
    await AppImageCache.clearLegacyOnce(failing.meta, () async => throw StateError('busy'));
    expect(await failing.meta.get(AppImageCache.legacyClearedKey), isNull, reason: 'tried again next start');
  });

  testWidgets('the app gives live_ui its image cache', (tester) async {
    final previous = AppImageCache.manager;
    addTearDown(() => AppImageCache.manager = previous);
    final manager = CacheManager(
      appImageCacheConfig(const _NoProxy(), repo: NonStoringObjectProvider(), fileSystem: MemoryCacheSystem()),
    );
    AppImageCache.manager = manager;
    final services = (await tester.runAsync(() async {
      final services = await testServices();
      await services.store.settings.set(Settings.showSplashPage, false);
      return services;
    }))!;
    final strings = (await tester.runAsync(loadStrings))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(Scaffold).first);
    expect(LiveUiScope.of(context).imageCacheManager, same(manager));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(services.close);
  });
}

final class _NoProxy implements ProxyPolicy {
  const new();

  @override
  ProxyRoute routeFor(String site, Uri url) => const DirectRoute();
}
