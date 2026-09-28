import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/app_prefs.dart';
import 'package:pure_live_app/core/store.dart';

void main() {
  test('principles §6.5: each tip shows once per installation and survives a restart', () async {
    final store = await LiveStore.inMemory();
    addTearDown(store.close);
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    final prefs = container.read(appPrefsProvider.notifier);

    expect(prefs.takeTip(Tip.fullscreen), isTrue);
    expect(prefs.takeTip(Tip.fullscreen), isFalse);
    expect(prefs.takeTip(Tip.quickPanel), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final loaded = await AppPrefs.load(store.meta);
    expect(loaded.shown(Tip.fullscreen), isTrue);
    expect(loaded.shown(Tip.quickPanel), isTrue);
    expect(loaded.shown(Tip.tvRoom), isFalse);
  });

  test('principles §5.2: the rail choice is remembered on this device', () async {
    final store = await LiveStore.inMemory();
    addTearDown(store.close);
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);
    expect((await AppPrefs.load(store.meta)).navRailExtended, isNull, reason: 'the window class decides at first');
    await container.read(appPrefsProvider.notifier).setNavRailExtended(extended: false);
    expect(container.read(appPrefsProvider).navRailExtended, isFalse);
    expect((await AppPrefs.load(store.meta)).navRailExtended, isFalse);
  });
}
