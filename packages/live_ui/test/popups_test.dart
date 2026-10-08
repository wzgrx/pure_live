import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

// The dialog, the panel and the toast (docs/A-界面设计/A02-组件/A02.2-弹窗组件):
// where each goes on a portrait phone (393 × 852), a
// landscape phone (852 × 393) and a tablet (1280 × 800), the keys, and the
// light and dark themes.

const Size _portrait = Size(393, 852);
const Size _landscape = Size(852, 393);
const Size _tablet = Size(1280, 800);

/// A page with a "open" button that runs [open] with its context, in the
/// given [size] and [dark]ness; with [navBar] a bottom navigation bar.
Future<void> _page(
  WidgetTester tester,
  void Function(BuildContext context) open, {
  Size size = _portrait,
  bool dark = false,
  bool navBar = false,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: const LiveTheme().light,
      darkTheme: const LiveTheme().dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        bottomNavigationBar: navBar
            ? NavigationBar(
                key: const ValueKey('nav'),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.favorite), label: '关注'),
                  NavigationDestination(icon: Icon(Icons.whatshot), label: '热门'),
                ],
              )
            : null,
        body: Builder(
          builder: (context) => Center(
            child: TextButton(onPressed: () => open(context), child: const Text('open')),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

double _fontSize(WidgetTester tester, Finder text) => tester.renderObject<RenderParagraph>(text).text.style!.fontSize!;

Rect _dialogRect(WidgetTester tester) =>
    tester.getRect(find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first);

void main() {
  group('dialog', () {
    for (final (name, size, width) in [
      ('portrait', _portrait, 361.0),
      ('landscape', _landscape, 400.0),
      ('tablet', _tablet, 400.0),
    ]) {
      testWidgets('confirm on a $name screen: the screen less 32, at most 400, in the middle; 20/14/14', (
        tester,
      ) async {
        final answers = <bool>[];
        await _page(tester, size: size, (context) async {
          answers.add(
            await showAppConfirmDialog(
              context: context,
              title: '退出登录',
              message: '确定要退出哔哩哔哩账号吗？',
              confirmLabel: '退出登录',
              confirmKey: const ValueKey('confirm'),
            ),
          );
        });
        final rect = _dialogRect(tester);
        expect(rect.width, width);
        expect(rect.center.dx, closeTo(size.width / 2, 0.5));
        expect(rect.center.dy, closeTo(size.height / 2, 0.5));
        expect(_fontSize(tester, find.byKey(const ValueKey('app-dialog-title'))), 20);
        expect(_fontSize(tester, find.text('确定要退出哔哩哔哩账号吗？')), 14);
        expect(_fontSize(tester, find.text('取消')), 14);
        // "取消" first, then the button that says what it does, filled.
        expect(
          tester.getCenter(find.text('取消')).dx,
          lessThan(tester.getCenter(find.byKey(const ValueKey('confirm'))).dx),
        );
        expect(find.descendant(of: find.byKey(const ValueKey('confirm')), matching: find.text('退出登录')), findsOneWidget);
        expect(tester.widget(find.byKey(const ValueKey('confirm'))), isA<DialogActionButton>());

        await tester.tap(find.byKey(const ValueKey('confirm')));
        await tester.pumpAndSettle();
        expect(answers, [true]);
      });
    }

    testWidgets('keys: Enter is the main button, Esc cancels; a tap outside closes', (tester) async {
      final answers = <bool>[];
      Future<void> ask(BuildContext context) async =>
          answers.add(await showAppConfirmDialog(context: context, message: '确定？', confirmLabel: '保存'));
      await _page(tester, ask, size: _tablet);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(answers, [true]);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(answers, [true, false]);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(answers, [true, false, false]);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a destructive question: red, the focus on "取消", so Enter does not destroy', (tester) async {
      final answers = <bool>[];
      await _page(tester, size: _tablet, (context) async {
        answers.add(
          await showAppConfirmDialog(
            context: context,
            title: '重置小窗位置和大小',
            message: '确定要清除已保存的小窗位置和大小吗？',
            confirmLabel: '重置',
            danger: true,
            confirmKey: const ValueKey('confirm'),
          ),
        );
      });
      final surface = tester.widget<Material>(
        find.descendant(of: find.byKey(const ValueKey('confirm')), matching: find.byType(Material)).first,
      );
      final scheme = const LiveTheme().light.colorScheme;
      expect(surface.color, scheme.error);
      expect(Focus.of(tester.element(find.text('取消'))).hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(answers, [false]);
    });

    testWidgets('options on a landscape phone: the title and "取消" stay while the list scrolls; a tap picks', (
      tester,
    ) async {
      final picked = <String?>[];
      const qualities = ['原画', '蓝光8M', '蓝光4M', '蓝光', '超清', '高清', '流畅', '标清'];
      await _page(tester, size: _landscape, (context) async {
        picked.add(
          await showAppOptionDialog<String>(
            context: context,
            title: '首选清晰度',
            selected: '原画',
            options: [for (final q in qualities) AppDialogOption(value: q, label: q, key: ValueKey('option-$q'))],
          ),
        );
      });
      final rect = _dialogRect(tester);
      expect(rect.top, greaterThanOrEqualTo(16));
      expect(rect.bottom, lessThanOrEqualTo(_landscape.height - 16));
      final title = tester.getRect(find.text('首选清晰度'));
      final cancel = tester.getRect(find.text('取消'));
      // The current option: primary colour, semi-bold, a tick.
      final scheme = const LiveTheme().light.colorScheme;
      final current = tester.renderObject<RenderParagraph>(find.text('原画')).text.style!;
      expect(current.color, scheme.primary);
      expect(current.fontWeight, FontWeight.w600);
      expect(
        find.descendant(of: find.byKey(const ValueKey('option-原画')), matching: find.byIcon(AppIcons.selected)),
        findsOneWidget,
      );

      await tester.drag(find.byKey(const ValueKey('app-dialog-body')), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('首选清晰度')), title);
      expect(tester.getRect(find.text('取消')), cancel);
      await tester.tap(find.text('标清'));
      await tester.pumpAndSettle();
      expect(picked, ['标清']);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('input: one line, the reason under the field, saving spins and nothing closes it', (tester) async {
      final results = <String?>[];
      final saving = Completer<String?>();
      await _page(tester, (context) async {
        results.add(
          await showAppInputDialog(
            context: context,
            title: '屏蔽弹幕关键词',
            label: '关键词',
            helper: '含这个词的弹幕都不再显示',
            maxLength: 40,
            confirmLabel: '屏蔽',
            fieldKey: const ValueKey('field'),
            confirmKey: const ValueKey('save'),
            check: (text) => text.length < 2 ? '至少两个字' : null,
            save: (_) => saving.future,
          ),
        );
      });
      final field = tester.widget<TextField>(find.byKey(const ValueKey('field')));
      expect(field.maxLines, 1);
      final editable = tester.widget<EditableText>(
        find.descendant(of: find.byKey(const ValueKey('field')), matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(find.text('0/40'), findsOneWidget);
      // Nothing typed: the main button does nothing.
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('save'))).onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('field')), '前');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('至少两个字'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('field')), ' 前排支持！ ');
      await tester.pump();
      expect(find.text('至少两个字'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('save')));
      await tester.pump();
      expect(find.byKey(const ValueKey('dialog-action-busy')), findsOneWidget);
      // Back, Esc and a tap outside do nothing while it saves.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.tapAt(const Offset(10, 10));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget);

      saving.complete(null);
      await tester.pumpAndSettle();
      expect(results, ['前排支持！']);
    });

    testWidgets('message: one "知道了"; with an action, the action is the main button', (tester) async {
      final answers = <bool>[];
      await _page(tester, (context) async {
        answers.add(await showAppMessageDialog(context: context, title: '无法打开画中画', message: '系统设置里关掉了权限。'));
      });
      expect(find.byType(FilledButton), findsNothing);
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(answers, [false]);
    });

    testWidgets('buttons stack, the main one on top, only when they do not fit (very large text)', (tester) async {
      await _page(tester, textScale: 2, (context) {
        unawaited(showAppConfirmDialog(context: context, message: '确定？', confirmLabel: '下载并安装这个新版本'));
      });
      expect(tester.getCenter(find.text('取消')).dy, greaterThan(tester.getCenter(find.text('下载并安装这个新版本')).dy));
    });

    for (final dark in [false, true]) {
      testWidgets('the ${dark ? 'dark' : 'light'} theme: the high container, 24-point corners', (tester) async {
        await _page(tester, dark: dark, (context) {
          unawaited(showAppConfirmDialog(context: context, message: '确定？', confirmLabel: '保存'));
        });
        final theme = dark ? const LiveTheme().dark : const LiveTheme().light;
        final material = tester.widget<Material>(
          find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first,
        );
        expect(material.color, theme.colorScheme.surfaceContainerHigh);
        expect((material.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(24));
      });
    }
  });

  group('panel', () {
    Widget content(BuildContext context) => PanelFrame(
      expand: false,
      header: const PanelHeader(title: '全部平台'),
      child: ListView(
        key: const ValueKey('list'),
        shrinkWrap: true,
        children: [for (var i = 0; i < 40; i++) ListTile(title: Text('平台 $i'))],
      ),
    );

    testWidgets('portrait: from the bottom with a handle; the header 52 high, 17/600; a line once scrolled', (
      tester,
    ) async {
      await _page(tester, (context) => unawaited(showAdaptivePanel<void>(context, builder: content)));
      expect(find.byType(BottomSheet), findsOneWidget);
      final sheet = tester.getRect(find.byType(BottomSheet));
      expect(sheet.bottom, _portrait.height);
      expect(sheet.width, _portrait.width);
      final title = tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('panel-title'))).text.style!;
      expect(title.fontSize, 17);
      expect(title.fontWeight, FontWeight.w600);
      expect(tester.getSize(find.byType(PanelHeader)).height, 52);

      Color line() => tester.widget<Divider>(find.byKey(const ValueKey('panel-header-line'))).color!;
      expect(line(), Colors.transparent);
      final header = tester.getRect(find.byType(PanelHeader));
      await tester.drag(find.byKey(const ValueKey('list')), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(line(), const LiveTheme().light.colorScheme.outlineVariant);
      expect(tester.getRect(find.byType(PanelHeader)), header);

      await tester.tap(find.byKey(const ValueKey('panel-close')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    for (final (name, size) in [('landscape', _landscape), ('tablet', _tablet)]) {
      testWidgets('$name: on the right, 360 wide, the full height; Esc closes', (tester) async {
        await _page(tester, size: size, (context) => unawaited(showAdaptivePanel<void>(context, builder: content)));
        final panel = tester.getRect(find.byKey(const ValueKey('side-panel')));
        expect(panel.width, sidePanelWidth);
        expect(panel.right, size.width);
        expect(panel.height, size.height);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('side-panel')), findsNothing);
      });
    }
  });

  group('toast', () {
    Rect toastRect(WidgetTester tester) =>
        tester.getRect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first);

    testWidgets('portrait: 16 above the bottom navigation bar, the screen less 32, 14 on two lines at most', (
      tester,
    ) async {
      await _page(tester, navBar: true, (context) => showAppToast(context, const AppToast('已复制到剪贴板')));
      final toast = toastRect(tester);
      final nav = tester.getRect(find.byKey(const ValueKey('nav')));
      expect(toast.bottom, nav.top - 16);
      expect(toast.left, 16);
      expect(toast.width, _portrait.width - 32);
      final text = tester.widget<Text>(find.text('已复制到剪贴板'));
      expect(text.maxLines, 2);
      expect(_fontSize(tester, find.text('已复制到剪贴板')), 14);
      final material = tester.widget<Material>(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first,
      );
      expect((material.shape! as RoundedRectangleBorder).borderRadius, BorderRadius.circular(8));
      // Gone after 3 s.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    for (final (name, size) in [('landscape', _landscape), ('tablet', _tablet)]) {
      testWidgets('$name: at the bottom in the middle, 560 wide', (tester) async {
        await _page(tester, size: size, (context) => showAppToast(context, const AppToast('已开始录制')));
        final toast = toastRect(tester);
        expect(toast.width, appToastMaxWidth);
        expect(toast.center.dx, closeTo(size.width / 2, 0.5));
        expect(toast.bottom, size.height - 16);
      });
    }

    testWidgets('an action: 4 s, and using it closes the toast', (tester) async {
      var undone = 0;
      await _page(
        tester,
        (context) => showAppToast(context, AppToast('已移除“前排”', actionLabel: '撤销', onAction: () => undone++)),
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text('撤销'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(undone, 1);
      expect(find.byType(SnackBar), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('one the user has to answer stays, with ✕, until ✕', (tester) async {
      await _page(
        tester,
        (context) => showAppToast(context, AppToast('这是一个直播间', actionLabel: '进入', onAction: () {}, persistent: true)),
      );
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.text('这是一个直播间'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app-toast-close')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    // A02.4: an accessibility service on (K90's select-to-speak) kept a toast
    // with an action up for good and without ✕.
    Future<void> accessiblePage(WidgetTester tester, AppToast toast) async {
      final messenger = GlobalKey<ScaffoldMessengerState>();
      tester.view
        ..physicalSize = _portrait
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        accessibleNavigation: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messenger,
          theme: const LiveTheme().light,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      showAppToastOn(messenger.currentState!, toast);
      await tester.pumpAndSettle();
    }

    testWidgets('an action with an accessibility service on: ✕, and gone after 30 s', (tester) async {
      await accessiblePage(tester, AppToast('已取消关注“前排”', actionLabel: '撤销', onAction: () {}));
      expect(find.byKey(const ValueKey('app-toast-close')), findsOneWidget);
      await tester.pump(const Duration(seconds: 29));
      await tester.pump();
      expect(find.text('撤销'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('an action with an accessibility service on: ✕ closes it', (tester) async {
      await accessiblePage(tester, AppToast('已取消关注“前排”', actionLabel: '撤销', onAction: () {}));
      await tester.tap(find.byKey(const ValueKey('app-toast-close')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('no action with an accessibility service on: no ✕, gone after 3 s as before', (tester) async {
      await accessiblePage(tester, const AppToast('已复制'));
      expect(find.byKey(const ValueKey('app-toast-close')), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a new page closes a toast with an action, not a plain one or one to answer', (tester) async {
      final messenger = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messenger,
          theme: const LiveTheme().light,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      final state = messenger.currentState!;
      showAppToastOn(state, AppToast('已取消关注“前排”', actionLabel: '撤销', onAction: () {}));
      await tester.pumpAndSettle();
      closePageAppToast(state);
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      showAppToastOn(state, const AppToast('已复制'));
      await tester.pumpAndSettle();
      closePageAppToast(state);
      await tester.pumpAndSettle();
      expect(find.text('已复制'), findsOneWidget);

      showAppToastOn(state, AppToast('画中画已关闭', actionLabel: '去设置', onAction: () {}, persistent: true));
      await tester.pumpAndSettle();
      closePageAppToast(state);
      await tester.pumpAndSettle();
      expect(find.text('画中画已关闭'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('the ${dark ? 'dark' : 'light'} theme: the inverse colours', (tester) async {
        await _page(tester, dark: dark, (context) => showAppToast(context, const AppToast('已复制')));
        final theme = dark ? const LiveTheme().dark : const LiveTheme().light;
        final material = tester.widget<Material>(
          find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first,
        );
        expect(material.color, theme.colorScheme.inverseSurface);
        expect(
          tester.renderObject<RenderParagraph>(find.text('已复制')).text.style!.color,
          theme.colorScheme.onInverseSurface,
        );
      });
    }

    testWidgets('AppToaster: the same words not again while they show; the new one replaces the old', (tester) async {
      final messenger = GlobalKey<ScaffoldMessengerState>();
      tester.view
        ..physicalSize = _portrait
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messenger,
          theme: const LiveTheme().light,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );
      final toaster = AppToaster(() => messenger.currentState);
      final shown = <String>[];
      void show(String words) {
        toaster.show(AppToast(words));
        shown.add(words);
      }

      show('已复制');
      await tester.pumpAndSettle();
      expect(find.text('已复制'), findsOneWidget);
      // The same words again at once: no second toast queued.
      toaster.show(const AppToast('已复制'));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      // After it went, the same words show again.
      show('已复制');
      await tester.pumpAndSettle();
      expect(find.text('已复制'), findsOneWidget);
      // A new message replaces the shown one.
      show('已开始录制');
      await tester.pumpAndSettle();
      expect(find.text('已复制'), findsNothing);
      expect(find.text('已开始录制'), findsOneWidget);
      expect(shown, ['已复制', '已复制', '已开始录制']);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });
}
