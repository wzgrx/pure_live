// B08 benchmark: a fake danmaku source sending 200 messages a second into
// the room page, frames at 120 Hz; D07.1 adds a run with 50 gifts a second
// on top (half of them combos of one gift, half each a gift of its own). Counts how often the chat list and its
// lines are built, how many widgets the page builds in all, and how long
// each frame takes here (debug mode on the test host: compare runs with
// each other, not with a phone's profile build).
//
// The default run is 3 simulated seconds; the full one
// (docs/D-弹幕/D04-数据流和性能/D04.1-弹幕性能和可读性) is
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
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/live_play_page.dart';
import 'package:pure_live/features/live_play/logic/gift_combiner.dart';
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

/// Gifts a second in the gift run (D07.1 c4).
const int _giftRate = 50;

/// The gift run's [index]th gift: even ones are combos of 粉丝荧光棒 by five
/// viewers (10 a send, the platform's running count rising), odd ones a
/// gift of their own.
LiveMessage _gift(int index) {
  final LiveGift gift;
  final String sender;
  if (index.isEven) {
    final viewer = index ~/ 2 % 5;
    sender = '连击$viewer';
    gift = LiveGift(id: '824', name: '粉丝荧光棒', count: 10, comboKey: '$sender:824', comboTotal: 10 * (index ~/ 10 + 1));
  } else {
    sender = '送礼$index';
    gift = LiveGift(id: '${index % 40}', name: '礼物${index % 40}');
  }
  return LiveMessage(
    type: LiveMessageType.gift,
    userName: sender,
    userId: sender,
    message: gift.plainText,
    color: LiveMessageColor.white,
    data: gift,
  );
}

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
    await _bench(tester, giftRate: 0);
  });

  testWidgets('200 messages and $_giftRate gifts a second for $_seconds s at 120 Hz (D07.1)', (tester) async {
    await _bench(tester, giftRate: _giftRate);
  });

  // D07.1: the feed and the gift combiner alone, on a fake clock: a flood of
  // 200 gifts a second in 20 combos, with and without 200 chat messages a
  // second, against one line a gift (before D07.1).
  for (final chatRate in [0, _rate]) {
    test('D07.1: 200 gifts a second in 20 combos${chatRate > 0 ? ' and $chatRate messages' : ''} for $_seconds s', () {
      final merged = _flood(chatRate: chatRate, combine: true);
      final before = _flood(chatRate: chatRate, combine: false);
      // The numbers go to the record (D07.1 record.md).
      // ignore: avoid_print
      print('D07.1 gift flood, $chatRate chat/s: merged $merged\n  one line a gift (before): $before');
      expect(merged.mostHeardInAFrame, 1, reason: 'still once a frame');
      expect(merged.giftLinesKept, lessThanOrEqualTo(GiftCombiner.maxGiftLines));
      expect(merged.giftLinesAdded, lessThanOrEqualTo(GiftCombiner.linesPerSecond * _seconds + 20));
      if (chatRate > 0) expect(merged.chatLinesKept, 500 - merged.giftLinesKept, reason: 'the rest is chat');
      expect(before.giftLinesAdded, 200 * _seconds);
    });
  }
}

/// What [_flood] measured.
typedef _Flood = ({
  int giftLinesAdded,
  int merges,
  int dropped,
  int giftLinesKept,
  int chatLinesKept,
  int mostHeardInAFrame,
  double microsecondsAGift,
});

