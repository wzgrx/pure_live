import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/multiview/logic/multiview_controller.dart';

import '../../support.dart';
import '../live_play/live_play_support.dart';
import 'multiview_support.dart';

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  setUpAll(loadStrings);

  test('a picked room plays, becomes the sound and the others stay silent', () async {
    final store = await memoryStore();
    await store.settings.set(Settings.roomVolumes, {roomVolumeKey(SiteIds.bilibili, '2'): 0.4});
    await store.settings.set(Settings.preferResolution, '超清');
    final site = RoomsSite();
    final controller = multiviewController(store, site);
    await controller.start();

    final assigning = controller.assign(0, pickRoom('1'));
    expect(controller.cells[0].stage, CellStage.resolving);
    await assigning;
    final first = controller.cells[0];
    expect(first.stage, CellStage.playing);
    // The detail replaces the card (fresh danmaku data, state).
    expect(first.room!.danmakuData, 'args-1');
    // The live room's quality preference (3.x's multi-view took the best).
    expect(first.qualities[first.qualityIndex].quality, '超清');
    expect(controller.audioIndex, 0);
    expect(first.playback.volume, 1);

    await controller.assign(1, pickRoom('2'));
    expect(controller.audioIndex, 1);
    expect(controller.cells[1].playback.volume, 0.4);
    await _settle();
    expect(first.playback.volume, 0);

    controller.toggleMuteAll();
    await _settle();
    expect(controller.cells[1].playback.volume, 0);
    controller.toggleMuteAll();
    await controller.setVolume(1, 0.7, save: true);
    expect(controller.cells[1].playback.volume, 0.7);
    expect(store.settings.get(Settings.roomVolumes)[roomVolumeKey(SiteIds.bilibili, '2')], 0.7);

    expect(controller.indexOfRoom(pickRoom('2')), 1);
    controller.dispose();
    await store.close();
  });

  test('C01.4: a cell names a served quality outside the list by the platform and says nothing on entry', () async {
    final store = await memoryStore();
    final toasts = <String>[];
    final site = _ServedSite()..qualities = const [LivePlayQuality(quality: '原画', id: 10000)];
    final controller = multiviewController(store, site, toasts: toasts);
    await controller.start();
    await controller.assign(0, pickRoom('1'));
    final cell = controller.cells[0];
    expect(cell.stage, CellStage.playing);
    final shown = cell.qualities[cell.qualityIndex];
    expect((shown.quality, shown.id, shown.isPlaybackUnconfirmed), ('超清', 250, false));
    expect(toasts, isEmpty, reason: 'four cells entering would say it four times');
    controller.dispose();
    await store.close();
  });

  test('G01.3: with 优先 H.264 a cell skips the HEVC quality named like the preference', () async {
    final store = await memoryStore();
    final site = RoomsSite()
      ..qualities = const [
        LivePlayQuality(quality: 'FLV', id: 'flv', codec: 'avc'),
        LivePlayQuality(quality: '原画', id: 'origin', sort: 1, codec: 'hevc'),
      ];
    final controller = multiviewController(store, site);
    await controller.start();
    await controller.assign(0, pickRoom('1'));
    expect(controller.cells[0].qualityIndex, 0);
    await store.settings.set(Settings.preferH264, false);
    await controller.assign(1, pickRoom('2'));
    expect(controller.cells[1].qualityIndex, 1);
    controller.dispose();
    await store.close();
  });

  test('offline rooms, failed rooms, retry and removing a cell', () async {
    final store = await memoryStore();
    final site = RoomsSite()
      ..offline.add('3')
      ..failing.add('4');
    final engines = <FakeEngine>[];
    final controller = multiviewController(store, site, engines: engines);
    await controller.start();

    // The stored card says live, the platform says offline: no player.
    await controller.assign(0, pickRoom('3'));
    expect(controller.cells[0].stage, CellStage.offline);
    expect(controller.cells[0].session, isNull);
    // A stored offline state is checked again (3.x trusted it).
    site.offline.clear();
    await controller.retry(0);
    expect(controller.cells[0].stage, CellStage.playing);

    await controller.assign(1, pickRoom('4'));
    expect(controller.cells[1].stage, CellStage.failed);
    expect(controller.cells[1].failure, isA<Exception>());
    expect(controller.cells[1].room!.isLiveStatusPending, isTrue);
    site.failing.clear();
    await controller.retry(1);
    expect(controller.cells[1].stage, CellStage.playing);
    expect(controller.audioIndex, 1);

    await controller.remove(1);
    expect(controller.cells[1].stage, CellStage.empty);
    expect(controller.cells[1].session, isNull);
    // The sound moves to the first cell that still plays.
    expect(controller.audioIndex, 0);
    controller.dispose();
    await store.close();
  });

  test('E06.2 c1: a carousel cell stays offline until asked, then plays from play_time', () async {
    final store = await memoryStore();
    final site = _CarouselRooms()..carousel.add('5');
    final engines = <FakeEngine>[];
    final controller = multiviewController(store, site, engines: engines);
    await controller.start();
    await controller.assign(0, pickRoom('5'));
    final cell = controller.cells[0];
    expect(cell.stage, CellStage.offline);
    expect(cell.session, isNull);

    await controller.playCarousel(0);
    expect(cell.stage, CellStage.playing);
    expect(cell.qualities.single.quality, '轮播');
    final media = engines.single.opens.single;
    expect((media.uri.path, media.start, media.onDemand), ('/5.mp4', const Duration(seconds: 37), false));
    expect(cell.room!.isPlayableNow, isFalse, reason: 'still a carousel for follows and recording');
    // A cell that plays, or one that is simply offline, has nothing to start.
    await controller.playCarousel(0);
    site.offline.add('6');
    await controller.assign(1, pickRoom('6'));
    await controller.playCarousel(1);
    expect(controller.cells[1].stage, CellStage.offline);
    expect(engines, hasLength(1));
    expect(engines.single.opens, hasLength(1));
    controller.dispose();
    await store.close();
  });

  test('B-7: four cells of one platform say a refused cookie once', () async {
    final store = await memoryStore();
    final toasts = <String>[];
    final site = _RefusingRooms();
    final controller = multiviewController(store, site, toasts: toasts);
    await controller.start();
    for (var i = 0; i < 4; i++) {
      await controller.assign(i, pickRoom('${i + 1}'));
    }
    site.refusals.add(null);
    expect(toasts, ['Twitch 的 Cookie 已失效，已改为匿名观看，请在账号页重新填写']);
    controller.dispose();
    expect(site.refusals.hasListener, isFalse);
    await store.close();
  });

  test('E06.2 c5: a cell whose recovery switched quality names the quality now played (11-1)', () async {
    final store = await memoryStore();
    final toasts = <String>[];
    final engines = <FakeEngine>[];
    final site = _ProfileChangedRooms()
      ..qualities = const [
        LivePlayQuality(quality: '720p60', id: '720p60'),
        LivePlayQuality(quality: '360p', id: '360p'),
      ];
    final controller = multiviewController(store, site, engines: engines, toasts: toasts);
    await controller.start();
    await controller.assign(0, pickRoom('1'));
    final cell = controller.cells[0];
    expect(cell.qualities[cell.qualityIndex].quality, '720p60');
    engines.single.emit(
      const EngineError(PlayerException(message: 'connection reset', type: PlayerErrorType.network, code: 'transport')),
    );
    await _settle();
    expect(engines.single.opens.last.uri.path, '/1080p60.m3u8');
    final shown = cell.qualities[cell.qualityIndex];
    expect((shown.quality, shown.isPlaybackUnconfirmed), ('1080p60', false));
    expect(toasts, isEmpty);
    controller.dispose();
    await store.close();
  });

  test('layouts: shrinking releases cells, focus keeps small cells silent and grows', () async {
    final store = await memoryStore();
    final site = RoomsSite();
    final controller = multiviewController(store, site);
    await controller.start();
    for (var i = 0; i < 4; i++) {
      await controller.assign(i, pickRoom('$i'));
    }
    expect(controller.audioIndex, 3);
    final released = controller.cells[3].session!;

    await controller.setLayout(MultiviewLayout.dual);
    expect(controller.cells, hasLength(2));
    expect(released.state.status, PlaybackStatus.stopped);
    expect(controller.audioIndex, 0);

    await controller.setLayout(MultiviewLayout.focus);
    expect(controller.cells, hasLength(4));
    // The large view follows the sound.
    expect(controller.focusedIndex, 0);
    await controller.assign(2, pickRoom('8'));
    expect(controller.audioIndex, 0, reason: 'a small cell starts silent');

    await controller.setSmallCellsLowQuality(enabled: true);
    await _settle();
    expect(controller.cells[2].qualityIndex, controller.cells[2].qualities.length - 1);
    await controller.promote(2);
    await _settle();
    expect(controller.focusedIndex, 2);
    expect(controller.audioIndex, 2);
    expect(controller.cells[2].qualityIndex, 0);
    expect(controller.cells[0].qualityIndex, controller.cells[0].qualities.length - 1);

    while (controller.canAddCell) {
      controller.addCell();
    }
    expect(controller.cells, hasLength(MultiviewController.desktopMaxCells));
    controller.dispose();

    final phone = multiviewController(store, site, mobile: true);
    await phone.setLayout(MultiviewLayout.focus);
    expect(phone.canAddCell, isFalse);
    phone.dispose();
    await store.close();
  });

  test('E05.4 c5: a cell built from the recording detail connects its danmaku arguments', () async {
    final store = await memoryStore();
    final danmaku = <FakeDanmaku>[];
    final controller = multiviewController(store, _RecordingSite(), danmaku: danmaku);
    await controller.start();
    await controller.assign(0, pickRoom('6'));
    controller.setDanmakuEnabled(enabled: true);
    await _settle();
    expect(controller.cells[0].stage, CellStage.playing);
    expect(danmaku.single.connects, ['recording-6']);
    controller.dispose();
    await store.close();
  });

  test('danmaku follow the selected cell and pass the filters', () async {
    final store = await memoryStore();
    await store.blockLists.add(BlockKind.keyword, '广告');
    final site = RoomsSite();
    final danmaku = <FakeDanmaku>[];
    final controller = multiviewController(store, site, danmaku: danmaku);
    await controller.start();
    await controller.assign(0, pickRoom('1'));
    await controller.assign(1, pickRoom('2'));
    expect(danmaku, isEmpty, reason: 'off by default (3.x)');

    final flying = <String>[];
    controller.flying.listen((message) => flying.add(message.message));
    controller.setDanmakuEnabled(enabled: true);
    await _settle();
    expect(danmaku.single.connects, ['args-2']);
    danmaku.single
      ..chat('你好')
      ..chat('看广告');
    expect(flying, ['你好']);

    await controller.setAudioFocus(0);
    await _settle();
    expect(danmaku, hasLength(2));
    expect(danmaku.first.closes, 1);
    expect(danmaku.last.connects, ['args-1']);

    controller.setDanmakuEnabled(enabled: false);
    await _settle();
    expect(danmaku.last.closes, 1);
    controller.dispose();
    await store.close();
  });

  test('the last arrangement is saved and can be restored', () async {
    final store = await memoryStore();
    final site = RoomsSite();
    final first = multiviewController(store, site);
    await first.start();
    await first.setLayout(MultiviewLayout.dual);
    await first.assign(1, pickRoom('5'));
    await _settle();
    first.dispose();
    final saved = jsonDecode((await store.meta.get(MultiviewController.sessionKey))!) as Map<String, Object?>;
    expect(saved['layout'], 'dual');

    final second = multiviewController(store, site);
    await second.start();
    expect(second.layout, MultiviewLayout.dual);
    expect(second.savedRooms.map((room) => room?.roomId), [null, '5']);
    await second.restoreLast();
    expect(second.cells[1].stage, CellStage.playing);
    expect(second.cells[1].room!.roomId, '5');
    expect(second.savedRooms, isEmpty);
    second.dispose();
    await store.close();
  });
  test('a cell out of sight decodes no video until it is back (UI_PLAN §9.3)', () async {
    final store = await memoryStore();
    final site = RoomsSite();
    final engines = <FakeEngine>[];
    final controller = multiviewController(store, site, engines: engines);
    await controller.start();
    await controller.assign(0, pickRoom('1'));
    final cell = controller.cells[0];
    controller.setOffscreen({cell.id});
    await _settle();
    expect(cell.offscreen, isTrue);
    expect(cell.session!.state.audioOnly, isTrue);
    expect(cell.session!.presentationVisible, isFalse);

    // A new stream for a cell out of sight opens without video.
    await controller.selectQuality(0, 2);
    expect(engines.single.opens.last.audioOnly, isTrue);

    controller.setOffscreen(const {});
    await _settle();
    expect(cell.offscreen, isFalse);
    expect(cell.session!.state.audioOnly, isFalse);
    expect(cell.session!.presentationVisible, isTrue);

    // An empty cell is only marked; it opens without video when it plays.
    final other = controller.cells[1];
    controller.setOffscreen({other.id});
    await controller.assign(1, pickRoom('2'));
    expect(engines.last.opens.single.audioOnly, isTrue);
    controller.dispose();
    await store.close();
  });
}

