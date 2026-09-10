import 'package:volume_controller/volume_controller.dart';
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

  VideoController volumeController(_SystemVolume volume, {String id = 'volume', _FakePlayerManager? sharedManager}) {
    final room = LiveRoom(platform: 'fixture', roomId: id);
    final manager = sharedManager ?? _FakePlayerManager(room, null);
    addTearDown(manager.disposeFixture);
    final controller = _controller(
      room: room,
      manager: manager,
      reuseCurrentSession: false,
      onSourceCommitted: (_) {},
      systemVolumeController: volume,
    );
    addTearDown(controller.dispose);
    addTearDown(volume.events.close);
    return controller;
  }

  test('system volume delayed initial read after disposal never writes the device', () async {
    final volume = _SystemVolume()..readReply = Completer<double>();
    final controller = volumeController(volume);
    await volume.readStarted.future;
    controller.dispose();
    volume.readReply!.complete(0.8);
    await controller.initialization;
    expect(volume.writes, isEmpty);
  });

  test('system volume initial snapshot does not overwrite the saved room preference', () async {
    SettingsService.to.vol.roomVolumes = {'room_vol_fixture_volume': 0.25};
    final volume = _SystemVolume()..readReply = Completer<double>();
    final controller = volumeController(volume);
    await volume.readStarted.future;
    if (volume.fetchInitial) volume.events.add(0.8);
    volume.readReply!.complete(0.8);
    await controller.initialization;
    expect(volume.writes, [0.25]);
    expect(controller.room.getSavedVolume(), 0.25);
  });

  test('system volume external event updates the visible value and saved preference', () async {
    final volume = _SystemVolume();
    final controller = volumeController(volume);
    await controller.initialization;
    volume.events.add(0.65);
    expect(controller.currentVolume.value, 0.65);
    expect(controller.room.getSavedVolume(), 0.65);
  });

  test('system volume late setter completion after disposal never publishes UI or preferences', () async {
    final volume = _SystemVolume();
    final controller = volumeController(volume);
    await controller.initialization;
    final saved = controller.room.getSavedVolume();
    final visible = controller.currentVolume.value;
    volume.writeReply = Completer<void>();
    final setting = controller.setVolume(0.3);
    controller.dispose();
    volume.writeReply!.complete();
    await setting;
    expect(controller.currentVolume.value, visible);
    expect(controller.room.getSavedVolume(), saved);
  });

  test('system volume retired room does not restore volume or replay after a newer room attaches', () async {
    SettingsService.to.vol.roomVolumes = {'room_vol_fixture_old': 0.2, 'room_vol_fixture_new': 0.6};
    final gate = Completer<double>();
    final volume = _SystemVolume()..readReply = gate;
    final manager = _FakePlayerManager(LiveRoom(platform: 'fixture', roomId: 'old'), null);
    final old = volumeController(volume, id: 'old', sharedManager: manager);
    await volume.readStarted.future;
    volume.readReply = null;
    final next = volumeController(volume, id: 'new', sharedManager: manager);
    await next.initialization;
    gate.complete(0.8);
    await old.initialization;
    expect(volume.writes, [0.6]);
    expect(manager.playCalls, 1);
    expect(manager.currentFloatRoom, next.room);
    volume.events.add(0.7);
    expect(old.room.getSavedVolume(), 0.2);
    expect(next.currentVolume.value, 0.7);
    old.dispose();
    expect(manager.ownsVideoController(next), isTrue);
  });

  test('system volume user event while initial read waits outranks the saved restore', () async {
    SettingsService.to.vol.roomVolumes = {'room_vol_fixture_volume': 0.2};
    final volume = _SystemVolume()..readReply = Completer<double>();
    final controller = volumeController(volume);
    await volume.readStarted.future;
    volume.events.add(0.45);
    volume.readReply!.complete(0.8);
    await controller.initialization;
    expect(volume.writes, isEmpty);
    expect(controller.currentVolume.value, 0.45);
    expect(controller.room.getSavedVolume(), 0.45);
  });

  test('system volume quantized native event outranks its pending setter completion', () async {
    final volume = _SystemVolume();
    final controller = volumeController(volume);
    await controller.initialization;
    volume.writeReply = Completer<void>();
    final setting = controller.setVolume(0.3);
    volume.events.add(0.267);
    volume.writeReply!.complete();
    await setting;
    expect(controller.currentVolume.value, 0.267);
    expect(controller.room.getSavedVolume(), 0.267);
  });

  test('system volume already-muted device stays muted without erasing room preference', () async {
    SettingsService.to.vol.roomVolumes = {'room_vol_fixture_volume': 0.25};
    final volume = _SystemVolume()..initialValue = 0;
    final controller = volumeController(volume);
    await controller.initialization;
    expect(volume.writes, isEmpty);
    expect(controller.currentVolume.value, 0);
    expect(controller.room.getSavedVolume(), 0.25);
  });

  test('system volume global mute still applies to an audible device', () async {
    SettingsService.to.vol.globalVolumeMute.value = true;
    final volume = _SystemVolume();
    final controller = volumeController(volume);
    await controller.initialization;
    expect(volume.writes, [0]);
    expect(controller.currentVolume.value, 0);
  });

  test('system volume rejects invalid events and ignores controls after disposal', () async {
    final volume = _SystemVolume();
    final controller = volumeController(volume);
    await controller.initialization;
    volume.writes.clear();
    volume.events.add(double.nan);
    await controller.setVolume(double.infinity);
    expect(controller.currentVolume.value, 1);
    expect(volume.writes, isEmpty);
    controller.dispose();
    await controller.setVolume(0.3);
    controller.updateVolumn(0.3);
    expect(await controller.volume(), isNull);
    expect(volume.writes, isEmpty);
    expect(controller.showVolume.value, isFalse);
  });

  test('system volume failed initial read does not prevent source dispatch', () async {
    final volume = _SystemVolume()..readError = StateError('platform read failed');
    final manager = _FakePlayerManager(LiveRoom(platform: 'fixture', roomId: 'volume'), null);
    final controller = volumeController(volume, sharedManager: manager);
    await controller.initialization;
    expect(
      manager.playCalls,
      1,
      reason: 'Volume preflight must finish before source dispatch; decoding is not simulated.',
    );
    expect(volume.writes, isEmpty);
    expect(await controller.volume(), 1);
  });

  test('system volume stalled initial read is bounded and its late result never writes', () async {
    final volume = _SystemVolume()..readReply = Completer<double>();
    final manager = _FakePlayerManager(LiveRoom(platform: 'fixture', roomId: 'volume'), null);
    final controller = volumeController(volume, sharedManager: manager);
    await controller.initialization.timeout(const Duration(seconds: 4));
    expect(
      manager.playCalls,
      1,
      reason: 'Volume preflight must finish before source dispatch; decoding is not simulated.',
    );
    volume.readReply!.complete(0.8);
    await Future<void>.delayed(Duration.zero);
    expect(volume.writes, isEmpty);
  });

  test('system volume older setter completion cannot overwrite a newer selection', () async {
    final volume = _SystemVolume();
    final controller = volumeController(volume);
    await controller.initialization;
    final firstReply = Completer<void>();
    volume.writeReply = firstReply;
    final first = controller.setVolume(0.2);
    final secondReply = Completer<void>();
    volume.writeReply = secondReply;
    final second = controller.setVolume(0.6);
    secondReply.complete();
    await second;
    firstReply.complete();
    await first;
    expect(controller.currentVolume.value, 0.6);
    expect(controller.room.getSavedVolume(), 0.6);
  });

  test('system volume in-flight query returns no value after its owner exits', () async {
    final volume = _SystemVolume();
    final controller = volumeController(volume);
    await controller.initialization;
    volume.readReply = Completer<double>();
    final read = controller.volume();
    controller.dispose();
    volume.readReply!.complete(0.3);
    expect(await read, isNull);
  });

  test('system volume observation error is contained and a later event remains usable', () async {
    final volume = _SystemVolume();
    final controller = volumeController(volume);
    await controller.initialization;
    volume.events.addError(StateError('platform observer failed'), StackTrace.current);
    volume.events.add(0.55);
    expect(controller.currentVolume.value, 0.55);
    await controller.setVolume(4);
    expect(volume.writes.last, 1);
    expect(controller.currentVolume.value, 1);
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
  VolumeController? systemVolumeController,
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
    systemVolumeController: systemVolumeController,
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

class _SystemVolume implements VolumeController {
  final events = StreamController<double>.broadcast(sync: true);
  final readStarted = Completer<void>();
  Completer<double>? readReply;
  Completer<void>? writeReply;
  final writes = <double>[];
  bool fetchInitial = false;
  double initialValue = 0.8;
  Object? readError;
  @override
  bool showSystemUI = true;
  @override
  Future<double> getVolume() {
    if (!readStarted.isCompleted) readStarted.complete();
    if (readError != null) return Future.error(readError!);
    return readReply?.future ?? Future.value(initialValue);
  }

  @override
  Future<void> setVolume(double value) async {
    writes.add(value);
    await writeReply?.future;
  }

  @override
  StreamSubscription<double> addListener(Function(double)? onData, {bool fetchInitialVolume = true}) {
    fetchInitial = fetchInitialVolume;
    return events.stream.listen(onData);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
