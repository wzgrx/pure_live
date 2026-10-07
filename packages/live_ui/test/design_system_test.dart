import 'dart:io';
import 'dart:math' as math;

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
    // docs/A-界面设计/A07-直播间界面/A07.1-竖屏普通布局/README.md and 3.x's live_play widgets.
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
      // U.2b-U.2d: 3.x's glyphs of the portrait room and the window
      // fullscreen; the chat column's own.
      (AppIcons.portraitFullscreenEnter, Icons.keyboard_arrow_down_rounded),
      (AppIcons.portraitFullscreenRestore, Icons.keyboard_arrow_up_rounded),
      (AppIcons.landscapeFullscreen, Icons.screen_rotation_rounded),
      (AppIcons.windowFullscreen, Icons.unfold_more_rounded),
      (AppIcons.windowFullscreenExit, Icons.unfold_less_rounded),
      (AppIcons.chatColumn, Icons.vertical_split_rounded),
      (AppIcons.chatColumnFold, Remix.arrow_right_s_line),
      (AppIcons.chatColumnUnfold, Remix.arrow_left_s_line),

      // U.2g and U.2e.
      (AppIcons.switchLine, Icons.alt_route_rounded),
      (AppIcons.banned, Icons.block_rounded),
      (AppIcons.statusUnknown, Icons.help_outline_rounded),
      (AppIcons.login, Icons.login_rounded),
      (AppIcons.guideTitle, Remix.calendar_todo_line),
      (AppIcons.catchup, Remix.history_line),
      (AppIcons.liveNow, Remix.live_line),
      (AppIcons.guideEmpty, Remix.inbox_line),
      (AppIcons.guideFailed, Remix.error_warning_line),
      (AppIcons.add, Remix.add_line),
      (AppIcons.unfoldLeft, Remix.arrow_left_s_line),
      (AppIcons.chatEmpty, Remix.chat_smile_3_line),
      (AppIcons.danmakuTimeout, Remix.wifi_off_line),
      (AppIcons.danmakuUnavailable, Remix.chat_off_line),
      (AppIcons.superChatPrice, Remix.money_cny_circle_fill),
      (AppIcons.superChatMark, Remix.vip_diamond_fill),
      (AppIcons.superChatTime, Remix.time_line),
      (AppIcons.chipRemove, Remix.close_line),
      // U.2k: the local interaction keeps 3.x's glyphs.
      (AppIcons.localStyle, Icons.auto_awesome_rounded),
      (AppIcons.localSend, Icons.send_rounded),
      (AppIcons.localCoins, Icons.toll_rounded),
      (AppIcons.localOverlay, Icons.subtitles_rounded),
      (AppIcons.localBadge, Icons.workspace_premium_rounded),
      (AppIcons.localLevel, Icons.military_tech_rounded),
      (AppIcons.localGiftEffects, Icons.celebration_rounded),
      (AppIcons.localClearHistory, Icons.delete_sweep_outlined),
      (AppIcons.localPreviewStage, Icons.live_tv_rounded),
      (AppIcons.localPreviewLive, Icons.play_circle_fill_rounded),
      (AppIcons.localStyleSync, Icons.sync_rounded),
      (AppIcons.localPlaceScroll, Icons.trending_flat_rounded),
      (AppIcons.localPlaceTop, Icons.vertical_align_top_rounded),
      (AppIcons.localPlaceBottom, Icons.vertical_align_bottom_rounded),
      (AppIcons.localBold, Icons.format_bold_rounded),
      (AppIcons.localItalic, Icons.format_italic_rounded),
      (AppIcons.localStroke, Icons.border_color_rounded),
      (AppIcons.localShadow, Icons.blur_on_rounded),
      // U.2j: the mini windows' buttons (3.x's play and pause; the new back
      // and pin).
      (AppIcons.backToRoom, Icons.open_in_full_rounded),
      (AppIcons.miniPlay, Icons.play_circle_filled),
      (AppIcons.miniPause, Icons.pause_circle_filled),
      (AppIcons.pinned, Remix.pushpin_fill),
      (AppIcons.unpinned, Remix.pushpin_line),
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
      // U.7a: the recording centre's bar keeps 3.x's glyphs.
      (AppIcons.recordFolder, Remix.folder_video_line),
      (AppIcons.recordSettings, Remix.settings_5_line),
      (AppIcons.recordEmpty, Icons.video_collection_outlined),
      (AppIcons.recordUnavailable, Icons.videocam_off_outlined),
      (AppIcons.enterRoom, Icons.open_in_new_rounded),
      (AppIcons.delete, Remix.delete_bin_line),
      // U.8: the multi-view keeps 3.x's glyphs of lib/modules/multiview.
      (AppIcons.immersive, Remix.expand_diagonal_line),
      (AppIcons.exitImmersive, Remix.collapse_diagonal_line),
      (AppIcons.gridFullscreen, Remix.fullscreen_line),
      (AppIcons.gridExitFullscreen, Remix.fullscreen_exit_line),
      (AppIcons.layoutSingle, Remix.aspect_ratio_line),
      (AppIcons.layoutDual, Remix.layout_column_line),
      (AppIcons.layoutQuad, Remix.layout_grid_line),
      (AppIcons.layoutFocus, Remix.focus_3_line),
      (AppIcons.muteAll, Remix.volume_up_line),
      (AppIcons.mutedAll, Remix.volume_mute_line),
      (AppIcons.smallCellSaver, Remix.speed_mini_line),
      (AppIcons.cellPlay, Remix.play_line),
      (AppIcons.cellPause, Remix.pause_line),
      (AppIcons.cellRefresh, Remix.refresh_line),
      (AppIcons.changeRoom, Remix.tv_2_line),
      (AppIcons.closeCell, Remix.close_circle_line),
      (AppIcons.cellVolume, Remix.volume_down_line),
      (AppIcons.audioFocus, Remix.volume_up_line),
      (AppIcons.addCell, Remix.add_circle_line),
      (AppIcons.roomOffline, Remix.live_line),
      (AppIcons.cellFailed, Remix.error_warning_line),
      (AppIcons.restoreLast, Remix.history_line),
      // U.9: 3.x iptv_page.dart and iptv_manage.dart.
      (AppIcons.syncAll, Remix.refresh_line),
      (AppIcons.importPlaylist, Remix.download_2_line),
      (AppIcons.importGuide, Remix.file_add_line),
      (AppIcons.playlist, Remix.play_list_2_line),
      (AppIcons.playlistAdd, Remix.play_list_add_line),
      (AppIcons.guide, Remix.tv_2_line),
      (AppIcons.networkSource, Remix.global_line),
      (AppIcons.localSource, Remix.folder_2_line),
      (AppIcons.localPlaylistFile, Remix.folder_open_line),
      (AppIcons.localGuideFile, Remix.draft_line),
      (AppIcons.networkGuide, Remix.cloud_windy_line),
      (AppIcons.syncOne, Remix.download_cloud_2_line),
      (AppIcons.autoSync, Remix.repeat_line),
      (AppIcons.syncInterval, Remix.time_line),
      (AppIcons.userAgent, Remix.tv_line),
      (AppIcons.choiceOn, Remix.checkbox_circle_fill),
      (AppIcons.choiceOff, Remix.checkbox_blank_circle_line),
      // U.10a-c: 3.x account_page.dart, account_cookie_editor.dart, qr_login_page.dart, the settings entries.
      (AppIcons.signOut, Remix.logout_box_r_line),
      (AppIcons.save, Icons.save_rounded),
      (AppIcons.qrCode, Remix.qr_code_line),
      (AppIcons.qrScanned, Remix.checkbox_circle_line),
      (AppIcons.failed, Remix.error_warning_line),
      (AppIcons.webDav, Remix.cloud_line),
      (AppIcons.deviceSync, Remix.qr_scan_2_line),
      (AppIcons.platformAccounts, Remix.account_box_line), // A01.4 c4
      // U.13: the title bar keeps 3.x's glyphs; a maximized window shows
      // "restore".
      (AppIcons.windowMinimize, Icons.remove),
      (AppIcons.windowMaximize, Icons.crop_square),
      (AppIcons.windowRestore, Icons.filter_none),
      (AppIcons.windowClose, Icons.close),
      // U.7b: 3.x record_settings_page.dart.
      (AppIcons.recordQuality, Remix.hd_line),
      (AppIcons.recordPinyin, Remix.input_method_line), // A01.4 c4
      (AppIcons.recordDanmaku, Remix.chat_3_line),
      (AppIcons.recordSizeLimit, Remix.exchange_box_line),
      (AppIcons.recordSizeCap, Remix.database_2_line),
      (AppIcons.recordUsedSpace, Remix.custom_size),
      (AppIcons.recordClear, Remix.delete_bin_4_line),
      (AppIcons.recordBestStream, Remix.video_download_line),
      (AppIcons.recordTimeout, Remix.timer_flash_line),
      (AppIcons.recordQueue, Remix.speed_mini_line),
      (AppIcons.recordSegment, Remix.scissors_cut_line), // A01.4 c4
      (AppIcons.recordMaxTasks, Remix.task_line),
      (AppIcons.recordReconnect, Remix.loop_right_line), // A01.4 c4
      (AppIcons.recordRetries, Remix.loop_left_line),
      (AppIcons.recordInterval, Remix.time_line),
      (AppIcons.recordPolling, Remix.radar_line),
      (AppIcons.recordBackoff, Remix.line_chart_line),
      (AppIcons.recordMaxInterval, Remix.hourglass_2_line),
      (AppIcons.recordResume, Remix.restart_line),
      // U.11a-c: 3.x backup_page.dart, web_dav_page.dart, remote_sync_page.dart.
      (AppIcons.syncTv, Remix.qr_code_line),
      (AppIcons.backupCreate, Remix.file_download_line),
      (AppIcons.backupRestore, Remix.file_upload_line),
      (AppIcons.backupFolder, Remix.folder_open_line),
      (AppIcons.webDavServers, Remix.server_line),
      (AppIcons.webDavBackupFile, Remix.file_shield_2_line),
      (AppIcons.help, Remix.question_line),
      (AppIcons.webDavName, Remix.bookmark_line),
      (AppIcons.webDavAddress, Remix.global_line),
      (AppIcons.userName, Remix.user_3_line),
      (AppIcons.password, Remix.lock_password_line),
      (AppIcons.syncStart, Remix.play_circle_line),
      (AppIcons.syncStop, Remix.stop_circle_line),
      // The pull-to-refresh header (3.x plugins/global.dart; U.1c c19).
      (AppIcons.refreshPull, Icons.arrow_downward_rounded),
      (AppIcons.refreshSucceeded, Icons.done_rounded),
      (AppIcons.refreshFailed, Icons.error_outline_rounded),
    ];
    for (final (actual, glyph) in expected) {
      expect(actual, glyph);
    }
    // 3.x's own font: the floating window is glyph 0xe806 of CustomIcons.
    expect(AppIcons.floatWindow.codePoint, 0xe806);
    expect(AppIcons.floatWindow.fontFamily, 'CustomIcons');
    expect(AppIcons.floatWindow.fontPackage, 'live_ui');
  });

  test('OnVideoColors.accent is the light tone of the primary colour in both themes (U.8)', () {
    final light = const LiveTheme().light.colorScheme;
    final dark = const LiveTheme().dark.colorScheme;
    expect(OnVideoColors.accent(light), light.inversePrimary);
    expect(OnVideoColors.accent(dark), dark.primary);
    expect(OnVideoColors.accent(light).computeLuminance(), greaterThan(0.3));
    expect(OnVideoColors.accent(dark).computeLuminance(), greaterThan(0.3));
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

  RecordGlyphPainter glyphPainter(WidgetTester tester, RecordGlyphState state) =>
      tester
              .widget<CustomPaint>(
                find.descendant(
                  of: find.byKey(ValueKey('record-glyph-${state.name}')),
                  matching: find.byType(CustomPaint),
                ),
              )
              .painter!
          as RecordGlyphPainter;

  // docs/A-界面设计/A10-录制界面/A10.3-录制按钮和状态图标 (problem 02: the idle glyph's red dot looked like
  // recording).
  testWidgets('U.2a2: RecordGlyph is red only while recording; the rest take the icon colour', (tester) async {
    const ink = Color(0xFF43474E);
    final scheme = const LiveTheme().light.colorScheme;
    for (final state in RecordGlyphState.values) {
      await tester.pumpWidget(
        _app(
          IconTheme(
            data: const IconThemeData(color: ink),
            child: RecordGlyph(state: state),
          ),
          reduceMotion: true,
        ),
      );
      final painter = glyphPainter(tester, state);
      expect(tester.getSize(find.byKey(ValueKey('record-glyph-${state.name}'))), const Size.square(24));
      final glyph = find.descendant(
        of: find.byKey(ValueKey('record-glyph-${state.name}')),
        matching: find.byType(CustomPaint),
      );
      switch (state) {
        case RecordGlyphState.recording:
          expect(painter.colors, [LiveSemanticColors.recording, LiveSemanticColors.onRecording]);
          // The halo, the red disc, the white square.
          expect(
            glyph,
            paints
              ..circle(radius: 11)
              ..circle(radius: 10, color: LiveSemanticColors.recording)
              ..rrect(color: LiveSemanticColors.onRecording),
          );
        case RecordGlyphState.reconnecting:
          expect(painter.colors, [LiveSemanticColors.warningLight], reason: 'amber');
        case RecordGlyphState.failed:
          expect(painter.colors, [ink, scheme.error, scheme.onError]);
        case RecordGlyphState.idle ||
            RecordGlyphState.waiting ||
            RecordGlyphState.preparing ||
            RecordGlyphState.processing:
          expect(painter.colors, [ink], reason: '$state takes the colour of the icons beside it');
      }
      if (state != RecordGlyphState.recording) {
        expect(painter.colors, isNot(contains(LiveSemanticColors.recording)), reason: '$state is not red');
      }
    }
    // The idle glyph: a ring and a dot in the same ink, nothing else.
    await tester.pumpWidget(
      _app(
        const IconTheme(
          data: IconThemeData(color: ink),
          child: RecordGlyph(state: RecordGlyphState.idle),
        ),
      ),
    );
    expect(
      find.descendant(of: find.byKey(const ValueKey('record-glyph-idle')), matching: find.byType(CustomPaint)),
      paints
        ..circle(radius: 9, color: ink, style: PaintingStyle.stroke, strokeWidth: 2)
        ..circle(radius: 3.5, color: ink, style: PaintingStyle.fill),
    );
  });

  testWidgets('U.2a2: on the picture the glyph takes the dark tones; an explicit colour wins', (tester) async {
    await tester.pumpWidget(
      _app(const RecordGlyph(state: RecordGlyphState.reconnecting, onVideo: true, color: OnVideoColors.foreground)),
    );
    expect(glyphPainter(tester, RecordGlyphState.reconnecting).colors, [LiveSemanticColors.warningDark]);
    await tester.pumpWidget(
      _app(const RecordGlyph(state: RecordGlyphState.failed, onVideo: true, color: OnVideoColors.foreground)),
    );
    expect(glyphPainter(tester, RecordGlyphState.failed).colors, [
      OnVideoColors.foreground,
      OnVideoColors.error,
      OnVideoColors.onError,
    ]);
  });

  testWidgets('U.2a2: the recording halo breathes, preparing spins; less motion holds both still', (tester) async {
    await tester.pumpWidget(_app(const RecordGlyph(state: RecordGlyphState.recording)));
    expect(tester.hasRunningAnimations, isTrue, reason: 'the halo breathes');
    final before = glyphPainter(tester, RecordGlyphState.recording).haloOpacity;
    await tester.pump(const Duration(milliseconds: 600));
    expect(glyphPainter(tester, RecordGlyphState.recording).haloOpacity, isNot(before));

    await tester.pumpWidget(_app(const RecordGlyph(state: RecordGlyphState.recording), reduceMotion: true));
    expect(tester.hasRunningAnimations, isFalse);
    expect(glyphPainter(tester, RecordGlyphState.recording).haloOpacity, RecordGlyphPainter.haloRest);

    await tester.pumpWidget(_app(const RecordGlyph(state: RecordGlyphState.preparing)));
    expect(tester.hasRunningAnimations, isTrue, reason: 'the arc turns');
    await tester.pumpWidget(_app(const RecordGlyph(state: RecordGlyphState.preparing), reduceMotion: true));
    expect(tester.hasRunningAnimations, isFalse);

    // A join with progress follows it; idle, waiting, reconnecting and failed
    // never move.
    for (final state in [
      RecordGlyphState.idle,
      RecordGlyphState.waiting,
      RecordGlyphState.reconnecting,
      RecordGlyphState.failed,
    ]) {
      await tester.pumpWidget(_app(RecordGlyph(state: state)));
      expect(tester.hasRunningAnimations, isFalse, reason: '$state');
    }
    await tester.pumpWidget(_app(const RecordGlyph(state: RecordGlyphState.processing, progress: 0.45)));
    expect(tester.hasRunningAnimations, isFalse);
    expect(glyphPainter(tester, RecordGlyphState.processing).progress, 0.45);
    await tester.pumpWidget(_app(const RecordGlyph(state: RecordGlyphState.processing)));
    expect(tester.hasRunningAnimations, isTrue, reason: 'no progress yet: it spins');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('U.2a2: RecordingBadge says recording on red, reconnecting and joining on a dark pill', (tester) async {
    expect(formatRecordingTime(const Duration(minutes: 12, seconds: 34)), '12:34');
    expect(formatRecordingTime(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(formatRecordingTime(const Duration(seconds: -5)), '00:00');
    Color fill(RecordGlyphState state) =>
        (tester.widget<DecoratedBox>(find.byKey(ValueKey('recording-badge-${state.name}'))).decoration as BoxDecoration)
            .color!;

    await tester.pumpWidget(_app(const RecordingBadge(elapsed: Duration(minutes: 12, seconds: 34), label: '录制中')));
    final text = tester.widget<Text>(find.text('录制中 12:34'));
    expect(text.style?.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(text.style?.fontWeight, FontWeight.w600);
    expect(fill(RecordGlyphState.recording), LiveSemanticColors.recording);
    expect(find.byType(RecordGlyph), findsNothing, reason: 'a white dot on the red pill');
    await tester.pumpWidget(
      _app(const RecordingBadge(elapsed: Duration(minutes: 12, seconds: 34), label: '录制中', compact: true)),
    );
    expect(find.text('12:34'), findsOneWidget);

    await tester.pumpWidget(
      _app(
        const RecordingBadge(
          state: RecordGlyphState.reconnecting,
          elapsed: Duration(minutes: 12, seconds: 34),
          label: '重连中',
        ),
      ),
    );
    expect(find.text('重连中 12:34'), findsOneWidget);
    expect(fill(RecordGlyphState.reconnecting), OnVideoColors.scrim, reason: 'not red');
    expect(find.byKey(const ValueKey('record-glyph-reconnecting')), findsOneWidget);

    await tester.pumpWidget(
      _app(const RecordingBadge(state: RecordGlyphState.processing, progress: 0.456, label: '合成中')),
    );
    expect(find.text('合成中 45%'), findsOneWidget);
    expect(fill(RecordGlyphState.processing), OnVideoColors.scrim);
    expect(glyphPainter(tester, RecordGlyphState.processing).progress, 0.456);
    await tester.pumpWidget(
      _app(const RecordingBadge(state: RecordGlyphState.processing, progress: 0.456, label: '合成中', compact: true)),
    );
    expect(find.text('45%'), findsOneWidget);
    // Before FFmpeg reports: the word alone; compact, the spinning glyph alone.
    await tester.pumpWidget(_app(const RecordingBadge(state: RecordGlyphState.processing, label: '合成中')));
    expect(find.text('合成中'), findsOneWidget);
    await tester.pumpWidget(
      _app(const RecordingBadge(state: RecordGlyphState.processing, label: '合成中', compact: true)),
    );
    expect(find.byType(Text), findsNothing);
    await tester.pumpWidget(const SizedBox());
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

  testWidgets("AmbientBackdrop: 3.x's gradient under a 15 % veil; a cover decoded tiny over it", (tester) async {
    await tester.pumpWidget(_app(const SizedBox(width: 200, height: 300, child: AmbientBackdrop(cover: ''))));
    final boxes = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).map((box) => box.decoration).toList();
    expect(boxes.whereType<BoxDecoration>().map((box) => box.gradient), contains(OnVideoColors.ambientFallback));
    expect(find.byKey(const ValueKey('ambient-backdrop-cover')), findsNothing);
    expect(tester.widget<ColoredBox>(find.byType(ColoredBox).last).color, OnVideoColors.ambientVeil);
    expect(ambientCoverDecodeWidth, lessThanOrEqualTo(32));
    expect(find.byType(ImageFiltered), findsNothing, reason: 'no blur per frame');
  });

  test("U.13: the close button's red and the recording note keep 4.5:1 with their text", () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    expect(WindowButtonColors.closeHover, const Color(0xFFE81123));
    expect(contrast(WindowButtonColors.closeHover, WindowButtonColors.onCloseHover), greaterThan(4.5));
    const theme = LiveTheme(primaryColor: Color(0xFF2196F3));
    final light = theme.light.colorScheme;
    final dark = theme.dark.colorScheme;
    expect(contrast(light.error, LiveSemanticColors.recordingNote(Brightness.light)), greaterThan(4.5));
    expect(contrast(dark.error, LiveSemanticColors.recordingNote(Brightness.dark)), greaterThan(4.5));
  });

  test('A01.4 c4: a settings icon means one thing', () {
    // The two that read wrong on the phone.
    expect(AppIcons.settingsPhoneVolume, Remix.volume_up_line);
    expect(AppIcons.settingsAppProxy, AppIcons.settingsNetwork);
    // Same meaning, same icon.
    expect(AppIcons.settingsDesktopVolume, AppIcons.settingsPhoneVolume);
    expect(AppIcons.settingsDanmakuFont, AppIcons.appFont);
    expect(AppIcons.recordReconnect, AppIcons.recordReconnecting);
    expect(AppIcons.settingsExitMinutes, AppIcons.settingsExitTimer);
    // Different meanings, different icons.
    final apart = <(IconData, IconData)>[
      (AppIcons.settingsAppProxy, AppIcons.settingsPlatformList),
      (AppIcons.settingsLanguage, AppIcons.settingsNetwork),
      (AppIcons.recordPinyin, AppIcons.settingsLanguage),
      (AppIcons.roomCardSettings, AppIcons.multiview),
      (AppIcons.settingsAutoSleep, AppIcons.themeMode),
      (AppIcons.settingsDanmakuStyle, AppIcons.themeColor),
      (AppIcons.settingsDanmakuFont, AppIcons.fontSizes),
      (AppIcons.recordSegment, AppIcons.settingsVideo),
      (AppIcons.settingsAutoUpdate, AppIcons.settingsAutoRefresh),
      (AppIcons.settingsDouyuRenew, AppIcons.settingsAutoRefresh),
      (AppIcons.recordReconnect, AppIcons.settingsAutoRefresh),
      (AppIcons.settingsDownloadReset, AppIcons.settingsAutoRefresh),
      (AppIcons.resetLayout, AppIcons.settingsRefreshOnResume),
      (AppIcons.settingsRefreshRate, AppIcons.settingsHardwareDecoding),
      (AppIcons.settingsWindowSize, AppIcons.settingsVideoFit),
      (AppIcons.portraitHeight, AppIcons.cardLayout),
      (AppIcons.recordTimeout, AppIcons.settingsExitMinutes),
      (AppIcons.platformAccounts, Remix.accessibility_line),
    ];
    for (final (index, (a, b)) in apart.indexed) {
      expect(a, isNot(b), reason: 'pair $index');
    }
  });
}
