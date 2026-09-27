// Legacy expected values for the recorded Bilibili samples (spec/sites/bilibili.md §11).
//
// second/getList has no page samples: the legacy guest request (valid WBI
// signature, x-rid-result 0) was answered with -352 every time on 2026-09-27
// (S02-signed-risk352).
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/services/settings/bilibili_account_service.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/core/site/bilibili/bilibili_site.dart';
import 'package:pure_live/core/site/v4_bridge/v4_bridge.dart';
import 'package:pure_live/modules/account/bilibili/qr_login_controller.dart';

import 'bilibili_support.dart';
import 'support.dart';

void main() {
  setUpAll(setUpBilibiliSettings);
  // These tests freeze the legacy parsers; keep lists off the v4 bridge.
  setUpAll(() => V4Bridge.platformsOverride = const {});
  tearDownAll(() => V4Bridge.platformsOverride = null);

  test('S01-guest', () async {
    final fixture = bilibiliSample('S01-guest');
    replayBilibili([fixture]);
    final categories = await BiliBiliSite().getCategores(1, 30);
    expectRecorded(fixture, 'BiliBiliSite.getCategores', [
      for (final category in categories)
        {
          'id': category.id,
          'name': category.name,
          'children': [for (final area in category.children) area.toJson()],
        },
    ]);
  });

  group('S02 second/getList', () {
    // S02-risk352 was requested without wts/w_rid; S02-signed-risk352 is the
    // legacy signed request (2/86 page 1), rejected by risk control anyway.
    for (final sample in ['S02-risk352', 'S02-signed-risk352']) {
      test(sample, () async {
        final fixture = bilibiliSample(sample);
        replayBilibili([fixture]);
        final query = fixture.url.queryParameters;
        final area = LiveArea(platform: 'bilibili', areaType: query['parent_area_id'], areaId: query['area_id']);
        final result = await settle(
          () async => [
            for (final room in await BiliBiliSite().getCategoryRooms(area, page: int.parse(query['page']!)))
              roomProjection(room),
          ],
        );
        expectRecorded(fixture, 'BiliBiliSite.getCategoryRooms', result);
      });
    }
  });

  group('S03/S04 recommend', () {
    for (final sample in ['S03-page1', 'S03-out-of-range', 'S04-page1']) {
      test(sample, () async {
        final fixture = bilibiliSample(sample);
        final result = await settle(
          () => [for (final room in BiliBiliSite.parseRecommendRooms(fixture.json)) roomProjection(room)],
        );
        expectRecorded(fixture, 'BiliBiliSite.parseRecommendRooms', result);
      });
    }
  });

  group('S05 search', () {
    for (final sample in ['S05-live-results', 'S05-no-results', 'S05-out-of-range', 'S05-no-buvid3']) {
      test(sample, () async {
        final fixture = bilibiliSample(sample);
        replayBilibili([fixture]);
        final query = fixture.url.queryParameters;
        final result = await settle(
          () async => [
            for (final room in await BiliBiliSite().searchRooms(
              query['keyword']!,
              page: int.parse(query['page']!),
              pageSize: int.parse(query['page_size']!),
            ))
              roomProjection(room),
          ],
        );
        expectRecorded(fixture, 'BiliBiliSite.searchRooms', result);
      });
    }
  });

  group('S06 getInfoByRoom', () {
    for (final sample in [
      'S06-live',
      'S06-offline',
      'S06-replay',
      'S06-short-id',
      'S06-short-id-long',
      'S06-not-found',
    ]) {
      test(sample, () async {
        final fixture = bilibiliSample(sample);
        replayBilibili([fixture]);
        final roomId = fixture.url.queryParameters['room_id']!;
        expectRecorded(fixture, 'BiliBiliSite.parseRoomInfoResponse + BiliBiliSite.getRoomDetailForRefresh', {
          // The long id the legacy code uses for danmaku (S:634-635).
          'parseRoomInfoResponse.room_info.room_id': await settle(
            () => (BiliBiliSite.parseRoomInfoResponse(fixture.json)['room_info'] as Map)['room_id'],
          ),
          'getRoomDetailForRefresh': await settle(
            () async =>
                roomProjection(await BiliBiliSite().getRoomDetailForRefresh(platform: 'bilibili', roomId: roomId)),
          ),
        });
      });
    }
  });

  test('S06-risk352', () async {
    // Recorded without wts/w_rid (see the header note).
    final fixture = bilibiliSample('S06-risk352');
    resetBilibiliStatics();
    final adapter = replayBilibili([fixture]);
    final roomId = fixture.url.queryParameters['room_id']!;
    final detail = await settle(
      () async => roomProjection(await BiliBiliSite().getRoomDetailForRefresh(platform: 'bilibili', roomId: roomId)),
    );
    expectRecorded(fixture, 'BiliBiliSite.parseRoomInfoResponse + BiliBiliSite.getRoomDetailForRefresh', {
      'parseRoomInfoResponse': await settle(() => BiliBiliSite.parseRoomInfoResponse(fixture.json)),
      'getRoomDetailForRefresh': detail,
      // One retry with a forced WBI refresh (S:400-418).
      'requests': requestCounts(adapter),
    });
  });

  group('S07 getRoomPlayInfo', () {
    for (final sample in [
      'S07-guest-qn0',
      'S07-guest-qn10000',
      'S07-hevc-qn10000',
      'S07-offline',
      'S07-replay',
      'S07-short-id',
      'S07-short-id-long',
    ]) {
      test(sample, () async {
        final fixture = bilibiliSample(sample);
        final qn = int.parse(fixture.url.queryParameters['qn']!);
        expectRecorded(
          fixture,
          'BiliBiliSite.parsePlayQualities (LiveQualityLabel.normalize) + BiliBiliSite.parsePlayUrlResolution',
          {
            'requestedQn': qn,
            'parsePlayQualities': await settle(
              () => [for (final quality in BiliBiliSite.parsePlayQualities(fixture.json)) qualityProjection(quality)],
            ),
            'parsePlayUrlResolution': await settle(
              () => resolutionProjection(BiliBiliSite.parsePlayUrlResolution(fixture.json, requestedQualityData: qn)),
            ),
          },
        );
      });
    }
  });

  test('S09-guest', () async {
    // Room entry: getInfoByRoom (S06-live) plus one danmaku discovery.
    final fixture = bilibiliSample('S09-guest');
    replayBilibili([bilibiliSample('S06-live'), fixture]);
    final roomId = fixture.url.queryParameters['id']!;
    final room = await BiliBiliSite().getRoomDetail(platform: 'bilibili', roomId: roomId);
    expectRecorded(fixture, 'BiliBiliSite.getRoomDetail (_discoverDanmaku)', {
      'room': roomProjection(room),
      'danmakuArgs': danmakuArgsProjection(room.danmakuData),
    });
  });

  test('S10-guest', () async {
    final fixture = bilibiliSample('S10-guest');
    replay([fixture]);
    resetBilibiliStatics();
    final site = BiliBiliSite();
    final buvid = await site.getBuvid();
    final header = await site.getHeader();
    expectRecorded(fixture, 'BiliBiliSite.getBuvid + BiliBiliSite.getHeader', {'getBuvid': buvid, 'getHeader': header});
  });

  test('S11-guest', () async {
    final fixture = bilibiliSample('S11-guest');
    replayBilibili([]);
    resetBilibiliStatics();
    final site = BiliBiliSite();
    final (imgKey, subKey) = await site.getWbiKeys(forceRefresh: true);
    expectRecorded(fixture, 'BiliBiliSite.getWbiKeys + BiliBiliSite.getMixinKey', {
      'imgKey': imgKey,
      'subKey': subKey,
      'mixinKey': site.getMixinKey(imgKey + subKey),
    });
  });

  test('S12-guest', () async {
    final fixture = bilibiliSample('S12-guest');
    replayBilibili([]);
    expectRecorded(fixture, 'BiliBiliSite.getAccessId', {'getAccessId': await BiliBiliSite().getAccessId()});
  });

  group('S15 QR login', () {
    BiliBiliQRLoginController controller(List<String> notices) {
      final controller = BiliBiliQRLoginController(
        notice: notices.add,
        completeLogin: () {},
        // Polls are driven by the test, never by the timer.
        pollInterval: const Duration(days: 1),
      );
      addTearDown(controller.onClose);
      return controller;
    }

    Map<String, Object?> state(BiliBiliQRLoginController controller, List<String> notices) => {
      'status': controller.qrStatus.value.name,
      'qrcodeKey': controller.qrcodeKey,
      'qrcodeUrl': controller.qrcodeUrl.value,
      'errorMessageKey': controller.errorMessageKey.value,
      'notices': notices,
    };

    test('S15-generate', () async {
      final fixture = bilibiliSample('S15-generate');
      replay([fixture]);
      final notices = <String>[];
      final qr = controller(notices);
      final loaded = await qr.loadQRCode();
      expectRecorded(fixture, 'BiliBiliQRLoginController.loadQRCode', {'loaded': loaded, ...state(qr, notices)});
    });

    for (final sample in ['S15-poll-86101', 'S15-poll-86038']) {
      test(sample, () async {
        final fixture = bilibiliSample(sample);
        replay([bilibiliSample('S15-generate'), fixture]);
        final notices = <String>[];
        final qr = controller(notices);
        await qr.loadQRCode();
        await qr.pollQRStatus();
        expectRecorded(fixture, 'BiliBiliQRLoginController.loadQRCode + pollQRStatus', state(qr, notices));
      });
    }
  });

  test('S16-no-cookie', () async {
    // Recorded without a Cookie; an expired login gets the same -101 answer.
    final fixture = bilibiliSample('S16-no-cookie');
    replay([fixture]);
    final cookies = SettingsService.to.cookieManager;
    cookies.bilibiliCookie.value = 'SESSDATA=fixture-expired';
    addTearDown(() => cookies.bilibiliCookie.value = '');
    final notices = <String>[];
    var browserCookieClears = 0;
    final service = BiliBiliAccountService(
      browserCookieClearer: () async => browserCookieClears++,
      notice: notices.add,
      initialLoadDelay: Duration.zero,
    );
    final loaded = await service.loadUserInfo();
    expectRecorded(fixture, 'BiliBiliAccountService.loadUserInfo', {
      'loaded': loaded,
      'logined': service.logined.value,
      'storedCookieAfter': cookies.bilibiliCookie.value,
      'browserCookieClears': browserCookieClears,
      'notices': notices,
    });
  });
}
