import 'package:flutter_test/flutter_test.dart';

import '../../support.dart';
import 'settings_harness.dart';

/// D02.2: the settings search finds the block page by its new switches and
/// by pattern words ("弹幕屏蔽" holds them, as the similarity filter).
void main() {
  setUpAll(loadStrings);

  testWidgets('"正则", "表情", "超长" find "弹幕屏蔽"', (tester) async {
    await pumpSettings(tester);
    for (final query in ['正则', '只有表情', '超长', '屏蔽 字数']) {
      await searchSettingsFor(tester, query);
      expect(settingsRow('video_block_list'), findsOneWidget, reason: query);
    }
  });
}
