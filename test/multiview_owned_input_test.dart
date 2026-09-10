import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/hls_source_query_policy.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/niconico/niconico_input_recipe.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/modules/multiview/cells/multiview_cell_player.dart';
import 'package:pure_live/modules/multiview/models/multiview_models.dart';
import 'package:pure_live/modules/multiview/multiview_controller.dart';
import 'package:pure_live/player/core/playback_source.dart';
import 'package:pure_live/player/core/playback_source_transport.dart';

Future<void> tick() => Future<void>.delayed(Duration.zero);
LiveRoom room([String id = 'lv123']) =>
    LiveRoom(roomId: id, platform: 'bilibili', status: true, liveStatus: LiveStatus.live);

class _Lease {
  _Lease(int id) {
    input = PlaybackInputLease(Uri.parse('http://127.0.0.1:19000/private/$id.m3u8'), () async {
      closes++;
      if (cleanup != null) await cleanup!.future;
    }, isUsable: () => usable);
  }
  late final PlaybackInputLease input;
  int closes = 0;
  bool usable = true;
  Completer<void>? cleanup;
}

class _Pool {
  final leases = <_Lease>[];
  final requests = <String>[];
  OwnedPlaybackSource source([String identity = 'public-recipe']) => OwnedPlaybackSource(
    identity: identity,
    createInput: (_) async {
      requests.add(identity);
      final lease = _Lease(leases.length);
      leases.add(lease);
      return lease.input;
    },
  );
}

class _Backend implements MultiviewCellPlayerHandle, MultiviewNativeInputRouting {
  final inputs = <(String, Map<String, String>, bool)>[];
  bool privateInput = false;
  bool reject = false;
  bool muted = true;
  int starts = 0;
  int opens = 0;
  int resumes = 0;
  int disposes = 0;
  Completer<void>? gate;
  @override
  double volume = 1;
  @override
  bool isPlaying = false;
  @override
  VideoController? get videoController => null;
  @override
  Stream<bool> get playingStream => const Stream.empty();
  @override
  void setPrivateInput(bool value) => privateInput = value;
  Future<void> _input(String url, Map<String, String> headers) async {
    inputs.add((url, headers, privateInput));
    if (gate != null) await gate!.future;
    if (reject) throw StateError('native fixture failure');
    if (disposes == 0) isPlaying = true;
  }

  @override
  Future<void> start({
    required String url,
    required Map<String, String> headers,
    HlsSourceQueryPolicy? sourceQueryPolicy,
  }) {
    starts++;
    muted = true;
    return _input(url, headers);
  }

  @override
  Future<void> open({
    required String url,
    required Map<String, String> headers,
    HlsSourceQueryPolicy? sourceQueryPolicy,
  }) {
    opens++;
    return _input(url, headers);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
  }

  @override
  Future<void> resume() async {
    resumes++;
    isPlaying = true;
  }

  @override
  Future<void> setMuted(bool value) async {
    muted = value;
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }

  @override
  Future<void> disposePlayer() async {
    disposes++;
    isPlaying = false;
  }
}

class _Danmaku extends LiveDanmaku {
  @override
  Future<void> start(dynamic args) async => markConnected();
  @override
  Future<void> stop() async => markDisconnected();
}

class _Site extends LiveSite implements LivePlayUrlResolver, LiveSiteRecordRoomResolver {
  final qualities = [LivePlayQuality(quality: 'HD', id: '800x450'), LivePlayQuality(quality: 'SD', id: '512x288')];
  String? applied;
  final requested = <String>[];
  int legacyCalls = 0;
  int detailCalls = 0;
  @override
  Future<LiveRoom> getRoomDetail({required String roomId, required String platform}) =>
      throw StateError('Use strict metadata');
  @override
  Future<LiveRoom> getRoomDetailForRecording({required String roomId, required String platform}) async {
    detailCalls++;
    return room(roomId);
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async => qualities;
  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    legacyCalls++;
    throw StateError('No exportable URLs');
  }

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({required LiveRoom detail, required LivePlayQuality quality}) async {
    requested.add(quality.selectionId.toString());
    return LivePlayUrlResolution.owned(
      input: NiconicoInputRecipe(programId: detail.roomId!, resolution: applied ?? quality.selectionId.toString()),
      appliedQualityData: applied ?? quality.selectionId,
    );
  }
}

