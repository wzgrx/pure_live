import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/douyu/douyu_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/controllers/player_controller.dart';
import 'package:pure_live/modules/live_play/states/live_play_state.dart';
import 'package:pure_live/modules/live_play/states/load_type.dart';
import 'package:pure_live/modules/live_play/states/player_state.dart';
import 'package:pure_live/modules/live_play/states/room_state.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/player/core/player_manager.dart';

void main() {
  test('selection policy clamps stale quality and line indices', () {
    expect(
      resolveStreamSelection(qualityCount: 3, playUrlCount: 2, requestedQualityIndex: 9, requestedLineIndex: 7),
      isA<StreamSelection>()
          .having((value) => value.isValid, 'isValid', isTrue)
          .having((value) => value.qualityIndex, 'quality', 2)
          .having((value) => value.lineIndex, 'line', 1),
    );
    expect(
      resolveStreamSelection(qualityCount: 0, playUrlCount: 2, requestedQualityIndex: 0, requestedLineIndex: 0).isValid,
      isFalse,
    );
  });

  test('server acknowledged quality overrides the tapped label', () {
    final qualities = [
      LivePlayQuality(quality: '原画', id: 10000, data: 10000),
      LivePlayQuality(quality: '蓝光', id: 400, data: 400),
      LivePlayQuality(quality: '超清', id: 250, data: 250),
    ];

    expect(resolveAppliedQualityIndex(qualities: qualities, requestedIndex: 0, appliedQualityData: 250), 2);
    expect(resolveAppliedQualityIndex(qualities: qualities, requestedIndex: 1, appliedQualityData: null), 1);
  });

  test('quality metadata uses stable ids and drops duplicate choices', () {
    final qualities = normalizePlayQualities([
      LivePlayQuality(quality: '原画', id: 0, data: const ['source']),
      LivePlayQuality(quality: '重复原画', id: 0, data: const ['duplicate']),
      LivePlayQuality(quality: '流畅', id: 500, data: const ['smooth']),
      LivePlayQuality(quality: '   ', id: 2000),
    ]);

    expect(qualities.map((quality) => quality.quality), ['原画', '流畅']);
    expect(qualities.map((quality) => quality.selectionId), [0, 500]);
    expect(hasSameStreamChoices(const ['a', 'b'], const ['b', 'a']), isTrue);
    expect(hasSameStreamChoices(const ['a'], const ['a?ratio=500']), isFalse);
    expect(normalizeResolvedPlayUrls(const [' a ', '', 'a', 'b']), const ['a', 'b']);
  });

  for (final appliedId in [null, 'unadvertised']) {
    test('unknown acknowledgement $appliedId reaches state and survives a local line switch', () async {
      final room = LiveRoom(roomId: 'room', platform: 'test');
      final host = _SelectionHost(room);
      final siteImpl = _AcknowledgedSelectionSite(appliedId: appliedId, unconfirmed: appliedId == null);
      final controller = PlayerController(
        host,
        streamSourceOpener: (url, urls, headers, openedRoom, audioOnly, resolver, refreshAt, sourceSelection) async {},
      )..initSite(Site(id: 'test', name: 'Test', logo: '', liveSite: siteImpl));

      expect(
        await controller.switchStreamSelection(type: ReloadDataType.changeQuality, qualityIndex: 1, lineIndex: 0),
        isTrue,
      );
      expect(host.state.value.player.qualitySafe.isPlaybackUnconfirmed, isTrue);
      expect(host.state.value.player.qualitySafe.selectionId, '原画');
      expect(host.state.value.player.qualitySafe.quality, '原画');
      expect(
        await controller.switchStreamSelection(type: ReloadDataType.changeLine, qualityIndex: 1, lineIndex: 1),
        isTrue,
      );
      expect(host.state.value.player.qualitySafe.isPlaybackUnconfirmed, isTrue);

      // A later successful acknowledgement clears the warning; switching away
      // and back uses the same original request identity and existing URLs API.
      siteImpl.appliedId = '高清';
      siteImpl.unconfirmed = false;
      expect(
        await controller.switchStreamSelection(type: ReloadDataType.changeQuality, qualityIndex: 0, lineIndex: 0),
        isTrue,
      );
      expect(host.state.value.player.qualitySafe.isPlaybackUnconfirmed, isFalse);
      expect(host.state.value.player.qualitySafe.quality, '高清');
      expect(host.state.value.player.qualites.every((quality) => !quality.isPlaybackUnconfirmed), isTrue);
    });
  }

  test('unknown quality metadata is not committed when native open fails', () async {
    final host = _SelectionHost(LiveRoom(roomId: 'room', platform: 'test'));
    final controller = PlayerController(
      host,
      streamSourceOpener: (url, urls, headers, room, audioOnly, resolver, refreshAt, sourceSelection) async =>
          throw StateError('open failed'),
    )..initSite(Site(id: 'test', name: 'Test', logo: '', liveSite: _AcknowledgedSelectionSite(unconfirmed: true)));
    expect(
      await controller.switchStreamSelection(type: ReloadDataType.changeQuality, qualityIndex: 1, lineIndex: 0),
      isFalse,
    );
    expect(host.state.value.player.qualitySafe.isPlaybackUnconfirmed, isFalse);
    expect(host.state.value.player.qualitySafe.quality, '高清');
    expect(host.state.value.player.currentQuality, 0);
  });

  test('post-commit failure restores quality confirmation with the previous selection', () async {
    final host = _ThrowingRoomHost(LiveRoom(roomId: 'room', platform: 'test'));
    final previous = host.state.value.player;
    final controller = PlayerController(
      host,
      streamSourceOpener: (url, urls, headers, room, audioOnly, resolver, refreshAt, sourceSelection) async {},
    )..initSite(Site(id: 'test', name: 'Test', logo: '', liveSite: _AcknowledgedSelectionSite(unconfirmed: true)));
    expect(
      await controller.switchStreamSelection(type: ReloadDataType.changeQuality, qualityIndex: 1, lineIndex: 0),
      isFalse,
    );
    expect(host.state.value.player.qualites, same(previous.qualites));
    expect(host.state.value.player.currentQuality, previous.currentQuality);
    expect(host.state.value.player.playUrls, previous.playUrls);
  });

  test('duplicate visible labels are numbered without changing stable ids', () {
    final qualities = normalizePlayQualities([
      LivePlayQuality(quality: '高清', id: 'hd-1'),
      LivePlayQuality(quality: '高清', id: 'hd-2'),
    ]);

    expect(qualities.map((quality) => quality.quality), ['高清 1', '高清 2']);
    expect(qualities.map((quality) => quality.selectionId), ['hd-1', 'hd-2']);
  });

  test('quality switch keeps old state until URLs resolve and clamps the new line', () async {
    final room = LiveRoom(roomId: 'room', platform: 'test');
    final siteImpl = _SelectionLiveSite();
    final host = _SelectionHost(room);
    final opened = <_OpenedStream>[];
    final controller = PlayerController(
      host,
      streamSourceOpener:
          (url, urls, headers, openedRoom, audioOnly, sourceResolver, sourceRefreshAt, sourceSelection) async {
            opened.add(_OpenedStream(url, urls, openedRoom, audioOnly));
          },
    )..initSite(Site(id: 'test', name: 'Test', logo: '', liveSite: siteImpl));

    final switching = controller.switchStreamSelection(
      type: ReloadDataType.changeQuality,
      qualityIndex: 1,
      lineIndex: 8,
    );
    expect(host.state.value.player.currentQuality, 0, reason: 'the old source stays active while the URL resolves');
    expect(controller.isStreamSwitching.value, isTrue);

    siteImpl.qualityUrls.complete(const ['https://new/one', 'https://new/two']);
    expect(await switching, isTrue);

    final state = host.state.value.player;
    expect(state.currentQuality, 1);
    expect(state.currentLineIndex, 1);
    expect(state.playUrls, const ['https://new/one', 'https://new/two']);
    expect(state.hasUseDefaultResolution, isTrue);
    expect(opened.single.url, 'https://new/two');
    expect(opened.single.room, same(room));
    expect(controller.isStreamSwitching.value, isFalse);
  });

  test('line switch reuses current URLs without refetching quality metadata', () async {
    final room = LiveRoom(roomId: 'room', platform: 'test');
    final siteImpl = _SelectionLiveSite();
    final host = _SelectionHost(room);
    final opened = <_OpenedStream>[];
    final controller = PlayerController(
      host,
      streamSourceOpener:
          (url, urls, headers, openedRoom, audioOnly, sourceResolver, sourceRefreshAt, sourceSelection) async {
            opened.add(_OpenedStream(url, urls, openedRoom, audioOnly));
          },
    )..initSite(Site(id: 'test', name: 'Test', logo: '', liveSite: siteImpl));

    expect(
      await controller.switchStreamSelection(type: ReloadDataType.changeLine, qualityIndex: 0, lineIndex: 1),
      isTrue,
    );

    expect(siteImpl.playUrlCalls, 0);
    expect(opened.single.url, 'https://old/two');
    expect(host.state.value.player.currentLineIndex, 1);
  });

  test('returning to the current quality supersedes a pending URL request', () async {
    final room = LiveRoom(roomId: 'room', platform: 'test');
    final host = _SelectionHost(room);
    final siteImpl = _ReversibleSelectionLiveSite();
    final opened = <String>[];
    final controller = PlayerController(
      host,
      streamSourceOpener: (url, urls, headers, room, audioOnly, resolver, refreshAt, sourceSelection) async {
        opened.add(url);
      },
    )..initSite(Site(id: 'test', name: 'Test', logo: '', liveSite: siteImpl));

    final first = controller.switchStreamSelection(type: ReloadDataType.changeQuality, qualityIndex: 1, lineIndex: 0);
    final latest = controller.switchStreamSelection(type: ReloadDataType.changeQuality, qualityIndex: 0, lineIndex: 0);
    expect(await latest, isTrue);
    siteImpl.newQuality.complete(const ['https://new/one']);
    expect(await first, isFalse);
    expect(host.state.value.player.currentQuality, 0);
    expect(opened, isNot(contains('https://new/one')));
    expect(controller.isStreamSwitching.value, isFalse);
  });

  test('returning to the current line queues a restore behind an opening source', () async {
    final room = LiveRoom(roomId: 'room', platform: 'test');
    final host = _SelectionHost(room);
    final opening = Completer<void>();
    final started = Completer<void>();
    final opened = <String>[];
    var nativeQueue = Future<void>.value();
    final controller = PlayerController(
      host,
      // Model PlayerManager's existing serial native lifecycle queue.
      streamSourceOpener: (url, urls, headers, room, audioOnly, resolver, refreshAt, sourceSelection) {
        nativeQueue = nativeQueue.then((_) async {
          opened.add(url);
          if (url.endsWith('/two')) {
            started.complete();
            await opening.future;
          }
        });
        return nativeQueue;
      },
    )..initSite(Site(id: 'test', name: 'Test', logo: '', liveSite: _SelectionLiveSite()));

    final first = controller.switchStreamSelection(type: ReloadDataType.changeLine, qualityIndex: 0, lineIndex: 1);
    await started.future;
    final latest = controller.switchStreamSelection(type: ReloadDataType.changeLine, qualityIndex: 0, lineIndex: 0);
    opening.complete();
    expect(await first, isFalse);
    expect(await latest, isTrue);
    expect(opened, ['https://old/two', 'https://old/one']);
    expect(host.state.value.player.currentLineIndex, 0);
    expect(controller.isStreamSwitching.value, isFalse);
  });

  test('signed platform line switch reacquires fresh URLs and installs a recovery resolver', () async {
    final room = LiveRoom(roomId: 'room', platform: 'signed');
    final siteImpl = _SignedSelectionLiveSite();
    final host = _SelectionHost(room);
    PlaybackSourceResolver? installedResolver;
    final opened = <_OpenedStream>[];
    final controller = PlayerController(
      host,
      streamSourceOpener:
          (url, urls, headers, openedRoom, audioOnly, sourceResolver, sourceRefreshAt, sourceSelection) async {
            installedResolver = sourceResolver;
            opened.add(_OpenedStream(url, urls, openedRoom, audioOnly));
          },
    )..initSite(Site(id: 'signed', name: 'Signed', logo: '', liveSite: siteImpl));

    expect(
      await controller.switchStreamSelection(type: ReloadDataType.changeLine, qualityIndex: 0, lineIndex: 1),
      isTrue,
    );

    expect(siteImpl.recoveryCalls, 1);
    expect(opened.single.url, 'https://fresh-1/two');
    expect(installedResolver, isNotNull);

    final refreshed = await installedResolver!(
      const PlaybackSourceRefreshRequest(currentLineIndex: 1, advanceLine: false),
    );
    expect(siteImpl.recoveryCalls, 2);
    expect(refreshed.urls, const <String>['https://fresh-2/one', 'https://fresh-2/two']);
    expect(refreshed.preferredLineIndex, 1);
  });

  test('Douyu recovery refreshes URL generations without changing quality or line cursor', () async {
    final room = LiveRoom(roomId: '24422', platform: Sites.douyuSite);
    final siteImpl = _FreshDouyuSelectionSite();
    final host = _SelectionHost(room);
    host.updatePlayer(
      qualites: [
        LivePlayQuality(
          quality: '蓝光4M',
          id: 1,
          data: DouyuPlayData(1, const <String>['main', 'backup']),
          isPlaybackUnconfirmed: true,
        ),
      ],
      currentQuality: 0,
      playUrls: const <String>['https://old.example/main.flv', 'https://old.example/backup.flv'],
      currentLineIndex: 0,
    );
    PlaybackSourceResolver? installedResolver;
    final opened = <_OpenedStream>[];
    final controller = PlayerController(
      host,
      streamSourceOpener:
          (url, urls, headers, openedRoom, audioOnly, sourceResolver, sourceRefreshAt, sourceSelection) async {
            installedResolver = sourceResolver;
            opened.add(_OpenedStream(url, urls, openedRoom, audioOnly));
          },
    )..initSite(Site(id: Sites.douyuSite, name: 'Douyu', logo: '', liveSite: siteImpl));

    expect(
      await controller.switchStreamSelection(type: ReloadDataType.changeLine, qualityIndex: 0, lineIndex: 1),
      isTrue,
    );

    expect(siteImpl.recoveryCalls, 1);
    expect(opened.single.url, 'https://fresh-1.example/backup.flv');
    expect(opened.single.urls, const <String>[
      'https://fresh-1.example/main.flv',
      'https://fresh-1.example/backup.flv',
    ]);
    expect(host.state.value.player.currentLineIndex, 1);
    expect(host.state.value.player.qualitySafe.selectionId, 1);
    expect(host.state.value.player.qualitySafe.isPlaybackUnconfirmed, isFalse);
    expect(installedResolver, isNotNull);

    final sameLine = await installedResolver!(
      const PlaybackSourceRefreshRequest(
        currentLineIndex: 1,
        currentUrl: 'https://fresh-1.example/backup.flv',
        advanceLine: false,
      ),
    );
    expect(siteImpl.recoveryCalls, 2);
    expect(sameLine.urls, const <String>['https://fresh-2.example/main.flv', 'https://fresh-2.example/backup.flv']);
    expect(sameLine.preferredLineIndex, 1);

    final nextLine = await installedResolver!(
      const PlaybackSourceRefreshRequest(
        currentLineIndex: 1,
        currentUrl: 'https://fresh-2.example/backup.flv',
        advanceLine: true,
      ),
    );
    expect(siteImpl.recoveryCalls, 3);
    expect(nextLine.urls, const <String>['https://fresh-3.example/main.flv', 'https://fresh-3.example/backup.flv']);
    expect(nextLine.preferredLineIndex, 0);
  });

  for (final appliedId in <Object?>[3, null, 'unadvertised']) {
    test('recovery acknowledgement $appliedId only changes UI after a source commit', () async {
      final room = LiveRoom(roomId: 'room', platform: 'test');
      final host = _SelectionHost(room)..updatePlayer(qualites: _recoveryQualities(), currentQuality: 0);
      final siteImpl = _AcknowledgedRecoverySite();
      PlaybackSourceResolver? resolver;
      final controller = PlayerController(
        host,
        streamSourceOpener: (url, urls, headers, room, audioOnly, nextResolver, refreshAt, sourceSelection) async {
          resolver = nextResolver;
          expect(sourceSelection?.quality.selectionId, 0);
        },
      )..initSite(Site(id: 'test', name: 'test', logo: '', liveSite: siteImpl));
      expect(
        await controller.switchStreamSelection(type: ReloadDataType.changeLine, qualityIndex: 0, lineIndex: 1),
        isTrue,
      );
      final before = host.state.value.player;
      siteImpl.appliedId = appliedId;
      final refreshed = await resolver!(
        PlaybackSourceRefreshRequest(currentLineIndex: 1, advanceLine: false, currentQuality: before.qualitySafe),
      );
      expect(host.state.value.player, same(before), reason: 'resolving is not a native source commit');
      expect(refreshed.selection, isNotNull);
      expect(refreshed.selection!.quality.selectionId, appliedId == 3 ? 3 : 0);
      expect(refreshed.selection!.quality.isPlaybackUnconfirmed, appliedId != 3);
      controller.applySourceCommit(_sourceCommit(room, refreshed, revision: 1));
      final committed = host.state.value.player;
      expect(committed.qualites, refreshed.selection!.qualities);
      expect(committed.currentQuality, refreshed.selection!.currentQuality);
      expect(committed.playUrls, refreshed.urls);
      expect(committed.currentLineIndex, 1);
      // Simulate the manager passing its canonical quality to the next refresh.
      // The resolver must not keep the source rate captured at first open.
      await resolver!(
        PlaybackSourceRefreshRequest(currentLineIndex: 1, advanceLine: false, currentQuality: committed.qualitySafe),
      );
      expect(siteImpl.requestedIds.last, appliedId == 3 ? 3 : 0);
      controller.applySourceCommit(_sourceCommit(room, refreshed, revision: 1));
      expect(host.state.value.player, same(committed), reason: 'duplicate commit is ignored');
      controller.applySourceCommit(_sourceCommit(LiveRoom(roomId: 'other', platform: 'test'), refreshed, revision: 2));
      expect(host.state.value.player, same(committed), reason: 'another room cannot update this route');
    });
  }

  for (final failsAfterCommit in [false, true]) {
    test('native recovery commit wins over the pending selection payload (failure=$failsAfterCommit)', () async {
      final room = LiveRoom(roomId: 'room', platform: 'test');
      final host = _SelectionHost(room)..updatePlayer(qualites: _recoveryQualities(), currentQuality: 0);
      final siteImpl = _AcknowledgedRecoverySite();
      late PlayerController controller;
      controller = PlayerController(
        host,
        streamSourceOpener: (url, urls, headers, room, audioOnly, resolver, refreshAt, sourceSelection) async {
          siteImpl.appliedId = 3;
          final recovered = await resolver!(
            PlaybackSourceRefreshRequest(
              currentLineIndex: 0,
              advanceLine: false,
              currentQuality: sourceSelection!.quality,
            ),
          );
          controller.applySourceCommit(_sourceCommit(room, recovered, revision: 5));
          if (failsAfterCommit) throw StateError('presentation update failed after the source committed');
        },
      )..initSite(Site(id: 'test', name: 'test', logo: '', liveSite: siteImpl));
      expect(
        await controller.switchStreamSelection(type: ReloadDataType.changeLine, qualityIndex: 0, lineIndex: 1),
        !failsAfterCommit,
      );
      expect(host.state.value.player.qualitySafe.selectionId, 3);
      expect(host.state.value.player.playUrlSafe, 'https://generation-2.example/one');
      expect(host.state.value.player.currentLineIndex, 0);
    });
  }

  for (final scenario in [
    (
      name: 'keeps the CDN when an earlier line disappears',
      urls: [
        'https://tx.flv.huya.com/src/room.flv?ctype=huya_pc_exe&t=100&seqid=new',
        'https://tx.hls.huya.com/src/room.m3u8?ctype=huya_live',
      ],
      advance: false,
      expected: 0,
    ),
    (
      name: 'advances from the matched CDN after reordering, not the stale index',
      urls: [
        'https://tx.flv.huya.com/src/room.flv?ctype=huya_pc_exe&t=100&seqid=new',
        'https://al.flv.huya.com/src/room.flv?ctype=huya_pc_exe&t=100&seqid=new',
        'https://tx.hls.huya.com/src/room.m3u8?ctype=huya_live',
      ],
      advance: true,
      expected: 1,
    ),
    (
      name: 'retains a native FLV option when the old CDN only has a web fallback',
      urls: [
        'https://al.flv.huya.com/src/room.flv?ctype=huya_pc_exe&t=100&seqid=new',
        'https://tx.flv.huya.com/src/room.flv?ctype=huya_live',
        'https://tx.hls.huya.com/src/room.m3u8?ctype=huya_live',
      ],
      advance: false,
      expected: 0,
    ),
  ]) {
    test('Huya recovery ${scenario.name}', () async {
      const currentUrl = 'https://tx.flv.huya.com/src/room.flv?ctype=huya_pc_exe&t=100&seqid=old';
      final host = _SelectionHost(LiveRoom(roomId: 'room', platform: Sites.huyaSite));
      final siteImpl = _HuyaRecoverySelectionLiveSite();
      PlaybackSourceResolver? resolver;
      final controller = PlayerController(
        host,
        streamSourceOpener: (url, urls, headers, room, audioOnly, sourceResolver, refreshAt, sourceSelection) async {
          resolver = sourceResolver;
        },
      )..initSite(Site(id: Sites.huyaSite, name: 'Huya', logo: '', liveSite: siteImpl));
      expect(
        await controller.switchStreamSelection(type: ReloadDataType.changeLine, qualityIndex: 0, lineIndex: 1),
        isTrue,
      );
      siteImpl.urls = scenario.urls;

      final refreshed = await resolver!(
        PlaybackSourceRefreshRequest(currentLineIndex: 1, currentUrl: currentUrl, advanceLine: scenario.advance),
      );

      expect(refreshed.preferredLineIndex, scenario.expected);
      expect(refreshed.urls, scenario.urls, reason: 'the displayed manifest must not be silently reordered');
      expect(refreshed.refreshAt, DateTime.utc(2030).add(Duration(minutes: scenario.expected)));
      expect(refreshed.invalidAt, DateTime.utc(2030).add(Duration(minutes: scenario.expected + 1)));
    });
  }

  test('failed player open rolls quality, line and URL state back atomically', () async {
    final room = LiveRoom(roomId: 'room', platform: 'test');
    final siteImpl = _SelectionLiveSite();
    final host = _SelectionHost(room);
    final controller = PlayerController(
      host,
      streamSourceOpener:
          (url, urls, headers, openedRoom, audioOnly, sourceResolver, sourceRefreshAt, sourceSelection) async {
            throw StateError('decoder rejected source');
          },
    )..initSite(Site(id: 'test', name: 'Test', logo: '', liveSite: siteImpl));

    final switching = controller.switchStreamSelection(
      type: ReloadDataType.changeQuality,
      qualityIndex: 1,
      lineIndex: 1,
    );
    siteImpl.qualityUrls.complete(const ['https://new/one', 'https://new/two']);

    expect(await switching, isFalse);
    expect(host.state.value.player.currentQuality, 0);
    expect(host.state.value.player.currentLineIndex, 0);
    expect(host.state.value.player.playUrls, const ['https://old/one', 'https://old/two']);
    expect(controller.isStreamSwitching.value, isFalse);
  });

  test('a different label resolving to the same stream is not committed', () async {
    final room = LiveRoom(roomId: 'room', platform: 'test');
    final siteImpl = _SelectionLiveSite();
    final host = _SelectionHost(room);
    var openCalls = 0;
    final controller = PlayerController(
      host,
      streamSourceOpener:
          (url, urls, headers, openedRoom, audioOnly, sourceResolver, sourceRefreshAt, sourceSelection) async {
            openCalls++;
          },
    )..initSite(Site(id: 'test', name: 'Test', logo: '', liveSite: siteImpl));

    final switching = controller.switchStreamSelection(
      type: ReloadDataType.changeQuality,
      qualityIndex: 1,
      lineIndex: 0,
    );
    siteImpl.qualityUrls.complete(const ['https://old/two', 'https://old/one']);

    expect(await switching, isFalse);
    expect(openCalls, 0);
    expect(host.state.value.player.currentQuality, 0);
  });
}

