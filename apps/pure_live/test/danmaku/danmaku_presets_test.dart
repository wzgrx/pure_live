import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/danmaku/danmaku_presets.dart';

void main() {
  late LiveStore store;

  setUp(() async => store = await LiveStore.inMemory());
  tearDown(() => store.close());

  test('F-DM-02: a preset sets the whole look and shows as selected', () async {
    final settings = store.settings;
    final comfort = danmakuPresets[1];
    expect(comfort.matches(settings), isFalse);
    await comfort.apply(settings);
    expect(settings.get(Settings.danmakuArea), 0.35);
    expect(settings.get(Settings.danmakuSpeed), 105);
    expect(settings.get(Settings.danmakuFontSize), 17);
    expect(comfort.matches(settings), isTrue);
    expect(danmakuPresets.first.matches(settings), isFalse);
  });

  test('F-DM-02: the saved style comes back, also from a 3.x template', () async {
    final settings = store.settings;
    expect(DanmakuTemplate.exists(settings), isFalse);
    expect(await DanmakuTemplate.restore(settings), isFalse);

    await settings.set(Settings.danmakuFontSize, 22);
    await settings.set(Settings.danmakuArea, 0.5);
    await DanmakuTemplate.save(settings);
    await danmakuPresets.last.apply(settings);
    expect(settings.get(Settings.danmakuFontSize), 16);
    expect(await DanmakuTemplate.restore(settings), isTrue);
    expect(settings.get(Settings.danmakuFontSize), 22);
    expect(settings.get(Settings.danmakuArea), 0.5);

    // 3.x's savedDanmakuTemplate (schema 2), ints where 3.x wrote them.
    await settings.set(
      Settings.danmakuTemplate,
      '{"version":2,"noEmojiMode":true,"area":0.2,"top":10,"bottom":0,"speed":118,"fontSize":16,'
      '"fontWeight":700,"fontBorder":1.5,"opacity":0.92,"stroke":true,"fps":60,"autoFps":false}',
    );
    expect(await DanmakuTemplate.restore(settings), isTrue);
    expect(settings.get(Settings.danmakuNoEmoji), isTrue);
    expect(settings.get(Settings.danmakuTopArea), 10);
    expect(settings.get(Settings.danmakuFontWeight), 700);
    expect(settings.get(Settings.danmakuAutoFps), isFalse);

    await settings.set(Settings.danmakuTemplate, 'not json');
    expect(await DanmakuTemplate.restore(settings), isFalse);
  });
}
