// U.6c: the video page, the portrait and audience pages it opens, the
// player page and its mpv option pages, the floating-window danmaku page
// (docs/ui/compare/U.6c).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/settings/playback_tiles.dart';
import 'package:pure_live/features/settings/settings_dialogs.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';

import '../../support.dart';
import 'settings_harness.dart';

Finder _text(String text) => find.text(text);

Finder _inRow(String id, Finder matching) => find.descendant(of: settingsRow(id), matching: matching);

SettingsRow _rowWidget(WidgetTester tester, String id) =>
    tester.widget<SettingsRow>(find.descendant(of: settingsRow(id), matching: find.byType(SettingsRow)).first);

void main() {
  setUpAll(loadStrings);

  group('video page (c2–c7, c12)', () {
    testWidgets('six groups in order; rows, icons and the renamed mini-window rows (Android)', (tester) async {
      await pumpSettings(tester, height: 3200, arguments: 'video');
      expectInOrder(tester, [
        for (final title in ['音频设置', '画质设置', '播放行为设置', '后台与助眠', '小窗', '弹幕设置']) _text(title),
      ]);
      expectInOrder(tester, [
        for (final id in [
          'global_mute',
          'mobile_volume',
          'prefer_resolution',
          'prefer_resolution_cellular',
          'prefer_h264',
          'video_fit',
          'fullscreen_default',
          'screen_keep_on',
          'portrait',
          'audience',
          'background_play',
          'asmr_sleep',
          'asmr_minutes',
          'float_play',
          'auto_pip',
          'video_danmaku_show',
          'danmaku_style',
          'video_danmaku_font',
          'video_block_list',
        ])
          settingsRow(id),
      ]);
      for (final (id, icon) in [
        ('global_mute', AppIcons.settingsUnmuted),
        ('prefer_resolution', AppIcons.settingsQuality),
        ('prefer_resolution_cellular', AppIcons.settingsCellularQuality),
        ('portrait', AppIcons.settingsPortrait),
        ('audience', AppIcons.settingsAudience),
        ('background_play', AppIcons.settingsBackgroundPlay),
        ('asmr_sleep', AppIcons.settingsAutoSleep),
        ('float_play', AppIcons.settingsLeaveRoomMini),
        ('video_danmaku_font', AppIcons.settingsDanmakuFont),
        ('video_block_list', AppIcons.settingsDanmakuBlock),
      ]) {
        expect(_inRow(id, find.byIcon(icon)), findsOneWidget, reason: id);
      }
      // c3: the left-the-room switch says what it does; c4 is new.
      expect(_inRow('float_play', _text('离开直播间时小窗播放')), findsOneWidget);
      expect(_inRow('auto_pip', _text('离开应用时自动画中画')), findsOneWidget);
      // The floating-window danmaku keeps one entry, on the overview (U.6a c7).
      expect(settingsRow('pip_danmaku'), findsNothing);
      // U.12d: "弹幕关键词过滤" is "弹幕屏蔽".
      expect(_inRow('video_block_list', _text('弹幕屏蔽')), findsOneWidget);
      // Desktop rows are not on phones.
      expect(settingsRow('pip_on_top'), findsNothing);
      expect(settingsRow('desktop_volume'), findsNothing);
    });

    testWidgets('computers: the desktop mini-window rows without "Windows", no background group', (tester) async {
      await withPlatform(TargetPlatform.windows, () async {
        await pumpSettings(tester, height: 2600, arguments: 'video');
        expect(_text('后台与助眠'), findsNothing);
        expectInOrder(tester, [
          for (final id in [
            'desktop_volume',
            'float_play',
            'pip_on_top',
            'pip_remember_position',
            'pip_reset_position',
          ])
            settingsRow(id),
        ]);
        expect(_inRow('pip_on_top', _text('小窗始终置顶')), findsOneWidget);
        expect(find.textContaining('Windows 小窗'), findsNothing);
        expect(settingsRow('auto_pip'), findsNothing);
        expect(settingsRow('screen_keep_on'), findsNothing);
      });
    });

    testWidgets('landscape phone and wide windows: rows at most 720 wide (c13)', (tester) async {
      for (final (width, height) in [(852.0, 393.0), (1280.0, 800.0), (1920.0, 1080.0)]) {
        await pumpSettings(tester, width: width, height: height, arguments: 'video');
        expect(find.byKey(const ValueKey('settings-page-video')), findsOneWidget);
        expect(tester.getSize(settingsRow('global_mute')).width, lessThanOrEqualTo(720), reason: '$width');
      }
    });

    testWidgets('global mute: the icon follows the switch', (tester) async {
      final h = await pumpSettings(tester, arguments: 'video');
      await tapSettings(tester, settingsRow('global_mute'));
      expect(h.settings.get(Settings.globalVolumeMute), isTrue);
      expect(_inRow('global_mute', find.byIcon(AppIcons.settingsMuted)), findsOneWidget);
    });

    testWidgets('a row that depends on a switch is greyed out and says so (c5)', (tester) async {
      final h = await pumpSettings(tester, height: 3200, arguments: 'video');
      expect(_rowWidget(tester, 'asmr_minutes').enabled, isFalse);
      expect(_inRow('asmr_minutes', _text('打开“新直播间自动助眠”后生效')), findsOneWidget);
      await tapSettings(tester, settingsRow('asmr_sleep'));
      expect(h.settings.get(Settings.enableAsmrSleepMode), isTrue);
      expect(_rowWidget(tester, 'asmr_minutes').enabled, isTrue);
      expect(_inRow('asmr_minutes', _text('1 小时')), findsOneWidget);
    });

    testWidgets('the duration dialog: a quick pick applies and closes; a typed value is checked (c7)', (tester) async {
      final h = await pumpSettings(
        tester,
        height: 3200,
        arguments: 'video',
        seed: (s) => s.set(Settings.enableAsmrSleepMode, true),
      );
      await tapSettings(tester, settingsRow('asmr_minutes'));
      expect(_text('自定义播放时长'), findsOneWidget);
      expect(_text('请输入 1 分钟至 365 天之间的分钟数'), findsOneWidget);
      expect(_text('1 天'), findsOneWidget);
      await tapSettings(tester, find.byKey(const ValueKey('settings-number-120')));
      expect(h.settings.get(Settings.asmrSleepMinutes), 120);
      expect(find.byKey(const ValueKey('settings-number-input')), findsNothing);

      await tapSettings(tester, settingsRow('asmr_minutes'));
      expect(tester.widget<TextField>(find.byKey(const ValueKey('settings-number-input'))).controller!.text, '120');
      await tester.enterText(find.byKey(const ValueKey('settings-number-input')), '0');
      await tapSettings(tester, find.byKey(const ValueKey('settings-number-save')));
      expect(find.byKey(const ValueKey('settings-number-input')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('settings-number-input')), '75');
      await tapSettings(tester, find.byKey(const ValueKey('settings-number-save')));
      expect(h.settings.get(Settings.asmrSleepMinutes), 75);
    });

    testWidgets('choice dialogs: the current option in the primary colour with a tick; a tap picks it', (tester) async {
      final h = await pumpSettings(tester, arguments: 'video');
      expect(_inRow('prefer_resolution', _text('原画')), findsOneWidget);
      await tapSettings(tester, settingsRow('prefer_resolution'));
      final current = find.byKey(const ValueKey('settings-choice-原画'));
      expect(find.descendant(of: current, matching: find.byIcon(AppIcons.selected)), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('settings-choice-超清')), matching: find.byIcon(AppIcons.selected)),
        findsNothing,
      );
      expect(_text('取消'), findsOneWidget);
      await tapSettings(tester, find.byKey(const ValueKey('settings-choice-超清')));
      expect(h.settings.get(Settings.preferResolution), '超清');
      expect(find.byType(SettingsChoiceRow), findsNothing);
    });

    testWidgets('"弹幕样式" opens the room\'s danmaku settings (c12)', (tester) async {
      await pumpSettings(tester, height: 3200, arguments: 'video');
      await tapSettings(tester, settingsRow('danmaku_style'));
      expect(find.byKey(const ValueKey('settings-danmaku-style')), findsOneWidget);
      expect(find.byType(DanmakuSettingsContent), findsOneWidget);
    });

    testWidgets('the block list opens its route', (tester) async {
      final h = await pumpSettings(tester, height: 3200, arguments: 'video');
      await tapSettings(tester, settingsRow('video_block_list'));
      expect(h.opened, [RoutePath.kSettingsDanmuShield]);
    });

    testWidgets('background play: a refused permission turns the explanation red and keeps it off', (tester) async {
      final h = await pumpSettings(
        tester,
        height: 3200,
        arguments: 'video',
        overrides: [switchGateProvider.overrideWithValue((_) async => SwitchGateResult.denied)],
      );
      await tapSettings(tester, settingsRow('background_play'));
      expect(h.settings.get(Settings.enableBackgroundPlay), isFalse);
      expect(_inRow('background_play', _text('通知权限已关闭：在系统设置里允许通知后再打开')), findsOneWidget);
    });

    testWidgets('background play: cancelling the explanation keeps it off without red words (3.x, F.0a)', (
      tester,
    ) async {
      final h = await pumpSettings(
        tester,
        height: 3200,
        arguments: 'video',
        overrides: [switchGateProvider.overrideWithValue((_) async => SwitchGateResult.cancelled)],
      );
      await tapSettings(tester, settingsRow('background_play'));
      expect(h.settings.get(Settings.enableBackgroundPlay), isFalse);
      expect(_inRow('background_play', _text('通知权限已关闭：在系统设置里允许通知后再打开')), findsNothing);
    });
  });

  group('portrait page', () {
    testWidgets('three groups; detection off greys height and layout; restore asks and clears rooms', (tester) async {
      final h = await pumpSettings(
        tester,
        height: 2400,
        arguments: 'video',
        seed: (s) => s.set(Settings.portraitRoomOverrides, {'bilibili:1': 'portrait'}),
      );
      await tapSettings(tester, settingsRow('portrait'));
      expectInOrder(tester, [
        for (final title in ['识别与普通页布局', '全屏、小窗与弹幕', '诊断与恢复']) _text(title),
      ]);
      expectInOrder(tester, [
        for (final id in [
          'portrait_detect',
          'portrait_height',
          'portrait_layout',
          'portrait_fullscreen',
          'portrait_display',
          'portrait_pip',
          'portrait_danmaku',
          'portrait_remember',
          'portrait_diagnostics',
          'portrait_reset',
        ])
          settingsRow(id),
      ]);
      // Long values sit under the explanation.
      expect(_inRow('portrait_layout', _text('均衡（推荐）')), findsOneWidget);
      await tapSettings(tester, settingsRow('portrait_detect'));
      expect(h.settings.get(Settings.enablePortraitStreamAdaptation), isFalse);
      expect(_rowWidget(tester, 'portrait_height').enabled, isFalse);
      expect(_rowWidget(tester, 'portrait_layout').enabled, isFalse);
      expect(_rowWidget(tester, 'portrait_fullscreen').enabled, isTrue);

      await tapSettings(tester, settingsRow('portrait_reset'));
      expect(_text('本页的设置恢复默认，同时清除已记住的直播间方向。'), findsOneWidget);
      await tapSettings(tester, find.byKey(const ValueKey('settings-confirm')));
      expect(h.settings.get(Settings.enablePortraitStreamAdaptation), isTrue);
      expect(h.settings.get(Settings.portraitRoomOverrides), isEmpty);
      expect(h.toasts, ['已恢复默认设置']);
    });
  });

  group('audience page (c15)', () {
    testWidgets('platform switches follow the mode; heat-only platforms in one row; the notes page', (tester) async {
      final h = await pumpSettings(tester, height: 3600, arguments: 'video');
      await tapSettings(tester, settingsRow('audience'));
      expectInOrder(tester, [
        settingsRow('audience_heat'),
        settingsRow('audience_online'),
        settingsRow('audience_platforms'),
        settingsRow('audience_heat_only'),
        settingsRow('audience_info'),
      ]);
      // Popularity first: the switches are greyed out.
      final douyin = find.byKey(const ValueKey('settings-audience-douyin'));
      expect(tester.widget<SettingsSwitchRow>(douyin).enabled, isFalse);
      // Platforms without a real count have no switch.
      expect(find.byKey(const ValueKey('settings-audience-bilibili')), findsNothing);
      expect(_inRow('audience_heat_only', find.textContaining('哔哩哔哩')), findsOneWidget);

      await tapSettings(tester, settingsRow('audience_online'));
      expect(h.settings.get(Settings.preferRealOnlineCounts), isTrue);
      expect(tester.widget<SettingsSwitchRow>(douyin).enabled, isTrue);
      await tapSettings(tester, douyin);
      expect(h.settings.get(Settings.realOnlinePlatforms), isNot(contains('douyin')));

      await tapSettings(tester, settingsRow('audience_info'));
      expect(find.byKey(const ValueKey('settings-audience-info')), findsOneWidget);
      // Bilibili's note in plain words (F.5a c2; 3.x named the WATCHED_CHANGE field).
      expect(find.textContaining('本场累计看过的人数'), findsOneWidget);
    });
  });

  group('player page (c8–c11)', () {
    testWidgets('four groups; the engine is fixed; takeovers grey rows with the reason', (tester) async {
      final h = await pumpSettings(tester, height: 2400, arguments: 'playerKernel');
      expectInOrder(tester, [
        for (final title in ['内核', '解码', '网络', 'MPV 高级设置']) _text(title),
      ]);
      expectInOrder(tester, [
        for (final id in [
          'kernel',
          'hard_stop',
          'hardware_decoding',
          'compat_mode',
          'player_proxy_link',
          'custom_output',
          'video_output',
          'audio_output',
          'hardware_decoder',
          'kernel_reset',
        ])
          settingsRow(id),
      ]);
      expect(_inRow('kernel', _text('Mpv播放器')), findsOneWidget);
      expect(_rowWidget(tester, 'kernel').onTap, isNull);
      expect(_inRow('player_proxy_link', _text('未开启')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-mpv-docs')), findsOneWidget);
      // The drivers wait for "custom drivers".
      expect(_rowWidget(tester, 'hardware_decoder').enabled, isFalse);
      expect(_inRow('hardware_decoder', _text('打开“自定义驱动与硬件加速”后生效')), findsOneWidget);
      await tapSettings(tester, settingsRow('custom_output'));
      expect(h.settings.get(Settings.customPlayerOutput), isTrue);
      expect(_rowWidget(tester, 'hardware_decoder').enabled, isTrue);
      expect(_rowWidget(tester, 'hardware_decoding').enabled, isFalse);
      expect(_inRow('hardware_decoding', _text('由“自定义驱动与硬件加速”接管')), findsOneWidget);
      // The compatibility mode takes over both.
      await tapSettings(tester, settingsRow('compat_mode'));
      expect(_inRow('custom_output', _text('由“兼容模式”接管')), findsOneWidget);
      expect(_rowWidget(tester, 'hardware_decoder').enabled, isFalse);
    });

    testWidgets("an option page lists this platform's decoders, marks the default, a tap picks it", (tester) async {
      final h = await pumpSettings(
        tester,
        height: 2400,
        arguments: 'playerKernel',
        seed: (s) => s.set(Settings.customPlayerOutput, true),
      );
      expect(_inRow('hardware_decoder', _text('启用任意可用解码器')), findsOneWidget);
      await tapSettings(tester, settingsRow('hardware_decoder'));
      expect(find.byKey(const ValueKey('settings-mpv-decoder')), findsOneWidget);
      final options = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('settings-mpv-option-'),
      );
      expect(options, findsNWidgets(9));
      expect(find.byKey(const ValueKey('settings-mpv-option-rkmpp')), findsNothing);
      expect(find.byKey(const ValueKey('settings-mpv-option-d3d11va')), findsNothing);
      expect(
        find.descendant(of: find.byKey(const ValueKey('settings-mpv-option-auto')), matching: find.text('默认')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('settings-mpv-option-auto')),
          matching: find.byIcon(AppIcons.selected),
        ),
        findsOneWidget,
      );
      await tapSettings(tester, find.byKey(const ValueKey('settings-mpv-option-mediacodec')));
      expect(h.settings.get(Settings.videoHardwareDecoder), 'mediacodec');
      expect(find.byKey(const ValueKey('settings-mpv-decoder')), findsNothing);
    });

    testWidgets('restore asks, says what goes back and leaves the preferred quality (c8)', (tester) async {
      final h = await pumpSettings(
        tester,
        height: 2400,
        arguments: 'playerKernel',
        seed: (s) async {
          await s.set(Settings.preferResolution, '超清');
          await s.set(Settings.useHardStopOnExit, true);
        },
      );
      await tapSettings(tester, settingsRow('kernel_reset'));
      expect(_text('恢复播放内核默认设置'), findsOneWidget);
      expect(find.textContaining('视频设置里的首选清晰度不变'), findsOneWidget);
      await tapSettings(tester, find.byKey(const ValueKey('settings-confirm')));
      expect(h.settings.get(Settings.useHardStopOnExit), isFalse);
      expect(h.settings.get(Settings.preferResolution), '超清');
      expect(h.toasts, ['已恢复默认设置']);
    });

    testWidgets('the proxy row opens the network page at the player proxy (c9)', (tester) async {
      await pumpSettings(tester, height: 2400, arguments: 'playerKernel');
      await tapSettings(tester, settingsRow('player_proxy_link'));
      expect(find.byKey(const ValueKey('settings-page-network')), findsOneWidget);
      expect(settingsRow('player_proxy'), findsOneWidget);
    });
  });

  group('floating-window danmaku page (c13, c14)', () {
    testWidgets('phone: the preview above the rows; groups in order; off greys every row', (tester) async {
      final h = await pumpSettings(tester, width: 393, height: 2600, arguments: 'pipDanmaku');
      expect(find.byKey(const ValueKey('settings-pip-one-column')), findsOneWidget);
      expect(_text('配置系统画中画、桌面小窗和应用内小窗的弹幕样式'), findsOneWidget);
      final preview = find.byKey(const ValueKey('settings-pip-preview'));
      expect(topOf(tester, preview), lessThan(topOf(tester, settingsRow('pip_danmaku'))));
      expectInOrder(tester, [
        for (final title in ['样式', '显示范围', '流畅度']) _text(title),
      ]);
      expectInOrder(tester, [
        for (final id in [
          'pip_danmaku',
          'pip_opacity',
          'pip_speed',
          'pip_size',
          'pip_weight',
          'pip_auto_scale',
          'pip_no_emoji',
          'pip_original_color',
          'pip_color',
          'pip_area',
          'pip_max_visible',
          'pip_interval',
          'pip_auto_fps',
          'pip_fps',
          'pip_reset',
        ])
          settingsRow(id),
      ]);
      // Values carry their units (c6).
      expect(_inRow('pip_speed', _text('90 px/s')), findsOneWidget);
      expect(_inRow('pip_size', _text('12.0 px')), findsOneWidget);
      expect(_inRow('pip_interval', _text('0.35 秒')), findsOneWidget);
      expect(_inRow('pip_auto_scale', _text('小窗越小字越小，最小 10 px')), findsOneWidget);
      // The colour waits for "keep the platform's colours" off; the frame
      // rate says which policy it follows.
      expect(_rowWidget(tester, 'pip_color').enabled, isFalse);
      expect(_rowWidget(tester, 'pip_fps').enabled, isFalse);
      expect(_inRow('pip_fps', _text('现在跟随“通用”里的“省电”档位')), findsOneWidget);
      expect(_inRow('pip_fps', _text('30 FPS')), findsOneWidget);
      // Off: everything below is greyed out, the preview says so.
      await tapSettings(tester, settingsRow('pip_danmaku'));
      expect(h.settings.get(Settings.enablePipDanmaku), isFalse);
      expect(_rowWidget(tester, 'pip_opacity').enabled, isFalse);
      expect(_text('小窗弹幕已关闭'), findsOneWidget);
    });

    testWidgets('wide and short screens: the preview on the left', (tester) async {
      await pumpSettings(tester, width: 740, height: 360, arguments: 'pipDanmaku');
      expect(find.byKey(const ValueKey('settings-pip-two-columns')), findsOneWidget);
      await pumpSettings(tester, width: 1280, height: 800, arguments: 'pipDanmaku');
      expect(find.byKey(const ValueKey('settings-pip-two-columns')), findsOneWidget);
      final preview = find.byKey(const ValueKey('settings-pip-preview'));
      expect(tester.getCenter(preview).dx, lessThan(tester.getCenter(settingsRow('pip_danmaku')).dx));
    });

    testWidgets('count: − and +; restore asks and brings everything back', (tester) async {
      final h = await pumpSettings(tester, width: 393, height: 2600, arguments: 'pipDanmaku');
      await tapSettings(tester, find.byKey(const ValueKey('settings-entry-pip_max_visible-increase')));
      expect(h.settings.get(Settings.pipDanmakuMaxVisibleCount), Settings.pipDanmakuMaxVisibleCount.defaultValue + 1);
      await tapSettings(tester, settingsRow('pip_original_color'));
      expect(_rowWidget(tester, 'pip_color').enabled, isTrue);
      await tapSettings(tester, settingsRow('pip_reset'));
      expect(find.textContaining('将全部恢复为默认值'), findsOneWidget);
      await tapSettings(tester, find.byKey(const ValueKey('settings-confirm')));
      expect(h.settings.get(Settings.pipDanmakuMaxVisibleCount), Settings.pipDanmakuMaxVisibleCount.defaultValue);
      expect(h.settings.get(Settings.pipDanmakuUseOriginalColor), isTrue);
      expect(h.toasts, ['已恢复默认设置']);
    });
  });
}
