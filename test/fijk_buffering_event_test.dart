import 'dart:async';
import 'dart:io';

import 'package:flv_lzc/fijkplayer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/player/adapters/fijk_adapter.dart';
import 'package:pure_live/player/models/player_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory hiveDirectory;
  late _NativeFijkFixture native;
  late FijkAdapter adapter;
  late List<bool> loading;
  late List<PlayerState> states;
  late List<StreamSubscription<dynamic>> subscriptions;

  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-fijk-buffering-test-');
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
  });

  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put(SettingsService());
    native = _NativeFijkFixture()..install();
    adapter = FijkAdapter();
    loading = [];
    states = [];
    subscriptions = [adapter.onLoading.listen(loading.add), adapter.onStateChanged.listen(states.add)];
    await adapter.init();
  });

  tearDown(() async {
    await adapter.hardDispose();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    native.uninstall();
    Get.reset();
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDirectory.delete(recursive: true);
  });

  Future<void> open() =>
      adapter.setDataSource('https://cdn.example/live.flv', const ['https://cdn.example/live.flv'], const {});

  test('native freeze events reach loading without pausing or reopening the source', () async {
    await open();
    await native.flush();
    expect(loading.last, isFalse);
    await native.freeze(true);
    expect(loading.last, isTrue);
    expect(states.last, PlayerState.buffering);
    expect(adapter.isPlayingNow, isTrue);
    final updates = loading.length;
    await native.freeze(true);
    expect(loading.length, updates, reason: 'duplicate native buffering must not restart watchdogs');
    await native.freeze(false);
    expect(loading.last, isFalse);
    expect(states.last, PlayerState.playing);
    expect(native.openCalls, 1);
    expect(native.pauseCalls, 0);
  });

  test('geometry and rendering events do not clear ongoing native buffering', () async {
    await open();
    await native.freeze(true);
    await native.send({'event': 'size_changed', 'width': 720, 'height': 1280});
    await native.send({'event': 'rendering_start', 'type': 'video'});
    expect(loading.last, isTrue);
    expect(states.last, PlayerState.buffering);
  });

  test('buffering before open completes survives the source snapshot and finally', () async {
    native.freezeDuringPrepare = true;
    await open();
    await native.flush();
    expect(loading.last, isTrue);
    expect(states.last, PlayerState.buffering);
    await native.freeze(false);
    expect(loading.last, isFalse);
  });

  test('pause clears loading and resume retains the actual source buffer state', () async {
    await open();
    await native.freeze(true);
    await adapter.pause();
    await native.flush();
    expect(loading.last, isFalse);
    expect(states.last, PlayerState.paused);
    await native.freeze(true);
    expect(loading.last, isFalse);
    await adapter.play();
    await native.flush();
    expect(loading.last, isTrue);
    expect(states.last, PlayerState.buffering);
    await native.freeze(false);
    expect(loading.last, isFalse);
    expect(native.openCalls, 1);
  });

  test('new source does not inherit the previous native buffering snapshot', () async {
    await open();
    await native.freeze(true);
    // The vendored player retains isBuffering across reset without freeze=end.
    // The adapter must scope its observations to each source instead.
    expect(adapter.fijkPlayer.isBuffering, isTrue);
    await open();
    await native.flush();
    expect(loading.last, isFalse);
    expect(states.last, PlayerState.playing);
    expect(native.openCalls, 2);
  });

  test('source transition and stop reject late buffering from the retired source', () async {
    await open();
    adapter.beginSourceTransition();
    await native.freeze(false);
    await native.send({'event': 'size_changed', 'width': 800, 'height': 450});
    expect(loading.last, isTrue, reason: 'retired source must not finish the next source loading');
    await open();
    await adapter.softStop();
    await native.freeze(true);
    expect(loading.last, isFalse);
    expect(states.last, PlayerState.idle);
    expect(adapter.isPlayingNow, isFalse);
  });

  test('disposing closes the event subscription and tolerates a late event', () async {
    await open();
    await native.freeze(true);
    await adapter.hardDispose();
    expect(native.eventCancelCalls, 1);
    expect(native.releaseCalls, 1);
    final count = loading.length;
    await native.freeze(false);
    expect(loading.length, count);
  });
}

/// Drive the vendored Dart FijkPlayer through its production channel contract,
/// not an adapter substitute; no native process, phone or network is used.
class _NativeFijkFixture {
  static const plugin = MethodChannel('befovy.com/fijk');
  static const player = MethodChannel('befovy.com/fijkplayer/4100');
  static const event = MethodChannel('befovy.com/fijkplayer/event/4100');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var state = FijkState.idle;
  var openCalls = 0;
  var pauseCalls = 0;
  var releaseCalls = 0;
  var eventCancelCalls = 0;
  bool freezeDuringPrepare = false;

  void install() {
    messenger.setMockMethodCallHandler(plugin, (call) async {
      if (call.method == 'createPlayer') return 4100;
      if (call.method == 'releasePlayer') releaseCalls++;
      return null;
    });
    messenger.setMockMethodCallHandler(event, (call) async {
      if (call.method == 'cancel') eventCancelCalls++;
      return null;
    });
    messenger.setMockMethodCallHandler(player, (call) async {
      switch (call.method) {
        case 'setDataSource':
          openCalls++;
          await change(FijkState.initialized);
        case 'prepareAsync':
          await change(FijkState.asyncPreparing);
          await change(FijkState.prepared);
          await change(FijkState.started);
          if (freezeDuringPrepare) await freeze(true);
        case 'pause':
          pauseCalls++;
          await change(FijkState.paused);
        case 'start':
          await change(FijkState.started);
        case 'stop':
          await change(FijkState.stopped);
        case 'reset':
          await change(FijkState.idle);
      }
      return null;
    });
  }

  Future<void> change(FijkState next) async {
    final previous = state;
    state = next;
    await send({'event': 'state_change', 'new': next.index, 'old': previous.index});
  }

  Future<void> freeze(bool value) => send({'event': 'freeze', 'value': value});

  Future<void> send(Map<String, Object> value) async {
    await messenger.handlePlatformMessage(event.name, const StandardMethodCodec().encodeSuccessEnvelope(value), (_) {});
    await flush();
  }

  Future<void> flush() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  void uninstall() {
    for (final channel in [plugin, player, event]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}