class _SelectionLiveSite extends LiveSite {
  final Completer<List<String>> qualityUrls = Completer<List<String>>();
  int playUrlCalls = 0;

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) {
    playUrlCalls++;
    return qualityUrls.future;
  }
}

class _AcknowledgedSelectionSite extends LiveSite implements LivePlayUrlResolver {
  _AcknowledgedSelectionSite({this.appliedId, this.unconfirmed = false});
  Object? appliedId;
  bool unconfirmed;

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution(
    urls: ['https://cdn.test/${quality.quality}/one', 'https://cdn.test/${quality.quality}/two'],
    appliedQualityData: appliedId,
    qualityUnconfirmed: unconfirmed,
  );
}

class _ReversibleSelectionLiveSite extends LiveSite {
  final newQuality = Completer<List<String>>();

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) {
    return quality.quality == '原画' ? newQuality.future : Future.value(const ['https://old/one', 'https://old/two']);
  }
}

class _SignedSelectionLiveSite extends LiveSite implements LivePlayRecoveryResolver {
  int recoveryCalls = 0;

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    recoveryCalls++;
    return LivePlayUrlResolution(
      urls: <String>['https://fresh-$recoveryCalls/one', 'https://fresh-$recoveryCalls/two'],
      appliedQualityData: quality.selectionId,
    );
  }
}

