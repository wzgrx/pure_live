import 'package:pure_live/player/core/playback_source.dart';

import 'dart:async';

import 'package:drift/native.dart';
import 'package:pure_live/core/iptv/local/database.dart';
import 'package:pure_live/core/iptv/local/epg_channel_identity.dart';
import 'package:pure_live/common/services/settings/iptv_settings_controller.dart';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/app_refresh_rate_mode.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings/app_settings_controller.dart';
import 'package:pure_live/common/services/settings/danmaku_settings_controller.dart';
import 'package:pure_live/common/services/settings/player_settings_controller.dart';
import 'package:pure_live/common/services/settings/volume_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/player/core/engine_fallback_manager.dart';
import 'package:pure_live/player/core/line_fallback_manager.dart';
import 'package:pure_live/player/core/player_manager.dart';
import 'package:pure_live/player/core/portrait_stream_support.dart';
import 'package:pure_live/player/interface/unified_player_interface.dart';
import 'package:pure_live/player/models/player_engine.dart';
import 'package:pure_live/player/models/player_exception.dart';
import 'package:pure_live/plugins/db_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Get.testMode = true;
    Get.put(GlobalPlayerState());
    Get.put<SettingsService>(_TestSettings());
  });

  tearDown(() {
    Get.reset();
    Get.testMode = false;
  });

  for (final reuse in [false, true]) {
    test('VideoController owned source dispatch/reentry (reuse=$reuse) uses no media placeholder', () async {
      final room = LiveRoom(platform: 'fixture', roomId: 'room');
      final source = OwnedPlaybackSource(
        identity: 'owned',
        createInput: (_) => throw StateError('dispatch-only fixture'),
      );
      final commit = PlaybackSourceCommitSnapshot(
        revision: 1,
        sessionId: 1,
        intentRevision: 1,
        room: room,
        urls: const [],
        source: source,
        currentLineIndex: 0,
        headers: const {},
        audioOnly: false,
        selection: null,
      );
      final manager = _FakePlayerManager(room, reuse ? commit : null);
      addTearDown(manager.disposeFixture);
      final received = <PlaybackSourceCommitSnapshot>[];
      final controller = _controller(
        room: room,
        manager: manager,
        reuseCurrentSession: reuse,
        ownedSource: source,
        onSourceCommitted: received.add,
      );
      await controller.initialization;
      expect(manager.playCalls, 0);
      expect(manager.ownedCalls, reuse ? isEmpty : [same(source)]);
      expect(received, reuse ? [same(commit)] : isEmpty);
      expect(controller.datasource, isEmpty);
      expect(controller.playUrs, isEmpty);
      controller.dispose();
    });
  }

  test('retained VideoController replays and follows only canonical room source commits', () async {
    final room = LiveRoom(platform: 'fixture', roomId: 'room');
    final canonical = _commit(revision: 5, room: room, url: 'https://fixture/retained.flv');
    final manager = _FakePlayerManager(room, canonical);
    final received = <PlaybackSourceCommitSnapshot>[];
    final controller = _controller(
      room: room,
      manager: manager,
      reuseCurrentSession: true,
      onSourceCommitted: received.add,
    );
    addTearDown(manager.disposeFixture);

    await controller.initialization;
    expect(received, <PlaybackSourceCommitSnapshot>[canonical]);

    final stale = _commit(revision: 4, room: room, url: 'https://fixture/stale.flv');
    manager.current = stale;
    manager.emit(stale);
    await Future<void>.delayed(Duration.zero);
    expect(received, <PlaybackSourceCommitSnapshot>[canonical]);

    final noncurrent = _commit(revision: 6, room: room, url: 'https://fixture/noncurrent.flv');
    manager.current = canonical;
    manager.emit(noncurrent);
    await Future<void>.delayed(Duration.zero);
    expect(received, <PlaybackSourceCommitSnapshot>[canonical]);

    final otherRoom = _commit(
      revision: 6,
      room: LiveRoom(platform: 'fixture', roomId: 'other'),
      url: 'https://fixture/other.flv',
    );
    manager.current = otherRoom;
    manager.emit(otherRoom);
    await Future<void>.delayed(Duration.zero);
    expect(received, <PlaybackSourceCommitSnapshot>[canonical]);

    final latest = _commit(revision: 7, room: room, url: 'https://fixture/latest.flv');
    manager.current = latest;
    manager.emit(latest);
    await Future<void>.delayed(Duration.zero);
    expect(received, <PlaybackSourceCommitSnapshot>[canonical, latest]);

    manager.emit(latest);
    await Future<void>.delayed(Duration.zero);
    expect(received, <PlaybackSourceCommitSnapshot>[canonical, latest]);

    controller.dispose();
    final afterDispose = _commit(revision: 8, room: room, url: 'https://fixture/disposed.flv');
    manager.current = afterDispose;
    manager.emit(afterDispose);
    await Future<void>.delayed(Duration.zero);

    expect(received, <PlaybackSourceCommitSnapshot>[canonical, latest]);
  });

  test('new VideoController does not replay a previous same-room source commit', () async {
    final room = LiveRoom(platform: 'fixture', roomId: 'room');
    final previous = _commit(revision: 10, room: room, url: 'https://fixture/previous.flv');
    final manager = _FakePlayerManager(room, previous, emitCurrentOnListen: true);
    final received = <PlaybackSourceCommitSnapshot>[];
    final controller = _controller(
      room: room,
      manager: manager,
      reuseCurrentSession: false,
      onSourceCommitted: received.add,
    );
    addTearDown(manager.disposeFixture);

    await controller.initialization;

    expect(manager.playCalls, 1);
    expect(received, isEmpty);
    controller.dispose();
  });
  test('video schedule resolves old room IDs only in the selected EPG source', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    for (final source in ['A', 'B']) {
      await db.upsertEpgSource(
        EpgSourcesCompanion.insert(id: source, name: source, url: 'https://fixture/$source.xml'),
      );
      await db.upsertEpgChannels([
        EpgChannelsCompanion.insert(
          id: epgChannelKey(source, 'common'),
          sourceId: source,
          channelId: 'common',
          displayName: 'Common',
        ),
      ]);
      await db.insertProgrammes([
        EpgProgrammesCompanion.insert(
          sourceId: source,
          epgChannelId: epgChannelKey(source, 'common'),
          title: source,
          start: now.subtract(const Duration(minutes: 1)),
          stop: now.add(const Duration(minutes: 30)),
        ),
      ]);
    }
    final room = LiveRoom(platform: 'fixture', roomId: 'room');
    final manager = _FakePlayerManager(room, _commit(revision: 5, room: room, url: 'https://fixture/retained.flv'));
    addTearDown(manager.disposeFixture);
    final controller = _controller(
      room: room,
      manager: manager,
      reuseCurrentSession: true,
      onSourceCommitted: (_) {},
      dbService: DbService()..db = db,
    );
    await controller.initialization;
    try {
      SettingsService.to.iptv.selectedSourceId.value = 'B';
      await controller.loadFullChannelSchedule('common');
      expect(controller.currentChannelSchedule.map((p) => p.title), ['B']);
      await controller.loadFullChannelSchedule(epgChannelKey('A', 'common'));
      expect(controller.currentChannelSchedule, isEmpty);
      await controller.loadFullChannelSchedule(epgChannelKey('B', 'common'));
      expect(controller.currentChannelSchedule.map((p) => p.title), ['B']);
      SettingsService.to.iptv.selectedSourceId.value = '';
      await controller.loadFullChannelSchedule('common');
      expect(controller.currentChannelSchedule, isEmpty);
    } finally {
      controller.dispose();
    }
  });
}

