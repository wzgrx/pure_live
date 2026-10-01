import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_ui/live_ui.dart';

Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: const LiveTheme().light,
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  test("AppIcons name each use and keep the icon 3.x's places showed", () {
    // docs/ui/compare/U.2a/README.md and 3.x's live_play widgets.
    final expected = <(IconData, IconData)>[
      (AppIcons.follow, Remix.add_line),
      (AppIcons.followed, Remix.check_line),
      (AppIcons.followHeart, Remix.heart_3_line),
      (AppIcons.followedHeart, Remix.heart_3_fill),
      (AppIcons.autoRecord, Remix.timer_line),
      (AppIcons.roomMenu, Remix.apps_2_line),
      (AppIcons.audioOnly, Remix.headphone_line),
      (AppIcons.audioOnlyActive, Remix.headphone_fill),
      (AppIcons.cast, Remix.tv_2_line),
      (AppIcons.floatWindow, CustomIcons.float_window),
      (AppIcons.play, Icons.play_arrow_rounded),
      (AppIcons.pause, Icons.pause_rounded),
      (AppIcons.refresh, Icons.refresh_rounded),
      (AppIcons.orientationAuto, Icons.screen_rotation_alt_rounded),
      (AppIcons.fullscreen, Icons.fullscreen_rounded),
      (AppIcons.exitFullscreen, Icons.fullscreen_exit_rounded),
      (AppIcons.aspectRatio, Remix.aspect_ratio_line),
      (AppIcons.dropDown, Remix.arrow_down_s_line),
      (AppIcons.share, Remix.share_forward_line),
      (AppIcons.openExternal, Icons.open_in_new_rounded),
      (AppIcons.audienceOnline, Icons.people_alt_rounded),
      (AppIcons.audienceHeat, Icons.whatshot_rounded),
      (AppIcons.audienceTotal, Icons.visibility_rounded),
      (AppIcons.iptvGuide, Icons.assignment_outlined),
      // U.2f: the room menu and the danmaku templates keep 3.x's glyphs.
      (AppIcons.switchRoom, Icons.swap_horiz_outlined),
      (AppIcons.sleepTimer, Remix.time_line),
      (AppIcons.roomVolume, Remix.volume_up_line),
      (AppIcons.streamLink, Remix.link_m),
      (AppIcons.newWindow, Icons.open_in_new_rounded),
      (AppIcons.localInteraction, Icons.auto_awesome_rounded),
      (AppIcons.templateSave, Icons.save_outlined),
      (AppIcons.templateRestore, Icons.restore_rounded),
      // U.3a, U.3b: the home shell keeps 3.x's glyphs, except the areas tab
      // (three shapes, c7) and "more" (U.3a c4).
      (AppIcons.homeFavorites, Remix.heart_3_line),
      (AppIcons.homeFavoritesSelected, Remix.heart_3_fill),
      (AppIcons.homePopular, Remix.fire_line),
      (AppIcons.homePopularSelected, Remix.fire_fill),
      (AppIcons.homeAreas, Remix.shapes_line),
      (AppIcons.homeAreasSelected, Remix.shapes_fill),
      (AppIcons.homeRecord, Remix.download_2_line),
      (AppIcons.homeRecordSelected, Remix.download_2_fill),
      (AppIcons.appMenu, Icons.menu_rounded),
      (AppIcons.search, CustomIcons.search),
      (AppIcons.more, Remix.more_2_fill),
      (AppIcons.watchHistory, Remix.history_line),
      (AppIcons.openLink, Remix.link),
      (AppIcons.multiview, Remix.layout_grid_line),
      (AppIcons.settings, Remix.settings_5_line),
      (AppIcons.about, Remix.information_line),
      (AppIcons.backup, Remix.cloud_line),
      (AppIcons.newPlayerWindow, Icons.add_to_photos_outlined),
      // U.3d: the download dialog keeps 3.x's glyphs.
      (AppIcons.downloadDone, Icons.check_circle_rounded),
      (AppIcons.downloadFailed, Icons.error_outline_rounded),
      (AppIcons.install, Icons.install_mobile_rounded),
      (AppIcons.retry, Icons.refresh_rounded),
    ];
    for (final (actual, glyph) in expected) {
      expect(actual, glyph);
    }
    // 3.x's own font: the floating window is glyph 0xe806 of CustomIcons.
    expect(AppIcons.floatWindow.codePoint, 0xe806);
    expect(AppIcons.floatWindow.fontFamily, 'CustomIcons');
    expect(AppIcons.floatWindow.fontPackage, 'live_ui');
  });

  testWidgets('DanmakuIcon draws 3.x on, off and settings pictures in the icon colour', (tester) async {
    for (final kind in DanmakuIconKind.values) {
      expect(File(kind.asset).existsSync(), isTrue, reason: kind.asset);
    }
    expect(DanmakuIconKind.on.asset, endsWith('danmu_open.svg'));
    expect(DanmakuIconKind.off.asset, endsWith('danmu_close.svg'));
    expect(DanmakuIconKind.settings.asset, endsWith('danmu_setting.svg'));

    await tester.pumpWidget(
      _app(
        const IconTheme(
          data: IconThemeData(color: OnVideoColors.foreground, size: 26, shadows: OnVideoColors.shadows),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DanmakuIcon(DanmakuIconKind.on),
              DanmakuIcon(DanmakuIconKind.off),
              DanmakuIcon(DanmakuIconKind.settings),
            ],
          ),
        ),
      ),
    );
    for (final kind in DanmakuIconKind.values) {
      final icon = find.byWidgetPredicate((widget) => widget is DanmakuIcon && widget.kind == kind);
      expect(tester.getSize(icon), const Size(26, 26));
      final pictures = tester.widgetList<SvgPicture>(find.descendant(of: icon, matching: find.byType(SvgPicture)));
      // The picture and its shadow copy.
      expect(pictures, hasLength(2));
      expect(pictures.last.colorFilter, const ColorFilter.mode(OnVideoColors.foreground, BlendMode.srcIn));
    }
  });

  testWidgets('RecordGlyph: a grey ring with a red dot, or a blinking white dot on red', (tester) async {
    await tester.pumpWidget(_app(const RecordGlyph(state: RecordGlyphState.idle)));
    expect(find.byKey(const ValueKey('record-glyph-idle')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('record-glyph-idle')), matching: find.byType(FadeTransition)),
      findsNothing,
    );

    await tester.pumpWidget(_app(const RecordGlyph(state: RecordGlyphState.recording)));
    expect(find.byKey(const ValueKey('record-glyph-recording')), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('record-glyph-recording')), matching: find.byType(FadeTransition)),
      findsOneWidget,
      reason: 'the dot blinks',
    );
    await tester.pump(const Duration(seconds: 1));

    // Less motion: the dot stays lit.
    await tester.pumpWidget(_app(const RecordGlyph(state: RecordGlyphState.recording), reduceMotion: true));
    expect(
      find.descendant(of: find.byKey(const ValueKey('record-glyph-recording')), matching: find.byType(FadeTransition)),
      findsNothing,
    );
  });

  testWidgets('RecordingBadge shows the word and a steady clock; compact keeps the time', (tester) async {
    expect(formatRecordingTime(const Duration(minutes: 12, seconds: 34)), '12:34');
    expect(formatRecordingTime(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(formatRecordingTime(const Duration(seconds: -5)), '00:00');

    await tester.pumpWidget(_app(const RecordingBadge(elapsed: Duration(minutes: 12, seconds: 34), label: '录制中')));
    final text = tester.widget<Text>(find.text('录制中 12:34'));
    expect(text.style?.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(text.style?.fontWeight, FontWeight.w600);

    await tester.pumpWidget(
      _app(const RecordingBadge(elapsed: Duration(minutes: 12, seconds: 34), label: '录制中', compact: true)),
    );
    expect(find.text('12:34'), findsOneWidget);
  });

  testWidgets('ListenableSelector rebuilds only when its part changes', (tester) async {
    final source = ValueNotifier<(int, String)>((1, 'a'));
    addTearDown(source.dispose);
    var builds = 0;
    await tester.pumpWidget(
      _app(
        ListenableSelector<String>(
          listenable: source,
          selector: () => source.value.$2,
          builder: (context, value, _) {
            builds++;
            return Text(value);
          },
        ),
      ),
    );
    expect(builds, 1);
    source.value = (2, 'a');
    await tester.pump();
    expect(builds, 1);
    source.value = (3, 'b');
    await tester.pump();
    expect(builds, 2);
    expect(find.text('b'), findsOneWidget);
  });

  test('roles: 60 % black under the bars, fixed red for live and recording', () {
    final shade = OnVideoColors.shade(edge: VerticalDirection.down);
    expect(shade.colors.first, const Color(0x99000000));
    expect(shade.colors.last.a, 0);
    expect(LiveSemanticColors.live, const Color(0xFFD92D20));
    expect(LiveSemanticColors.onLive, const Color(0xFFFFFFFF));
    expect(LiveSemanticColors.success(Brightness.light), isNot(LiveSemanticColors.success(Brightness.dark)));
    expect(InkOnColor.on(const Color(0xFFFFF3C4)), InkOnColor.dark);
    expect(InkOnColor.on(const Color(0xFF1B3A6B)), InkOnColor.light);
    expect(const TextStyle().tabular.fontFeatures, [const FontFeature.tabularFigures()]);
  });
}
