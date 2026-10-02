import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/fonts.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/settings/font_manager_page.dart';
import 'package:pure_live/features/settings/settings_model.dart';
import 'package:pure_live/features/settings/settings_tiles.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/danmaku/danmaku_settings_content.dart';
import 'package:pure_live/shared/danmaku/setting_rows.dart';

/// 设置 → 弹幕 (U.6a c6, F02 c1): the live room's danmaku settings, the same
/// component ([DanmakuSettingsContent], U.2f), with "改动立即生效" right of
/// the first group's title as in the room's tab (U.2e c8); then "更多": what
/// the room keeps elsewhere and only the settings hold for every room (the
/// global "显示弹幕", the player's "在画面上显示飞行弹幕", YouTube's chat, the
/// danmaku font and the block list). The room's own "弹幕列表" group (its
/// chat list) and "小窗弹幕" (its own row on the overview, U.6a c7) are not
/// repeated here.
///
/// The overview's "弹幕" row shows it (in the right pane from 840 wide);
/// `RoutePath.kDanmakuSettings` opens it on its own.
class DanmakuSettingsPage extends StatelessWidget {
  /// Creates the page; [route] when opened by its path.
  const new({this.route, this.onBack, super.key});

  /// The path and arguments the page was opened with (none are read).
  final RouteArgs? route;

  /// The back button of the settings' one-column layout (back to the
  /// overview); null uses the navigator's.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final start = SettingsPane.of(context);
    return Scaffold(
      key: const ValueKey('settings-page-danmaku'),
      appBar: settingsAppBar(
        context,
        title: i18n(SettingsSection.danmaku.titleKey),
        embedded: start,
        leading: onBack == null ? null : BackButton(onPressed: onBack),
      ),
      body: Align(
        alignment: start ? Alignment.topLeft : Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: start ? 12 : 4),
            child: DanmakuSettingsContent(
              hint: i18n('danmaku_settings_live_hint'),
              extra: [PanelGroupTitle(i18n('more')), const _More()],
            ),
          ),
        ),
      ),
    );
  }
}

/// "更多": the settings of every room the room's panel does not hold.
class _More extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    void set(BoolSetting setting, {required bool on}) => unawaited(settings.set(setting, on));
    return PanelCard(
      key: const ValueKey('danmaku-settings-more'),
      children: [
        SettingSwitchRow(
          settingKey: 'show',
          title: i18n('show_danmaku'),
          subtitle: i18n('settings_danmaku_show_desc'),
          value: watchSetting(ref, Settings.enableDanmakuDisplay),
          onChanged: (value) => set(Settings.enableDanmakuDisplay, on: value),
        ),
        // `hideDanmaku` is the room's danmaku button; shown the other way
        // round, as "on the video".
        SettingSwitchRow(
          settingKey: 'onVideo',
          title: i18n('live_play_danmaku_on_video'),
          subtitle: i18n('settings_danmaku_on_video_desc'),
          value: !watchSetting(ref, Settings.hideDanmaku),
          onChanged: (value) => set(Settings.hideDanmaku, on: !value),
        ),
        SettingSwitchRow(
          settingKey: 'youtubeAllChat',
          title: i18n('settings_youtube_all_chat'),
          subtitle: i18n('settings_youtube_all_chat_desc'),
          value: watchSetting(ref, Settings.youtubeShowAllChat),
          onChanged: (value) => set(Settings.youtubeShowAllChat, on: value),
        ),
        _LinkRow(
          settingKey: 'font',
          title: i18n('change_danmaku_font_family'),
          value: const _DanmakuFontName(),
          onTap: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FontManagerPage(danmaku: true))),
        ),
        _LinkRow(
          settingKey: 'block',
          title: i18n('settings_danmaku_block'),
          subtitle: i18n('settings_block_list_desc'),
          onTap: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kSettingsDanmuShield)),
        ),
      ],
    );
  }
}

/// A row of the panel that opens a page: the title, the current value and
/// a chevron.
class _LinkRow extends StatelessWidget {
  const new({required this.settingKey, required this.title, required this.onTap, this.subtitle, this.value});

  final String settingKey;
  final String title;
  final String? subtitle;
  final Widget? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: InkWell(
      key: ValueKey('danmaku-link-$settingKey'),
      onTap: onTap,
      child: SettingRow(
        settingKey: settingKey,
        title: title,
        subtitle: subtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?value,
            Icon(AppIcons.navigate, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    ),
  );
}

/// The danmaku font's name ("系统默认" for the system's), as on the video
/// page's font row (U.6c c6).
class _DanmakuFontName extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = watchSetting(ref, Settings.danmakuFontFamilyName);
    final library = ref.watch(fontLibraryProvider);
    final isDefault = id.isEmpty || id == Settings.danmakuFontFamilyName.defaultValue;
    final systemName = !kIsWeb && Platform.isWindows ? 'Microsoft YaHei' : i18n('font_system_default');
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) => FutureBuilder<FontFamily?>(
        future: isDefault ? null : library.family(id),
        builder: (context, snapshot) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            isDefault ? systemName : (snapshot.data?.name ?? id),
            key: const ValueKey('danmaku-value-font'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.regular.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
