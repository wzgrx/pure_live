// D07.6 (docs/D-弹幕/D07-礼物和付费消息/D07.6-已有样本的平台补礼物): what the platform gift
// tests share: one gift line (A08.11) pumped as the chat list draws it, what
// it shows, and D07.1's merging of a run of gifts.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/image_cache.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/danmaku/chat_list.dart';
import 'package:pure_live/features/live_play/danmaku/gift_line.dart';
import 'package:pure_live/features/live_play/logic/gift_combiner.dart';

import '../../support.dart';
import 'no_images.dart';

/// Loads the strings and swaps the app's image cache for [NoImages] around
/// every test.
void useGiftLineTests() {
  late BaseCacheManager? images;
  setUpAll(loadStrings);
  setUp(() {
    images = AppImageCache.manager;
    AppImageCache.manager = NoImages();
  });
  tearDown(() => AppImageCache.manager = images);
}

/// Pumps [message]'s gift line in [room], 360 wide.
Future<void> pumpGiftLine(WidgetTester tester, LiveMessage message, {GiftLineRoom room = GiftLineRoom.none}) async {
  final line = ChatLine.gift(message)..id = 1;
  await tester.pumpWidget(
    LiveUiScope(
      config: LiveUiConfig(imageCacheManager: NoImages()),
      child: MaterialApp(
        theme: const LiveTheme().light,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: ChatLineView(key: const ValueKey(1), line: line, giftRoom: room),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

String? _text(WidgetTester tester, String key) {
  final found = find.byKey(ValueKey(key));
  return found.evaluate().isEmpty ? null : tester.widget<Text>(found).data;
}

/// The line's value ("10 元"), or null without one.
String? giftLineValue(WidgetTester tester) => _text(tester, 'live-play-gift-value');

/// The line's "×N", or null without one.
String? giftLineCount(WidgetTester tester) => _text(tester, 'live-play-gift-count');

/// The line's whole text as it reads.
String giftLineText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('live-play-gift-text'))).textSpan!.toPlainText();

/// The address the line's picture asks for, or null without one.
String? giftLinePicture(WidgetTester tester) {
  final image = find.byKey(const ValueKey('live-play-gift-image'));
  if (image.evaluate().isEmpty) return null;
  final provider = (tester.widget<Image>(image).image as ResizeImage).imageProvider;
  return provider is CachedNetworkImageProvider ? provider.url : (provider as NetworkImage).url;
}

/// Whether the line has [tier]'s mark.
bool giftLineMarked(WidgetTester tester, LiveGiftTier tier) =>
    find.byKey(ValueKey('live-play-gift-tier-${tier.name}')).evaluate().isNotEmpty;

/// The gift lines D07.1 makes of [gifts], each arriving [gap] after the one
/// before it (at most a second apart, so every combo stays in its window).
List<ChatLine> combinedGiftLines(Iterable<LiveMessage> gifts, {Duration gap = const Duration(milliseconds: 500)}) {
  var now = DateTime(2026, 10, 9, 20);
  final feed = ChatFeed(giftCapacity: GiftCombiner.maxGiftLines, schedule: (_) {});
  final combiner = GiftCombiner(feed: feed, clock: () => now);
  for (final gift in gifts) {
    now = now.add(gap);
    combiner.add(gift);
  }
  expect(combiner.dropped, 0);
  return [
    for (final line in feed.lines)
      if (line.kind == ChatLineKind.gift) line,
  ];
}