/// Rooms whose every request is served at 250 (a Bilibili guest).
/// A platform whose cells are built from the recording detail (Six Room,
/// AcFun, Kilakila since E05.4): it carries the danmaku arguments.
class _RecordingSite extends RoomsSite implements LiveSiteRecordRoomResolver {
  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async =>
      throw StateError('multi-view asks the recording detail');

  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId}) async =>
      pickRoom(roomId).copyWith(danmakuData: 'recording-$roomId');
}

/// Rooms whose ids are in [RoomsSite.carousel] loop old videos (UPGRADES
/// 1-1): one 轮播 quality, an MP4 started at its `play_time`.
class _CarouselRooms extends RoomsSite implements LivePlayUrlResolver {
  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async =>
      detail.effectiveLiveStatus == LiveStatus.carousel ? const [BilibiliApi.carouselQuality] : qualities;

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => quality.data == BilibiliApi.carouselQualityId
      ? LivePlayUrlResolution.lines(
          [LivePlayLine('https://upos.example/${detail.roomId}.mp4', format: StreamFormat.other)],
          appliedQualityData: BilibiliApi.carouselQualityId,
          start: const Duration(seconds: 37),
        )
      : LivePlayUrlResolution(
          urls: await getPlayUrls(detail: detail, quality: quality),
          appliedQualityData: quality.selectionId,
        );
}

/// Rooms whose recovery plays another profile than the one opened
/// (Picarto, UPGRADES 11-1).
class _ProfileChangedRooms extends RoomsSite implements LivePlayRecoveryResolver {
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution.lines(
    const [LivePlayLine('https://edge.example/1080p60.m3u8')],
    appliedQualityData: '1080p60',
    appliedQuality: const LivePlayQuality(quality: '1080p60', id: '1080p60'),
  );
}

/// Rooms of a platform that refuses stored cookies when the test says (B-7).
class _RefusingRooms extends RoomsSite implements LiveSiteCookieRefusals {
  final StreamController<void> refusals = StreamController.broadcast(sync: true);

  @override
  Stream<void> get cookieRefusals => refusals.stream;
}

class _ServedSite extends RoomsSite implements LivePlayUrlResolver {
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution(urls: const ['https://a.example/250.flv'], appliedQualityData: 250);
}