List<LivePlayQuality> _recoveryQualities() => [
  LivePlayQuality(quality: 'Original', id: 0),
  LivePlayQuality(quality: 'Fluent', id: 3),
];

PlaybackSourceCommitSnapshot _sourceCommit(
  LiveRoom room,
  PlaybackSourceRefreshResult result, {
  required int revision,
}) => PlaybackSourceCommitSnapshot(
  revision: revision,
  sessionId: revision,
  intentRevision: 1,
  room: room,
  urls: result.urls,
  currentUrl: result.urls[result.preferredLineIndex],
  currentLineIndex: result.preferredLineIndex,
  headers: const {},
  audioOnly: false,
  selection: result.selection,
);

class _AcknowledgedRecoverySite extends LiveSite implements LivePlayRecoveryResolver {
  Object? appliedId = 0;
  final requestedIds = <Object>[];
  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async {
    requestedIds.add(quality.selectionId);
    return LivePlayUrlResolution(
      urls: [
        'https://generation-${requestedIds.length}.example/one',
        'https://generation-${requestedIds.length}.example/two',
      ],
      appliedQualityData: appliedId,
      qualityUnconfirmed: appliedId == null,
    );
  }
}

class _FreshDouyuSelectionSite extends DouyuSite {
  int recoveryCalls = 0;

