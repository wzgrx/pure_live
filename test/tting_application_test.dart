import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/base/base_page_scroll_bone.dart';
import 'package:pure_live/common/base/live_directory_controller.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/common/utils/live_url_tool.dart';
import 'package:pure_live/core/interface/live_directory.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/tting/tting_api.dart';
import 'package:pure_live/core/site/tting/tting_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/area_rooms/area_rooms_binding.dart';
import 'package:pure_live/modules/live_play/services/room_external_opener.dart';
import 'package:pure_live/modules/multiview/danmaku/multiview_danmaku_session.dart';
import 'package:pure_live/modules/popular/popular_controller.dart';
import 'package:pure_live/modules/search/search_capability.dart';
import 'package:pure_live/modules/search/search_controller.dart';
import 'package:pure_live/player/core/playback_header_resolver.dart';
import 'package:pure_live/recorder/services/ffmpeg_header_factory.dart';
import 'package:pure_live/recorder/services/stream_resolver_service.dart';

Map<String, dynamic> _json(String name) =>
    jsonDecode(File('test/fixtures/tting/$name.json').readAsStringSync()) as Map<String, dynamic>;
({int status, String body}) _ok(Object value) => (status: 200, body: jsonEncode(value));
Matcher _failure(TtingFailure kind) => throwsA(isA<TtingException>().having((e) => e.kind, 'kind', kind));

class _Fixture {
  DateTime now = DateTime.fromMillisecondsSinceEpoch(1900000000000, isUtc: true);
  String generation = 'first';
  int expiry = 2000000000;
  String family = 'ncp';
  int owner = 202;
  bool live = true;
  bool restricted = false;
  int? status;
  final paths = <String>[];
  List<int> resolutions = [1080, 720, 480, 0];
  late final site = TtingSite(
    api: TtingApi(
      now: () => now,
      request: (uri, cancel) async {
        paths.add(uri.path);
        if (status != null) return (status: status!, body: '');
        if (uri.path.endsWith('live-list-main')) return _ok(_json('directory'));
        if (uri.path.endsWith('/profile')) {
          final profile = _json('profile');
          profile['isInLive'] = live ? 1 : 0;
          profile['owner']['id'] = owner;
          profile['barrier']['isLocked'] = restricted;
          return _ok(profile);
        }
        expect(uri.path, '/api/channels/101/stream');
        final stream = _json('stream');
        stream['owner']['id'] = owner;
        stream['sourceType'] = family;
        stream['sources'] = [
          for (final raw in stream['sources'] as List)
            if (resolutions.contains(raw['resolution']))
              {
                ...raw as Map<String, dynamic>,
                'format': family,
                'url': (raw['url'] as String)
                    .replaceAll('exp=2000000000', 'exp=$expiry')
                    .replaceAll('hmac=fixture', 'hmac=$generation'),
              },
        ];
        return _ok(stream);
      },
    ),
    now: () => now,
  );
  Future<LiveRoom> room() => site.getRoomDetail(roomId: '101', platform: 'ttinglive');
}

class _Directory extends LiveDirectoryController {
  _Directory(LiveSiteDirectoryPager source) : super(directory: source);
  @override
  bool get usesDesktopPagination => true;
  @override
  Future<bool> checkNetworkBeforeRequest() async => true;
  @override
  void handleError(Object error, {bool showPageError = false}) {
    errorMsg.value = error.toString();
    pageError.value = true;
  }
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

