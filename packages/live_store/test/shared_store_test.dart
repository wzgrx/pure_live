import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Two desktop windows on one data folder (docs/A-界面设计/A16-桌面界面/A16.1-桌面窗口 c14): each
/// process opens the same database file; what one writes the other takes in
/// with `syncExternal`.
void main() {
  late Directory folder;
  late LiveStore main;
  late LiveStore second;

  setUp(() async {
    // Two processes in production; two databases of one isolate here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    folder = await Directory.systemTemp.createTemp('live_store_shared_');
    main = await LiveStore.open(folder, cipher: const FakeCipher(), shared: true);
    second = await LiveStore.open(folder, cipher: const FakeCipher(), shared: true);
  });

  tearDown(() async {
    await second.close();
    await main.close();
    await folder.delete(recursive: true);
  });

  test('nothing to take in until the other store writes; its own writes do not count', () async {
    expect(await main.syncExternal(), isFalse);
    await main.settings.set(Settings.textScaleFactor, 1.3);
    expect(await main.syncExternal(), isFalse, reason: "data_version ignores the connection's own commits");
    expect(await second.syncExternal(), isTrue);
    expect(second.settings.get(Settings.textScaleFactor), 1.3);
    expect(await second.syncExternal(), isFalse);
  });

  test('settings: changed values are reported once, removed ones go back to the default', () async {
    await second.settings.setAll({Settings.textScaleFactor: 1.4, Settings.themeMode: 'Dark'});
    final changes = <String>[];
    final subscription = main.settings.changes.listen((setting) => changes.add(setting.key));
    expect(await main.syncExternal(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(main.settings.get(Settings.textScaleFactor), 1.4);
    expect(main.settings.get(Settings.themeMode), 'Dark');
    expect(changes, unorderedEquals([Settings.textScaleFactor.key, Settings.themeMode.key]));

    changes.clear();
    await second.settings.reset(Settings.themeMode);
    await main.syncExternal();
    await Future<void>.delayed(Duration.zero);
    expect(main.settings.isSet(Settings.themeMode), isFalse);
    expect(changes, [Settings.themeMode.key]);
    await subscription.cancel();
  });

  test('follows and history watchers query again', () async {
    final seen = <int>[];
    final subscription = main.follows.watchAll().listen((rooms) => seen.add(rooms.length));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen, [0]);
    await second.follows.add(LiveRoom(platform: 'douyu', roomId: '5526219', nick: 'a'));
    await main.syncExternal();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen.last, 1);
    await subscription.cancel();
  });

  test('secrets: a sign-in and a sign-out in the other window', () async {
    final changes = <String>[];
    final subscription = main.secrets.cookieChanges.listen(changes.add);
    await second.secrets.setCookie('bilibili', 'SESSDATA=1');
    await main.syncExternal();
    await Future<void>.delayed(Duration.zero);
    expect(main.secrets.cookieFor('bilibili'), 'SESSDATA=1');
    expect(changes, ['bilibili']);

    await second.secrets.setCookie('bilibili', '');
    await main.syncExternal();
    await Future<void>.delayed(Duration.zero);
    expect(main.secrets.cookieFor('bilibili'), isNull);
    expect(changes, ['bilibili', 'bilibili']);

    // A value of the main window's own stays and is not reported again.
    await main.secrets.setCookie('douyu', 'acf=1');
    await Future<void>.delayed(Duration.zero);
    changes.clear();
    await second.settings.set(Settings.textScaleFactor, 1.5);
    await main.syncExternal();
    await Future<void>.delayed(Duration.zero);
    expect(main.secrets.cookieFor('douyu'), 'acf=1');
    expect(changes, isEmpty);
    await subscription.cancel();
  });

  test('a write of its own during the read is not overwritten by the older value', () async {
    await second.settings.set(Settings.textScaleFactor, 1.2);
    final sync = main.syncExternal();
    final write = main.settings.set(Settings.textScaleFactor, 1.9);
    await Future.wait([sync, write]);
    expect(main.settings.get(Settings.textScaleFactor), 1.9);
    await second.syncExternal();
    expect(second.settings.get(Settings.textScaleFactor), 1.9);
  });

  test('both windows write at once: the second waits instead of failing', () async {
    await Future.wait([
      for (var i = 0; i < 10; i++) ...[
        main.history.record(LiveRoom(platform: 'douyu', roomId: 'm$i')),
        second.history.record(LiveRoom(platform: 'huya', roomId: 's$i')),
      ],
    ]);
    expect(await main.history.all(), hasLength(20));
  });
}
