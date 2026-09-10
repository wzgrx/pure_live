import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/niconico/niconico_api.dart';
import 'package:pure_live/core/site/niconico/niconico_input_recipe.dart';
import 'package:pure_live/core/site/niconico/niconico_quality_catalog.dart';
import 'package:pure_live/core/site/niconico/niconico_site.dart';
import 'package:pure_live/core/site/niconico/niconico_watch.dart';
import 'package:pure_live/model/live_play_quality.dart';

import 'niconico_hls_input_test.dart' as fixture;
import 'niconico_quality_catalog_test.dart' show page, kind;

class Catalog extends NiconicoQualityCatalog {
  int calls = 0;
  @override
  Future<List<NiconicoQuality>> load(String programId, {CancelToken? cancel}) async {
    calls++;
    return NiconicoQuality.parse(Uri.parse('https://fixture.example/master.m3u8'), fixture.officialMaster);
  }
}

void main() {
  late NiconicoSite site;
  late Catalog catalog;
  late Map<String, dynamic> data;
  int requests = 0;
  int http = 200;
  setUp(() {
    requests = 0;
    http = 200;
    data = fixture.fixture('live');
    catalog = Catalog();
    site = NiconicoSite(
      api: NiconicoApi(
        request: (_, _) async {
          requests++;
          return (status: http, body: page(data));
        },
      ),
      catalog: catalog,
    );
  });
  Future<LiveRoom> detail() => site.getRoomDetail(roomId: 'lv100', platform: 'niconico');
  test('room metadata is refreshable without acquiring a seat or persisting bootstrap', () async {
    final room = await detail();
    expect(room.roomId, 'lv100');
    expect(room.isLiveNow, isTrue);
    expect(room.totalViewers, '25');
    expect(room.onlineViewers, isEmpty);
    expect(room.audienceMetricType, AudienceMetricType.totalViewers);
    expect(room.link, 'https://live.nicovideo.jp/watch/lv100');
    expect(jsonEncode(room.toJson()), isNot(contains('audience_token')));
    expect(jsonEncode(room.toJson()), isNot(contains('webSocket')));
    expect(catalog.calls, 0);
    expect(requests, 1);
    await site.getRoomDetailForRefresh(roomId: 'lv100', platform: 'niconico');
    expect(catalog.calls, 0);
  });
  test('strict detail preserves metadata failures instead of false offline', () async {
    http = 503;
    await expectLater(
      site.getRoomDetailForRecording(roomId: 'lv100', platform: 'niconico'),
      kind(NiconicoFailure.service),
    );
  });
  for (final status in ['RELEASED', 'ENDED']) {
    test('$status stays non-live and does not discover media qualities', () async {
      data['program']['status'] = status;
      final room = await detail();
      expect(room.isExplicitlyOfflineNow, isTrue);
      expect(await site.getPlayQualites(detail: room), isEmpty);
      expect(catalog.calls, 0);
    });
  }
  test('region restrictions preserve live broadcast status and an access notice', () async {
    data = fixture.fixture('region');
    final room = await detail();
    expect(room.isLiveNow, isTrue);
    expect(room.notice, isNotEmpty);
  });
  test('discovered public selection flows to owned playback, recording cursor and recovery', () async {
    final room = await detail();
    final choices = await site.getPlayQualites(detail: room);
    expect(choices.map((e) => e.selectionId), ['800x450@1080800', '512x288@412800', '512x288@201600']);
    expect(jsonEncode(choices.map((e) => e.toString()).toList()), isNot(contains('https://')));
    final resolved = await site.resolvePlayUrls(detail: room, quality: choices.last);
    final recipe = resolved.inputRecipe! as NiconicoInputRecipe;
    expect(recipe.programId, 'lv100');
    expect(recipe.resolution, '512x288');
    expect(recipe.bandwidth, 201600);
    expect(resolved.urls, isEmpty);
    expect(resolved.hasSources, isTrue);
    expect(resolved.lineCount, 1);
    expect(resolved.appliedQualityData, choices.last.selectionId);
    final recovery = await site.resolvePlayUrlsForRecovery(detail: room, quality: choices.last);
    expect(recovery.inputRecipe!.identity, recipe.identity);
    expect(await site.getPlayUrls(detail: room, quality: choices.last), isEmpty);
    expect((await site.resolvePlayUrlAtRaw(detail: room, quality: choices.last, lineIndex: 1)).hasSources, isFalse);
    expect(catalog.calls, 1);
    expect(requests, 1);
  });
  test('quality selected in a different program is not accepted', () async {
    final room = await detail();
    final choices = await site.getPlayQualites(detail: room);
    await expectLater(
      site.resolvePlayUrls(
        detail: room.copyWith(roomId: 'lv101'),
        quality: choices.first,
      ),
      kind(NiconicoFailure.identity),
    );
    await expectLater(
      site.resolvePlayUrls(
        detail: room,
        quality: LivePlayQuality(quality: 'forged', id: 'wrong', data: choices.first.data),
      ),
      kind(NiconicoFailure.identity),
    );
  });
  test('foreign platform and malformed ID fail before metadata', () async {
    await expectLater(site.getRoomDetail(roomId: 'lv100', platform: 'bilibili'), kind(NiconicoFailure.identity));
    await expectLater(site.getRoomDetail(roomId: 'lv0', platform: 'niconico'), kind(NiconicoFailure.identity));
    expect(requests, 0);
  });
  test('observed optional artwork remains public and reaches room cards', () async {
    data['program']['thumbnail'] = {
      'small': 'https://nicolive.cdn.nimg.jp/small.jpg',
      'huge': {'s640x360': 'https://listing-thumbnail.live.nicovideo.jp?image=fixture&w=640'},
    };
    data['program']['supplier']['icons'] = {'uri150x150': 'https://secure-dcdn.cdn.nimg.jp/avatar.jpg'};
    final room = await detail();
    expect(room.cover, contains('w=640'));
    expect(room.avatar, endsWith('/avatar.jpg'));
  });

  test('live screenshot is preferred over an available static placeholder', () async {
    data['program']['thumbnail'] = {'small': 'https://secure-dcdn.cdn.nimg.jp/404.jpg'};
    data['program']['screenshot'] = {
      'urlSet': {'middle': 'https://asset2.dlive.nicovideo.jp/fixture/thumbnail-640x360/screenshot.jpg'},
    };
    final room = await detail();
    expect(room.cover, contains('/thumbnail-640x360/screenshot.jpg'));
  });
  test('invalid screenshot falls back to public thumbnail', () async {
    data['program']['thumbnail'] = {'large': 'https://nicolive.cdn.nimg.jp/cover.jpg'};
    data['program']['screenshot'] = {
      'urlSet': {'middle': 'https://unrelated.example/image.jpg'},
    };
    expect((await detail()).cover, 'https://nicolive.cdn.nimg.jp/cover.jpg');
  });
  for (final bad in [
    null,
    42,
    'http://cdn.nimg.jp/a',
    'https://cdn.nimg.jp.evil.example/a',
    'https://name@cdn.nimg.jp/a',
    'https://cdn.nimg.jp:443/a',
    'https://cdn.nimg.jp/a#frag',
  ]) {
    test('optional malformed artwork $bad does not discard valid live metadata', () async {
      data['program']['thumbnail'] = {'large': bad};
      data['program']['supplier']['icons'] = {'uri150x150': bad};
      final room = await detail();
      expect(room.isLiveNow, isTrue);
      expect(room.cover, isEmpty);
      expect(room.avatar, isEmpty);
    });
  }
}
