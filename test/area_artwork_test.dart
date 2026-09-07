import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/category_artwork.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_page.dart';
import 'package:pure_live/modules/areas/widgets/area_card.dart';
import 'package:pure_live/plugins/area_pic_mapper.dart';
import 'package:pure_live/plugins/cache_manager.dart';

const sprite = 'https://static.maoercdn.com/live/catalog/icon/104.png';
const webSprite = 'https://static.maoercdn.com/live/catalog/icon/104-web.png';
const cover = 'https://example.com/cover.png';

LiveArea area(String url, {String name = '音乐'}) => LiveArea(
  platform: 'missevan',
  areaType: 'catalog',
  areaId: '104',
  areaName: name,
  typeName: '猫耳 FM',
  areaPic: url,
  shortName: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('area-artwork-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(paths, (call) async {
      if (call.method == 'getTemporaryDirectory' || call.method == 'getApplicationSupportDirectory') {
        return directory.path;
      }
      throw StateError('Unexpected path provider call: ${call.method}');
    });
    // CacheManager initializes its metadata storage even when decoded image
    // providers are seeded. Complete that I/O outside the widget fake clock.
    await CustomImageCacheManager.initialize();
    await CustomImageCacheManager.instance.getFileFromCache('fixture-no-file');
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
    await HivePrefUtil.setString('cached_area_pics', jsonEncode({'LegacySprite': sprite, '英雄联盟': cover}));
  });
  tearDownAll(() async {
    await CustomImageCacheManager.instance.dispose();
    await Hive.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(paths, null);
    await directory.delete(recursive: true);
  });
  tearDown(() {
    Get.reset();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test('legacy sprite cache does not become a generic category cover', () {
    expect(AreaPicMapper.getPic('LegacySprite'), isEmpty);
    expect(AreaPicMapper.getPic('moba'), cover);
  });
  test('new sprites do not replace useful covers in the cross-platform map', () async {
    AreaPicMapper.updateAreaListMaps([
      LiveCategory(id: '1', name: '', children: [area(cover)]),
    ]);
    AreaPicMapper.updateAreaListMaps([
      LiveCategory(id: '1', name: '', children: [area(sprite)]),
    ]);
    expect(AreaPicMapper.getPic('音乐'), cover);
    await Hive.box<dynamic>('app_settings').flush();
    expect((jsonDecode(HivePrefUtil.getString('cached_area_pics')!) as Map).values, isNot(contains(sprite)));
  });

  test('only the verified mobile and web resources select a sprite frame', () {
    for (final stem in [
      'catalog/icon/104',
      'catalog/icon/105',
      'catalog/icon/115',
      'catalog/icon/116',
      'catalog/icon/122',
      'tags/icon/001_20210322112121',
    ]) {
      expect(categoryArtworkAlignment('https://static.maoercdn.com/live/$stem.png'), Alignment.bottomCenter);
      expect(categoryArtworkAlignment('https://static.maoercdn.com/live/$stem-web.png'), Alignment.topCenter);
      expect(isCategoryIconSprite('https://static.maoercdn.com/live/$stem-web.png'), isTrue);
    }
    expect(
      categoryArtworkAlignment(' //static.maoercdn.com/live/catalog/icon/104.png?version=1 '),
      Alignment.bottomCenter,
    );
    expect(categoryArtworkAlignment('http://static.maoercdn.com/live/catalog/icon/104.png'), Alignment.bottomCenter);
    for (final url in [
      null,
      '',
      cover,
      'https://static.maoercdn.com.evil.test/live/catalog/icon/104.png',
      'https://name@static.maoercdn.com/live/catalog/icon/104.png',
      'https://static.maoercdn.com:8787/live/catalog/icon/104.png',
      'https://static.maoercdn.com/live/catalog/icon/999.png',
      'https://static.maoercdn.com/live/cover/104.png',
      'https://static.maoercdn.com/live/catalog/icon/104.png/other',
      'https://static.maoercdn.com/live/catalog/icon/104.jpg',
      'file:///live/catalog/icon/104.png',
    ]) {
      expect(categoryArtworkAlignment(url), Alignment.center, reason: '$url');
      expect(isCategoryIconSprite(url), isFalse, reason: '$url');
    }
  });

  for (final url in [sprite, webSprite, cover]) {
    testWidgets('card and follow avatar paint the correct square for $url', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      Get.testMode = true;
      Get.put(SettingsService());
      // Seed the actual providers, not a replacement widget: no HTTP or image-file reads.
      // A 60x120 image has a red upper state and a green lower state.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 60, 60), Paint()..color = Colors.red);
      canvas.drawRect(const Rect.fromLTWH(0, 60, 60, 60), Paint()..color = Colors.green);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(60, 120);
      picture.dispose();
      for (final width in [160, 64]) {
        final provider = ResizeImage.resizeIfNeeded(width, null, CachedNetworkImageProvider(url));
        final key = await provider.obtainKey(ImageConfiguration.empty);
        PaintingBinding.instance.imageCache.putIfAbsent(
          key,
          () => OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image.clone()))),
        );
      }
      image.dispose();
      final boundaryKey = GlobalKey();
      final original = area(url);
      final restored = LiveArea.fromJson(original.toJson());
      expect(restored.toJson(), original.toJson());
      expect(restored.identityKey, original.identityKey);
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 160,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AreaCard(category: restored),
                      FavoriteAreaFloatingButton(area: restored),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final images = find.byType(CachedNetworkImage);
      expect(images, findsNWidgets(2));
      expect(find.byType(RawImage), findsNWidgets(2));
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
      final data = (await tester.runAsync(() async {
        final screenshot = await boundary.toImage();
        try {
          return (width: screenshot.width, bytes: (await screenshot.toByteData())!);
        } finally {
          screenshot.dispose();
        }
      }))!;
      final origin = tester.getTopLeft(find.byKey(boundaryKey));
      for (final finder in [images.at(0), images.at(1)]) {
        final widget = tester.widget<CachedNetworkImage>(finder);
        expect(widget.fit, BoxFit.cover);
        final rect = tester.getRect(finder).shift(-origin);
        for (final fraction in [0.25, 0.75]) {
          final x = rect.center.dx.floor();
          final y = (rect.top + rect.height * fraction).floor();
          final offset = (y * data.width + x) * 4;
          final expected = url == sprite || (url != webSprite && fraction > 0.5) ? Colors.green : Colors.red;
          expect(data.bytes.getUint8(offset), (expected.r * 255).round(), reason: 'red at $fraction in $rect');
          expect(data.bytes.getUint8(offset + 1), (expected.g * 255).round(), reason: 'green at $fraction in $rect');
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
