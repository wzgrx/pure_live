import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/controllers/live_play_controller.dart';
import 'package:pure_live/modules/live_play/states/live_play_state.dart';
import 'package:pure_live/modules/live_play/states/room_state.dart';
import 'package:pure_live/modules/live_play/widgets/local_interaction/local_interaction_controller.dart';
import 'package:pure_live/recorder/pages/recorder/recorder_controller.dart';

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
  final owners = <LivePlayController>[];

  LivePlayController owner(IptvPlayerStarter starter, {LiveRoom? room}) {
    final initial = room ?? LiveRoom(roomId: 'fixture-room', platform: Sites.iptvSite, link: 'https://fixture/live');
    final controller = LivePlayController.withIptvPlayerStarter(starter, room: initial, site: Sites.iptvSite);
    controller.state.value = LivePlayState(room: RoomState(detail: initial, success: true));
    owners.add(controller);
    return controller;
  }

  setUp(() {
    Get.lazyPut<RecorderController>(() => _Recorder());
    Get.lazyPut<LocalInteractionController>(() => _Interaction());
  });

  tearDown(() {
    for (final owner in owners) {
      // These fixtures intentionally skip onInit, so only constructor-owned
      // reactive objects exist and need closing.
      owner.state.close();
      owner.danmakuMessages.close();
      owner.danmakuPresentationRevision.close();
      owner.localGiftEffect.close();
      owner.superChats.close();
    }
    owners.clear();
    Get.reset();
  });

  test('catch-up remains loading until the direct player starter completes', () async {
    final gate = Completer<bool>();
    final rooms = <LiveRoom>[];
    final controller = owner((room) {
      rooms.add(room);
      return gate.future;
    });

    var completed = false;
    final action = controller
        .startCatchUp(catchUpUrl: '  https://fixture/catchup  ', startTime: 1000, endTime: 2000)
        .then((value) {
          completed = true;
          return value;
        });
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    expect(rooms, hasLength(1));
    expect(rooms.single.catchUpUrl, 'https://fixture/catchup');
    expect(rooms.single.catchUpStart, 1000);
    expect(rooms.single.catchUpEnd, 2000);
    expect(controller.state.value.player.playUrls, ['https://fixture/catchup']);
    expect(controller.state.value.room.success, isFalse);
    expect(controller.state.value.room.isLoading, isTrue);

    gate.complete(true);
    expect(await action, isTrue);
    expect(controller.state.value.room.success, isTrue);
    expect(controller.state.value.room.isLoading, isFalse);
    expect(controller.state.value.room.loadError, isNull);
  });

  test('a rejected direct player start ends loading without a false success', () async {
    final controller = owner((_) async => false);

    final result = await controller.startCatchUp(catchUpUrl: 'https://fixture/rejected');

    expect(result, isFalse);
    expect(controller.state.value.room.success, isFalse);
    expect(controller.state.value.room.isLoading, isFalse);
    expect(controller.state.value.room.loadError, isNotEmpty);
  });

  test('a thrown direct player start publishes failure before propagating the error', () async {
    final controller = owner((_) async => throw StateError('fixture open failure'));

    await expectLater(controller.startCatchUp(catchUpUrl: 'https://fixture/failure'), throwsA(isA<StateError>()));

    expect(controller.state.value.room.success, isFalse);
    expect(controller.state.value.room.isLoading, isFalse);
    expect(controller.state.value.room.loadError, isNotEmpty);
  });

  test('a late older direct start cannot commit over the newer catch-up request', () async {
    final firstGate = Completer<bool>();
    final secondGate = Completer<bool>();
    final controller = owner((room) {
      return room.catchUpUrl == 'https://fixture/first' ? firstGate.future : secondGate.future;
    });

    final first = controller.startCatchUp(catchUpUrl: 'https://fixture/first', startTime: 1000, endTime: 2000);
    final second = controller.startCatchUp(catchUpUrl: 'https://fixture/second', startTime: 3000, endTime: 4000);

    secondGate.complete(true);
    expect(await second, isTrue);
    expect(controller.state.value.room.detail?.catchUpUrl, 'https://fixture/second');
    expect(controller.state.value.room.success, isTrue);

    firstGate.complete(true);
    expect(await first, isFalse);
    expect(controller.state.value.room.detail?.catchUpUrl, 'https://fixture/second');
    expect(controller.state.value.room.detail?.catchUpStart, 3000);
    expect(controller.state.value.room.success, isTrue);
  });

  test('a late older failure cannot replace or report failure for the newer request', () async {
    final firstGate = Completer<bool>();
    final secondGate = Completer<bool>();
    final controller = owner((room) {
      return room.catchUpUrl == 'https://fixture/first' ? firstGate.future : secondGate.future;
    });

    final first = controller.startCatchUp(catchUpUrl: 'https://fixture/first');
    final second = controller.startCatchUp(catchUpUrl: 'https://fixture/second');

    secondGate.complete(true);
    expect(await second, isTrue);

    firstGate.completeError(StateError('stale fixture failure'));
    expect(await first, isFalse);
    expect(controller.state.value.room.detail?.catchUpUrl, 'https://fixture/second');
    expect(controller.state.value.room.success, isTrue);
    expect(controller.state.value.room.loadError, isNull);
  });

  test('missing room identity or URL starts no direct player transaction', () async {
    var calls = 0;
    final controller = owner((_) async {
      calls++;
      return true;
    }, room: LiveRoom(roomId: ' ', platform: Sites.iptvSite));

    expect(await controller.startCatchUp(catchUpUrl: 'https://fixture/catchup'), isFalse);
    expect(await controller.startCatchUp(catchUpUrl: '   '), isFalse);
    expect(calls, 0);
  });

  test('initial IPTV setup awaits the fenced direct-source path', () {
    final liveSource = File('lib/modules/live_play/controllers/live_play_controller.dart').readAsStringSync();
    final playerSource = File('lib/modules/live_play/controllers/player_controller.dart').readAsStringSync();

    expect(liveSource, contains('await _initIptvPlayer(liveRoom, loadEpoch: loadEpoch)'));
    expect(liveSource, contains('playerController.setDirectPlayer(room: expectedRoom, site: currentSite)'));
    expect(playerSource, contains('loadEpoch: loadEpoch'));
    expect(playerSource, contains('await controller.initialization'));
  });
}
