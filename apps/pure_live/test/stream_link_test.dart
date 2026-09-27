import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/features/rooms/stream_link.dart';

import 'fakes.dart';

void main() {
  late FakeSite site;
  late List<String> copied;
  late bool clipboardWorks;
  Uri? result;

  Future<void> open(WidgetTester tester, RoomRef room) async {
    site = FakeSite('douyu', offline: {'off'});
    copied = [];
    clipboardWorks = true;
    result = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sitesProvider.overrideWithValue({'douyu': PlatformSite(site)}),
        ],
        child: MaterialApp(
          theme: PureTheme.of(Appearance.light, platform: TargetPlatform.android),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () async {
                  result = await showStreamLinkPicker(
                    context,
                    ref,
                    room,
                    title: '主播',
                    clipboard: (text) async {
                      if (!clipboardWorks) return false;
                      copied.add(text);
                      return true;
                    },
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('F-SRC-04: pick a quality, then a line; the copy is confirmed before it is reported', (tester) async {
    await open(tester, RoomRef('douyu', '1'));
    expect(find.text('获取直链 · 主播'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '原画'), findsOneWidget);
    expect(find.text('线路 1 · HLS'), findsOneWidget);
    expect(site.streamRequests, ['1']);

    await tester.tap(find.widgetWithText(ChoiceChip, '高清'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(site.streamRequests, ['1', '1'], reason: 'the lines of the chosen quality');
    expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '高清')).selected, isTrue);

    clipboardWorks = false;
    await tester.tap(find.text('线路 1 · HLS'));
    await tester.pump();
    expect(find.text('没能写入剪贴板，再试一次'), findsOneWidget);
    expect(result, isNull);

    clipboardWorks = true;
    await tester.tap(find.text('线路 1 · HLS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(copied, ['https://cdn.example.com/1/sd.m3u8']);
    expect(result, Uri.parse('https://cdn.example.com/1/sd.m3u8'));
    expect(find.text('直链已复制，有时效，过期后需要重新复制'), findsOneWidget);
  });

  testWidgets('an offline room has no link to copy', (tester) async {
    await open(tester, RoomRef('douyu', 'off'));
    expect(find.text('主播现在没有开播，拿不到直链。'), findsOneWidget);
    expect(site.streamRequests, isEmpty);
  });

  testWidgets('F-FAV-08: a platform without an adapter says so', (tester) async {
    await open(tester, RoomRef('cc', '1'));
    expect(find.text('平台暂不支持'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
  });
}
