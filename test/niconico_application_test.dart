import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/base/base_page_scroll_bone.dart';
import 'package:pure_live/common/base/live_directory_controller.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/core/interface/live_directory.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/niconico/niconico_api.dart';
import 'package:pure_live/core/site/niconico/niconico_input_recipe.dart';
import 'package:pure_live/core/site/niconico/niconico_link.dart';
import 'package:pure_live/core/site/niconico/niconico_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_binding.dart';
import 'package:pure_live/modules/live_play/services/room_external_opener.dart';
import 'package:pure_live/modules/multiview/danmaku/multiview_danmaku_session.dart';
import 'package:pure_live/modules/multiview/multiview_controller.dart';
import 'package:pure_live/modules/popular/popular_controller.dart';
import 'package:pure_live/modules/search/search_capability.dart';
import 'package:pure_live/modules/search/search_controller.dart' as search;
import 'package:pure_live/modules/search/web_search_room_parser.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';

import 'niconico_api_test.dart' as watch;
import 'niconico_directory_test.dart' as listing;
import 'niconico_site_test.dart' show Catalog;

class _Directory extends LiveDirectoryController {
  _Directory(LiveSiteDirectoryPager directory) : super(directory: directory);
  @override
  Future<bool> checkNetworkBeforeRequest() async => true;
  @override
  bool get usesDesktopPagination => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put(SettingsService());
  });
  tearDown(Get.reset);
  tearDownAll(Hive.close);

  test('registered niconico resolves one adapter and explicit playback/recording/directory contracts', () {
    final site = Sites.of(' NICONICO ');
    expect(Sites.isSupported(' NICONICO '), isTrue);
    expect(site.liveSite, isA<NiconicoSite>());
    expect(site.liveSite, isA<LiveSiteDirectoryPager>());
    expect(site.liveSite, isA<LiveSiteRecordRoomResolver>());
    expect(site.liveSite, isA<LiveSiteRoomRefresher>());
    expect(site.liveSite, isA<LivePlayUrlResolver>());
    expect(site.liveSite, isA<LivePlayUrlCursorResolver>());
    expect(Sites.supportSites.where((s) => s.id == site.id), hasLength(1));
    final capability = LiveSearchCapabilities.forPlatform(site.id);
    expect(capability.coverage, NativeSearchCoverage.liveOnly);
    expect(capability.supportsPagination, isTrue);
    expect(capability.supportsWebSearch, isTrue);
    expect(capability.mayIncludeOffline, isFalse);
    expect(MultiviewDanmakuSession.isSupportedPlatform(site.id), isFalse);
  });
  test('popular and category bindings use native pager with scope notice', () async {
    final adapter = NiconicoSite(
      api: NiconicoApi(request: (_, _) async => (status: 200, body: jsonEncode(listing.envelope(rows: [], total: 0)))),
    );
    final site = Site(id: 'niconico', name: 'niconico', logo: 'assets/images/logo.png', liveSite: adapter);
    final popular = PopularController();
    addTearDown(popular.onClose);
    popular.initControllers([site]);
    final controller = Get.find<BasePageScrollAndStateBone<LiveRoom>>(tag: site.id);
    expect(controller, isA<LiveDirectoryController>());
    expect(controller.pageNotice, 'niconico_directory_scope');
    final area = (await adapter.getCategores(1, 30)).single.children[2];
    final category = AreaRoomsBinding.createController(site, area);
    addTearDown(category.onClose);
    expect(category, isA<LiveDirectoryController>());
    expect((category as LiveDirectoryController).category?.areaId, 'live');
  });
  test('closing actual directory controller cancels adapter I/O and ignores late cards', () async {
    final started = Completer<CancelToken>();
    final response = Completer<({int status, String body})>();
    final adapter = NiconicoSite(
      api: NiconicoApi(
        request: (_, token) {
          started.complete(token);
          return response.future;
        },
      ),
    );
    final controller = _Directory(adapter);
    final pending = controller.loadData();
    final token = await started.future;
    controller.onClose();
    response.complete((status: 200, body: jsonEncode(listing.envelope())));
    await pending;
    expect(token.isCancelled, isTrue);
    expect(controller.list, isEmpty);
  });
  test('official web search uses encoded native keyword and onair status', () {
    final controller = search.SearchController();
    addTearDown(controller.onClose);
    final uri = Uri.parse(controller.buildSearchUrl('niconico', 'ゲーム & status=past'));
    expect(uri.host, 'live.nicovideo.jp');
    expect(uri.path, '/search');
    expect(uri.queryParameters, {'keyword': 'ゲーム & status=past', 'status': 'onair'});
  });
  for (final raw in [
    'https://live.nicovideo.jp/watch/lv100',
    'https://live.nicovideo.jp/watch/lv100?ref=share#player',
    '  https://live.nicovideo.jp/watch/lv100  ',
  ]) {
    test('verified watch URL enters common share and web routes: $raw', () async {
      expect(NiconicoLink.parse(raw), 'lv100');
      final target = WebSearchRoomParser.parse(raw)!;
      expect(target.key, 'niconico:lv100');
      expect(LiveUrlTool.containsSupportedLink('节目 $raw'), isTrue);
      expect(await LiveUrlTool.parseLiveUrl('节目 $raw', clientFactory: () => throw StateError('no redirect I/O')), [
        'lv100',
        'niconico',
      ]);
    });
  }
  for (final raw in [
    'lv100',
    'http://live.nicovideo.jp/watch/lv100',
    'https://live.nicovideo.jp.evil.invalid/watch/lv100',
    'https://user@live.nicovideo.jp/watch/lv100',
    'https://live.nicovideo.jp:443/watch/lv100',
    'https://live.nicovideo.jp/watch/%6cv100',
    'https://live.nicovideo.jp/watch/other/../lv100',
    'https://live.nicovideo.jp/watch/lv0',
    'https://live.nicovideo.jp/user/100',
    'https://live.nicovideo.jp/search?keyword=lv100',
    'https://asset2.dlive.nicovideo.jp/master.m3u8',
  ]) {
    test('non-watch URL is not salvaged into a room: $raw', () async {
      expect(NiconicoLink.parse(raw), isNull);
      expect(WebSearchRoomParser.parse(raw), isNull);
      expect(LiveUrlTool.containsSupportedLink(raw), isFalse);
      expect(await LiveUrlTool.parseLiveUrl(raw, clientFactory: () => throw StateError('no redirect I/O')), isEmpty);
    });
  }
  test('share cancellation performs no lookup', () async {
    expect(
      await LiveUrlTool.parseLiveUrl(
        'https://live.nicovideo.jp/watch/lv100',
        cancelToken: CancelToken()..cancel(),
        clientFactory: () => throw StateError('no I/O'),
      ),
      isEmpty,
    );
  });
  test('external action reconstructs canonical public watch URL, not stored untrusted link', () {
    final room = LiveRoom(platform: 'niconico', roomId: 'lv100', link: 'https://evil.invalid');
    final target = RoomExternalOpener.resolve('niconico', room)!;
    expect(target.web, 'https://live.nicovideo.jp/watch/lv100');
    expect(target.native, isNull);
    expect(RoomExternalOpener.resolve('niconico', LiveRoom(roomId: '100')), isNull);
  });
  test('registered identity reaches actual recorder and multiview resolvers as owned sources', () async {
    final catalog = Catalog();
    final adapter = NiconicoSite(
      catalog: catalog,
      api: NiconicoApi(request: (_, _) async => (status: 200, body: watch.page(watch.fixture()))),
    );
    final recorder = StreamResolverService(
      siteResolver: (platform) {
        expect(Sites.isSupported(platform), isTrue);
        return adapter;
      },
    );
    final record = await recorder.resolveStream(roomId: 'lv100', platform: 'niconico', preferredQuality: 'highest');
    expect(record.inputRecipe, isA<NiconicoInputRecipe>());
    expect(record.url, isEmpty);
    expect(record.candidateUrls, isEmpty);
    final source = await MultiviewController.resolveStreamForSite(
      LiveRoom(platform: 'niconico', roomId: 'lv100'),
      site: Site(id: 'niconico', name: 'niconico', logo: '', liveSite: adapter),
      preferLowest: false,
    );
    expect(source.ownedSource, isNotNull);
    expect(source.lines, isEmpty);
    expect(catalog.calls, 2);
  });
}
