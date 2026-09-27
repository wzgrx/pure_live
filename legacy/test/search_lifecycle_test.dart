import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/search/search_controller.dart' as search;

class _Probe extends search.SearchController {
  final answer = Completer<bool>();
  int probes = 0;
  int dialogs = 0;
  @override
  Future<bool> isWebView2Installed() {
    probes++;
    return answer.future;
  }

  @override
  void showWebView2MissingDialog() {
    dialogs++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  setUp(() async {
    Get.testMode = true;
    Get.reset();
    await HivePrefUtil.clear();
    Get.put(SettingsService());
  });
  tearDown(Get.reset);
  tearDownAll(Hive.close);

  testWidgets('closed search page does not launch queued Windows probe', (tester) async {
    final c = _Probe();
    c.onInit();
    c.onClose();
    c.answer.complete(true);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(c.probes, 0);
  }, skip: !Platform.isWindows);
  testWidgets('late missing WebView result does not open a dialog after exit', (tester) async {
    final c = _Probe();
    c.onInit();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(c.probes, 1);
    c.onClose();
    c.answer.complete(false);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(c.dialogs, 0);
  }, skip: !Platform.isWindows);
}
