import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/tv/tv_theme.dart';
import 'package:pure_live/tv/widgets/tv_area_card.dart';
import 'package:pure_live/tv/widgets/tv_button.dart';
import 'package:pure_live/tv/widgets/tv_dialogs.dart';
import 'package:pure_live/tv/widgets/tv_focusable.dart';
import 'package:pure_live/tv/widgets/tv_page_header.dart';
import 'package:pure_live/tv/widgets/tv_room_card.dart';
import 'package:pure_live/tv/widgets/tv_room_dialog.dart';
import 'package:pure_live/tv/widgets/tv_room_push_dialog.dart';
import 'package:pure_live/tv/widgets/tv_settings_rows.dart';
import 'package:pure_live/tv/widgets/tv_status.dart';
import 'package:pure_live/tv/widgets/tv_tabs.dart';

import '../support.dart';

// The TV design system and shared components (docs/A-界面设计/A17-电视界面/A17.1-电视设计系统和通用组件).

/// The dark scheme of the default blue (the TV is dark only, choice A2).
final ColorScheme _scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF2196F3), brightness: Brightness.dark);

/// Panels: a 1080p television (960 x 540 logical at 2x), the same panel at
/// 1x, and a 720p box.
const Map<String, (Size, double)> _panels = {
  '1080p@2x': (Size(1920, 1080), 2),
  '1080p@1x': (Size(1920, 1080), 1),
  '720p@1x': (Size(1280, 720), 1),
};

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String panel = '1080p@2x',
  bool zoom = true,
  bool center = true,
}) async {
  final (size, ratio) = _panels[panel]!;
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = ratio;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorScheme: _scheme),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            navigationMode: NavigationMode.directional,
            textScaler: TextScaler.linear(TvScale.legibilityLift(context)),
          ),
          child: TvTheme(
            palette: TvPalette.of(_scheme),
            zoom: zoom,
            child: Scaffold(
              body: TvBackground(child: center ? Center(child: child) : child),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Lets a store answer (real time) and the frames run.
Future<void> _settle(WidgetTester tester, {int rounds = 4}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump(const Duration(milliseconds: 200));
}

Key? get _focusedKey {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  Key? key;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is TvButton || widget is TvOptionRow || widget is TvSettingsRow || widget is TvRoomCard) {
      key = widget.key;
      return false;
    }
    if (widget is TvFocusable && widget.key != null) {
      key = widget.key;
      return false;
    }
    return true;
  });
  return key;
}

/// The ring and growth a focusable draws now.
({bool ring, double scale}) _look(WidgetTester tester, Finder target) {
  final focusable = find.descendant(of: target, matching: find.byType(TvFocusable), matchRoot: true).first;
  final box = tester.widget<DecoratedBox>(find.descendant(of: focusable, matching: find.byType(DecoratedBox)).first);
  final border = (box.decoration as BoxDecoration).border as Border?;
  final scale = tester.widget<AnimatedScale>(
    find.descendant(of: focusable, matching: find.byType(AnimatedScale)).first,
  );
  return (ring: border != null && border.top.color == TvColors.focusRing, scale: scale.scale);
}

/// The smallest text size drawn under [finder].
double _smallestText(WidgetTester tester, Finder finder) {
  var smallest = double.infinity;
  // Icons are glyphs and an avatar without a picture draws an initial: not text.
  final glyphs = {
    ...tester.widgetList<RichText>(find.descendant(of: find.byType(Icon), matching: find.byType(RichText))),
    ...tester.widgetList<RichText>(find.descendant(of: find.byType(CommonAvatar), matching: find.byType(RichText))),
  };
  for (final text in tester.widgetList<RichText>(find.descendant(of: finder, matching: find.byType(RichText)))) {
    if (glyphs.contains(text)) continue;
    final scaler = text.textScaler;
    text.text.visitChildren((span) {
      final size = span.style?.fontSize;
      if (size != null) smallest = scaler.scale(size) < smallest ? scaler.scale(size) : smallest;
      return true;
    });
  }
  return smallest;
}

const RoomCardData _live = RoomCardData(
  platformId: SiteIds.bilibili,
  title: '深夜电台 · 点歌接龙到天亮，今晚聊聊你的故事，一直聊到天亮',
  anchorName: '晚风',
  isLive: true,
  audience: RoomAudience(kind: RoomAudienceKind.popularity, value: '84.7万'),
);

