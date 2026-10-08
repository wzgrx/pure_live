import 'dart:io';

import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A08.6 c3 (G1 A): "在聊天列表显示礼物" is a setting; the choice a room
/// kept in `meta` before is taken over once.
void main() {
  test('gifts show by default; a danmaku setting carried by backups', () async {
    final store = await memoryStore();
    addTearDown(store.close);
    expect(store.settings.get(Settings.showChatGifts), isTrue);
    expect(Settings.showChatGifts.section, 'danmaku');
    expect(Settings.showChatGifts.scope, SettingScope.synced);
    expect(Settings.byKey('showChatGifts'), Settings.showChatGifts);
  });

  test("the room's old switch in meta is taken over once, then forgotten", () async {
    final dir = await Directory.systemTemp.createTemp('chat_gifts');
    addTearDown(() => dir.delete(recursive: true));
    var store = await LiveStore.open(dir, cipher: const FakeCipher());
    await store.meta.set(LiveStore.legacyShowGiftsKey, '0');
    await store.close();

    store = await LiveStore.open(dir, cipher: const FakeCipher());
    expect(store.settings.get(Settings.showChatGifts), isFalse);
    expect(await store.meta.get(LiveStore.legacyShowGiftsKey), isNull);
    // Turned on later: it stays on.
    await store.settings.set(Settings.showChatGifts, true);
    await store.close();

    store = await LiveStore.open(dir, cipher: const FakeCipher());
    expect(store.settings.get(Settings.showChatGifts), isTrue);
    await store.close();
  });

  test('an old "on" only clears meta; a fresh install stores nothing', () async {
    final dir = await Directory.systemTemp.createTemp('chat_gifts');
    addTearDown(() => dir.delete(recursive: true));
    var store = await LiveStore.open(dir, cipher: const FakeCipher());
    await store.meta.set(LiveStore.legacyShowGiftsKey, '1');
    await store.close();

    store = await LiveStore.open(dir, cipher: const FakeCipher());
    expect(store.settings.get(Settings.showChatGifts), isTrue);
    expect(store.settings.isSet(Settings.showChatGifts), isFalse);
    expect(await store.meta.get(LiveStore.legacyShowGiftsKey), isNull);
    await store.close();

    final fresh = await memoryStore();
    addTearDown(fresh.close);
    expect(fresh.settings.isSet(Settings.showChatGifts), isFalse);
  });
}
