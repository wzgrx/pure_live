import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/danmaku/pip_danmaku_settings.dart';
import 'package:pure_live/shared/danmaku/setting_rows.dart';

/// The look of the chat list (the `danmakuListStyle` setting, U.2a choice
/// A): compact lines by default, 3.x's cards on request.
enum ChatListStyle {
  /// One line per message: "用户名：" in the name role (A08.10: semibold, a
  /// secondary colour or the platform's), then the message.
  compact,

  /// 3.x `DanmakuItem`: a card per message with a coloured dot.
  card;

  /// The style stored as [name], compact for anything else.
  static ChatListStyle of(String name) => name == card.name ? card : compact;
}

/// How far apart the chat list's lines sit (the `danmakuListLineSpacing`
/// setting, "行间距", docs/A-界面设计/A08-弹幕界面/A08.15-聊天列表字号和行距 c1): every vertical gap of a
/// line (between lines, a card's padding) and the height of its wrapped
/// text.
enum ChatSpacing {
  /// Half the gaps; the text 1.4 high (the least UI.md §8.2 allows).
  compact,

  /// The gaps and text height as before A08.15.
  standard,

  /// One and a half times the gaps; the text 1.7 high.
  loose;

  /// The spacing stored as [name], standard for anything else.
  static ChatSpacing of(String name) => values.firstWhere((value) => value.name == name, orElse: () => standard);

  /// A gap that is [base] at the standard spacing.
  double gap(double base) => switch (this) {
    compact => base / 2,
    standard => base,
    loose => base * 1.5,
  };

  /// The height of the text's lines, or null for the theme's.
  double? get textHeight => switch (this) {
    compact => 1.4,
    standard => null,
    loose => 1.7,
  };
}

/// The stop at the left end of the "列表文字大小" slider: the theme's size
/// (the setting's 0), one step under the smallest size, 12 (A08.15).
const int chatListFontSizeDefaultStop = 11;

/// The "列表文字大小" value as shown: "默认" for the theme's size (0, or the
/// slider's [chatListFontSizeDefaultStop]), else "16 px".
String chatListFontSizeText(int size) =>
    size <= chatListFontSizeDefaultStop ? i18n('danmaku_list_font_size_default') : '$size px';

/// The setting's value for the slider's [value]: 0 at the left end.
int chatListFontSizeOf(double value) {
  final size = value.round();
  return size <= chatListFontSizeDefaultStop ? 0 : size;
}

/// The groups the danmaku settings end with wherever they show (U.2e c9,
/// E1; A08.6 c1, c2): "弹幕列表" ([ChatListSettings]) and "小窗弹幕"
/// ([PipDanmakuSettings]). The room's tab and panel and 设置 → 弹幕 put
/// them after the shared `DanmakuSettingsContent`.
List<Widget> danmakuListAndPipGroups() => [
  PanelGroupTitle(i18n('danmaku_list')),
  const ChatListSettings(),
  PanelGroupTitle(i18n('pip_danmaku')),
  const PipDanmakuSettings(),
];

/// "弹幕列表": the room's chat list look (U.2a, v4), its text size and line
/// spacing (A08.15), whether it names the senders (A08.10), whether gifts
/// show in it (B-21) and which ones and with what value (A08.12). All are settings of every room (A08.6 c3), so
/// a change here applies to the rooms already open.
class ChatListSettings extends ConsumerWidget {
  /// Creates the group.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(storeProvider).settings;
    void set<T extends Object>(Setting<T> setting, T value) => unawaited(settings.set(setting, value));
    final listStyle = ChatListStyle.of(watchSetting(ref, Settings.danmakuListStyle));
    final fontSize = watchSetting(ref, Settings.danmakuListFontSize);
    final spacing = ChatSpacing.of(watchSetting(ref, Settings.danmakuListLineSpacing));
    final gifts = watchSetting(ref, Settings.showChatGifts);
    return PanelCard(
      children: [
        SettingRow(
          settingKey: 'listStyle',
          title: i18n('danmaku_list_style'),
          subtitle: i18n('danmaku_list_style_desc'),
          trailing: const SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<ChatListStyle>(
            key: const ValueKey('danmaku-list-style'),
            segments: [
              ButtonSegment(value: ChatListStyle.compact, label: Text(i18n('danmaku_list_style_compact'))),
              ButtonSegment(value: ChatListStyle.card, label: Text(i18n('danmaku_list_style_card'))),
            ],
            selected: {listStyle},
            onSelectionChanged: (selection) => set(Settings.danmakuListStyle, selection.first.name),
          ),
        ),
        // A08.15: the text size and the spacing, under the look they change.
        SettingSliderRow(
          settingKey: 'listFontSize',
          title: i18n('danmaku_list_font_size'),
          value: (fontSize == 0 ? chatListFontSizeDefaultStop : fontSize).toDouble(),
          min: chatListFontSizeDefaultStop.toDouble(),
          max: Settings.danmakuListFontSize.max!.toDouble(),
          divisions: Settings.danmakuListFontSize.max! - chatListFontSizeDefaultStop,
          display: chatListFontSizeText(fontSize),
          onChanged: (value) {
            final next = chatListFontSizeOf(value);
            if (next != fontSize) set(Settings.danmakuListFontSize, next);
          },
        ),
        SettingRow(
          settingKey: 'listSpacing',
          title: i18n('danmaku_list_spacing'),
          subtitle: i18n('danmaku_list_spacing_desc'),
          trailing: const SizedBox.shrink(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SegmentedButton<ChatSpacing>(
            key: const ValueKey('danmaku-list-spacing'),
            segments: [
              for (final value in ChatSpacing.values)
                ButtonSegment(value: value, label: Text(i18n('danmaku_list_spacing_${value.name}'))),
            ],
            selected: {spacing},
            onSelectionChanged: (selection) => set(Settings.danmakuListLineSpacing, selection.first.name),
          ),
        ),
        // A08.10: names on or off, right under the look they change.
        SettingSwitchRow(
          settingKey: 'names',
          title: i18n('danmaku_list_show_names'),
          subtitle: i18n('danmaku_list_show_names_desc'),
          value: watchSetting(ref, Settings.showChatNames),
          onChanged: (value) => set(Settings.showChatNames, value),
        ),
        SettingSwitchRow(
          settingKey: 'gifts',
          title: i18n('live_play_show_gifts'),
          subtitle: i18n('live_play_show_gifts_desc'),
          value: gifts,
          onChanged: (value) => set(Settings.showChatGifts, value),
        ),
        // A08.12: what the gift lines show, right under the switch that
        // shows them; greyed out while it is off (D4).
        SettingSwitchRow(
          settingKey: 'valuableGifts',
          title: i18n('danmaku_list_valuable_gifts'),
          subtitle: i18n('danmaku_list_valuable_gifts_desc'),
          value: watchSetting(ref, Settings.chatGiftsAboveTier),
          onChanged: gifts ? (value) => set(Settings.chatGiftsAboveTier, value) : null,
        ),
        SettingSwitchRow(
          settingKey: 'giftYuan',
          title: i18n('danmaku_list_gift_yuan'),
          subtitle: i18n('danmaku_list_gift_yuan_desc'),
          value: watchSetting(ref, Settings.giftValueInYuan),
          onChanged: gifts ? (value) => set(Settings.giftValueInYuan, value) : null,
        ),
      ],
    );
  }
}