  test('registration enters popular and category factories without claiming chat or full search', () async {
    final site = Sites.of(' TTINGLIVE ');
    expect(site.liveSite, isA<TtingSite>());
    expect(Sites.supportSites.where((s) => s.id == 'ttinglive'), hasLength(1));
    final capability = LiveSearchCapabilities.forPlatform(site.id);
    expect(capability.coverage, NativeSearchCoverage.channelLookup);
    expect(capability.mayIncludeOffline, isTrue);
    expect(capability.supportsPagination, isFalse);
    expect(capability.supportsWebSearch, isFalse);
    expect(MultiviewDanmakuSession.isSupportedPlatform(site.id), isFalse);
    final popular = PopularController();
    addTearDown(popular.onClose);
    popular.initControllers([site]);
    expect(Get.find<BasePageScrollAndStateBone<LiveRoom>>(tag: site.id), isA<LiveDirectoryController>());
    final category = (await site.liveSite.getCategores(1, 30)).single.children.single;
    final controller = AreaRoomsBinding.createController(site, category);
    addTearDown(controller.onClose);
    expect(controller, isA<LiveDirectoryController>());
    expect((controller as LiveDirectoryController).pageNotice, 'tting_directory_scope');
  });
  test('finite homepage snapshot stops paging and exposes list-only audience without inventing owner', () async {
    final fixture = _Fixture();
    final controller = _Directory(fixture.site);
    addTearDown(controller.onClose);
    await controller.loadData();
    await controller.loadMoreData();
    expect(fixture.paths, ['/api/channels/live-list-main']);
    expect(controller.list.single.roomId, '101');
    expect(controller.list.single.userId, anyOf(isNull, isEmpty));
    expect(controller.list.single.onlineViewers, '16');
    expect(controller.list.single.totalViewers, anyOf(isNull, isEmpty));
    expect(controller.canLoadMore.value, isFalse);
    expect((await fixture.site.getDirectoryPage(page: 2)).rooms, isEmpty);
    expect(fixture.paths, hasLength(1));
    expect(LiveRoom.audienceCapabilityFor('ttinglive').onlineAvailableInRoomLists, isTrue);
  });
  test('directory rejects foreign category and cancels the owned transport', () async {
    final fixture = _Fixture();
    await expectLater(
      fixture.site.getDirectoryPage(
        category: LiveArea(platform: 'other', areaId: 'live', areaType: 'directory'),
      ),
      _failure(TtingFailure.schema),
    );
    expect(fixture.paths, isEmpty);
    final pending = Completer<({int status, String body})>();
    final started = Completer<void>();
    CancelToken? owned;
    final site = TtingSite(
      api: TtingApi(
        request: (_, token) {
          owned = token;
          started.complete();
          return pending.future;
        },
      ),
    );
    final cancel = CancelToken();
    final future = site.getDirectoryPage(cancel: cancel);
    final checked = expectLater(future, _failure(TtingFailure.cancelled));
    await started.future;
    cancel.cancel();
    await checked;
    expect(owned!.isCancelled, isTrue);
    pending.completeError(const SocketException('late fixture error'));
    await Future<void>.delayed(Duration.zero);
  });
  test('favorite metadata refresh and channel lookup avoid signed-stream requests', () async {
    final fixture = _Fixture();
    final room = await fixture.site.getRoomDetailForRefresh(roomId: '101', platform: 'ttinglive');
    expect(room.userId, '202');
    expect(room.data, isNull);
    expect(room.isLiveNow, isTrue);
    expect(room.onlineViewers, anyOf(isNull, isEmpty));
    for (final input in ['101', 'https://www.ttinglive.com/channels/101/live']) {
      expect((await fixture.site.searchRooms(input)).single.roomId, '101');
    }
    expect(await fixture.site.searchRooms('fixture nickname'), isEmpty);
    expect(await fixture.site.searchRooms('101', page: 2), isEmpty);
    expect(fixture.paths, List.filled(3, '/api/channels/101/profile'));
    fixture.live = false;
    expect((await fixture.site.searchRooms('101')).single.isExplicitlyOfflineNow, isTrue);
  });
  test('lookup distinguishes missing channels from access and transport failures', () async {
    final fixture = _Fixture()..status = 404;
    expect(await fixture.site.searchRooms('101'), isEmpty);
    fixture.status = 403;
    await expectLater(fixture.site.searchRooms('101'), _failure(TtingFailure.access));
    fixture.status = 503;
    await expectLater(
      fixture.site.getRoomDetailForRefresh(roomId: '101', platform: 'ttinglive'),
      _failure(TtingFailure.service),
    );
  });
  test(
    'real search page explains exact lookup in selected and aggregate tabs; keywords do not issue requests',
    () async {
      final controller = SearchController();
      addTearDown(controller.onClose);
      expect(controller.capabilityText, contains('search_coverage_channel_lookup'));
      controller.index.value = controller.sites.indexWhere((s) => s.id == 'ttinglive') + 1;
      expect(controller.index.value, greaterThan(0));
      expect(controller.capabilityText, 'search_coverage_channel_lookup');
      expect(controller.canOpenWebSearch, isFalse);
      expect(() => controller.buildSearchUrl('ttinglive', 'fixture'), throwsStateError);
      controller.searchController.text = 'fixture nickname';
      await controller.doSearch();
      expect(controller.results, isEmpty);
      expect(controller.errorMessage.value, isEmpty);
      expect(controller.loading.value, isFalse);
      expect(controller.hasMore.value, isFalse);
    },
  );
  for (final family in ['ncp', 'ncp_llh']) {
    test('$family playback and recorder preserve selected source policy and expiry', () async {
      final fixture = _Fixture()..family = family;
      final room = await fixture.room();
      final qualities = await fixture.site.getPlayQualites(detail: room);
      expect(qualities.map((q) => q.selectionId), [1080, 720, 480, 0]);
      expect(qualities.every((q) => q.data == null), isTrue);
      expect(qualities.first.quality, contains(family == 'ncp' ? ' · HLS' : ' · LL-HLS'));
      final quality = qualities[1];
      final result = await fixture.site.resolvePlayUrls(detail: room, quality: quality);
      final source = Uri.parse(result.urls.single);
      final policy = result.sourceQueryPolicies[result.urls.single]!;
      expect(policy.matchesSource(source), isTrue);
      expect(policy.apply(source.resolve('segment.m4s')).queryParameters['token'], source.queryParameters['token']);
      expect(policy.apply(Uri.parse('https://elsewhere.example/segment.m4s')).queryParameters, isEmpty);
      final recorder = StreamResolverService(siteResolver: (_) => fixture.site);
      // Recorder preferences are display labels/five-level preferences, not
      // platform IDs. Its continuation cursor is the stable selection ID.
      final recorded = await recorder.resolveStream(
        roomId: '101',
        platform: 'ttinglive',
        preferredQuality: quality.quality,
      );
      expect(recorded.quality.selectionId, 720);
      expect(recorded.sourceQueryPolicy!.matchesSource(Uri.parse(recorded.url)), isTrue);
      expect(recorded.invalidAt, DateTime.fromMillisecondsSinceEpoch(2000000000000, isUtc: true));
      expect(recorded.refreshAt, recorded.invalidAt!.subtract(const Duration(seconds: 30)));
      fixture.generation = 'renewed';
      fixture.family = family == 'ncp' ? 'ncp_llh' : 'ncp';
      final renewed = await recorder.resolveStream(
        roomId: '101',
        platform: 'ttinglive',
        preferredQuality: quality.quality,
        previousQualityId: recorded.qualityCursorId,
        previousLineIndex: recorded.lineIndex,
        renewCurrent: true,
      );
      expect(renewed.quality.selectionId, 720);
      expect(renewed.url, contains('hmac=renewed'));
      expect(renewed.sourceQueryPolicy!.matchesSource(Uri.parse(recorded.url)), isFalse);
      final forged = LivePlayQuality(id: 720, quality: 'fake', data: ['https://elsewhere.example/a']);
      expect(await fixture.site.getPlayUrls(detail: room, quality: forged), result.urls);
    });
  }
  test('recovery refresh replaces token and can change family without changing quality identity', () async {
    final fixture = _Fixture();
    final room = await fixture.room();
    final quality = (await fixture.site.getPlayQualites(detail: room))[1];
    final first = await fixture.site.resolvePlayUrls(detail: room, quality: quality);
    fixture.generation = 'next';
    fixture.family = 'ncp_llh';
    fixture.expiry = 2000000600;
    final next = await fixture.site.resolvePlayUrlsForRecovery(detail: room, quality: quality);
    expect(next.urls.single, isNot(first.urls.single));
    expect(next.appliedQualityData, 720);
    expect(next.sourceQueryPolicies.keys, next.urls);
    expect(next.sourceQueryPolicies[next.urls.single]!.matchesSource(Uri.parse(first.urls.single)), isFalse);
    expect(fixture.paths, hasLength(4));
  });
  test('expired normal resolution reacquires a fresh stream; active snapshots do not refetch', () async {
    final fixture = _Fixture();
    final room = await fixture.room();
    final quality = (await fixture.site.getPlayQualites(detail: room)).first;
    await fixture.site.resolvePlayUrls(detail: room, quality: quality);
    expect(fixture.paths, hasLength(2));
    fixture.now = DateTime.fromMillisecondsSinceEpoch(2000000000000, isUtc: true);
    fixture.expiry = 2000000600;
    fixture.generation = 'fresh';
    final result = await fixture.site.resolvePlayUrls(detail: room, quality: quality);
    expect(result.urls.single, contains('hmac=fresh'));
    expect(fixture.paths, hasLength(4));
  });
  test('renewal rejects owner reassignment, disappearing quality and offline transition', () async {
    final fixture = _Fixture();
    final room = await fixture.room();
    final quality = (await fixture.site.getPlayQualites(detail: room)).first;
    fixture.owner = 999;
    await expectLater(
      fixture.site.resolvePlayUrlsForRecovery(detail: room, quality: quality),
      _failure(TtingFailure.identity),
    );
    fixture.owner = 202;
    fixture.resolutions = [720];
    await expectLater(
      fixture.site.resolvePlayUrlsForRecovery(detail: room, quality: quality),
      _failure(TtingFailure.mediaUnavailable),
    );
    fixture.live = false;
    await expectLater(
      fixture.site.resolvePlayUrlsForRecovery(detail: room, quality: quality),
      _failure(TtingFailure.notLive),
    );
  });
  test('offline skips signed stream while restricted live remains an error rather than false offline', () async {
    final fixture = _Fixture()..live = false;
    final room = await fixture.room();
    expect(room.isExplicitlyOfflineNow, isTrue);
    expect(await fixture.site.getPlayQualites(detail: room), isEmpty);
    expect(fixture.paths, ['/api/channels/101/profile']);
    fixture.live = true;
    fixture.restricted = true;
    final metadata = await fixture.site.getRoomDetailForRefresh(roomId: '101', platform: 'ttinglive');
    expect(metadata.isLiveNow, isTrue);
    expect(metadata.notice, 'tting_restricted');
    await expectLater(fixture.room(), _failure(TtingFailure.restricted));
    expect(fixture.paths.every((p) => p.endsWith('/profile')), isTrue);
  });
  test('wrong platform and malformed channel never send a request', () async {
    final fixture = _Fixture();
    for (final id in ['0', '101/stream', '-1', '9007199254740992']) {
      await expectLater(fixture.site.getRoomDetail(roomId: id, platform: 'ttinglive'), _failure(TtingFailure.identity));
    }
    await expectLater(fixture.site.getRoomDetail(roomId: '101', platform: 'other'), _failure(TtingFailure.identity));
    expect(fixture.paths, isEmpty);
  });
  test('media headers match recorder headers and exclude API routing header', () async {
    final headers = await PlaybackHeaderResolver.resolve(platform: 'ttinglive', roomId: '101');
    expect(headers, {
      'referer': 'https://www.flextv.co.kr/',
      'origin': 'https://www.flextv.co.kr',
      'user-agent': 'Mozilla/5.0',
    });
    expect(await FFmpegHeaderFactory.build(platform: 'ttinglive', roomId: '101'), headers);
    expect(headers.containsKey('x-site-code'), isFalse);
  });
  test('share and external actions canonicalize channel links without trusting an imported room URL', () async {
    for (final host in ['www.flextv.co.kr', 'ttinglive.com']) {
      final url = 'https://$host/channels/101/live?share=fixture';
      expect(LiveUrlTool.containsSupportedLink(url), isTrue);
      expect(await LiveUrlTool.parseLiveUrl('分享 $url'), ['101', 'ttinglive']);
    }
    for (final url in [
      'https://evil.flextv.co.kr/channels/101/live',
      'https://www.flextv.co.kr/channels/101/../102/live',
      'https://www.flextv.co.kr:8787/channels/101/live',
    ]) {
      expect(LiveUrlTool.containsSupportedLink(url), isFalse);
      expect(await LiveUrlTool.parseLiveUrl(url), isEmpty);
    }
    expect(
      RoomExternalOpener.resolve('ttinglive', LiveRoom(roomId: '101', link: 'https://elsewhere.example'))!.web,
      'https://www.flextv.co.kr/channels/101/live',
    );
    expect(RoomExternalOpener.resolve('ttinglive', LiveRoom(roomId: 'invalid')), isNull);
  });
  test('lease metadata rejects foreign authority, bad port and duplicate expiration fields', () async {
    final fixture = _Fixture();
    final room = await fixture.room();
    final quality = (await fixture.site.getPlayQualites(detail: room)).first;
    final url = (await fixture.site.getPlayUrls(detail: room, quality: quality)).single;
    for (final invalid in [
      url.replaceAll('fixture.edge.naverncp.com', 'elsewhere.example'),
      url.replaceAll('.com/', '.com:8080/'),
      url.replaceAll('~hmac', '~exp=2000000001~hmac'),
      '$url#fragment',
    ]) {
      expect(fixture.site.getPlayUrlInvalidAt(invalid), isNull);
    }
  });
}
