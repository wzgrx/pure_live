import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_player/live_player.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/live_play/danmaku/chat_feed.dart';
import 'package:pure_live/features/live_play/logic/blocked_count.dart';
import 'package:pure_live/features/live_play/logic/room_controller.dart';
import 'package:pure_live/shared/danmaku/emotes.dart';

import '../../support.dart';
import 'live_play_support.dart';

/// D02.2 in the room: pattern block words, the emoticon-only and length
/// blocks, and "本场已屏蔽 N 条" (counted, never stored; a new room starts
/// at 0).
void main() {
  late LiveStore store;
  late FakeDanmaku danmaku;
  late FakeEngine engine;
  late PlaybackSession session;
  final now = DateTime.utc(2026, 10, 9, 12);

  setUpAll(loadStrings);

  setUp(() async {
    store = await LiveStore.memory(cipher: FakeCipher());
    danmaku = FakeDanmaku();
    engine = FakeEngine();
    session = fakeSession(engine);
  });

  tearDown(() async {
    await session.dispose();
    await store.close();
  });

  LiveRoomController controllerFor({EmoteLibrary? emotes}) => LiveRoomController(
    room: liveRoom(),
    site: FakeSite(liveRoom()),
    session: session,
    danmaku: danmaku,
    danmakuSupported: true,
    store: store,
    emotes: emotes,
    now: () => now,
    refreshInterval: Duration.zero,
  );

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

  List<String> chatTexts(LiveRoomController controller) => [
    for (final line in controller.chat.lines)
      if (line.kind == ChatLineKind.chat) line.text,
  ];

  test('a pattern blocks; the blocks count, duplicates and repeats do not', () async {
    await store.blockLists.add(BlockKind.keyword, r'/^[0-9]+$/');
    await store.settings.set(Settings.collapseRepeatedDanmaku, true);
    final controller = controllerFor();
    var heard = 0;
    controller.blocked.addListener(() => heard++);
    await controller.start();
    await settle();
    expect(controller.blocked.value, 0);

    danmaku
      ..chat('123')
      ..chat('主播666')
      ..chat('4567')
      ..chat('你好', id: 'm1')
      ..chat('你好', id: 'm1')
      ..chat('主播666', user: '别人');
    expect(chatTexts(controller), ['主播666', '你好']);
    expect(controller.blocked.value, 2, reason: 'the duplicate packet and the repeat are not blocks');
    expect(heard, 2, reason: 'without a frame scheduler each change is heard at once');
    controller.dispose();
  });

  test("a blocked platform gift counts too (D07.1 gifts go through the block list)", () async {
    await store.blockLists.add(BlockKind.keyword, '/^荧光棒/');
    final controller = controllerFor();
    await controller.start();
    await settle();
    void gift(String name, String id) => danmaku.emit(
      DanmakuReceived(
        LiveMessage(
          type: LiveMessageType.gift,
          userName: '观众',
          userId: '观众',
          message: '$name ×1',
          color: LiveMessageColor.white,
          messageId: id,
          data: LiveGift(id: name, name: name),
        ),
      ),
    );
    gift('荧光棒', 'g1');
    gift('火箭', 'g2');
    expect(
      [
        for (final line in controller.chat.lines)
          if (line.kind == ChatLineKind.gift) line.text,
      ],
      ['火箭 ×1'],
    );
    expect(controller.blocked.value, 1);
    controller.dispose();
  });

  test('the two switches are off by default; on, they block and count; the next room starts at 0', () async {
    final first = controllerFor();
    await first.start();
    await settle();
    danmaku
      ..chat('😂😂😂')
      ..chat('长' * 40);
    expect(chatTexts(first), ['😂😂😂', '长' * 40], reason: 'off: as before');
    expect(first.blocked.value, 0);

    await store.settings.set(Settings.blockEmoteOnlyDanmaku, true);
    await store.settings.set(Settings.blockLongDanmaku, true);
    await settle();
    danmaku
      ..chat('😂😂')
      ..chat('好😂')
      ..chat('短' * 30)
      ..chat('超' * 31);
    expect(chatTexts(first).skip(2), ['好😂', '短' * 30]);
    expect(first.blocked.value, 2);

    await store.settings.set(Settings.blockLongDanmakuLength, 50);
    await settle();
    danmaku.chat('中' * 40);
    expect(chatTexts(first).last, '中' * 40, reason: 'the length applies to the next message');
    first.dispose();

    // Another room: a new controller, nothing counted yet.
    final second = controllerFor();
    await second.start();
    await settle();
    expect(second.blocked.value, 0);
    danmaku.chat('😂');
    expect(second.blocked.value, 1);
    second.dispose();
  });

  test("the platform's bundled emoticons count as emoticons (as the list draws them)", () async {
    final library = EmoteLibrary(bundle: FileAssetBundle());
    final table = await library.load(SiteIds.bilibili);
    final code = table.codes.keys.firstWhere((code) => code.startsWith('['));
    await store.settings.set(Settings.blockEmoteOnlyDanmaku, true);
    final controller = controllerFor(emotes: library);
    await controller.start();
    await settle();
    danmaku
      ..chat('$code$code')
      ..chat('好$code')
      ..chat('[不是表情]');
    expect(chatTexts(controller), ['好$code', '[不是表情]']);
    expect(controller.blocked.value, 1);
    controller.dispose();
  });

  test('blocking a pattern from the room takes the matching lines off the list', () async {
    final controller = controllerFor();
    await controller.start();
    await settle();
    danmaku
      ..chat('123')
      ..chat('abc')
      ..chat('ABC9');
    expect(await controller.blockKeyword(r'/^[0-9]+$/'), isTrue);
    expect(chatTexts(controller), ['abc', 'ABC9']);
    expect(await controller.blockKeyword('/^abc/'), isTrue);
    expect(chatTexts(controller), isEmpty, reason: 'without regard to case');
    expect(await store.blockLists.list(BlockKind.keyword), [r'/^[0-9]+$/', '/^abc/']);
    controller.dispose();
  });

  test('BlockedCount: the value at once, the listeners at most once a frame', () {
    final flushes = <void Function()>[];
    final count = BlockedCount(schedule: flushes.add);
    var heard = 0;
    count.addListener(() => heard++);
    for (var i = 0; i < 200; i++) {
      count.add();
    }
    expect(count.value, 200);
    expect(heard, 0);
    expect(flushes, hasLength(1));
    flushes.single();
    expect(heard, 1);
    count.add();
    expect(flushes, hasLength(2));
    count.dispose();
    flushes.last();
    expect(heard, 1, reason: 'not after dispose');
  });
}
