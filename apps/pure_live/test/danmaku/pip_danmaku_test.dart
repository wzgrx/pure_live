import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/danmaku/danmaku_preferences.dart';

void main() {
  test('F-DM-07: picture-in-picture danmaku has its own look and limit', () async {
    final store = await LiveStore.inMemory();
    addTearDown(store.close);
    await store.settings.set(Settings.danmakuPipFontSize, 14);
    await store.settings.set(Settings.danmakuPipMaxVisibleCount, 3);
    await store.settings.set(Settings.danmakuPipEnabled, false);
    final look = PipDanmakuLook.of(store.settings);
    expect(look.enabled, isFalse);
    expect(look.style.fontSize, 14);
    expect(look.budget.maxVisible, 3);
    expect(look.style.area, store.settings.get(Settings.danmakuPipArea));
  });
}
