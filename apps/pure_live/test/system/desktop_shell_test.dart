import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/desktop_window.dart';
import 'package:pure_live_app/features/system/close_behaviour.dart';
import 'package:pure_live_app/features/system/desktop_shell.dart';
import 'package:pure_live_app/features/system/media_controls.dart';
import 'package:pure_live_app/features/system/windows_native.dart';

import 'fake_window.dart';

final class _FakeNative implements WindowsNative {
  final calls = <String>[];
  final forwarded = StreamController<List<String>>.broadcast(sync: true);
  final tray = StreamController<TrayEvent>.broadcast(sync: true);

  @override
  Stream<List<String>> get forwardedArguments => forwarded.stream;

  @override
  Stream<TrayEvent> get trayEvents => tray.stream;

  @override
  Stream<MediaCommand> get mediaCommands => const Stream.empty();

  @override
  Future<void> ready() async => calls.add('ready');

  @override
  Future<void> setStartMaximized({required bool maximized}) async => calls.add('startMaximized $maximized');

  @override
  Future<void> setTitleBarDark({required bool dark}) async => calls.add('dark $dark');

  @override
  Future<void> showTray({
    required String tooltip,
    required String show,
    required String hide,
    required String exit,
  }) async => calls.add('tray $tooltip $show $hide $exit');

  @override
  Future<void> hideTray() async => calls.add('hideTray');

  @override
  Future<bool> setLaunchAtStartup({required String name, required bool enabled}) async {
    calls.add('autostart $name $enabled');
    return true;
  }

  @override
  Future<void> updateMediaControls(MediaInfo info, {required bool playing}) async {}

  @override
  Future<void> clearMediaControls() async {}
}

