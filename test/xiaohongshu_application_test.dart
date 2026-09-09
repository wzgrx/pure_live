import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/base/base_page_scroll_bone.dart';
import 'package:pure_live/common/base/base_page_view.dart';
import 'package:pure_live/common/base/live_directory_controller.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/xiaohongshu/xiaohongshu_api.dart';
import 'package:pure_live/core/site/xiaohongshu/xiaohongshu_link.dart';
import 'package:pure_live/core/site/xiaohongshu/xiaohongshu_share.dart';
import 'package:pure_live/core/site/xiaohongshu/xiaohongshu_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/services/room_external_opener.dart';
import 'package:pure_live/modules/multiview/danmaku/multiview_danmaku_session.dart';
import 'package:pure_live/modules/popular/popular_controller.dart';
import 'package:pure_live/modules/search/search_capability.dart';
import 'package:pure_live/modules/search/search_controller.dart' as search;
import 'package:pure_live/player/core/playback_header_resolver.dart';
import 'package:pure_live/recorder/services/ffmpeg_header_factory.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const roomId = '570429070963278308';
Matcher failure(XiaohongshuFailure kind) => throwsA(isA<XiaohongshuException>().having((e) => e.kind, 'kind', kind));

class _Fixture {
  Map<String, dynamic> state =
      jsonDecode(File('test/fixtures/xiaohongshu/live.json').readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> get room => state['roomData']['roomInfo'] as Map<String, dynamic>;
  final paths = <String>[];
  int status = 200;
  late final site = XiaohongshuSite(
    api: XiaohongshuApi(
      request: (uri, cancel) async {
        paths.add(uri.path);
        expect(uri.toString(), '${XiaohongshuApi.origin}/livestream/$roomId');
        return (status: status, body: '<script>window.__INITIAL_STATE__=${jsonEncode({'liveStream': state})}</script>');
      },
    ),
  );
  Future<LiveRoom> detail() => site.getRoomDetail(roomId: roomId, platform: 'xiaohongshu');
  void offline() {
    room['status'] = 3;
    state['liveStatus'] = 'end';
  }

  void streams(void Function(Map<String, dynamic>) edit) {
    final config = jsonDecode(room['pullConfig'] as String) as Map<String, dynamic>;
    edit(config);
    room['pullConfig'] = jsonEncode(config);
  }
}

class _Directory extends LiveDirectoryController {
  _Directory(XiaohongshuSite site) : super(directory: site);
  @override
  Future<bool> checkNetworkBeforeRequest() async => true;
}

class _Loader extends AssetLoader {
  const _Loader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
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