final LiveRoom _room = LiveRoom(
  platform: SiteIds.bilibili,
  roomId: '21452505',
  title: '深夜电台 · 点歌接龙到天亮',
  nick: '晚风',
  liveStatus: LiveStatus.live,
);

void main() {
  final toasts = <String>[];
  setUpAll(loadStrings);
  setUp(() {
    toasts.clear();
    AppNavigator.toast = toasts.add;
  });

  test('the palette is the phone dark roles of the theme colour; every text pair reads at 4.5:1 (c4, A2)', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
    }

    for (final seed in const [Color(0xFF2196F3), Color(0xFFFF66CC), Color(0xFF2AD39A), Color(0xFFFF9F43)]) {
      // A light app theme still gives the TV its dark palette.
      final palette = TvPalette.of(ColorScheme.fromSeed(seedColor: seed));
      expect(palette.scheme.brightness, Brightness.dark);
      for (final ground in [palette.background, palette.card, palette.raised, palette.highest]) {
        expect(contrast(palette.text, ground), greaterThanOrEqualTo(4.5));
        expect(contrast(palette.textSecondary, ground), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(palette.accent, palette.highest), greaterThanOrEqualTo(4.5), reason: 'main action on a button');
      expect(contrast(palette.danger, palette.highest), greaterThanOrEqualTo(4.5), reason: 'delete on a button');
      expect(contrast(palette.onSelected, palette.selected), greaterThanOrEqualTo(4.5), reason: 'selected tab');
    }
  });

  group('focus and selection (c2, c3)', () {
    testWidgets('a focused button gets the near-white ring and grows 1.05; no glow; a row does not grow', (
      tester,
    ) async {
      await _pump(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvButton(key: const ValueKey('a'), label: '确定', autofocus: true, onTap: () {}),
            const SizedBox(height: 20),
            TvSwitchRow(id: 'row', title: '导航栏始终展开', value: false, onChanged: (_) {}),
          ],
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      final button = _look(tester, find.byKey(const ValueKey('a')));
      expect(button.ring, isTrue);
      expect(button.scale, tvFocusZoom);
      // No blurred shadow anywhere (UI_PLAN §9.3, P6).
      for (final box in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
        final decoration = box.decoration;
        if (decoration is BoxDecoration) expect(decoration.boxShadow, isNull);
      }

      await _press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(seconds: 1));
      final row = _look(tester, find.byKey(const ValueKey('tv-setting-row')));
      expect(row.ring, isTrue);
      expect(row.scale, 1, reason: 'whole rows are ringed, never grown');
      expect(_look(tester, find.byKey(const ValueKey('a'))).ring, isFalse);
    });

    testWidgets('the focus-zoom setting off keeps only the ring', (tester) async {
      await _pump(tester, TvButton(key: const ValueKey('a'), label: '确定', autofocus: true, onTap: () {}), zoom: false);
      await tester.pump(const Duration(seconds: 1));
      final look = _look(tester, find.byKey(const ValueKey('a')));
      expect((look.ring, look.scale), (true, 1.0));
    });

    testWidgets('tabs: selected is the primary container, focus is the ring; both on one tab', (tester) async {
      var selected = 0;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => TvTabBar(
            tabs: const [
              TvTab(id: 'all', label: '全部', icon: TvIcons.allPlatforms, badge: 36),
              TvTab(id: 'bilibili', label: '哔哩哔哩', logo: SiteIds.bilibili, badge: 20),
              TvTab(id: 'douyu', label: '斗鱼', logo: SiteIds.douyu, badge: 8),
            ],
            selected: selected,
            onSelect: (index) => setState(() => selected = index),
          ),
        ),
      );
      Color fill(String id) {
        final container = tester.widget<Container>(
          find.descendant(of: find.byKey(ValueKey('tv-tab-$id')), matching: find.byType(Container)).first,
        );
        return (container.decoration! as ShapeDecoration).color!;
      }

      final palette = TvPalette.of(_scheme);
      expect(fill('all'), palette.selected);
      expect(fill('bilibili'), palette.card);
      expect(find.text('36'), findsOneWidget, reason: 'the count after the label');
      // Order: all, bilibili, douyu from the left.
      final xs = [
        for (final id in ['all', 'bilibili', 'douyu']) tester.getTopLeft(find.byKey(ValueKey('tv-tab-$id'))).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()));

      FocusManager.instance.rootScope.requestFocus();
      tester.state<TvTabBarState>(find.byType(TvTabBar)).focusSelected();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(seconds: 1));
      // Focus moved, selection did not (OK switches, P3).
      expect(_look(tester, find.byKey(const ValueKey('tv-tab-bilibili'))).ring, isTrue);
      expect(fill('bilibili'), palette.card);
      expect(fill('all'), palette.selected);
      await _press(tester, LogicalKeyboardKey.select);
      expect(fill('bilibili'), palette.selected);
      expect(_look(tester, find.byKey(const ValueKey('tv-tab-bilibili'))).ring, isTrue, reason: 'selected and focused');
    });

    testWidgets('buttons: the main action in the primary colour, deleting in the error colour; disabled is skipped', (
      tester,
    ) async {
      await _pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TvButton(key: const ValueKey('a'), label: '确定', autofocus: true, onTap: () {}),
            const TvButton(key: ValueKey('off'), label: '不可用'),
            TvButton(key: const ValueKey('pri'), label: '下载并安装', kind: TvButtonKind.primary, onTap: () {}),
            TvButton(key: const ValueKey('err'), label: '取消关注', kind: TvButtonKind.danger, onTap: () {}),
          ],
        ),
      );
      Color ink(String label) => tester.widget<Text>(find.text(label)).style!.color!;
      expect(ink('确定'), _scheme.onSurface);
      expect(ink('下载并安装'), _scheme.primary);
      expect(ink('取消关注'), _scheme.error);
      expect(
        tester.widget<Opacity>(find.ancestor(of: find.text('不可用'), matching: find.byType(Opacity)).first).opacity,
        0.38,
      );
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_focusedKey, const ValueKey('pri'), reason: 'the disabled button is skipped');
    });

    testWidgets('text is at least 14 on a 1080p television (c5)', (tester) async {
      await _pump(
        tester,
        SizedBox(
          width: 720,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 184,
                height: 160,
                child: TvRoomCard(data: _live, showPlatform: true, followed: true),
              ),
              TvSettingsGroup(
                title: '导航栏显示方式',
                children: [
                  TvSwitchRow(
                    id: 'nav',
                    title: '导航栏始终展开',
                    subtitle: '关闭时导航栏只显示图标，焦点移过去时展开',
                    value: true,
                    onChanged: (_) {},
                  ),
                ],
              ),
              TvButton(label: '确定', onTap: () {}),
            ],
          ),
        ),
      );
      expect(_smallestText(tester, find.byType(Scaffold)), greaterThanOrEqualTo(14));
    });
  });

  group('room card (c7, c8, U.4a)', () {
    Future<void> card(WidgetTester tester, RoomCardData data, {bool platform = false, bool followed = false}) => _pump(
      tester,
      SizedBox(
        width: 184,
        height: TvRoomCard.heightFor(184, const TvScale(unit: 0.5, textScale: 1)),
        child: TvRoomCard(key: const ValueKey('card'), data: data, showPlatform: platform, followed: followed),
      ),
    );

    testWidgets('live: the audience bottom right in equal-width figures; no platform in a one-platform list', (
      tester,
    ) async {
      await card(tester, _live);
      expect(find.byKey(const ValueKey('tv-card-platform')), findsNothing);
      expect(find.text('84.7万'), findsOneWidget);
      final rect = tester.getRect(find.byKey(const ValueKey('card')));
      final chip = tester.getRect(find.byKey(const ValueKey('tv-card-audience')));
      expect(chip.right, greaterThan(rect.center.dx));
      expect(chip.bottom, lessThan(rect.center.dy + rect.height / 4));
      final style = tester.widget<Text>(find.text('84.7万')).style!;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(find.text('晚风'), findsOneWidget);
      expect(find.byType(CommonAvatar), findsOneWidget);
    });

    testWidgets('a mixed list shows "logo + 中文名" top left and the followed heart after it', (tester) async {
      await card(tester, _live, platform: true, followed: true);
      expect(
        find.descendant(of: find.byKey(const ValueKey('tv-card-platform')), matching: find.text('哔哩哔哩')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const ValueKey('tv-card-platform')), matching: find.byType(PlatformLogo)),
        findsOneWidget,
      );
      final platform = tester.getRect(find.byKey(const ValueKey('tv-card-platform')));
      final heart = tester.getRect(find.byKey(const ValueKey('tv-card-followed')));
      final rect = tester.getRect(find.byKey(const ValueKey('card')));
      expect(platform.left, lessThan(rect.center.dx));
      expect(heart.left, greaterThan(platform.right));
    });

    testWidgets('replay is "录播" top right; off air is dimmed with "未开播"; a restriction shows its reason', (
      tester,
    ) async {
      await card(
        tester,
        const RoomCardData(platformId: SiteIds.douyu, title: '周末露营', anchorName: '山野', isReplay: true),
      );
      expect(
        find.descendant(of: find.byKey(const ValueKey('tv-card-replay')), matching: find.text('录播')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('tv-card-audience')), findsNothing);
      expect(find.byKey(const ValueKey('tv-card-off-air')), findsNothing);

      await card(tester, const RoomCardData(platformId: SiteIds.douyu, title: '英语口语陪练', anchorName: 'Aki老师'));
      expect(find.byKey(const ValueKey('tv-card-off-air')), findsOneWidget);
      expect(find.text('未开播'), findsOneWidget);

      await card(
        tester,
        const RoomCardData(
          platformId: SiteIds.douyu,
          title: '主机游戏',
          anchorName: '不吃香菜',
          isLive: true,
          restrictionLabel: '需登录',
        ),
      );
      expect(
        find.descendant(of: find.byKey(const ValueKey('tv-card-mark')), matching: find.text('需登录')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(const ValueKey('tv-card-mark')), matching: find.byIcon(AppIcons.restricted)),
        findsOneWidget,
      );
    });

    testWidgets('no cover shows the one placeholder (never the offline glyph); IPTV shows the channel number', (
      tester,
    ) async {
      await card(tester, const RoomCardData(platformId: 'iptv', title: 'CCTV-13 新闻', anchorName: '央视', isLive: true));
      expect(find.byKey(const ValueKey('tv-cover-placeholder')), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_rounded), findsNothing);
      await _pump(
        tester,
        const SizedBox(
          width: 184,
          height: 160,
          child: TvRoomCard(
            data: RoomCardData(platformId: 'iptv', title: 'CCTV-13 新闻', anchorName: '央视', isLive: true),
            channelNumber: 12,
          ),
        ),
      );
      expect(find.text('12'), findsOneWidget);
      expect(find.byType(CommonAvatar), findsNothing);
    });

    testWidgets('the focused card scrolls a long title; it stops when the focus leaves', (tester) async {
      await _pump(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 184,
              height: 160,
              child: TvRoomCard(key: const ValueKey('card'), data: _live, onTap: () {}),
            ),
            const SizedBox(width: 20),
            TvButton(key: const ValueKey('next'), label: '确定', onTap: () {}),
          ],
        ),
      );
      Finder moving() => find.descendant(of: find.byType(TvMarquee), matching: find.byType(Transform));
      expect(moving(), findsNothing, reason: 'unfocused: one line with an ellipsis');
      FocusManager.instance.rootScope.requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(_focusedKey, const ValueKey('card'));
      await tester.pump(const Duration(seconds: 2));
      expect(moving(), findsOneWidget);
      final offset = tester.widget<Transform>(moving()).transform.getTranslation().x;
      expect(offset, lessThan(0), reason: 'the title moves left after the pause');
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(seconds: 1));
      expect(moving(), findsNothing);
    });

    testWidgets('a held OK, the menu key and a right click are the long press (Appendix A 14)', (tester) async {
      var taps = 0;
      var holds = 0;
      await _pump(
        tester,
        SizedBox(
          width: 184,
          height: 160,
          child: TvRoomCard(data: _live, onTap: () => taps++, onLongPress: () => holds++),
        ),
      );
      await tester.tap(find.byType(TvRoomCard), buttons: kSecondaryButton);
      await tester.pump();
      expect((taps, holds), (0, 1));
      await _press(tester, LogicalKeyboardKey.contextMenu);
      expect((taps, holds), (0, 2));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      expect((taps, holds), (0, 3));
      await _press(tester, LogicalKeyboardKey.select);
      expect((taps, holds), (1, 3));
    });
  });

  testWidgets('area card: its own colour, the followed heart top right, the platform line (c6)', (tester) async {
    await _pump(
      tester,
      const SizedBox(
        width: 117,
        height: 170,
        child: TvAreaCard(key: ValueKey('area'), name: '王者荣耀', subtitle: '哔哩哔哩', followed: true),
      ),
    );
    final container = tester.widget<Container>(
      find.descendant(of: find.byKey(const ValueKey('area')), matching: find.byType(Container)).first,
    );
    expect((container.decoration! as BoxDecoration).color, TvPalette.of(_scheme).card);
    final rect = tester.getRect(find.byKey(const ValueKey('area')));
    final heart = tester.getRect(find.byKey(const ValueKey('tv-area-followed')));
    expect((heart.right > rect.center.dx, heart.top < rect.center.dy), (true, true));
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.byKey(const ValueKey('tv-cover-placeholder')), findsOneWidget);
  });

  group('settings rows (11–14)', () {
    testWidgets('switch: OK flips, ← off and → on; otherwise the arrow moves on', (tester) async {
      var value = false;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 600,
            child: TvSwitchRow(
              id: 's',
              title: '开关',
              value: value,
              autofocus: true,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      await _press(tester, LogicalKeyboardKey.select);
      expect(value, isTrue);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(value, isTrue, reason: 'already on: → is let through');
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(value, isFalse);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(value, isTrue);
      expect(find.byType(TvSwitchIndicator), findsOneWidget);
    });

    testWidgets('slider: ←→ step; at the end the focus may leave the row', (tester) async {
      var value = 0.9;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvSliderRow(
                  id: 'scale',
                  title: '全局文字缩放',
                  value: value,
                  min: 0.8,
                  max: 1,
                  step: 0.1,
                  label: '${(value * 100).round()}%',
                  onChanged: (v) => setState(() => value = v),
                ),
                TvButton(key: const ValueKey('below'), label: '确定', onTap: () {}),
              ],
            ),
          ),
        ),
      );
      FocusManager.instance.rootScope.requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusedKey, const ValueKey('tv-setting-scale'));
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(value, closeTo(1, 1e-9));
      expect(find.text('100%'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(value, closeTo(1, 1e-9));
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(value, closeTo(0.8, 1e-9));
    });

    testWidgets('choice: the value and ▾; OK opens the choices on the current value; link: ›', (tester) async {
      var value = 50;
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 600,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TvChoiceRow<int>(
                  id: 'limit',
                  title: '观看记录保留数量',
                  value: value,
                  autofocus: true,
                  options: const [
                    TvChoice(value: 20, label: '20'),
                    TvChoice(value: 50, label: '50'),
                    TvChoice(value: 100, label: '100'),
                  ],
                  onChanged: (v) => setState(() => value = v),
                ),
                TvLinkRow(id: 'link', title: '主题外观', onTap: () {}),
              ],
            ),
          ),
        ),
      );
      expect(find.byIcon(TvIcons.choice), findsOneWidget);
      expect(find.byIcon(TvIcons.chevron), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      expect(_focusedKey, const ValueKey('tv-choice-1'));
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      expect(value, 100);
      expect(_focusedKey, const ValueKey('tv-setting-limit'), reason: 'the focus is back on the row');
    });
  });

  group('dialogs (c12, c16)', () {
    Future<(Future<T?>,)> open<T>(WidgetTester tester, Future<T?> Function(BuildContext context) show) async {
      late BuildContext context;
      await _pump(
        tester,
        Builder(
          builder: (inner) {
            context = inner;
            return TvButton(key: const ValueKey('opener'), label: '打开', autofocus: true, onTap: () {});
          },
        ),
      );
      final result = show(context);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return (result,);
    }

    testWidgets('a dangerous question has the focus on 取消 and its action in the error colour; Back cancels', (
      tester,
    ) async {
      final (answer,) = await open(
        tester,
        (context) => showTvConfirm(context, title: '取消关注', message: '确定要取消关注晚风吗？', confirmLabel: '取消关注', danger: true),
      );
      await tester.pump();
      expect(_focusedKey, const ValueKey('tv-confirm-no'));
      final no = tester.getCenter(find.byKey(const ValueKey('tv-confirm-no')));
      final yes = tester.getCenter(find.byKey(const ValueKey('tv-confirm-yes')));
      expect(no.dx, lessThan(yes.dx), reason: 'cancel before the main button');
      expect(
        tester
            .widget<Text>(
              find.descendant(of: find.byKey(const ValueKey('tv-confirm-yes')), matching: find.text('取消关注')),
            )
            .style!
            .color,
        _scheme.error,
      );
      // The frame: no ring, no glow; a 60 % black scrim.
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect((dialog.shape! as RoundedRectangleBorder).side, BorderSide.none);
      expect(
        tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).map((barrier) => barrier.color),
        contains(TvColors.scrim),
      );
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(await answer, isFalse);
      expect(_focusedKey, const ValueKey('opener'), reason: 'the focus goes back where it was');
    });

    testWidgets('another question has the focus on its action, which ignores OK for half a second', (tester) async {
      late BuildContext context;
      await _pump(
        tester,
        Builder(
          builder: (inner) {
            context = inner;
            return const SizedBox();
          },
        ),
      );
      final answer = showTvConfirm(context, title: '关注', message: '确定要关注晚风吗？', confirmLabel: '关注');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_focusedKey, const ValueKey('tv-confirm-yes'));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget, reason: 'too soon after opening');
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      expect(await answer, isTrue);
    });

    testWidgets('choice: the current one in the primary colour with a tick, the focus on it; 关闭 keeps it', (
      tester,
    ) async {
      final (picked,) = await open(
        tester,
        (context) => showTvChoice<int>(
          context,
          title: '观看记录保留数量',
          subtitle: '现在 50 条',
          current: 50,
          options: const [
            TvChoice(value: 20, label: '20'),
            TvChoice(value: 50, label: '50'),
            TvChoice(value: 100, label: '100'),
          ],
        ),
      );
      await tester.pump();
      expect(_focusedKey, const ValueKey('tv-choice-1'));
      expect(find.text('现在 50 条'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tv-choice-1')),
          matching: find.byKey(const ValueKey('tv-option-current')),
        ),
        findsOneWidget,
      );
      expect(tester.widget<Text>(find.text('50')).style!.color, _scheme.primary);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      // Focus and current read apart (P3): the focused row is not primary.
      expect(tester.widget<Text>(find.text('100')).style!.color, _scheme.onSurface);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusedKey, const ValueKey('tv-choice-close'));
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      expect(await picked, isNull);
    });

    testWidgets('input: the field has the focus at once, a line says how to type, 取消 / 确定', (tester) async {
      final (typed,) = await open(
        tester,
        (context) => showTvInput(context, title: '自定义数量', subtitle: '观看记录保留数量', numeric: true, suffix: '条'),
      );
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv input field');
      expect(find.text('用屏幕键盘输入；遥控器有数字键也可以直接按'), findsOneWidget);
      final cancel = tester.getCenter(find.byKey(const ValueKey('tv-input-cancel')));
      final ok = tester.getCenter(find.byKey(const ValueKey('tv-input-confirm')));
      expect(cancel.dx, lessThan(ok.dx));
      await tester.enterText(find.byKey(const ValueKey('tv-text-input')), '8a0');
      await tester.tap(find.byKey(const ValueKey('tv-input-confirm')));
      await tester.pump(const Duration(seconds: 1));
      expect(await typed, '80');
    });
  });

  group('card dialog and tags (c9, c11)', () {
    late LiveStore store;

    Future<void> openDialog(
      WidgetTester tester, {
      List<TvRoomAction> actions = const [],
      String panel = '1080p@2x',
    }) async {
      store = (await tester.runAsync(() => LiveStore.memory(cipher: FakeCipher())))!;
      addTearDown(() => tester.runAsync(store.close));
      late BuildContext context;
      await _pump(
        tester,
        Builder(
          builder: (inner) {
            context = inner;
            return const SizedBox();
          },
        ),
        panel: panel,
      );
      unawaited(showTvRoomDialog(context, store: store, room: _room, actions: actions));
      await _settle(tester);
    }

    for (final panel in _panels.keys) {
      testWidgets('the dialog on $panel: header, title, buttons in order, the focus on 设置标签', (tester) async {
        await openDialog(
          tester,
          panel: panel,
          actions: [
            TvRoomAction(key: const ValueKey('delete'), icon: TvIcons.delete, label: '删除这条记录', onSelected: () {}),
          ],
        );
        expect(tester.takeException(), isNull);
        expect(find.text('晚风'), findsOneWidget);
        expect(find.text('哔哩哔哩 · 房间号 21452505'), findsOneWidget);
        expect(find.text('深夜电台 · 点歌接龙到天亮'), findsOneWidget);
        expect(_focusedKey, const ValueKey('tv-room-dialog-tags'));
        Offset at(String key) => tester.getCenter(find.byKey(ValueKey(key)));
        // 设置标签, 删除这条记录 in a row; 关闭 at the left under them, 关注 at the right.
        expect(at('tv-room-dialog-tags').dx, lessThan(at('delete').dx));
        expect(at('tv-room-dialog-close').dy, greaterThan(at('tv-room-dialog-tags').dy));
        expect(at('tv-room-dialog-close').dx, lessThan(at('tv-room-dialog-follow').dx));
        expect(
          find.descendant(of: find.byKey(const ValueKey('tv-room-dialog-follow')), matching: find.text('关注')),
          findsOneWidget,
        );
        final dialog = tester.getRect(find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first);
        final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
        expect(screen.contains(dialog.topLeft) && screen.contains(dialog.bottomRight), isTrue);
      });
    }

    testWidgets('关注 follows at once and flips; 已关注 asks first with the focus on 取消', (tester) async {
      await openDialog(tester);
      await tester.tap(find.byKey(const ValueKey('tv-room-dialog-follow')));
      await _settle(tester);
      expect(await tester.runAsync(() => store.follows.contains(_room)), isTrue);
      expect(toasts, ['已关注 晚风']);
      expect(
        find.descendant(of: find.byKey(const ValueKey('tv-room-dialog-follow')), matching: find.text('已关注')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('tv-room-dialog-follow')));
      await _settle(tester);
      expect(find.text('确定要取消关注晚风吗？'), findsOneWidget);
      expect(_focusedKey, const ValueKey('tv-confirm-no'));
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.select);
      await _settle(tester);
      expect(await tester.runAsync(() => store.follows.contains(_room)), isFalse);
      expect(find.byKey(const ValueKey('tv-room-dialog')), findsOneWidget, reason: 'the dialog stays');
    });

    testWidgets('a page action that asks first: 删除这条记录', (tester) async {
      var deleted = 0;
      await openDialog(
        tester,
        actions: [
          TvRoomAction(
            key: const ValueKey('delete'),
            icon: TvIcons.delete,
            label: '删除这条记录',
            confirmTitle: '删除这条记录',
            confirmMessage: '将从观看记录里删除“晚风”。',
            onSelected: () => deleted++,
          ),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('delete')));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('tv-room-dialog')), findsNothing);
      expect(_focusedKey, const ValueKey('tv-confirm-no'));
      await _press(tester, LogicalKeyboardKey.arrowRight);
      await _press(tester, LogicalKeyboardKey.select);
      await _settle(tester);
      expect(deleted, 1);
    });

    testWidgets('设置标签 follows first; no tags: 新建标签 has the focus, a new tag is ticked, 确认 saves', (tester) async {
      TvTextInput.prompt = (
        context, {
        required title,
        hint = '',
        text = '',
        subtitle,
        numeric = false,
        suffix,
        maxLength,
      }) async => '睡前听';
      addTearDown(() => TvTextInput.prompt = TvTextInput.defaultPrompt);
      await openDialog(tester);
      await _press(tester, LogicalKeyboardKey.select);
      await _settle(tester, rounds: 6);
      expect(await tester.runAsync(() => store.follows.contains(_room)), isTrue);
      expect(find.byKey(const ValueKey('tv-room-tags')), findsOneWidget);
      expect(find.text('晚风 · 哔哩哔哩'), findsOneWidget);
      expect(_focusedKey, const ValueKey('tv-tags-new'));

      await _press(tester, LogicalKeyboardKey.select);
      await _settle(tester, rounds: 6);
      final tags = (await tester.runAsync(store.tags.all))!;
      expect(tags.map((tag) => tag.name), ['睡前听']);
      final ticks = tester.widgetList<TvTick>(find.byType(TvTick));
      expect(ticks.single.ticked, isTrue, reason: 'a new tag is ticked at once');
      // 新建标签 stays at the end of the list.
      expect(
        tester.getCenter(find.byKey(const ValueKey('tv-tags-new'))).dy,
        greaterThan(tester.getCenter(find.byKey(ValueKey('tv-tag-${tags.single.id}'))).dy),
      );
      await tester.tap(find.byKey(const ValueKey('tv-room-tags-save')));
      await _settle(tester, rounds: 6);
      expect(await tester.runAsync(() => store.tags.tagsOf(_room)), [tags.single.id]);
      expect(find.byKey(const ValueKey('tv-room-tags')), findsNothing);
    });
  });

  group('status pages (c14)', () {
    testWidgets('a network failure in words with 重试; a login wall with 前往登录; the button takes the focus', (
      tester,
    ) async {
      var retries = 0;
      await _pump(
        tester,
        TvStatusView.failure(
          const NetworkFailure(SiteIds.bilibili, 'DioException [connection timeout]'),
          onRetry: () => retries++,
          autofocus: true,
        ),
      );
      expect(find.text('网络请求失败'), findsOneWidget);
      expect(find.text('网络连接失败，请检查网络或代理设置'), findsOneWidget);
      expect(find.textContaining('DioException'), findsNothing, reason: 'never the adapter text (P14)');
      expect(find.text('重试'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.select);
      expect(retries, 1);

      var logins = 0;
      await _pump(
        tester,
        TvStatusView.failure(const NeedsLogin(SiteIds.bilibili), onLogin: () => logins++, autofocus: true),
      );
      expect(find.text('需要登录账号'), findsOneWidget);
      expect(find.text('前往登录'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.select);
      expect(logins, 1);
    });

    testWidgets('the first load is a static skeleton without a focus target; empty says what to do', (tester) async {
      await _pump(tester, const SizedBox(width: 800, height: 500, child: TvSkeletonGrid()), center: false);
      expect(find.byKey(const ValueKey('tv-skeleton')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(TvFocusable), findsNothing);

      await _pump(
        tester,
        TvStatusView(
          icon: TvIcons.noRooms,
          title: '未发现直播',
          subtitle: '这个平台暂时没有直播。\n按上键回到平台标签换个平台，或者刷新',
          actions: [TvStatusAction(icon: AppIcons.refresh, label: '刷新', onTap: () {})],
        ),
      );
      expect(find.textContaining('按上键回到平台标签'), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-status-action-0')), findsOneWidget);
      // No bounce: nothing animates the icon (P15).
      var animated = false;
      tester.element(find.byIcon(TvIcons.noRooms)).visitAncestorElements((element) {
        if (element.widget is TvStatusView) return false;
        if (element.widget is ScaleTransition || element.widget is AnimatedScale) animated = true;
        return true;
      });
      expect(animated, isFalse);
    });
  });

  testWidgets('sub-page header: the title and its line, actions on the right, no 返回 button (c13)', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 800,
        child: TvPageHeader(
          title: '英雄联盟',
          subtitle: '哔哩哔哩',
          actions: [TvButton(key: const ValueKey('follow'), label: '关注分区', onTap: () {})],
        ),
      ),
    );
    expect(find.text('返回'), findsNothing);
    expect(find.byIcon(AppIcons.back), findsNothing);
    expect(
      tester.getCenter(find.byKey(const ValueKey('follow'))).dx,
      greaterThan(tester.getCenter(find.text('英雄联盟')).dx),
    );
  });

  group('phone push (c15)', () {
    Future<(Future<TvRoomPushChoice?>,)> push(WidgetTester tester, {LiveRoom? room}) async {
      late BuildContext context;
      await _pump(
        tester,
        Builder(
          builder: (inner) {
            context = inner;
            return const SizedBox();
          },
        ),
      );
      final choice = showTvRoomPush(context, text: 'https://live.bilibili.com/21452505?share=1', room: room);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return (choice,);
    }

    testWidgets('a recognised room: who, where and 进入房间 focused', (tester) async {
      final (choice,) = await push(tester, room: _room);
      expect(find.text('打开分享的直播间'), findsOneWidget);
      expect(find.text('从手机推送'), findsOneWidget);
      expect(find.text('深夜电台 · 点歌接龙到天亮'), findsOneWidget);
      expect(find.text('哔哩哔哩 · 房间号 21452505'), findsOneWidget);
      expect(find.byKey(const ValueKey('tv-room-push-text')), findsNothing);
      expect(_focusedKey, const ValueKey('tv-room-push-go'));
      expect(
        find.descendant(of: find.byKey(const ValueKey('tv-room-push-go')), matching: find.text('进入房间')),
        findsOneWidget,
      );
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      expect(await choice, TvRoomPushChoice.open);
    });

    testWidgets('nothing recognised: the pushed text and 搜索这段文字', (tester) async {
      final (choice,) = await push(tester);
      expect(find.byKey(const ValueKey('tv-room-push-text')), findsOneWidget);
      expect(_focusedKey, const ValueKey('tv-room-push-go'));
      expect(find.text('搜索这段文字'), findsOneWidget);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      expect(_focusedKey, const ValueKey('tv-room-push-cancel'));
      await _press(tester, LogicalKeyboardKey.select);
      await tester.pump(const Duration(seconds: 1));
      expect(await choice, isNull);
    });
  });
}
