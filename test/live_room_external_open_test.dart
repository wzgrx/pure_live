import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/states/live_play_state.dart';
import 'package:pure_live/modules/live_play/states/room_state.dart';
import 'package:pure_live/modules/live_play/widgets/local_interaction/local_interaction_controller.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_controller.dart';

// Constructor-only controller: do not start a player, timers, disk services or
// network requests. The real menu entry method and launcher channel still run.
class _Recorder extends Fake implements RecorderController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Interaction extends Fake implements LocalInteractionController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launches = <Map<Object?, Object?>>[];
  final owners = <LivePlayController>[];
  var launchResult = true;
  var throwLaunch = false;
  Completer<bool>? pendingLaunch;

  LivePlayController controller(String site, {String? roomId = '12345', Object? danmakuData}) {
    final room = LiveRoom(roomId: roomId, platform: site, danmakuData: danmakuData);
    final owner = LivePlayController(room: room, site: site);
    owner.state.value = LivePlayState(room: RoomState(detail: room));
    owners.add(owner);
    return owner;
  }

  setUp(() {
    launches.clear();
    launchResult = true;
    throwLaunch = false;
    pendingLaunch = null;
    // The fake dependency lifecycle is inert; no real service starts.
    Get.lazyPut<RecorderController>(() => _Recorder());
    Get.lazyPut<LocalInteractionController>(() => _Interaction());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'launch') throw StateError('Unexpected launcher call: ${call.method}');
      launches.add(Map<Object?, Object?>.from(call.arguments as Map));
      if (pendingLaunch != null) return pendingLaunch!.future;
      if (throwLaunch) throw PlatformException(code: 'fixture-launch-failure');
      return launchResult;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    for (final owner in owners) {
      // onInit was never invoked; invoking onClose would refer to absent player
      // children. Only the constructor's public reactive values need closing.
      owner.state.close();
      owner.danmakuMessages.close();
      owner.danmakuPresentationRevision.close();
      owner.localGiftEffect.close();
      owner.superChats.close();
    }
    owners.clear();
    Get.reset();
  });

  test('YY menu hands the official room URL to the external launcher', () async {
    await controller(Sites.yySite).openNaviteAPP();
    expect(launches.map((call) => call['url']), ['https://www.yy.com/12345']);
    expect(launches.single['useWebView'], isFalse);
    expect(launches.single['useSafariVC'], isFalse);
  });

  for (final site in ['unknown-fixture', Sites.iptvSite]) {
    test('$site never hands an empty or local target to the OS', () async {
      await controller(site).openNaviteAPP();
      expect(launches, isEmpty);
    });
  }

  for (final roomId in <String?>[null, '', '  ']) {
    test('YY missing room identity $roomId does not open a guessed room', () async {
      await controller(Sites.yySite, roomId: roomId).openNaviteAPP();
      expect(launches, isEmpty);
    });
  }

  test('desktop Douyin webpage does not depend on live danmaku args', () async {
    await controller(Sites.douyinSite).openNaviteAPP();
    expect(launches.map((call) => call['url']), ['https://live.douyin.com/12345']);
  });

  test('desktop Huya webpage does not depend on live danmaku args', () async {
    await controller(Sites.huyaSite).openNaviteAPP();
    expect(launches.map((call) => call['url']), ['https://www.huya.com/12345']);
  });

  test('a failed webpage launch is contained and not retried identically', () async {
    throwLaunch = true;
    await controller(Sites.twitchSite).openNaviteAPP();
    expect(launches.length, 1);
  });

  test('false webpage result does not trigger duplicate browser launches', () async {
    launchResult = false;
    await controller(Sites.twitchSite).openNaviteAPP();
    expect(launches.length, 1);
  });

  test('missing detail does not call a launcher', () async {
    final owner = controller(Sites.yySite);
    owner.state.value = const LivePlayState();
    await owner.openNaviteAPP();
    expect(launches, isEmpty);
  });

  test('repeated menu input shares one pending launch and releases after completion', () async {
    final owner = controller(Sites.yySite);
    final pending = pendingLaunch = Completer<bool>();
    final action = owner.openNaviteAPP();
    await owner.openNaviteAPP();
    // Allow the method-channel request to reach its handler without a timer.
    await Future<void>.delayed(Duration.zero);
    expect(launches.length, 1);
    pending.complete(true);
    await action;
    pendingLaunch = null;
    await owner.openNaviteAPP();
    expect(launches.length, 2);
  });

  test('room replacement while the OS request is pending leaves the new room intact', () async {
    final owner = controller(Sites.yySite);
    final pending = pendingLaunch = Completer<bool>();
    final action = owner.openNaviteAPP();
    final next = LiveRoom(roomId: '999', platform: Sites.yySite);
    owner.state.value = LivePlayState(room: RoomState(detail: next));
    pending.complete(false);
    await action;
    expect(owner.state.value.room.detail, same(next));
    expect(launches.map((call) => call['url']), ['https://www.yy.com/12345']);
    pendingLaunch = null;
    await owner.openNaviteAPP();
    expect(launches.last['url'], 'https://www.yy.com/999');
  });
}