  @override
  Future<LiveRoom> getRoomDetailForRecording({required String platform, required String roomId}) async {
    return LiveRoom(roomId: roomId, platform: platform, status: true);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    return <LivePlayQuality>[
      LivePlayQuality(quality: '蓝光4M', id: 1, data: DouyuPlayData(1, const <String>['main', 'backup'])),
    ];
  }

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    final generation = ++recoveryCalls;
    return LivePlayUrlResolution(
      urls: <String>['https://fresh-$generation.example/main.flv', 'https://fresh-$generation.example/backup.flv'],
      appliedQualityData: quality.selectionId,
    );
  }
}

class _HuyaRecoverySelectionLiveSite extends LiveSite implements LivePlayRecoveryResolver, LivePlayLeaseMetadata {
  List<String> urls = [
    'https://al.flv.huya.com/src/room.flv?ctype=huya_pc_exe&t=100',
    'https://tx.flv.huya.com/src/room.flv?ctype=huya_pc_exe&t=100&seqid=old',
  ];

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsForRecoveryRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => LivePlayUrlResolution(urls: urls, appliedQualityData: quality.selectionId);

  @override
  DateTime getPlayUrlRefreshAt(String url, {DateTime? now}) =>
      DateTime.utc(2030).add(Duration(minutes: urls.indexOf(url)));