void main() {
  group('close behaviour (F-WIN-04)', () {
    test('an extra window quits; otherwise ask until "不再询问"', () {
      expect(closeChoice(secondaryWindow: true, dontAsk: false, action: CloseAction.minimize), CloseChoice.exit);
      expect(closeChoice(secondaryWindow: false, dontAsk: false, action: CloseAction.minimize), CloseChoice.ask);
      expect(closeChoice(secondaryWindow: false, dontAsk: true, action: CloseAction.minimize), CloseChoice.minimize);
      expect(closeChoice(secondaryWindow: false, dontAsk: true, action: CloseAction.exit), CloseChoice.exit);
    });
  });

  group('WindowsShell', () {
    late LiveStore store;
    late _FakeNative native;
    late FakeWindow window;
    late List<String> events;
    CloseAnswer? answer;

    setUp(() async {
      store = await LiveStore.inMemory();
      native = _FakeNative();
      window = FakeWindow();
      events = [];
      answer = null;
    });

    tearDown(() => store.close());

    WindowsShell shell({bool secondary = false}) => WindowsShell(
      native: native,
      window: window,
      settings: store.settings,
      secondaryWindow: secondary,
      askClose: () async {
        events.add('ask');
        return answer;
      },
      openRoom: (room) => events.add('open ${room.key}'),
      beforeExit: () async => events.add('release'),
    );

    test('the main window gets the tray, the autostart setting and close protection', () async {
      await store.settings.set(Settings.launchAtStartup, true);
      final main = shell();
      await main.start();
      expect(window.preventClose, isTrue);
      expect(native.calls, ['tray 纯粹直播 显示窗口 隐藏窗口 退出', 'autostart $autostartValueName true', 'ready']);
      await store.settings.set(Settings.launchAtStartup, false);
      await pumpEventQueue();
      expect(native.calls.last, 'autostart $autostartValueName false');
      await main.dispose();
    });

    test('an extra window has no tray and no autostart, and quits on close', () async {
      final extra = shell(secondary: true);
      await extra.start();
      expect(native.calls, ['ready']);
      await extra.handleClose();
      expect(events, ['release']);
      expect(window.destroyed, isTrue);
      expect(window.preventClose, isFalse);
      await extra.dispose();
    });

    test('asks, remembers "不再询问" and then hides without asking', () async {
      final main = shell();
      await main.start();
      answer = (action: CloseAction.minimize, remember: true);
      await main.handleClose();
      expect(events, ['ask']);
      expect(window.visible, isFalse);
      expect(store.settings.get(Settings.closeDontAsk), isTrue);
      expect(store.settings.get(Settings.closeAction), CloseAction.minimize);

      await window.show();
      await main.handleClose();
      expect(events, ['ask'], reason: 'no second question');
      expect(window.visible, isFalse);
      await main.dispose();
    });

    test('a dismissed dialog keeps the window; quitting releases playback first', () async {
      final main = shell();
      await main.start();
      await main.handleClose();
      expect(window.destroyed, isFalse);
      answer = (action: CloseAction.exit, remember: false);
      await main.handleClose();
      expect(events, ['ask', 'ask', 'release']);
      expect(native.calls.last, 'hideTray');
      expect(window.destroyed, isTrue);
      expect(store.settings.get(Settings.closeDontAsk), isFalse);
      await main.dispose();
    });

    test('tray: a click toggles the window, the menu shows, hides and quits (F-WIN-03)', () async {
      final main = shell();
      await main.start();
      native.tray.add(TrayEvent.click);
      await pumpEventQueue();
      expect(window.visible, isFalse);
      native.tray.add(TrayEvent.click);
      await pumpEventQueue();
      expect(window.visible, isTrue);
      expect(window.calls, containsAllInOrder(['hide', 'show', 'focus']));
      window.minimized = true;
      native.tray.add(TrayEvent.click);
      await pumpEventQueue();
      expect(window.visible, isTrue, reason: 'a minimised window is shown, not hidden');
      native.tray.add(TrayEvent.hide);
      await pumpEventQueue();
      expect(window.visible, isFalse);
      native.tray.add(TrayEvent.exit);
      await pumpEventQueue();
      expect(window.destroyed, isTrue);
      await main.dispose();
    });

    test('a second launch shows the window and opens its room (F-WIN-01)', () async {
      final main = shell();
      await main.start();
      window.visible = false;
      native.forwarded
        ..add(const ['--open-room=douyu:9999'])
        ..add(const [])
        ..add(const ['--open-room=douyu:../x']);
      await pumpEventQueue();
      expect(window.visible, isTrue);
      expect(events, ['open douyu:9999']);
      await main.dispose();
    });
  });

  group('window placement (F-WIN-06)', () {
    test('positions round-trip and must keep the title bar on a screen', () {
      expect(parseWindowPosition(''), isNull);
      expect(parseWindowPosition('12,-30'), const Offset(12, -30));
      expect(parseWindowPosition('a,b'), isNull);
      expect(parseWindowPosition('1,2,3'), isNull);
      expect(formatWindowPosition(const Offset(12.4, -30.6)), '12,-31');

      const screens = [Rect.fromLTWH(0, 0, 1920, 1040), Rect.fromLTWH(1920, 0, 1280, 984)];
      const size = Size(1280, 720);
      expect(restorablePosition(const Offset(100, 100), size, screens), const Offset(100, 100));
      expect(restorablePosition(const Offset(2000, 50), size, screens), const Offset(2000, 50));
      expect(restorablePosition(const Offset(3300, 50), size, screens), isNull, reason: 'the screen is gone');
      expect(restorablePosition(const Offset(100, 1030), size, screens), isNull, reason: 'title bar below the screen');
      expect(restorablePosition(null, size, screens), isNull);
    });

    test('remembers normal bounds, not maximised, fullscreen or PiP ones', () async {
      final store = await LiveStore.inMemory();
      addTearDown(store.close);
      final window = FakeWindow(bounds: const Rect.fromLTWH(40, 60, 1000, 700));
      final memory = WindowPlacementMemory(store.settings, window);
      await memory.save();
      expect(store.settings.get(Settings.windowWidth), 1000);
      expect(store.settings.get(Settings.windowHeight), 700);
      expect(store.settings.get(Settings.windowPosition), '40,60');

      await window.setBounds(const Rect.fromLTWH(1424, 754, 480, 270));
      await memory.save();
      expect(store.settings.get(Settings.windowPosition), '40,60', reason: 'smaller than 360x400 is the PiP window');

      window.maximized = true;
      await window.setBounds(const Rect.fromLTWH(0, 0, 1920, 1040));
      await memory.save();
      expect(store.settings.get(Settings.windowWidth), 1000);

      memory
        ..onWindowMaximize()
        ..onWindowUnmaximize()
        ..onWindowMaximize();
      await pumpEventQueue();
      expect(store.settings.get(Settings.windowMaximized), isTrue);
      expect(isMainWindowBounds(const Rect.fromLTWH(0, 0, 360, 400)), isTrue);
    });
  });

  test('the title bar follows the theme, or the system when the theme does', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final native = _FakeNative();
    bool? mode = true;
    final sync = TitleBarSync(native, () => mode)
      ..update()
      ..update();
    mode = false;
    sync.update();
    mode = null;
    TestWidgetsFlutterBinding.instance.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(TestWidgetsFlutterBinding.instance.platformDispatcher.clearPlatformBrightnessTestValue);
    sync.didChangePlatformBrightness();
    await pumpEventQueue();
    expect(native.calls, ['dark true', 'dark false', 'dark true']);
  });
}
