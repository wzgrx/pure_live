// B08 benchmark: a fake danmaku source sending 200 messages a second into
// the room page, frames at 120 Hz. Counts how often the chat list and its
// lines are built, how many widgets the page builds in all, and how long
// each frame takes here (debug mode on the test host: compare runs with
// each other, not with a phone's profile build).
//
// The default run is 3 simulated seconds; the full one (docs/TASKS.md/
// B08.md) is
//   flutter test test/features/live_play/chat_benchmark_test.dart \
//     --dart-define=CHAT_BENCH_SECONDS=60
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/room_orientation.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// Simulated seconds of the run.
const int _seconds = int.fromEnvironment('CHAT_BENCH_SECONDS', defaultValue: 3);

/// Messages a second.
const int _rate = 200;

/// Frames a second (the K90's 120 Hz).
const int _hz = 120;

const List<LiveMessageColor> _colors = [
  LiveMessageColor.white,
  LiveMessageColor(255, 255, 0),
  LiveMessageColor(0, 255, 255),
  LiveMessageColor(255, 102, 0),
  LiveMessageColor(0, 0, 160),
  LiveMessageColor(255, 0, 255),
];

const List<String> _texts = [
  '666',
  '这波团战打得漂亮',
  '前排',
  '主播今天状态不错啊，这把能赢吗',
  '哈哈哈哈哈哈',
  '[笑哭][笑哭]',
  'GG',
  '有没有人知道这个皮肤叫什么名字？',
];

double _percentile(List<int> sorted, double p) => sorted.isEmpty
    ? 0
    : sorted[math.min(sorted.length - 1, (sorted.length * p).ceil() - 1).clamp(0, sorted.length - 1)] / 1000;

void main() {
  testWidgets('200 messages a second for $_seconds s at 120 Hz', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    RoomOrientationChoice.clearSession();
    final services = (await tester.runAsync(testServices))!;
    await tester.runAsync(loadStrings);
    final previous = AppNavigator.toast;
    AppNavigator.toast = (_) {};
    addTearDown(() => AppNavigator.toast = previous);
    final platform = FakeSite(liveRoom(startedAt: DateTime.now().subtract(const Duration(minutes: 30))));
    final danmaku = FakeDanmaku();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appServicesProvider.overrideWithValue(services),
          sitesProvider.overrideWithValue(SiteRegistry({platform.id: () => platform})),
          danmakuProvider.overrideWithValue(DanmakuRegistry({platform.id: () => danmaku})),
          playbackSessionFactoryProvider.overrideWithValue(({config}) => fakeSession(FakeEngine())),
        ],
        child: MaterialApp(
          theme: const LiveTheme().light,
          home: LivePlayPage(
            route: RouteArgs(
              RoutePath.kLivePlay,
              arguments: LiveRoom(platform: platform.id, roomId: '6', nick: '主播'),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(find.byType(ChatList), findsOneWidget);

    var chatListBuilds = 0;
    var listViewBuilds = 0;
    var lineBuilds = 0;
    var allBuilds = 0;
    final byType = <Type, int>{};
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      allBuilds++;
      final widget = element.widget;
      byType.update(widget.runtimeType, (count) => count + 1, ifAbsent: () => 1);
      if (widget is ChatList) chatListBuilds++;
      if (widget.key == const ValueKey('live-play-chat')) listViewBuilds++;
      if (widget is ChatLineView) lineBuilds++;
    };
    const frame = Duration(microseconds: Duration.microsecondsPerSecond ~/ _hz);
    const frames = _seconds * _hz;
    final times = <int>[];
    var sent = 0;
    final watch = Stopwatch();
    try {
      for (var f = 0; f < frames; f++) {
        final due = ((f + 1) * _rate / _hz).floor();
        while (sent < due) {
          final color = _colors[sent % _colors.length];
          danmaku.emit(
            DanmakuReceived(
              LiveMessage(
                type: LiveMessageType.chat,
                userName: '观众${sent % 97}',
                userId: '${sent % 97}',
                message: '${_texts[sent % _texts.length]} #$sent',
                color: color,
              ),
            ),
          );
          sent++;
        }
        watch
          ..reset()
          ..start();
        await tester.pump(frame);
        watch.stop();
        times.add(watch.elapsedMicroseconds);
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    final sorted = [...times]..sort();
    final mean = times.fold<int>(0, (sum, t) => sum + t) / times.length / 1000;
    // The numbers go to the record (docs/T06/T06d/T06d.3/record.md).
    // ignore: avoid_print
    print(
      'B08 chat benchmark: $_seconds s, $sent messages, $frames frames at $_hz Hz\n'
      '  ChatList builds: $chatListBuilds (${(chatListBuilds / _seconds).toStringAsFixed(1)}/s)\n'
      '  list (ListView) builds: $listViewBuilds (${(listViewBuilds / _seconds).toStringAsFixed(1)}/s)\n'
      '  ChatLineView builds: $lineBuilds (${(lineBuilds / _seconds).toStringAsFixed(1)}/s)\n'
      '  all widget builds: $allBuilds (${(allBuilds / frames).toStringAsFixed(1)} a frame)\n'
      '  frame ms: mean ${mean.toStringAsFixed(2)}, P50 ${_percentile(sorted, 0.5).toStringAsFixed(2)}, '
      'P90 ${_percentile(sorted, 0.9).toStringAsFixed(2)}, P99 ${_percentile(sorted, 0.99).toStringAsFixed(2)}, '
      'max ${(sorted.last / 1000).toStringAsFixed(2)}\n'
      '  most built: ${(byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(12).map((e) => '${e.key} ${e.value}').join(', ')}',
    );
    // Before B08: the list and every room widget built each frame (about
    // 300 builds a frame) and each visible line again on every message.
    expect(chatListBuilds, lessThanOrEqualTo(2), reason: 'the hint and the states build only when they change');
    expect(listViewBuilds, lessThanOrEqualTo(frames), reason: 'at most once a frame');
    expect(lineBuilds, lessThanOrEqualTo(sent + 20), reason: 'each line is built once');
    expect(allBuilds / frames, lessThan(150), reason: 'the rest of the room page does not hear of chat');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(seconds: 5));
    await tester.runAsync(services.close);
  });
}
