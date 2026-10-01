import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/app.dart';
import 'package:pure_live/app/desktop/close_dialog.dart';
import 'package:pure_live/app/desktop/desktop_window.dart';
import 'package:pure_live/app/desktop/shared_data.dart';
import 'package:pure_live/app/desktop/title_bar.dart';
import 'package:pure_live/app/desktop/tray.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_observer.dart';
import 'package:pure_live/routes/route_path.dart';

import 'support.dart';

/// The window actions the title bar asked for.
final class _FakeControls implements WindowControls {
  final List<String> calls = [];

  @override
  Future<void> minimize() async => calls.add('minimize');

  @override
  Future<void> maximize() async {
    calls.add('maximize');
    DesktopWindow.maximized.value = true;
  }

  @override
  Future<void> restore() async {
    calls.add('restore');
    DesktopWindow.maximized.value = false;
  }

  @override
  Future<void> showSystemMenu() async => calls.add('menu');

  @override
  Future<void> startDragging() async => calls.add('drag');
}

const _seed = Color(0xFF2196F3);

/// A window of [size] with the title bar over a page.
Future<_FakeControls> _pumpWindow(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controls = _FakeControls();
  DesktopWindow.controls = controls;
  DesktopWindow.maximized.value = false;
  DesktopWindow.resizing.value = null;
  addTearDown(() => DesktopWindow.controls = null);
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme(primaryColor: _seed).light,
      darkTheme: const LiveTheme(primaryColor: _seed).dark,
      themeMode: mode,
      navigatorObservers: [liveRouteObserver],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: DesktopFrame(enabled: true, child: child!),
      ),
      home: const Scaffold(body: Text('page')),
    ),
  );
  await tester.pumpAndSettle();
  return controls;
}

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _hover(WidgetTester tester, Finder target) async {
  final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: Offset.zero);
  await mouse.moveTo(tester.getCenter(target));
  await tester.pump();
}