class _Harness {
  _Harness({MultiviewStreamResolver? resolver}) {
    controller = MultiviewController(
      streamResolver:
          resolver ??
          (value, {required preferLowest}) => MultiviewController.resolveStreamForSite(
            value,
            site: Site(id: 'bilibili', name: 'Owned fixture', logo: '', liveSite: site),
            preferLowest: preferLowest,
            bindOwnedInput: (recipe) => pool.source(recipe.identity),
          ),
      playerFactory: ({required renderWidth, required renderHeight}) {
        final backend = _Backend();
        backends.add(backend);
        return MultiviewCellPlayer(renderWidth: renderWidth, renderHeight: renderHeight, backend: backend);
      },
      pauseGlobalPlayback: () async {},
      roomVolumeLoader: (_) => .4,
      roomVolumeSaver: (_, _) async {},
      danmakuEngineFactory: (_) => _Danmaku(),
    );
  }
  final pool = _Pool();
  final site = _Site();
  final backends = <_Backend>[];
  late final MultiviewController controller;
}

void main() {
  test('production resolver accepts an owned source with no URL or eager seat creation', () async {
    final site = _Site();
    final source = await MultiviewController.resolveStreamForSite(
      room(),
      site: Site(id: 'bilibili', name: 'Fixture', logo: '', liveSite: site),
      preferLowest: false,
    );
    expect(source.ownedSource!.identity, 'niconico:lv123:800x450:auto');
    expect(source.url, isEmpty);
    expect(source.headers, isEmpty);
    expect(source.lines, isEmpty);
    expect(source.sourceQueryPolicies, isEmpty);
    expect(source.lineCount, 1);
    expect(site.legacyCalls, 0);
  });
  test('quality loader retains lazy binding and server acknowledgement', () async {
    final site = _Site()..applied = '512x288';
    final pool = _Pool();
    final source = await MultiviewController.resolveStreamForSite(
      room(),
      site: Site(id: 'bilibili', name: 'Fixture', logo: '', liveSite: site),
      preferLowest: false,
      bindOwnedInput: (recipe) => pool.source(recipe.identity),
    );
    expect(source.qualityIndex, 1);
    final next = await source.qualityLoader!(site.qualities.first);
    expect(next.qualityIndex, 1);
    expect(next.ownedSource!.identity, contains('512x288'));
    expect(pool.leases, isEmpty);
    expect(site.detailCalls, 1);
    expect(site.legacyCalls, 0);
  });
  test('owned state survives unrelated updates and clears on direct or room replacement', () {
    final owned = _Pool().source();
    final state = MultiviewCellState(index: 0, ownedSource: owned);
    expect(state.lineCount, 1);
    expect(state.copyWith(qualityIndex: 1).ownedSource, same(owned));
    expect(state.copyWith(lines: ['https://direct']).ownedSource, isNull);
    expect(state.copyWith(clearQuality: true).ownedSource, isNull);
    expect(state.copyWith(clearOwnedSource: true).ownedSource, isNull);
  });
  test('same public source opened by two real cell owners gets independent private inputs', () async {
    final pool = _Pool();
    final source = pool.source();
    final backends = [_Backend(), _Backend()];
    final cells = [
      for (final backend in backends) MultiviewCellPlayer(renderWidth: 640, renderHeight: 360, backend: backend),
    ];
    try {
      await Future.wait([for (final cell in cells) cell.startOwned(source)]);
      expect(pool.leases, hasLength(2));
      expect(backends[0].inputs.single.$1, isNot(backends[1].inputs.single.$1));
      for (final backend in backends) {
        expect(backend.inputs.single.$2, isEmpty);
        expect(backend.inputs.single.$3, isTrue);
        expect(backend.muted, isTrue);
      }
      await cells.first.disposePlayer();
      expect(pool.leases.map((e) => e.closes), [1, 0]);
      expect(cells.last.isPlaying, isTrue);
    } finally {
      await Future.wait([for (final cell in cells) cell.disposePlayer()]);
    }
    expect(pool.leases.map((e) => e.closes), [1, 1]);
  });
  test('owned quality replacement retires previous input only after native acceptance', () async {
    final pool = _Pool();
    final backend = _Backend();
    final cell = MultiviewCellPlayer(renderWidth: 640, renderHeight: 360, backend: backend);
    try {
      await cell.startOwned(pool.source('HD'));
      backend.gate = Completer<void>();
      final opening = cell.openOwned(pool.source('SD'));
      await tick();
      expect(pool.leases.map((e) => e.closes), [0, 0]);
      backend.gate!.complete();
      await opening;
      expect(pool.leases.map((e) => e.closes), [1, 0]);
      expect(backend.starts, 1);
      expect(backend.opens, 1);
    } finally {
      if (backend.gate?.isCompleted == false) backend.gate!.complete();
      await cell.disposePlayer();
    }
  });
  test('failed owned candidate closes without retiring the last working input', () async {
    final pool = _Pool();
    final backend = _Backend();
    final cell = MultiviewCellPlayer(renderWidth: 640, renderHeight: 360, backend: backend);
    try {
      await cell.startOwned(pool.source());
      backend.reject = true;
      await expectLater(cell.openOwned(pool.source('failed')), throwsStateError);
      expect(pool.leases.map((e) => e.closes), [0, 1]);
    } finally {
      await cell.disposePlayer();
    }
    expect(pool.leases.map((e) => e.closes), [1, 1]);
  });
  test('owned to direct resets private routing and retires the seat', () async {
    final pool = _Pool();
    final backend = _Backend();
    final cell = MultiviewCellPlayer(renderWidth: 640, renderHeight: 360, backend: backend);
    try {
      await cell.startOwned(pool.source());
      await cell.open(url: 'https://direct.example/live.flv', headers: const {'x-test': 'direct'});
      expect(backend.inputs.last.$1, 'https://direct.example/live.flv');
      expect(backend.inputs.last.$2, {'x-test': 'direct'});
      expect(backend.inputs.last.$3, isFalse);
      expect(pool.leases.single.closes, 1);
    } finally {
      await cell.disposePlayer();
    }
  });
  test('close during owned acquisition cancels and joins late lease cleanup', () async {
    final ready = Completer<void>();
    final input = Completer<PlaybackInputLease>();
    final lease = _Lease(0)..cleanup = Completer<void>();
    CancelToken? cancel;
    final backend = _Backend();
    final cell = MultiviewCellPlayer(renderWidth: 640, renderHeight: 360, backend: backend);
    final observed = expectLater(
      cell.startOwned(
        OwnedPlaybackSource(
          identity: 'pending',
          createInput: (token) {
            cancel = token;
            ready.complete();
            return input.future;
          },
        ),
      ),
      throwsStateError,
    );
    await ready.future;
    var closed = false;
    final closing = cell.disposePlayer().then((_) => closed = true);
    try {
      await tick();
      expect(cancel!.isCancelled, isTrue);
      expect(closed, isFalse);
      input.complete(lease.input);
      await tick();
      expect(lease.closes, 1);
      expect(backend.starts, 0);
      expect(closed, isFalse);
    } finally {
      if (!input.isCompleted) input.complete(lease.input);
      lease.cleanup!.complete();
      await observed;
      await closing;
    }
    expect(backend.disposes, 1);
  });
  test('new request cancels a pending owned factory before native serialization can proceed', () async {
    final pool = _Pool();
    final backend = _Backend();
    final cell = MultiviewCellPlayer(renderWidth: 640, renderHeight: 360, backend: backend);
    final ready = Completer<void>();
    CancelToken? cancel;
    try {
      await cell.startOwned(pool.source('old'));
      final abandoned = expectLater(
        cell.openOwned(
          OwnedPlaybackSource(
            identity: 'pending',
            createInput: (token) async {
              cancel = token;
              ready.complete();
              await token.whenCancel;
              throw token.cancelError!;
            },
          ),
        ),
        throwsA(isA<DioException>()),
      );
      await ready.future;
      final next = cell.openOwned(pool.source('new'));
      await abandoned;
      await next;
      expect(cancel!.isCancelled, isTrue);
      expect(backend.inputs, hasLength(2));
      expect(pool.leases.map((e) => e.closes), [1, 0]);
    } finally {
      await cell.disposePlayer();
    }
  });

  test('replacement during initial owned acquisition performs native start exactly once', () async {
    final pool = _Pool();
    final backend = _Backend();
    final cell = MultiviewCellPlayer(renderWidth: 640, renderHeight: 360, backend: backend);
    final ready = Completer<void>();
    try {
      final abandoned = expectLater(
        cell.startOwned(
          OwnedPlaybackSource(
            identity: 'initial',
            createInput: (token) async {
              ready.complete();
              await token.whenCancel;
              throw token.cancelError!;
            },
          ),
        ),
        throwsA(isA<DioException>()),
      );
      await ready.future;
      final next = cell.openOwned(pool.source('replacement'));
      await abandoned;
      await next;
      expect(backend.starts, 1);
      expect(backend.opens, 0);
      expect(pool.requests, ['replacement']);
    } finally {
      await cell.disposePlayer();
    }
  });
  test('pause while owned input opens remains paused and ordinary resume retains the valid seat', () async {
    final pool = _Pool();
    final backend = _Backend()..gate = Completer<void>();
    final cell = MultiviewCellPlayer(renderWidth: 640, renderHeight: 360, backend: backend);
    final opening = cell.startOwned(pool.source());
    try {
      await tick();
      await cell.pause();
      backend.gate!.complete();
      await opening;
      expect(cell.isPlaying, isFalse);
      await cell.resume();
      expect(cell.isPlaying, isTrue);
      expect(pool.leases, hasLength(1));
      expect(backend.resumes, 1);
    } finally {
      if (backend.gate?.isCompleted == false) backend.gate!.complete();
      await opening;
      await cell.disposePlayer();
    }
  });
  test('resume after remote session closure reacquires once instead of reusing an expired URI', () async {
    final pool = _Pool();
    final backend = _Backend();
    final cell = MultiviewCellPlayer(renderWidth: 640, renderHeight: 360, backend: backend);
    try {
      await cell.startOwned(pool.source());
      await cell.pause();
      pool.leases.first.usable = false;
      await Future.wait([cell.resume(), cell.resume()]);
      expect(pool.leases, hasLength(2));
      expect(backend.opens, 1);
      expect(backend.resumes, 0);
      expect(pool.leases.first.closes, 1);
      expect(cell.isPlaying, isTrue);
    } finally {
      await cell.disposePlayer();
    }
  });

  test('stale resume never replaces a newer explicit source request', () async {
    final pool = _Pool();
    final backend = _Backend();
    final cell = MultiviewCellPlayer(renderWidth: 640, renderHeight: 360, backend: backend);
    try {
      await cell.startOwned(pool.source('old'));
      await cell.pause();
      pool.leases.first.usable = false;
      final resuming = cell.resume();
      final replacing = cell.openOwned(pool.source('new'));
      await Future.wait([resuming, replacing]);
      expect(pool.leases, hasLength(2));
      expect(pool.requests, ['old', 'new']);
      expect(backend.inputs, hasLength(2));
    } finally {
      await cell.disposePlayer();
    }
  });
  test('pause during expired-session renewal wins over the pending native open', () async {
    final pool = _Pool();
    final backend = _Backend();
    final cell = MultiviewCellPlayer(renderWidth: 640, renderHeight: 360, backend: backend);
    try {
      await cell.startOwned(pool.source());
      await cell.pause();
      pool.leases.first.usable = false;
      backend.gate = Completer<void>();
      final resuming = cell.resume();
      await tick();
      await cell.pause();
      backend.gate!.complete();
      await resuming;
      expect(cell.isPlaying, isFalse);
      expect(pool.leases, hasLength(2));
      expect(backend.resumes, 0);
    } finally {
      if (backend.gate?.isCompleted == false) backend.gate!.complete();
      await cell.disposePlayer();
    }
  });
  test('controller uses real per-cell owners for independent source and quality state', () async {
    final h = _Harness();
    final c = h.controller;
    try {
      await c.assignRoom(0, room());
      await c.assignRoom(1, room());
      expect(c.cells.take(2).map((e) => e.status), everyElement(MultiviewCellStatus.playing));
      expect(c.cells[0].lineCount, 1);
      expect(c.cells[0].lines, isEmpty);
      expect(c.cells[0].ownedSource!.identity, contains('800x450'));
      expect(h.backends[0].muted, isTrue);
      expect(h.backends[1].muted, isFalse);
      expect(h.backends[1].volume, .4);
      await c.setCellQuality(0, 1);
      expect(c.cells[0].qualityIndex, 1);
      expect(c.cells[0].ownedSource!.identity, contains('512x288'));
      expect(c.cells[0].lineIndex, 0);
      expect(c.cells[1].ownedSource!.identity, contains('800x450'));
      expect(h.pool.leases.map((e) => e.closes), [1, 0, 0]);
      expect(c.cells[0].headers, isEmpty);
      c.removeCell(0);
      await tick();
      expect(c.cells[0].ownedSource, isNull);
      expect(h.pool.leases[2].closes, 1);
      expect(h.pool.leases[1].closes, 0);
    } finally {
      await c.disposeAll();
    }
    expect(h.pool.leases.map((e) => e.closes), [1, 1, 1]);
  });
  test('controller switches direct lines to owned and back without stale line or source state', () async {
    final pool = _Pool();
    final qualities = [LivePlayQuality(quality: 'Direct', id: 1), LivePlayQuality(quality: 'Owned', id: 2)];
    late MultiviewQualityLoader load;
    load = (q) async => q.selectionId == 2
        ? MultiviewStreamSource.owned(source: pool.source(), qualities: qualities, qualityIndex: 1, qualityLoader: load)
        : MultiviewStreamSource(
            url: 'https://direct/0',
            headers: const {},
            lines: const ['https://direct/0', 'https://direct/1'],
            qualities: qualities,
            qualityLoader: load,
          );
    final h = _Harness(resolver: (_, {required preferLowest}) => load(qualities.first));
    final c = h.controller;
    try {
      await c.assignRoom(0, room());
      await c.setCellLine(0, 1);
      await c.setCellQuality(0, 1);
      expect(c.cells[0].ownedSource, isNotNull);
      expect(c.cells[0].lines, isEmpty);
      expect(c.cells[0].lineIndex, 0);
      await c.setCellQuality(0, 0);
      expect(c.cells[0].ownedSource, isNull);
      expect(c.cells[0].lines, hasLength(2));
      expect(c.cells[0].lineIndex, 0);
      expect(pool.leases.single.closes, 1);
      expect(h.backends.single.inputs.last.$3, isFalse);
    } finally {
      await c.disposeAll();
    }
  });

  test('controller presents failed session renewal instead of leaking an unhandled UI future', () async {
    final lease = _Lease(0);
    var attempts = 0;
    final source = OwnedPlaybackSource(
      identity: 'expires',
      createInput: (_) async {
        if (++attempts > 1) throw StateError('metadata fixture ended');
        return lease.input;
      },
    );
    final h = _Harness(resolver: (_, {required preferLowest}) async => MultiviewStreamSource.owned(source: source));
    try {
      await h.controller.assignRoom(0, room());
      await h.controller.toggleCellPlayPause(0);
      lease.usable = false;
      await h.controller.toggleCellPlayPause(0);
      expect(h.controller.cells[0].status, MultiviewCellStatus.error);
      expect(h.controller.cells[0].errorKind, MultiviewCellErrorKind.startFailure);
      expect(h.controller.playingFlags[0], isFalse);
    } finally {
      await h.controller.disposeAll();
    }
  });
  test('removing a cell during resume suppresses the stale completion and failure state', () async {
    final lease = _Lease(0);
    final ready = Completer<void>();
    var attempts = 0;
    CancelToken? renewal;
    final source = OwnedPlaybackSource(
      identity: 'expires',
      createInput: (token) async {
        if (++attempts == 1) return lease.input;
        renewal = token;
        ready.complete();
        await token.whenCancel;
        throw token.cancelError!;
      },
    );
    final h = _Harness(resolver: (_, {required preferLowest}) async => MultiviewStreamSource.owned(source: source));
    await h.controller.assignRoom(0, room());
    await h.controller.toggleCellPlayPause(0);
    lease.usable = false;
    final resuming = h.controller.toggleCellPlayPause(0);
    await ready.future;
    h.controller.removeCell(0);
    try {
      await resuming;
      expect(renewal!.isCancelled, isTrue);
      expect(h.controller.cells[0].status, MultiviewCellStatus.empty);
      expect(h.controller.playingFlags[0], isFalse);
      expect(h.controller.cells[0].errorKind, isNull);
    } finally {
      await h.controller.disposeAll();
    }
    expect(lease.closes, 1);
    expect(h.backends.single.disposes, 1);
  });
  test('page teardown joins previously removed owned acquisition and late cleanup', () async {
    final ready = Completer<void>();
    final input = Completer<PlaybackInputLease>();
    final lease = _Lease(0)..cleanup = Completer<void>();
    CancelToken? cancel;
    final source = OwnedPlaybackSource(
      identity: 'pending',
      createInput: (token) {
        cancel = token;
        ready.complete();
        return input.future;
      },
    );
    final h = _Harness(resolver: (_, {required preferLowest}) async => MultiviewStreamSource.owned(source: source));
    final assigning = h.controller.assignRoom(0, room());
    await ready.future;
    h.controller.removeCell(0);
    var closed = false;
    final closing = h.controller.disposeAll().then((_) => closed = true);
    try {
      await tick();
      expect(cancel!.isCancelled, isTrue);
      expect(closed, isFalse);
      input.complete(lease.input);
      await tick();
      expect(closed, isFalse);
      expect(lease.closes, 1);
    } finally {
      if (!input.isCompleted) input.complete(lease.input);
      lease.cleanup!.complete();
      await assigning;
      await closing;
    }
    expect(h.backends.single.starts, 0);
    expect(h.backends.single.disposes, 1);
    expect(h.controller.cells[0].status, MultiviewCellStatus.empty);
  });
}