  @override
  DateTime getPlayUrlInvalidAt(String url, {DateTime? now}) => getPlayUrlRefreshAt(url).add(const Duration(minutes: 1));
}

class _SelectionHost implements PlayerSessionHost {
  _SelectionHost(LiveRoom room)
    : state = LivePlayState(
        room: RoomState(detail: room, success: true, isLiving: true),
        player: PlayerState(
          qualites: [
            LivePlayQuality(quality: '高清'),
            LivePlayQuality(quality: '原画'),
          ],
          currentQuality: 0,
          playUrls: const ['https://old/one', 'https://old/two'],
          currentLineIndex: 0,
        ),
      ).obs;

  @override
  final Rx<LivePlayState> state;

  @override
  bool get isClosed => false;

  @override
  Future<void> setCurrentRoomAudioOnlyFromUser(bool value) async {}

  @override
  void updatePlayer({
    VideoController? videoController,
    bool clearVideoController = false,
    List<LivePlayQuality>? qualites,
    int? currentQuality,
    List<String>? playUrls,
    int? currentLineIndex,
    bool? isCurrentRoomAudioOnly,
    bool? hasUseDefaultResolution,
  }) {
    state.value = state.value.copyWith(
      player: state.value.player.copyWith(
        videoController: resolveVideoControllerUpdate(
          current: state.value.player.videoController,
          next: videoController,
          clear: clearVideoController,
        ),
        qualites: qualites,
        currentQuality: currentQuality,
        playUrls: playUrls,
        currentLineIndex: currentLineIndex,
        isCurrentRoomAudioOnly: isCurrentRoomAudioOnly,
        hasUseDefaultResolution: hasUseDefaultResolution,
      ),
    );
  }

  @override
  void updateRoom({LiveRoom? detail, bool? isLiving, bool? success, bool? isLoading, String? loadError}) {
    state.value = state.value.copyWith(
      room: state.value.room.copyWith(
        detail: detail,
        isLiving: isLiving,
        success: success,
        isLoading: isLoading,
        loadError: loadError,
      ),
    );
  }
}

class _ThrowingRoomHost extends _SelectionHost {
  _ThrowingRoomHost(super.room);
  @override
  void updateRoom({LiveRoom? detail, bool? isLiving, bool? success, bool? isLoading, String? loadError}) {
    throw StateError('post-commit room update failed');
  }
}

class _OpenedStream {
  const _OpenedStream(this.url, this.urls, this.room, this.audioOnly);

  final String url;
  final List<String> urls;
  final LiveRoom room;
  final bool audioOnly;
}