/// 200 gifts a second for [_seconds] s at [_hz] frames a second: 20 viewers
/// each in a combo of one gift (10 a send, the platform's running count
/// rising), and [chatRate] chat messages a second, through a
/// [GiftCombiner] when [combine], else a line each as before D07.1.
_Flood _flood({required int chatRate, required bool combine}) {
  final due = <VoidCallback>[];
  final feed = ChatFeed(giftCapacity: combine ? GiftCombiner.maxGiftLines : null, schedule: due.add);
  var clock = DateTime(2026, 10, 9, 20);
  final combiner = GiftCombiner(feed: feed, clock: () => clock);
  var heard = 0;
  var mostHeard = 0;
  feed.addListener(() => heard++);
  const giftRate = 200;
  const combos = 20;
  final hits = List.filled(combos, 0);
  var gifts = 0;
  var chats = 0;
  var giftLines = 0;
  final watch = Stopwatch();
  for (var f = 0; f < _seconds * _hz; f++) {
    clock = DateTime(2026, 10, 9, 20).add(Duration(microseconds: f * Duration.microsecondsPerSecond ~/ _hz));
    final chatsDue = ((f + 1) * chatRate / _hz).floor();
    while (chats < chatsDue) {
      feed.add(
        ChatLine.chat(
          LiveMessage(
            type: LiveMessageType.chat,
            userName: '观众${chats % 97}',
            message: '${_texts[chats % _texts.length]} #$chats',
            color: LiveMessageColor.white,
          ),
        ),
      );
      chats++;
    }
    final giftsDue = ((f + 1) * giftRate / _hz).floor();
    while (gifts < giftsDue) {
      final viewer = gifts % combos;
      hits[viewer] += 10;
      final gift = LiveGift(id: '824', name: '粉丝荧光棒', count: 10, comboKey: 'v$viewer:824', comboTotal: hits[viewer]);
      final message = LiveMessage(
        type: LiveMessageType.gift,
        userName: '送礼$viewer',
        userId: 'v$viewer',
        message: gift.plainText,
        color: LiveMessageColor.white,
        data: gift,
      );
      watch.start();
      if (combine) {
        if (combiner.add(message) == GiftOutcome.added) giftLines++;
      } else {
        feed.add(ChatLine.gift(message));
        giftLines++;
      }
      watch.stop();
      gifts++;
    }
    final flushes = [...due];
    due.clear();
    heard = 0;
    for (final flush in flushes) {
      flush();
    }
    mostHeard = math.max(mostHeard, heard);
  }
  feed.dispose();
  return (
    giftLinesAdded: giftLines,
    merges: feed.replacements,
    dropped: combiner.dropped,
    giftLinesKept: feed.lines.where((line) => line.kind == ChatLineKind.gift).length,
    chatLinesKept: feed.lines.where((line) => line.kind == ChatLineKind.chat).length,
    mostHeardInAFrame: mostHeard,
    microsecondsAGift: watch.elapsedMicroseconds / gifts,
  );
}

Future<void> _bench(WidgetTester tester, {required int giftRate}) async {
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
  final feed = tester.widget<ChatList>(find.byType(ChatList)).controller.chat;

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
  var gifts = 0;
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
      final giftsDue = ((f + 1) * giftRate / _hz).floor();
      while (gifts < giftsDue) {
        danmaku.emit(DanmakuReceived(_gift(gifts)));
        gifts++;
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
  // The numbers go to the record (docs/D-弹幕/D04-数据流和性能/D04.1-弹幕性能和可读性/record.md).
  // ignore: avoid_print
  print(
    'B08 chat benchmark: $_seconds s, $sent messages, $gifts gifts, $frames frames at $_hz Hz\n'
    '  feed: ${feed.added} lines added, ${feed.replacements} replaced (merged gifts), '
    '${feed.lines.where((l) => l.kind == ChatLineKind.gift).length} gift and '
    '${feed.lines.where((l) => l.kind == ChatLineKind.chat).length} chat lines kept of ${feed.length}\n'
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
  expect(lineBuilds, lessThanOrEqualTo(feed.added + feed.replacements + 20), reason: 'each line is built once');
  expect(allBuilds / frames, lessThan(150), reason: 'the rest of the room page does not hear of chat');
  // D07.1: gifts do not push the chat out.
  expect(feed.giftLines, lessThanOrEqualTo(GiftCombiner.maxGiftLines));
  if (giftRate > 0) expect(feed.added - sent, lessThan(gifts), reason: 'combos merge');

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump(const Duration(seconds: 5));
  await tester.runAsync(services.close);
}