VideoController _controller({
  required LiveRoom room,
  required _FakePlayerManager manager,
  required bool reuseCurrentSession,
  required ValueChanged<PlaybackSourceCommitSnapshot> onSourceCommitted,
  DbService? dbService,
  OwnedPlaybackSource? ownedSource,
}) {
  return VideoController(
    room: room,
    datasource: ownedSource == null ? 'https://fixture/requested.flv' : '',
    ownedSource: ownedSource,
    headers: const <String, String>{},
    playUrs: ownedSource == null ? const <String>['https://fixture/requested.flv'] : const [],
    qualiteName: 'fixture',
    currentLineIndex: 0,
    currentQuality: 0,
    isAudioOnly: false,
    reuseCurrentSession: reuseCurrentSession,
    onSourceCommitted: onSourceCommitted,
    battery: _FakeBattery(),
    playerManager: manager,
    settingsService: SettingsService.to,
    dbService: dbService ?? _FakeDbService(),
    livePlayController: _FakeLivePlayController(),
  );
}

PlaybackSourceCommitSnapshot _commit({required int revision, required LiveRoom room, required String url}) {
  return PlaybackSourceCommitSnapshot(
    revision: revision,
    sessionId: 3,
    intentRevision: 9,
    room: room,
    urls: <String>[url],
    currentUrl: url,
    currentLineIndex: 0,
    headers: const <String, String>{},
    audioOnly: false,
    selection: null,
  );
}

class _FakePlayerManager extends PlayerManager {
  _FakePlayerManager(LiveRoom room, this.current, {this.emitCurrentOnListen = false})
    : super(
        fallbackManager: EngineFallbackManager(
          defaultEngine: PlayerEngine.mediaKit,
          supportedEngines: const <PlayerEngine>[PlayerEngine.mediaKit],
        ),
        lineManager: LineFallbackManager(),
        playerCreator: (_) => _StubPlayer(),
        useHardStopOnExit: () => false,
        audioSessionStart: (_) async {},
      ) {
    currentFloatRoom = room;
    _commits = StreamController<PlaybackSourceCommitSnapshot>.broadcast(
      sync: true,
      onListen: () {
        final snapshot = current;
        if (emitCurrentOnListen && snapshot != null) _commits.add(snapshot);
      },
    );
  }