/// The close dialog in a window (no tray when [tray] is false).
Future<Completer<CloseChoice?>> _pumpDialog(
  WidgetTester tester, {
  bool tray = true,
  int recording = 0,
  bool askRemember = true,
  bool remember = false,
  Size size = const Size(1280, 800),
  ThemeMode mode = ThemeMode.light,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final answer = Completer<CloseChoice?>();
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme(primaryColor: _seed).light,
      darkTheme: const LiveTheme(primaryColor: _seed).dark,
      themeMode: mode,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => answer.complete(
              await showCloseWindowDialog(
                context,
                tray: tray,
                recording: recording,
                askRemember: askRemember,
                remember: remember,
              ),
            ),
            child: const Text('close'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('close'));
  await tester.pumpAndSettle();
  return answer;
}

void main() {
  setUpAll(() async => currentStrings = await loadStrings());

  group('title bar', () {
    testWidgets('1280 × 800: icon, name, then minimize, maximize and close at the right, 46 × 32 each (c1)', (
      tester,
    ) async {
      await _pumpWindow(tester);
      final bar = tester.getRect(_key('title-bar'));
      expect(bar, const Rect.fromLTWH(0, 0, 1280, DesktopTitleBar.height));
      expect(tester.getTopLeft(find.text('page')).dy, greaterThanOrEqualTo(32), reason: 'the page is under the bar');

      final icon = tester.getRect(_key('title-bar-icon'));
      expect(icon.size, const Size(24, 24));
      expect(icon.center.dx, 20, reason: 'the 16 icon sits 12 from the edge');
      expect(tester.getSize(find.byType(Image)), const Size(16, 16));
      final name = tester.getRect(find.text('纯粹直播'));
      expect(name.left, greaterThan(icon.right));
      final style = tester.widget<Text>(find.text('纯粹直播')).style!;
      expect((style.fontSize, style.fontWeight), (13, FontWeight.w600));

      final buttons = [
        ('title-bar-minimize', AppIcons.windowMinimize, 1280 - 3 * 46.0),
        ('title-bar-maximize', AppIcons.windowMaximize, 1280 - 2 * 46.0),
        ('title-bar-close', AppIcons.windowClose, 1280 - 46.0),
      ];
      for (final (key, glyph, left) in buttons) {
        expect(tester.getRect(_key(key)), Rect.fromLTWH(left, 0, 46, 32), reason: key);
        expect(find.descendant(of: _key(key), matching: find.byIcon(glyph)), findsOneWidget, reason: key);
        expect(tester.getSize(find.descendant(of: _key(key), matching: find.byType(Icon))), const Size(16, 16));
      }
    });

    testWidgets('names under the pointer; a maximized window shows "restore" (c3)', (tester) async {
      final controls = await _pumpWindow(tester);
      for (final (key, words) in [
        ('title-bar-minimize', '最小化'),
        ('title-bar-maximize', '最大化'),
        ('title-bar-close', '关闭'),
      ]) {
        expect(find.byTooltip(words), findsOneWidget, reason: key);
        expect(
          find.descendant(of: _key(key), matching: find.byType(Tooltip)),
          findsOneWidget,
          reason: 'the frame gives the bar an overlay for the names',
        );
      }
      await tester.tap(_key('title-bar-maximize'));
      await tester.pump();
      expect(controls.calls, ['maximize']);
      expect(find.descendant(of: _key('title-bar-maximize'), matching: find.byIcon(AppIcons.windowRestore)), findsOne);
      expect(find.byTooltip('向下还原'), findsOneWidget);

      await _hover(tester, _key('title-bar-maximize'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('向下还原'), findsOneWidget, reason: 'the name shows after a moment');
      expect(tester.getTopLeft(find.text('向下还原')).dy, greaterThan(32), reason: 'below the button, over the page');

      await tester.tap(_key('title-bar-maximize'));
      await tester.pump();
      expect(controls.calls, ['maximize', 'restore']);
      expect(find.descendant(of: _key('title-bar-maximize'), matching: find.byIcon(AppIcons.windowMaximize)), findsOne);
      await tester.tap(_key('title-bar-minimize'));
      await tester.pump(const Duration(seconds: 1));
      expect(controls.calls.last, 'minimize');
    });

    testWidgets('close turns red with a white cross under the pointer', (tester) async {
      await _pumpWindow(tester);
      await _hover(tester, _key('title-bar-close'));
      final box = tester.widget<Container>(
        find.descendant(of: _key('title-bar-close'), matching: find.byType(Container)).first,
      );
      expect((box.decoration! as BoxDecoration).color, WindowButtonColors.closeHover);
      final icon = tester.widget<Icon>(find.descendant(of: _key('title-bar-close'), matching: find.byType(Icon)));
      expect(icon.color, WindowButtonColors.onCloseHover);
    });

    testWidgets('the icon and a right click open the window menu; the name is no link (c13)', (tester) async {
      final controls = await _pumpWindow(tester);
      await tester.tap(_key('title-bar-icon'));
      await tester.pump();
      expect(controls.calls, ['menu']);
      await tester.tapAt(tester.getCenter(find.text('纯粹直播')), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(controls.calls, ['menu', 'menu']);
      await tester.tapAt(const Offset(600, 16), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(controls.calls, ['menu', 'menu', 'menu'], reason: 'anywhere on the drag area');

      // A click on the name opens nothing; a double click maximizes, a drag
      // moves the window.
      await tester.tap(find.text('纯粹直播'));
      await tester.pump(const Duration(seconds: 1));
      expect(controls.calls, hasLength(3));
      await tester.tapAt(const Offset(600, 16));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(600, 16));
      await tester.pump(const Duration(seconds: 1));
      expect(controls.calls.last, 'maximize');
      await tester.dragFrom(const Offset(500, 16), const Offset(80, 40));
      await tester.pump(const Duration(seconds: 1));
      expect(controls.calls.last, 'drag');
    });

    testWidgets('the size while the edge is dragged; hidden in full screen and as the mini window', (tester) async {
      await _pumpWindow(tester);
      DesktopWindow.resizing.value = const Size(1280, 800);
      await tester.pump();
      expect(find.text('[1280 × 800]'), findsOneWidget);
      DesktopWindow.resizing.value = null;
      await tester.pump();
      expect(_key('title-bar-size'), findsNothing);

      await DesktopWindow.setFullScreen(on: true);
      await tester.pump();
      expect(find.byType(DesktopTitleBar), findsNothing);
      await DesktopWindow.setFullScreen(on: false);
      DesktopWindow.mini.value = true;
      await tester.pump();
      expect(find.byType(DesktopTitleBar), findsNothing);
      DesktopWindow.mini.value = false;
      await tester.pump();
      expect(find.byType(DesktopTitleBar), findsOneWidget);
      expect(find.text('page'), findsOneWidget);
    });

    testWidgets('the ground is the page surface: light, dark (no black strip) and the splash (c4)', (tester) async {
      await _pumpWindow(tester);
      final light = const LiveTheme(primaryColor: _seed).light.colorScheme;
      expect(tester.widget<Material>(_key('title-bar')).color, light.surface);
      expect(
        tester.widget<Text>(find.text('纯粹直播')).style!.color,
        light.onSurface,
      );

      await _pumpWindow(tester, mode: ThemeMode.dark);
      final dark = const LiveTheme(primaryColor: _seed).dark.colorScheme;
      expect(tester.widget<Material>(_key('title-bar')).color, dark.surface);
      expect(dark.surface, isNot(const Color(0xFF000000)));

      // The splash page's top is the same surface (U.3c c3).
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).last)
        ..push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: RoutePath.kSplash),
            builder: (_) => const Scaffold(body: Text('splash')),
          ),
        );
      await tester.pumpAndSettle();
      expect(tester.widget<Material>(_key('title-bar')).color, dark.surface);
      navigator.pop();
      await tester.pumpAndSettle();
    });

    testWidgets('in a room: "纯粹直播 · 晚风"; the taskbar name "晚风 - 纯粹直播"; menus over it keep it (c11)', (
      tester,
    ) async {
      await _pumpWindow(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).last)
        ..push(
          MaterialPageRoute<void>(
            settings: RouteSettings(
              name: RoutePath.kLivePlay,
              arguments: LiveRoom(platform: 'bilibili', roomId: '1', nick: '晚风'),
            ),
            builder: (_) => const Scaffold(body: Text('room')),
          ),
        );
      await tester.pumpAndSettle();
      expect(find.text(' · 晚风'), findsOneWidget);
      final room = tester.widget<Text>(_key('title-bar-room')).style!;
      expect(room.fontWeight, FontWeight.w400);
      expect(tester.getRect(_key('title-bar-room')).left, greaterThan(tester.getRect(find.text('纯粹直播')).right - 1));
      expect(roomNameOf(liveRouteObserver.topPage.value), '晚风');
      expect(nativeWindowTitle('纯粹直播', roomNameOf(liveRouteObserver.topPage.value)), '晚风 - 纯粹直播');

      unawaited(showDialog<void>(context: navigator.context, builder: (_) => const AlertDialog(content: Text('m'))));
      await tester.pumpAndSettle();
      expect(find.text(' · 晚风'), findsOneWidget, reason: 'a dialog over the room is not a page');
      navigator.pop();
      await tester.pumpAndSettle();

      navigator.pop();
      await tester.pumpAndSettle();
      expect(_key('title-bar-room'), findsNothing);
      expect(roomNameOf(liveRouteObserver.topPage.value), isNull);
      expect(nativeWindowTitle('纯粹直播', null), '纯粹直播');
      expect(roomNameOf(RouteSettings(name: RoutePath.kLivePlay, arguments: LiveRoom(platform: 'a', roomId: '2'))), isNull);
    });

    testWidgets('the smallest window 360 × 400 and a 1.5× system font: one line, nothing spills', (tester) async {
      await _pumpWindow(tester, size: DesktopShell.minimumSize, textScale: 1.5);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).last)
        ..push(
          MaterialPageRoute<void>(
            settings: RouteSettings(
              name: RoutePath.kLivePlay,
              arguments: LiveRoom(platform: 'bilibili', roomId: '1', nick: '一个名字非常非常长的主播在这里直播'),
            ),
            builder: (_) => const Scaffold(body: Text('room')),
          ),
        );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getSize(_key('title-bar')).height, 32);
      expect(tester.getRect(_key('title-bar-close')).right, 360);
      expect(tester.getRect(_key('title-bar-room')).right, lessThanOrEqualTo(360 - 3 * 46.0));
      navigator.pop();
      await tester.pumpAndSettle();
    });

    testWidgets('1920 × 1080: the buttons stay at the right edge', (tester) async {
      await _pumpWindow(tester, size: const Size(1920, 1080));
      expect(tester.getRect(_key('title-bar-close')).right, 1920);
      expect(tester.getRect(_key('title-bar-minimize')).left, 1920 - 138);
    });
  });

  group('close dialog', () {
    testWidgets('title, question, "不再询问" with the hint; minimize at the left, red exit at the right (c7, c8)', (
      tester,
    ) async {
      final answer = await _pumpDialog(tester);
      expect(find.text('关闭窗口'), findsOneWidget);
      expect(find.text('退出应用，还是最小化到托盘继续运行？'), findsOneWidget);
      expect(find.text('不再询问'), findsOneWidget);
      expect(find.text('以后可以在“设置 → 通用 → 关闭窗口时”里改'), findsOneWidget);
      expect(_key('close-recording'), findsNothing);
      expect(find.text('最小化到托盘'), findsOneWidget);
      expect(find.text('退出应用'), findsOneWidget);
      expect(find.text('确定要退出吗？'), findsNothing, reason: "3.x's question did not match its buttons");

      final dialog = tester.getRect(find.descendant(of: _key('close-dialog'), matching: find.byType(Material)).first);
      expect(dialog.width, CloseWindowDialog.width);
      final minimize = tester.getRect(_key('close-minimize'));
      final exit = tester.getRect(_key('close-exit'));
      expect(minimize.center.dy, closeTo(exit.center.dy, 1), reason: 'one row');
      expect(minimize.left - dialog.left, lessThan(24), reason: 'at the left end');
      expect(dialog.right - exit.right, 24, reason: 'at the right end');
      expect(tester.getRect(find.text('不再询问')).top, greaterThan(tester.getRect(find.text('退出应用，还是最小化到托盘继续运行？')).bottom));
      expect(tester.getRect(find.text('以后可以在“设置 → 通用 → 关闭窗口时”里改')).left, closeTo(tester.getRect(find.text('不再询问')).left, 6));
      final scheme = const LiveTheme(primaryColor: _seed).light.colorScheme;
      final exitStyle = tester.widget<FilledButton>(_key('close-exit')).style!;
      expect(exitStyle.backgroundColor!.resolve({}), scheme.error);
      expect(exitStyle.foregroundColor!.resolve({}), scheme.onError);
      final hint = tester.widget<Text>(find.text('以后可以在“设置 → 通用 → 关闭窗口时”里改'));
      expect(hint.style!.color, scheme.onSurfaceVariant);

      await tester.tap(_key('close-remember'));
      await tester.pump();
      await tester.tap(_key('close-minimize'));
      await tester.pumpAndSettle();
      expect(await answer.future, (action: CloseAction.minimize, remember: true));
    });

    testWidgets('Esc and a tap outside cancel', (tester) async {
      var answer = await _pumpDialog(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(await answer.future, isNull);
      answer = await _pumpDialog(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(await answer.future, isNull);
    });

    testWidgets('while recording: the red note, the exit answer (c9)', (tester) async {
      final answer = await _pumpDialog(tester, recording: 2, remember: true);
      expect(find.text('正在录制 2 个直播间'), findsOneWidget);
      expect(find.text('退出会停止录制，已经录下的部分会保存。'), findsOneWidget);
      final note = tester.getRect(_key('close-recording'));
      expect(note.top, greaterThan(tester.getRect(_key('close-question')).bottom));
      expect(note.bottom, lessThan(tester.getRect(find.text('不再询问')).top));
      final scheme = const LiveTheme(primaryColor: _seed).light.colorScheme;
      expect(tester.widget<Text>(find.text('正在录制 2 个直播间')).style!.color, scheme.error);
      expect(
        (tester.widget<DecoratedBox>(_key('close-recording')).decoration as BoxDecoration).color,
        LiveSemanticColors.recordingNote(Brightness.light),
      );
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue, reason: 'the stored "不再询问" shows');
      await tester.tap(_key('close-exit'));
      await tester.pumpAndSettle();
      expect(await answer.future, (action: CloseAction.exit, remember: true));
    });

    testWidgets('no tray (a desktop without one): "最小化" to the taskbar; no "不再询问" when not offered', (tester) async {
      final answer = await _pumpDialog(tester, tray: false, askRemember: false, recording: 1);
      expect(find.text('退出应用，还是最小化到任务栏继续运行？'), findsOneWidget);
      expect(find.text('最小化'), findsOneWidget);
      expect(find.text('最小化到托盘'), findsNothing);
      expect(find.text('不再询问'), findsNothing);
      expect(_key('close-hint'), findsNothing);
      await tester.tap(_key('close-minimize'));
      await tester.pumpAndSettle();
      expect(await answer.future, (action: CloseAction.minimize, remember: false));
    });

    testWidgets('a phone-sized window, dark, 1.5× font: nothing spills', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpDialog(tester, recording: 2, size: const Size(360, 400), mode: ThemeMode.dark);
      expect(tester.takeException(), isNull);
      expect(
        (tester.widget<DecoratedBox>(_key('close-recording')).decoration as BoxDecoration).color,
        LiveSemanticColors.recordingNote(Brightness.dark),
      );
    });
  });

  group('closing', () {
    late LiveStore store;
    late List<String> calls;
    late List<({bool tray, int recording, bool askRemember, bool remember})> asked;
    CloseChoice? reply;
    var recording = 0;
    var tray = true;
    var refuse = false;

    WindowCloser closer({bool primary = true}) => WindowCloser(
      settings: store.settings,
      primary: primary,
      hasTray: () => tray,
      recordings: () => recording,
      ask: ({required tray, required recording, required askRemember, required remember}) async {
        asked.add((tray: tray, recording: recording, askRemember: askRemember, remember: remember));
        return reply;
      },
      hide: () async => calls.add('hide'),
      minimize: () async => calls.add('minimize'),
      exit: () async {
        if (refuse) throw StateError('refused');
        calls.add('exit');
      },
      show: () async => calls.add('show'),
      failed: () => calls.add('failed'),
    );

    setUp(() async {
      store = await LiveStore.memory(cipher: FakeCipher());
      calls = [];
      asked = [];
      reply = null;
      recording = 0;
      tray = true;
      refuse = false;
    });
    tearDown(() => store.close());

    test('the main window asks, then does and remembers the answer (3.x)', () async {
      reply = (action: CloseAction.minimize, remember: false);
      await closer().close();
      expect(asked.single, (tray: true, recording: 0, askRemember: true, remember: false));
      expect(calls, ['hide'], reason: 'minimize hides to the tray');
      expect(store.settings.get(Settings.exitChoose), 'minimize');

      reply = (action: CloseAction.exit, remember: true);
      await closer().close();
      expect(calls, ['hide', 'exit']);
      expect(store.settings.get(Settings.dontAskExit), isTrue);

      reply = null;
      asked.clear();
      calls.clear();
      await store.settings.setAll({Settings.dontAskExit: false});
      await closer().close();
      expect(asked, hasLength(1));
      expect(calls, isEmpty, reason: 'dismissed: nothing happens');
    });

    test('"不再询问": the remembered answer at once; without a tray minimize goes to the taskbar', () async {
      await store.settings.setAll({Settings.dontAskExit: true, Settings.exitChoose: 'minimize'});
      await closer().close();
      tray = false;
      await closer().close();
      expect(calls, ['hide', 'minimize']);
      expect(asked, isEmpty);
    });

    test('quitting while recording asks even with "不再询问" (c9); minimizing does not', () async {
      recording = 2;
      await store.settings.setAll({Settings.dontAskExit: true, Settings.exitChoose: 'exit'});
      reply = (action: CloseAction.minimize, remember: true);
      await closer().close();
      expect(asked.single, (tray: true, recording: 2, askRemember: true, remember: true));
      expect(calls, ['hide']);
      // Now "minimize" is remembered: no question, the recording goes on.
      await closer().close();
      expect(asked, hasLength(1));
      expect(calls, ['hide', 'hide']);
    });

    test('a refused action: the old answer comes back and "窗口操作失败，请重试"', () async {
      refuse = true;
      reply = (action: CloseAction.exit, remember: true);
      await closer().close();
      expect(calls, ['failed']);
      expect(store.settings.get(Settings.dontAskExit), isFalse);
      expect(store.settings.get(Settings.exitChoose), 'exit');

      await store.settings.setAll({Settings.dontAskExit: true, Settings.exitChoose: 'exit'});
      await closer().close();
      expect(store.settings.get(Settings.dontAskExit), isFalse, reason: '3.x asks again next time');
    });

    test('an extra window closes at once; while it records it asks, without "不再询问" (c10)', () async {
      await closer(primary: false).close();
      expect(calls, ['exit']);
      expect(asked, isEmpty);
      recording = 1;
      reply = (action: CloseAction.minimize, remember: false);
      await closer(primary: false).close();
      expect(asked.single, (tray: false, recording: 1, askRemember: false, remember: false));
      expect(calls, ['exit', 'minimize'], reason: 'an extra window has no tray');
    });

    test("the tray's exit: at once, or after showing the window and asking while recording (c9)", () async {
      await closer().exitFromTray();
      expect(calls, ['exit']);
      recording = 3;
      reply = null;
      await closer().exitFromTray();
      expect(calls, ['exit', 'show']);
      expect(asked.single, (tray: true, recording: 3, askRemember: false, remember: false));
    });
  });

  group('tray', () {
    test('rows and hint: recording first while recording (c9, T4)', () {
      expect(trayMenuRows(recording: 0), [TrayRow.window, TrayRow.separator, TrayRow.exit]);
      expect(trayMenuRows(recording: 2), [
        TrayRow.recording,
        TrayRow.separator,
        TrayRow.window,
        TrayRow.separator,
        TrayRow.exit,
      ]);
      expect(trayRowLabel(TrayRow.recording, visible: true, recording: 2), '正在录制 2 个直播间');
      expect(trayRowLabel(TrayRow.window, visible: true, recording: 0), '隐藏窗口');
      expect(trayRowLabel(TrayRow.window, visible: false, recording: 0), '显示窗口');
      expect(trayRowLabel(TrayRow.exit, visible: true, recording: 0), '退出应用');
      expect(trayTooltip(recording: 0), '纯粹直播');
      expect(trayTooltip(recording: 2), '纯粹直播 · 正在录制 2 个');
    });
  });

  group('window', () {
    test('a remembered place off every display goes back to the middle (c6)', () {
      const displays = [Rect.fromLTWH(0, 0, 1920, 1040)];
      expect(titleRowOnScreen(const Offset(100, 80), const Size(1280, 720), displays), isTrue);
      expect(titleRowOnScreen(const Offset(-1000, 80), const Size(1280, 720), displays), isTrue, reason: 'partly on screen');
      expect(
        titleRowOnScreen(const Offset(2100, 80), const Size(1280, 720), displays),
        isFalse,
        reason: 'the second monitor was unplugged',
      );
      expect(titleRowOnScreen(const Offset(100, -200), const Size(1280, 720), displays), isFalse);
      expect(DesktopShell.minimumSize, const Size(360, 400), reason: 'UI_PLAN §5.3: falls to the phone layout');
    });

    test('new windows: offered with a launcher and the setting; the room is passed (c12, appendix A 15)', () async {
      final store = await LiveStore.memory(cipher: FakeCipher());
      addTearDown(store.close);
      addTearDown(() => DesktopWindow.newWindowLauncher = null);
      DesktopWindow.newWindowLauncher = null;
      expect(DesktopWindow.offersNewWindow(store.settings), isFalse, reason: 'phones and tests');
      expect(await DesktopWindow.openNewWindow(), isFalse);

      final rooms = <LiveRoom?>[];
      DesktopWindow.newWindowLauncher = ({room}) async => rooms.add(room);
      expect(DesktopWindow.offersNewWindow(store.settings), isTrue);
      await store.settings.set(Settings.enableNewWindowPlay, false);
      expect(DesktopWindow.offersNewWindow(store.settings), isFalse);

      final room = LiveRoom(platform: 'bilibili', roomId: '1', nick: '晚风');
      expect(await DesktopWindow.openNewWindow(room: room), isTrue);
      expect(rooms.single, room);

      final toasts = <String>[];
      final toast = AppNavigator.toast;
      addTearDown(() => AppNavigator.toast = toast);
      AppNavigator.toast = toasts.add;
      DesktopWindow.newWindowLauncher = ({room}) async => throw const ProcessException('pure_live.exe', []);
      expect(await DesktopWindow.openNewWindow(), isFalse);
      expect(toasts, ['新窗口启动失败，请重试']);
    });

    test('the page on top: menus and dialogs are not pages', () {
      final page = MaterialPageRoute<void>(
        settings: const RouteSettings(name: RoutePath.kLivePlay),
        builder: (_) => const SizedBox(),
      );
      final other = MaterialPageRoute<void>(
        settings: const RouteSettings(name: RoutePath.kInitial),
        builder: (_) => const SizedBox(),
      );
      final observer = LiveRouteObserver();
      final dialog = RawDialogRoute<void>(pageBuilder: (_, _, _) => const SizedBox());
      observer
        ..didPush(other, null)
        ..didPush(page, other);
      expect(observer.topPage.value?.name, RoutePath.kLivePlay);
      observer.didPush(dialog, page);
      expect(observer.topPage.value?.name, RoutePath.kLivePlay);
      observer
        ..didPop(dialog, page)
        ..didRemove(page, other);
      expect(observer.topPage.value?.name, RoutePath.kInitial);
    });
  });

  group('shared data (c14)', () {
    test('a write of another window reaches this one without polling', () async {
      final folder = await Directory.systemTemp.createTemp('desktop_shared_');
      addTearDown(() => folder.delete(recursive: true));
      final mine = await LiveStore.open(folder, cipher: FakeCipher(), shared: true);
      final other = await LiveStore.open(folder, cipher: FakeCipher(), shared: true);
      addTearDown(other.close);
      addTearDown(mine.close);
      final watch = SharedDataWatch(mine, folder)..start();
      addTearDown(watch.dispose);
      expect(isDatabaseFile('${folder.path}/pure_live.db-journal'), isTrue);
      expect(isDatabaseFile('${folder.path}/logs/app.log'), isFalse);

      final changed = mine.settings.watch(Settings.themeMode).firstWhere((mode) => mode == 'Dark');
      await other.settings.set(Settings.themeMode, 'Dark');
      expect(await changed.timeout(const Duration(seconds: 5)), 'Dark');
    });
  });

  testWidgets('the home menu offers the new window on a desktop with the setting (c12)', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <LiveRoom?>[];
    DesktopWindow.newWindowLauncher = ({room}) async => opened.add(room);
    addTearDown(() => DesktopWindow.newWindowLauncher = null);
    final services = (await tester.runAsync(() async {
      final services = await testServices();
      await services.store.settings.set(Settings.showSplashPage, false);
      return services;
    }))!;
    final strings = (await tester.runAsync(loadStrings))!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appServicesProvider.overrideWithValue(services)],
        child: PureLiveApp(strings: strings, bundle: FileAssetBundle()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-menu')));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('home-menu-newWindow'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('新建独立播放窗口')), findsOneWidget);
    expect(find.descendant(of: row, matching: find.byIcon(AppIcons.newPlayerWindow)), findsOneWidget);
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(opened, [null], reason: 'a new home window');

    await tester.runAsync(() => services.store.settings.set(Settings.enableNewWindowPlay, false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-menu-newWindow')), findsNothing);
    await tester.tapAt(const Offset(600, 700));
    await tester.pumpAndSettle();
    await tester.runAsync(services.close);
  });
}
