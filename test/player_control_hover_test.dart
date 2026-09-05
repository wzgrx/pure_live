import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings/font_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/live_play/controllers/player_state.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';

class _FontSettings implements FontSettingsController {
  @override
  final fontSizeTitleMedium = 15.0.obs;
  @override
  final fontSizeTitleLarge = 20.0.obs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends SettingsService {
  @override
  final font = _FontSettings();
  @override
  // This fixture intentionally skips persistence and background-service startup.
  // ignore: must_call_super
  void onInit() {}
}

class _HoverController implements VideoController {
  @override
  final showController = true.obs;
  @override
  final showLocked = false.obs;
  @override
  final audioModeSwitching = false.obs;
  @override
  final audioOnlyState = false.obs;
  @override
  bool get isAudioOnly => audioOnlyState.value;
  @override
  final room = LiveRoom(platform: 'huya', roomId: 'fixture', title: 'Live fixture');
  final owners = <Object?>{};
  int enters = 0;
  int exits = 0;
  int taps = 0;

  @override
  void onMouseEnterController([Object? owner]) {
    enters++;
    owners.add(owner);
  }

  @override
  void onMouseExitController([Object? owner]) {
    exits++;
    owners.remove(owner);
  }

  @override
  void enableController() {}

  @override
  Future<void> toggleAudioOnly() async {
    taps++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('production top controls acquire and release their hover ownership', (tester) async {
    Get.testMode = true;
    Get.put(GlobalPlayerState());
    Get.put<SettingsService>(_Settings());
    addTearDown(() {
      Get.reset();
      Get.testMode = false;
    });
    final controller = _HoverController();
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Stack(children: [TopActionBar(controller: controller, barHeight: 56)]),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 200));
    await mouse.moveTo(const Offset(200, 28));
    await tester.pump();
    expect(controller.owners, hasLength(1), reason: 'A visible action bar must pin controls while hovered.');
    await mouse.moveTo(const Offset(240, 28));
    await tester.pump(const Duration(seconds: 5));
    expect(controller.enters, 1, reason: 'Pointer motion inside the bar must not allocate repeated owners.');
    expect(controller.owners, hasLength(1));
    await mouse.moveTo(const Offset(200, 180));
    await tester.pump();
    expect(controller.owners, isEmpty);
    expect(controller.exits, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
