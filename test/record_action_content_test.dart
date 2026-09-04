import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/live_play/widgets/button/record_action_content.dart';

void main() {
  Widget scene({bool compact = false, double scale = 1, String label = '录制'}) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Center(
        child: SizedBox(
          width: compact ? 40 : 120,
          height: 38,
          child: RecordActionContent(compactHeader: compact, label: label, icon: Icons.circle),
        ),
      ),
    ),
  );

  testWidgets('outgoing label fits while the recording button becomes icon-only', (tester) async {
    await tester.pumpWidget(scene(label: '正在录制直播'));
    await tester.pumpWidget(scene(compact: true));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long labels and enlarged text remain within the button', (tester) async {
    await tester.pumpWidget(scene(scale: 1.8, label: 'Monitoring live recording'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(scene(scale: 1.8, label: '正在录制直播'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
