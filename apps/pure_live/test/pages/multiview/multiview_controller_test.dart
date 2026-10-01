import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/pages/multiview/multiview_controller.dart';

import '../../live_play_support.dart';
import '../../support.dart';
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
}
