import 'package:pure_live/core/interface/live_quality_discovery.dart';
import 'package:pure_live/core/interface/live_site.dart';

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/hls_source_query_policy.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/site/niconico/niconico_site.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/live_play/controllers/player_controller.dart';
import 'package:pure_live/modules/live_play/states/live_play_state.dart';
import 'package:pure_live/modules/live_play/states/player_state.dart';
import 'package:pure_live/modules/live_play/states/room_state.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/player/core/playback_source.dart';
import 'package:pure_live/modules/toolbox/toolbox_action_scope.dart';
import 'package:pure_live/modules/toolbox/toolbox_direct_link_flow.dart';

import 'niconico_quality_catalog_test.dart' as catalog;
import 'niconico_hls_input_test.dart' as fixture;

LiveRoom room() => LiveRoom(roomId: 'lv100', platform: 'niconico', liveStatus: LiveStatus.live);
Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final action in ['invalidate', 'close', 'site', 'destroy']) {
    test('main $action cancels actual discovery read and joins seat cleanup', () async {
      final h = catalog.Harness();
      final started = Completer<CancelToken>();
      final reply = Completer<String>();
      h.reader = (_, _, token, _) {
        started.complete(token);
        return reply.future;
      };
      final site = NiconicoSite(api: h.api, catalog: h.catalog());
      final host = _Host(room());
      final controller = PlayerController(host)
        ..initSite(Site(id: 'niconico', name: 'niconico', logo: '', liveSite: site));
      final pending = controller.getPlayQualites();
      final token = await started.future;
      Future<void>? teardown;
      try {
        switch (action) {
          case 'invalidate':
            controller.invalidateLoad();
          case 'close':
            controller.onClose();
          case 'site':
            controller.initSite(Site(id: 'other', name: 'other', logo: '', liveSite: LiveSite()));
          case 'destroy':
            teardown = controller.destroyPlayer();
        }
        await tick();
        expect(token.isCancelled, isTrue);
      } finally {
        reply.complete(fixture.officialMaster);
        await pending;
        await teardown;
        controller.onClose();
        await controller.getPlayQualites();
        expect(h.reads, 1);
      }
      expect(h.owners.single.closes, 1);
      expect(h.owners.single.grant.retainedCookieCount, 0);
      expect(host.state.value.player.qualites.first.quality, '高清');
    });
  }
  test('toolbox cancellation reaches actual discovery read without choices or exports', () async {
    final h = catalog.Harness();
    final started = Completer<CancelToken>();
    final reply = Completer<String>();
    h.reader = (_, _, token, _) {
      started.complete(token);
      return reply.future;
    };
    final site = NiconicoSite(api: h.api, catalog: h.catalog());
    final scope = ToolBoxActionScope(timeout: const Duration(seconds: 2));
    final flow = ToolBoxDirectLinkFlow(siteFor: (_) => site, copyText: (_) async => fail('unexpected export'));
    final pending = expectLater(
      flow.run(
        room: room(),
        scope: scope,
        chooseQuality: (_) async => throw StateError('unexpected quality choice'),
        chooseLine: (_) async => throw StateError('unexpected line choice'),
        notify: (_) => fail('unexpected notice'),
      ),
      throwsA(isA<ToolBoxActionCancelled>()),
    );
    final token = await started.future;
    try {
      scope.cancel();
      await tick();
      expect(token.isCancelled, isTrue);
    } finally {
      reply.complete(fixture.officialMaster);
      await pending;
      await tick();
    }
    expect(h.owners.single.closes, 1);
    expect(h.owners.single.grant.retainedCookieCount, 0);
  });
  test('main replacement cancels only previous discovery and teardown joins both seats', () async {
    final h = catalog.Harness();
    final tokens = <CancelToken>[];
    final replies = <Completer<String>>[];
    final ready = [Completer<void>(), Completer<void>()];
    h.reader = (_, _, token, _) {
      tokens.add(token);
      final reply = Completer<String>();
      replies.add(reply);
      ready[tokens.length - 1].complete();
      return reply.future;
    };
    final controller = PlayerController(_Host(room()))
      ..initSite(
        Site(
          id: 'niconico',
          name: 'niconico',
          logo: '',
          liveSite: NiconicoSite(api: h.api, catalog: h.catalog()),
        ),
      );
    final first = controller.getPlayQualites();
    await ready[0].future;
    final second = controller.getPlayQualites();
    await ready[1].future;
    try {
      expect(tokens.first.isCancelled, true);
      expect(tokens.last.isCancelled, false);
      var destroyed = false;
      final teardown = controller.destroyPlayer().then((_) => destroyed = true);
      await tick();
      expect(tokens.last.isCancelled, true);
      expect(destroyed, false);
      for (final reply in replies) {
        reply.complete(fixture.officialMaster);
      }
      await teardown;
      expect(h.owners.map((o) => o.closes), [1, 1]);
      expect(h.owners.every((o) => o.grant.retainedCookieCount == 0), true);
    } finally {
      controller.onClose();
      for (final reply in replies) {
        if (!reply.isCompleted) reply.complete(fixture.officialMaster);
      }
      await Future.wait([first, second]);
    }
  });
  test('old destruction never destroys a replacement video during discovery cleanup', () async {
    final h = catalog.Harness();
    final owner = fixture.Seat()..closeGate = Completer<void>();
    h.factory = (_, _, _) async => owner;
    final started = Completer<void>();
    h.reader = (_, _, cancel, _) async {
      started.complete();
      await cancel.whenCancel;
      throw StateError('cancelled transport');
    };
    final host = _Host(room());
    final old = _Video();
    final replacement = _Video();
    host.updatePlayer(videoController: old);
    final controller = PlayerController(host)
      ..initSite(
        Site(
          id: 'niconico',
          name: 'niconico',
          logo: '',
          liveSite: NiconicoSite(api: h.api, catalog: h.catalog()),
        ),
      );
    final pending = controller.getPlayQualites();
    await started.future;
    var destroyed = false;
    final teardown = controller.destroyPlayer().then((_) => destroyed = true);
    host.updatePlayer(videoController: replacement);
    try {
      await owner.closeStarted.future;
      expect(old.destroys, 1);
      expect(old.disposes, 1);
      expect(replacement.destroys, 0);
      expect(destroyed, false);
      expect(host.state.value.player.videoController, same(replacement));
    } finally {
      owner.closeGate!.complete();
      await teardown;
      await pending;
      controller.onClose();
    }
    expect(host.state.value.player.videoController, same(replacement));
    expect(replacement.disposes, 0);
  });
  test('toolbox deadline cancels child and joins real catalog cleanup before reporting timeout', () async {
    final h = catalog.Harness();
    final owner = fixture.Seat()..closeGate = Completer<void>();
    h.factory = (_, _, _) async => owner;
    final started = Completer<CancelToken>();
    h.reader = (_, _, cancel, _) async {
      started.complete(cancel);
      await cancel.whenCancel;
      throw StateError('cancelled transport');
    };
    final scope = ToolBoxActionScope(timeout: const Duration(milliseconds: 100));
    final flow = ToolBoxDirectLinkFlow(
      siteFor: (_) => NiconicoSite(api: h.api, catalog: h.catalog()),
    );
    var finished = false;
    final observed = expectLater(
      flow.run(
        room: room(),
        scope: scope,
        chooseQuality: (_) async => throw StateError('unexpected quality choice'),
        chooseLine: (_) async => throw StateError('unexpected line choice'),
        notify: (_) => fail('unexpected notice'),
      ),
      throwsA(isA<TimeoutException>()),
    ).then((_) => finished = true);
    try {
      final cancel = await started.future;
      await owner.closeStarted.future.timeout(const Duration(seconds: 2));
      expect(cancel.isCancelled, true);
      expect(scope.isActive, true);
      expect(finished, false);
    } finally {
      owner.closeGate!.complete();
      await observed;
      scope.cancel();
    }
    expect(owner.closes, 1);
    expect(owner.grant.retainedCookieCount, 0);
  });
  test('toolbox successful cancellable operation preserves caller token', () async {
    final scope = ToolBoxActionScope();
    CancelToken? child;
    expect(
      await scope.waitCancellable((token) async {
        child = token;
        return 42;
      }),
      42,
    );
    expect(child!.isCancelled, true);
    expect(scope.cancelToken.isCancelled, false);
    scope.cancel();
  });
  test('pre-cancelled discovery allocates neither legacy request nor niconico seat', () async {
    final cancel = CancelToken()..cancel();
    final legacy = _Legacy();
    await expectLater(legacy.discoverPlayQualities(detail: room(), cancel: cancel), throwsA(isA<DioException>()));
    expect(legacy.calls, 0);
    final h = catalog.Harness();
    final site = NiconicoSite(api: h.api, catalog: h.catalog());
    await expectLater(site.discoverPlayQualities(detail: room(), cancel: cancel), throwsA(isA<DioException>()));
    expect(h.requests, 0);
  });
  test('legacy discovery result is fenced after caller cancellation without claiming transport cancellation', () async {
    final legacy = _Legacy();
    final cancel = CancelToken();
    final observed = expectLater(
      legacy.discoverPlayQualities(detail: room(), cancel: cancel),
      throwsA(isA<DioException>()),
    );
    cancel.cancel();
    legacy.reply.complete([LivePlayQuality(quality: 'fixture')]);
    await observed;
    expect(legacy.calls, 1);
  });
  test('ordinary legacy discovery keeps its successful result', () async {
    final legacy = _Legacy();
    legacy.reply.complete([LivePlayQuality(quality: 'fixture')]);
    final cancel = CancelToken();
    expect((await legacy.discoverPlayQualities(detail: room(), cancel: cancel)).single.quality, 'fixture');
    expect(cancel.isCancelled, false);
  });
}

class _Host implements PlayerSessionHost {
  _Host(LiveRoom room)
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
    Map<String, HlsSourceQueryPolicy>? sourceQueryPolicies,
    OwnedPlaybackSource? ownedSource,
    bool clearOwnedSource = false,
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
        sourceQueryPolicies: sourceQueryPolicies,
        ownedSource: ownedSource,
        clearOwnedSource: clearOwnedSource,
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

class _Legacy extends LiveSite {
  int calls = 0;
  final reply = Completer<List<LivePlayQuality>>();
  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) {
    calls++;
    return reply.future;
  }
}

class _Video implements VideoController {
  int destroys = 0;
  int disposes = 0;
  @override
  Future<void> destory() async {
    destroys++;
  }

  @override
  void dispose() {
    disposes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