  test('registered site has exact room lookup and persistent empty-directory explanation', () async {
    final site = Sites.of(' XIAOHONGSHU ');
    expect(site.liveSite, isA<XiaohongshuSite>());
    expect(Sites.supportSites.where((s) => s.id == 'xiaohongshu'), hasLength(1));
    final capability = LiveSearchCapabilities.forPlatform(site.id);
    expect(capability.coverage, NativeSearchCoverage.roomLookup);
    expect(capability.mayIncludeOffline, true);
    expect(capability.supportsPagination, false);
    expect(capability.supportsWebSearch, false);
    expect(MultiviewDanmakuSession.isSupportedPlatform(site.id), false);
    final popular = PopularController();
    addTearDown(popular.onClose);
    popular.initControllers([site]);
    final controller = Get.find<BasePageScrollAndStateBone<LiveRoom>>(tag: site.id);
    expect(controller, isA<LiveDirectoryController>());
    expect(controller.pageNotice, 'xiaohongshu_directory_scope');
    expect(await site.liveSite.getCategores(1, 30), isEmpty);
  });
  test('directory never fetches fixed seeds or pages recommendations', () async {
    final f = _Fixture();
    final c = _Directory(f.site);
    addTearDown(c.onClose);
    await c.loadData();
    await c.loadMoreData();
    expect(c.list, isEmpty);
    expect(c.canLoadMore.value, false);
    expect(f.paths, isEmpty);
    expect((await f.site.getDirectoryPage(page: 2)).hasMore, false);
    await expectLater(f.site.getDirectoryPage(cancel: CancelToken()..cancel()), failure(XiaohongshuFailure.cancelled));
  });
  for (final input in [
    roomId,
    'https://www.xiaohongshu.com/livestream/$roomId',
    'http://www.xiaohongshu.com/livestream/$roomId/?share=fixture',
    'https://xiaohongshu.com/livestream/$roomId',
    'https://www.xiaohongshu.com/hina/livestream/$roomId',
    'https://www.xiaohongshu.com/hina/livestream/$roomId/123',
    'https://www.xiaohongshu.com/livestream/dynpath9oMyTyTC/$roomId',
  ]) {
    test('exact lookup preserves broadcast identity: $input', () async {
      final f = _Fixture();
      final r = (await f.site.searchRooms(input)).single;
      expect(r.roomId, roomId);
      expect(r.userId, anyOf(isNull, isEmpty));
      expect(r.data, isNull);
      expect(r.isLiveNow, true);
      expect(r.notice, contains('xiaohongshu_room_scope'));
      expect(r.onlineViewers, anyOf(isNull, isEmpty));
      expect(r.totalViewers, anyOf(isNull, isEmpty));
      expect(LiveRoom.audienceCapabilityFor(r.platform).supportsConcurrentOnline, false);
      expect(r.audienceValue(preferRealOnline: false, platformEnabled: false), isEmpty);
      expect(await f.site.searchRooms(input, page: 2), isEmpty);
      expect(f.paths, hasLength(1));
    });
  }
  test('keywords issue no request; room search keeps missing, access and unknown separate', () async {
    final f = _Fixture();
    expect(await f.site.searchRooms('主播昵称'), isEmpty);
    expect(f.paths, isEmpty);
    f.status = 404;
    expect(await f.site.searchRooms(roomId), isEmpty);
    f.status = 403;
    await expectLater(f.site.searchRooms(roomId), failure(XiaohongshuFailure.access));
    f.status = 200;
    f.room['status'] = 9;
    expect((await f.site.searchRooms(roomId)).single.effectiveLiveStatus, LiveStatus.unknown);
    await expectLater(
      f.site.getLiveStatus(roomId: roomId, platform: 'xiaohongshu'),
      failure(XiaohongshuFailure.schema),
    );
  });
  test('search page labels broadcast lookup separately from persistent channel lookup', () async {
    final c = search.SearchController();
    addTearDown(c.onClose);
    expect(c.capabilityText, contains('search_coverage_room_lookup'));
    c.index.value = c.sites.indexWhere((s) => s.id == 'xiaohongshu') + 1;
    expect(c.capabilityText, 'search_coverage_room_lookup');
    expect(c.canOpenWebSearch, false);
    expect(() => c.buildSearchUrl('xiaohongshu', 'nickname'), throwsStateError);
    c.searchController.text = 'fixture nickname';
    await c.doSearch();
    expect(c.results, isEmpty);
    expect(c.hasMore.value, false);
    expect(c.loading.value, false);
    expect(c.errorMessage.value, isEmpty);
  });
  test('one quality exposes HLS and three FLV lines to playback and real recorder resolution', () async {
    final f = _Fixture();
    final detail = await f.detail();
    final qualities = await f.site.getPlayQualites(detail: detail);
    expect(qualities, hasLength(1));
    expect(qualities.single.selectionId, 'h264:HD');
    expect(qualities.single.data, null);
    final r = await f.site.resolvePlayUrls(detail: detail, quality: qualities.single);
    expect(r.urls, hasLength(4));
    expect(r.appliedQualityData, 'h264:HD');
    expect(r.urls.first, endsWith('.m3u8'));
    final resolver = StreamResolverService(siteResolver: (_) => f.site);
    final first = await resolver.resolveStream(
      roomId: roomId,
      platform: 'xiaohongshu',
      preferredQuality: qualities.single.quality,
    );
    expect(first.url, r.urls.first);
    expect(first.candidateUrls, r.urls);
    expect(first.qualityCursorId, 'h264:HD');
    expect(first.refreshAt, null);
    expect(first.invalidAt, null);
    final second = await resolver.resolveStream(
      roomId: roomId,
      platform: 'xiaohongshu',
      preferredQuality: qualities.single.quality,
      previousQualityId: first.qualityCursorId,
      previousLineIndex: 0,
    );
    expect(second.lineIndex, 1);
    expect(second.url, r.urls[1]);
  });
  test('codec-qualified quality IDs survive reorder; recovery fetches fresh matching source', () async {
    final f = _Fixture();
    f.streams((c) {
      c['h265'] = [c['h264'][0]];
    });
    final detail = await f.detail();
    final qualities = await f.site.getPlayQualites(detail: detail);
    expect(qualities.map((q) => q.selectionId), ['h264:HD', 'h265:HD']);
    f.streams((c) {
      c['h264'] = (c['h264'] as List).reversed.toList();
      for (final row in c['h265']) {
        row['master_url'] += '?token=renewed';
      }
    });
    final result = await f.site.resolvePlayUrlsForRecovery(detail: detail, quality: qualities.last);
    expect(result.urls.single, endsWith('?token=renewed'));
    expect(result.appliedQualityData, 'h265:HD');
    expect(f.paths, hasLength(2));
  });
  test('recovery rejects ended/restricted/mismatched rooms and disappearing quality', () async {
    final f = _Fixture();
    final detail = await f.detail();
    final q = (await f.site.getPlayQualites(detail: detail)).single;
    f.room['roomId'] = '123';
    await expectLater(
      f.site.resolvePlayUrlsForRecovery(detail: detail, quality: q),
      failure(XiaohongshuFailure.identity),
    );
    f.room['roomId'] = roomId;
    f.room['monetizeType'] = 1;
    await expectLater(
      f.site.resolvePlayUrlsForRecovery(detail: detail, quality: q),
      failure(XiaohongshuFailure.access),
    );
    f.room['monetizeType'] = 0;
    f.offline();
    await expectLater(
      f.site.resolvePlayUrlsForRecovery(detail: detail, quality: q),
      failure(XiaohongshuFailure.notLive),
    );
    f.room['status'] = 2;
    f.state['liveStatus'] = 'success';
    f.streams((c) {
      for (final row in c['h264']) {
        row['quality_type'] = 'SD';
      }
    });
    await expectLater(
      f.site.resolvePlayUrlsForRecovery(detail: detail, quality: q),
      failure(XiaohongshuFailure.mediaUnavailable),
    );
  });
  test('media request validates room ownership and selection rather than trusting quality payload URLs', () async {
    final f = _Fixture();
    final detail = await f.detail();
    final q = (await f.site.getPlayQualites(detail: detail)).single;
    detail.roomId = '123';
    await expectLater(f.site.getPlayQualites(detail: detail), failure(XiaohongshuFailure.identity));
    detail.roomId = roomId;
    detail.platform = 'other';
    await expectLater(f.site.getPlayUrls(detail: detail, quality: q), failure(XiaohongshuFailure.identity));
    detail.platform = 'xiaohongshu';
    await expectLater(
      f.site.getPlayUrls(
        detail: detail,
        quality: LivePlayQuality(id: 'missing', quality: 'HD', data: ['https://evil.test/a.flv']),
      ),
      failure(XiaohongshuFailure.mediaUnavailable),
    );
  });
  test('offline recording is terminal notLive, while missing/restricted media is not false offline', () async {
    final f = _Fixture()..offline();
    final r = await f.detail();
    expect(await f.site.getPlayQualites(detail: r), isEmpty);
    final resolver = StreamResolverService(siteResolver: (_) => f.site);
    await expectLater(
      resolver.resolveStream(roomId: roomId, platform: 'xiaohongshu', preferredQuality: ''),
      throwsA(isA<StreamException>().having((e) => e.type, 'type', StreamErrorType.notLive)),
    );
    f.room['status'] = 2;
    f.state['liveStatus'] = 'success';
    f.room['monetizeType'] = 1;
    final metadata = await f.site.getRoomDetailForRefresh(roomId: roomId, platform: 'xiaohongshu');
    expect(metadata.isLiveNow, true);
    expect(metadata.notice, contains('xiaohongshu_restricted'));
    await expectLater(
      f.site.getRoomDetailForRecording(roomId: roomId, platform: 'xiaohongshu'),
      failure(XiaohongshuFailure.access),
    );
    f.room['monetizeType'] = 0;
    f.room.remove('pullConfig');
    await expectLater(
      f.site.getRoomDetailForRecording(roomId: roomId, platform: 'xiaohongshu'),
      failure(XiaohongshuFailure.mediaUnavailable),
    );
  });
  test('shared playback and recorder headers are identical, with no imported account cookie', () async {
    final headers = await PlaybackHeaderResolver.resolve(platform: 'xiaohongshu', roomId: roomId);
    expect(headers['referer'], 'https://www.xiaohongshu.com/');
    expect(headers.containsKey('cookie'), false);
    expect(await FFmpegHeaderFactory.build(platform: 'xiaohongshu', roomId: roomId), headers);
  });
  test('share import and external action use canonical room, not an imported URL', () async {
    final url = 'https://www.xiaohongshu.com/livestream/$roomId?share=fixture';
    expect(LiveUrlTool.containsSupportedLink(url), true);
    expect(await LiveUrlTool.parseLiveUrl('分享 $url。'), [roomId, 'xiaohongshu']);
    expect(
      RoomExternalOpener.resolve('xiaohongshu', LiveRoom(roomId: roomId, link: 'https://evil.test'))!.web,
      XiaohongshuLink.url(roomId),
    );
  });
  for (final url in [
    'https://www.xiaohongshu.com.evil.test/livestream/$roomId',
    'https://www.xiaohongshu.com/user/profile/$roomId',
    'https://www.xiaohongshu.com/livestream/1/../$roomId',
    'https://www.xiaohongshu.com/livestream/%35$roomId',
    'https://www.xiaohongshu.com:8787/livestream/$roomId',
    'https://user@www.xiaohongshu.com/livestream/$roomId',
    'https://xhslink.com/a/fixture',
  ]) {
    test('unverified/malformed link stays unrecognized: $url', () async {
      expect(XiaohongshuLink.parse(url), null);
      expect(LiveUrlTool.containsSupportedLink(url), false);
      expect(await LiveUrlTool.parseLiveUrl(url), isEmpty);
    });
  }
  for (final lang in ['zh', 'en']) {
    testWidgets('empty directory keeps actual $lang scope visible at narrow width', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = _Fixture();
      final c = _Directory(f.site);
      addTearDown(c.onClose);
      await c.loadData();
      final labels = jsonDecode(File('assets/translations/$lang.json').readAsStringSync()) as Map;
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: [Locale(lang)],
          startLocale: Locale(lang),
          fallbackLocale: Locale(lang),
          saveLocale: false,
          path: 'assets/translations',
          assetLoader: const _Loader(),
          child: Builder(
            builder: (context) => GetMaterialApp(
              locale: context.locale,
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              home: Scaffold(
                body: BasePageView<LiveDirectoryController, LiveRoom>(
                  controller: c,
                  showScrollToTopBtn: false,
                  emptyBuilder: (_) => const Text('EMPTY'),
                  contentBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(labels['xiaohongshu_directory_scope'] as String), findsOneWidget);
      expect(find.text('EMPTY'), findsOneWidget);
      expect(tester.takeException(), null);
      expect(f.paths, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