  late final StreamController<PlaybackSourceCommitSnapshot> _commits;
  final _player = _StubPlayer();
  final bool emitCurrentOnListen;
  PlaybackSourceCommitSnapshot? current;
  int playCalls = 0;
  final ownedCalls = <PlaybackSource>[];
  bool _fixtureDisposed = false;

  void emit(PlaybackSourceCommitSnapshot snapshot) => _commits.add(snapshot);

  @override
  PlaybackSourceCommitSnapshot? get currentSourceCommit => current;

  @override
  Stream<PlaybackSourceCommitSnapshot> get onSourceCommitted => _commits.stream;

  @override
  bool isSourceCommitCurrent(PlaybackSourceCommitSnapshot snapshot) => identical(current, snapshot);

  @override
  UnifiedPlayer? get currentPlayer => _player;

  @override
  bool get desiredAudioOnlyMode => false;

  @override
  Stream<PlayerException> get onError => const Stream<PlayerException>.empty();

  @override
  Stream<bool> get onPlaying => const Stream<bool>.empty();

  @override
  Stream<bool> get onLoading => const Stream<bool>.empty();

  @override
  Future<void> play(
    String url,
    List<String> playUrls,
    Map<String, String> headers, {
    LiveRoom? room,
    bool audioOnly = false,
    PlaybackSourceResolver? sourceResolver,
    DateTime? sourceRefreshAt,
    PlaybackSourceQualitySelection? sourceSelection,
  }) async {
    playCalls++;
    currentFloatRoom = room;
  }

  @override
  Future<void> playSource(
    PlaybackSource source, {
    List<String> playUrls = const [],
    Map<String, String> headers = const {},
    LiveRoom? room,
    bool audioOnly = false,
    PlaybackSourceResolver? sourceResolver,
    DateTime? sourceRefreshAt,
    PlaybackSourceQualitySelection? sourceSelection,
  }) async {
    expect(playUrls, isEmpty);
    expect(headers, isEmpty);
    ownedCalls.add(source);
    currentFloatRoom = room;
  }

  Future<void> disposeFixture() async {
    if (_fixtureDisposed) return;
    _fixtureDisposed = true;
    await _commits.close();
    await super.dispose();
  }
}

class _StubPlayer implements UnifiedPlayer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestSettings extends SettingsService {
  @override
  final iptv = _TestIptvSettings();
  @override
  final app = _TestAppSettings();
  @override
  final danmaku = _TestDanmakuSettings();
  @override
  final player = _TestPlayerSettings();
  @override
  final vol = _TestVolumeSettings();

  @override
  // The fixture owns in-memory settings and starts no persistent services.
  // ignore: must_call_super
  void onInit() {}
}

class _TestAppSettings implements AppSettingsController {
  @override
  final enableFullScreenDefault = false.obs;
  @override
  final refreshRateModeName = AppRefreshRateMode.powerSaving.storageValue.obs;
  @override
  AppRefreshRateMode get refreshRateMode => AppRefreshRateMode.powerSaving;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDanmakuSettings implements DanmakuSettingsController {
  @override
  final hideDanmaku = false.obs;
  @override
  final noEmojiMode = false.obs;
  @override
  final danmakuTopArea = 0.0.obs;
  @override
  final danmakuArea = 1.0.obs;
  @override
  final danmakuBottomArea = 0.5.obs;
  @override
  final danmakuSpeed = 120.0.obs;
  @override
  final danmakuFontSize = 16.0.obs;
  @override
  final danmakuFontWeight = 500.obs;
  @override
  final danmakuFontBorder = 1.5.obs;
  @override
  final danmakuOpacity = 1.0.obs;
  @override
  final enableDanmakuStroke = true.obs;
  @override
  final danmakuFps = 60.obs;
  @override
  final danmakuAutoFps = false.obs;
  @override
  final danmakuFontFamilyName = 'Default'.obs;

  @override
  int resolvedDanmakuFps({bool pip = false, AppRefreshRateMode refreshRateMode = AppRefreshRateMode.powerSaving}) =>
      pip ? 30 : 60;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestPlayerSettings implements PlayerSettingsController {
  @override
  final videoFitIndex = 0.obs;
  @override
  final enablePortraitStreamAdaptation = true.obs;
  @override
  final portraitPipFollowSource = true.obs;
  @override
  List<BoxFit> get videoFitArray => const <BoxFit>[BoxFit.contain];
  @override
  PortraitOrientationOverride portraitOverrideForRoom(LiveRoom? room) => PortraitOrientationOverride.automatic;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestVolumeSettings implements VolumeSettingsController {
  @override
  final defaultMobileVolume = 0.5.obs;
  @override
  final defaultDesktopVolume = 1.0.obs;
  @override
  final globalVolumeMute = false.obs;
  @override
  Map<String, double> roomVolumes = <String, double>{};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBattery implements Battery {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDbService extends DbService {}

class _FakeLivePlayController implements LivePlayController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestIptvSettings implements IptvSettingsController {
  @override
  final selectedSourceId = ''.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
