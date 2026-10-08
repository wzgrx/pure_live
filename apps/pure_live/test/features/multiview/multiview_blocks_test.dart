import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';

import '../../support.dart';
import '../live_play/live_play_support.dart';
import 'multiview_support.dart';

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// D02.2: the multi-view's danmaku take the same pattern words and content
/// blocks as the room.
void main() {
  setUpAll(loadStrings);

  test('patterns and the two switches apply to the selected cell', () async {
    final store = await memoryStore();
    await store.blockLists.add(BlockKind.keyword, r'/^[0-9]+$/');
    final danmaku = <FakeDanmaku>[];
    final controller = multiviewController(store, RoomsSite(), danmaku: danmaku);
    await controller.start();
    await controller.assign(0, pickRoom('1'));
    final flying = <String>[];
    controller.flying.listen((message) => flying.add(message.message));
    controller.setDanmakuEnabled(enabled: true);
    await _settle();
    danmaku.single
      ..chat('123')
      ..chat('😂😂')
      ..chat('长' * 31);
    expect(flying, ['😂😂', '长' * 31], reason: 'the switches are off by default');

    await store.settings.set(Settings.blockEmoteOnlyDanmaku, true);
    await store.settings.set(Settings.blockLongDanmaku, true);
    await _settle();
    danmaku.single
      ..chat('😂😂😂')
      ..chat('长' * 32)
      ..chat('你好');
    expect(flying.skip(2), ['你好']);
    controller.dispose();
    await store.close();
  });
}
