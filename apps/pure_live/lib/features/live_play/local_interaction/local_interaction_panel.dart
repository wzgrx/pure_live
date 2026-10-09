import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/layout/room_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_composer.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/local_style_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_path.dart';

/// The local interaction panel (U.2k-d, 3.x `local_interaction_sheet.dart`):
/// a room panel like the record panel (c2: under the picture in portrait,
/// on the right otherwise), with what is used most first (c3): who you are,
/// the composer, the gifts and coins, then the profile, what shows on the
/// picture and the history. "设置 ›" opens the settings page; "本地弹幕样式 ›"
/// is the panel's second page (K3).
///
/// [startWithStyle] opens the style page by itself (a composer's star): it
/// has no back then.
class LocalInteractionPanel extends ConsumerStatefulWidget {
  /// Creates the panel.
  const new({required this.onClose, this.dragToClose = false, this.startWithStyle = false, super.key});

  /// Closes the panel.
  final VoidCallback onClose;

  /// A downward drag on the header closes it (portrait).
  final bool dragToClose;

  /// Opens on the style page.
  final bool startWithStyle;

  @override
  ConsumerState<LocalInteractionPanel> createState() => _LocalInteractionPanelState();
}

class _LocalInteractionPanelState extends ConsumerState<LocalInteractionPanel> {
  late bool _style = widget.startWithStyle;

  @override
  Widget build(BuildContext context) {
    if (_style) {
      return LocalDanmakuStylePanel(
        onClose: widget.onClose,
        dragToClose: widget.dragToClose,
        onBack: widget.startWithStyle ? null : () => setState(() => _style = false),
      );
    }
    final interaction = ref.watch(localInteractionProvider);
    final session = LocalRoomScope.maybeOf(context);
    return RoomSidePanel(
      key: const ValueKey('local-interaction-panel'),
      title: i18n('local_interaction_title'),
      onClose: widget.onClose,
      dragToClose: widget.dragToClose,
      actions: [
        PanelLink(
          key: const ValueKey('local-panel-settings'),
          text: i18n('settings_title'),
          onPressed: () => unawaited(AppNavigator.toNamed<void>(RoutePath.kLocalInteraction)),
        ),
      ],
      child: ListenableBuilder(
        listenable: interaction,
        builder: (context, _) => _content(context, interaction, session),
      ),
    );
  }

  Widget _content(BuildContext context, LocalInteraction local, LocalRoomSession? session) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final platform = session?.platform ?? '';
    final pack = LocalCatalog.packFor(platform);
    final gifts = LocalCatalog.giftsFor(platform);
    return ListView(
      key: const ValueKey('local-panel-list'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            i18n('local_interaction_desc'),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
          ),
        ),
        LocalIdentityCard(interaction: local, pack: pack, platform: platform),
        const Padding(
          key: ValueKey('local-panel-composer'),
          padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: LocalDanmakuComposer(place: LocalComposerPlace.panel),
        ),
        PanelGroupTitle(i18n('local_gift_center')),
        _GiftGrid(gifts: gifts, coins: local.coins, onSend: (gift) => session?.sendGift(gift)),
        LocalRechargeRow(interaction: local, label: i18n('local_experience_coins')),
        PanelGroupTitle(i18n('local_group_profile_mine')),
        LocalProfileEditor(interaction: local),
        PanelGroupTitle(i18n('local_group_on_video')),
        _SwitchRow(
          id: 'overlay',
          title: i18n('local_overlay_message'),
          subtitle: i18n('local_overlay_message_desc'),
          value: local.showAsDanmaku,
          onChanged: (value) => local.showAsDanmaku = value,
        ),
        _SwitchRow(
          id: 'giftEffects',
          title: i18n('local_gift_effects'),
          subtitle: i18n('local_gift_effects_desc'),
          value: local.enableGiftEffects,
          onChanged: (value) => local.enableGiftEffects = value,
        ),
        InkWell(
          key: const ValueKey('local-panel-style'),
          onTap: () => setState(() => _style = true),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      i18n('local_danmaku_style'),
                      style: theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 15),
                    ),
                  ),
                  Text(
                    local.presetLabel,
                    key: const ValueKey('local-panel-style-value'),
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  Icon(AppIcons.forward, size: 20, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
        LocalHistory(
          interaction: local,
          clearLabel: i18n('local_clear_history_short'),
          inPanel: true,
          session: session,
        ),
      ],
    );
  }
}

/// Who you are in this room (c3, c12): the badge, "听众 · Pure Live" and
/// "哔哩哔哩 · 用户等级 Lv.1 · 1000 电池" in the platform's colours.
class LocalIdentityCard extends StatelessWidget {
  /// Creates the card.
  const new({required this.interaction, required this.pack, required this.platform, super.key});

  /// The profile.
  final LocalInteraction interaction;

  /// The room's pack.
  final LocalPlatformPack pack;

  /// The room's platform.
  final String platform;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = Color(pack.accent);
    final ink = localAccentInk(pack.accent, theme.brightness);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        key: const ValueKey('local-identity-card'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.05)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scheme.surfaceContainerLowest, shape: BoxShape.circle),
              child: Text(
                localEmojiText(pack.badge),
                style: localEmojiStyle(theme.textTheme.titleLarge?.copyWith(fontSize: 22, color: ink)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${interaction.titleLabel} · ${interaction.userName}',
                    key: const ValueKey('local-identity-name'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.emphasis.copyWith(fontSize: 15, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (pack != LocalCatalog.genericPack) i18n(pack.nameKey),
                      interaction.statusLine(pack),
                    ].join(' · '),
                    key: const ValueKey('local-identity-status'),
                    style: theme.textTheme.bodySmall?.emphasis.tabular.copyWith(color: ink),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four gifts a row (3.x); a gift the coins do not cover is faded but still
/// says so when tapped (c11); the price has the coin icon.
class _GiftGrid extends StatelessWidget {
  const new({required this.gifts, required this.coins, required this.onSend});

  final List<LocalGift> gifts;
  final int coins;
  final ValueChanged<LocalGift> onSend;

  @override
  Widget build(BuildContext context) {
    final rows = <List<LocalGift?>>[];
    for (var i = 0; i < gifts.length; i += 4) {
      rows.add([for (var j = i; j < i + 4; j++) gifts.elementAtOrNull(j)]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (final (index, row) in rows.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (final (column, gift) in row.indexed) ...[
                  if (column > 0) const SizedBox(width: 8),
                  Expanded(
                    child: gift == null
                        ? const SizedBox.shrink()
                        : _GiftTile(gift: gift, affordable: coins >= gift.price, onTap: () => onSend(gift)),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _GiftTile extends StatelessWidget {
  const new({required this.gift, required this.affordable, required this.onTap});

  final LocalGift gift;
  final bool affordable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = i18n(gift.nameKey);
    return Opacity(
      key: ValueKey('local-gift-${gift.id}'),
      opacity: affordable ? 1 : 0.45,
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Semantics(
            button: true,
            label: '$name, ${gift.price}',
            excludeSemantics: true,
            child: SizedBox(
              height: 88,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(localEmojiText(gift.emoji), style: localEmojiStyle(const TextStyle(fontSize: 28, height: 1.2))),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.regular.copyWith(fontSize: 13, color: scheme.onSurface),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(AppIcons.localCoins, size: 13, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 2),
                      Text(
                        '${gift.price}',
                        style: theme.textTheme.bodySmall?.tabular.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "本地体验币" and +500, +2000, +10000 (#9).
class LocalRechargeRow extends StatelessWidget {
  /// Creates the row; [label] goes before the buttons when given.
  const new({required this.interaction, this.label, super.key});

  /// The coins.
  final LocalInteraction interaction;

  /// The words before the buttons.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final buttons = [
      for (final amount in LocalCatalog.rechargeAmounts)
        OutlinedButton(
          key: ValueKey('local-recharge-$amount'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: const StadiumBorder(),
            side: BorderSide(color: scheme.outlineVariant),
            textStyle: theme.textTheme.bodyMedium?.emphasis.tabular.copyWith(fontSize: 14),
          ),
          onPressed: () => interaction.recharge(amount),
          child: Text('+$amount'),
        ),
    ];
    final wrap = Wrap(key: const ValueKey('local-recharge'), spacing: 8, runSpacing: 8, children: buttons);
    final text = label;
    if (text == null) return wrap;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(child: Text(text, style: theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 14))),
          wrap,
        ],
      ),
    );
  }
}

/// The nickname (#10: saved as it is typed, at most 20, an empty one not
/// saved) and the four titles (#11).
class LocalProfileEditor extends StatefulWidget {
  /// Creates the editor.
  const new({required this.interaction, super.key});

  /// The profile.
  final LocalInteraction interaction;

  @override
  State<LocalProfileEditor> createState() => _LocalProfileEditorState();
}

class _LocalProfileEditorState extends State<LocalProfileEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.interaction.userName);

  @override
  void dispose() {
    widget.interaction.updateName(_name.text);
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: TextField(
            key: const ValueKey('local-name-input'),
            controller: _name,
            maxLength: LocalCatalog.nameLimit,
            textInputAction: TextInputAction.done,
            onChanged: widget.interaction.updateName,
            onSubmitted: widget.interaction.updateName,
            decoration: InputDecoration(
              labelText: i18n('local_user_name'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              counterText: '',
              suffix: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _name,
                builder: (context, value, _) => Text(
                  '${value.text.characters.length} / ${LocalCatalog.nameLimit}',
                  style: theme.textTheme.bodySmall?.tabular.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(i18n('local_title_select'), style: theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 14)),
        ),
        Padding(
          key: const ValueKey('local-titles'),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in LocalCatalog.titles)
                ChoiceChip(
                  key: ValueKey('local-title-$id'),
                  label: Text(i18n('local_title_$id')),
                  selected: widget.interaction.title == id,
                  onSelected: (_) => widget.interaction.title = id,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "本地互动记录" (c12: in the panel and on the settings page, one widget).
///
/// D08.1 c5: the entries (data, read in the language of now), newest first,
/// split "全部 / 弹幕 / 礼物 / 币"; each says when and in which room; in a
/// room a local danmaku or gift has "再发一次" (a gift costs its coins
/// again, "体验币余额不足" as usual) and "只看本直播间" narrows the list. The
/// settings page copies them to the clipboard ([exportable]). The newest
/// [pageSize] show first, "显示更多" adds as many.
///
/// A08.13: a clear is undone from its toast for 4 s (docs/specs/UI.md §7,
/// as removing a blocked word or unfollowing), no question first.
class LocalHistory extends StatefulWidget {
  /// Creates the history.
  const new({
    required this.interaction,
    required this.clearLabel,
    this.inPanel = false,
    this.session,
    this.exportable = false,
    super.key,
  });

  /// The history's owner.
  final LocalInteraction interaction;

  /// The clear button's words.
  final String clearLabel;

  /// In the room panel: the title is a group title.
  final bool inPanel;

  /// The room the panel is in: "再发一次" and "只看本直播间" (null on the
  /// settings page).
  final LocalRoomSession? session;

  /// "导出到剪贴板" (the settings page).
  final bool exportable;

  /// How many entries show at first, and how many more each "显示更多"
  /// adds.
  static const int pageSize = 50;

  @override
  State<LocalHistory> createState() => _LocalHistoryState();
}

class _LocalHistoryState extends State<LocalHistory> {
  LocalHistoryFilter _filter = LocalHistoryFilter.all;
  bool _thisRoom = false;
  int _shown = LocalHistory.pageSize;

  LocalInteraction get _local => widget.interaction;

  void _clear(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final interaction = _local;
    final cleared = interaction.clearHistory();
    final count = cleared.events.isNotEmpty ? cleared.events.length : cleared.lines.length;
    final toast = AppToast(
      i18n('local_history_cleared', args: {'count': '$count'}),
      key: const ValueKey('local-history-undo'),
      actionLabel: i18n('room_undo'),
      onAction: () => interaction.restoreHistory(cleared),
    );
    if (messenger == null) {
      AppNavigator.showToast(toast);
    } else {
      showAppToastOn(messenger, toast);
    }
  }

  /// "再发一次" of [event] in the panel's room.
  void _again(LocalRoomSession session, LocalEvent event) {
    switch (event.kind) {
      case LocalEventKind.chat:
        if (session.sendChat(event.text)) session.toast(i18n('local_history_sent_again'));
      case LocalEventKind.gift:
        if (LocalCatalog.giftById(event.giftId) case final gift?) session.sendGift(gift);
      case LocalEventKind.recharge || LocalEventKind.level || LocalEventKind.legacy:
        break;
    }
  }

  Future<void> _export(List<LocalEvent> events) async {
    final text = [for (final event in events) localHistoryLine(_local, event)].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    AppNavigator.toast(i18n('local_history_exported', args: {'count': '${events.length}'}));
  }

  bool _canAgain(LocalEvent event) => switch (event.kind) {
    LocalEventKind.chat => event.text.isNotEmpty,
    LocalEventKind.gift => LocalCatalog.giftById(event.giftId) != null,
    LocalEventKind.recharge || LocalEventKind.level || LocalEventKind.legacy => false,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inPanel = widget.inPanel;
    final session = widget.session;
    final place = session?.place;
    final all = _local.events;
    final events = [
      for (final event in all)
        if (_filter.accepts(event) &&
            (!_thisRoom || place == null || (event.platform == place.platform && event.roomId == place.roomId)))
          event,
    ];
    final shown = events.take(_shown).toList();
    final side = EdgeInsets.symmetric(horizontal: inPanel ? 16 : 0);
    final count = i18n('local_history_count', args: {'count': '${events.length}'});
    final again = session != null && _local.enabled;
    return Column(
      key: const ValueKey('local-history'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: inPanel ? const EdgeInsets.fromLTRB(16, 16, 16, 6) : const EdgeInsets.only(top: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  i18n('local_history'),
                  style: inPanel
                      ? theme.textTheme.labelLarge?.emphasis.copyWith(fontSize: 13, color: scheme.primary)
                      : theme.textTheme.bodyLarge?.emphasis.copyWith(fontSize: 14),
                ),
              ),
              Text(
                count,
                key: const ValueKey('local-history-count'),
                style: theme.textTheme.bodyMedium?.tabular.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Padding(
          padding: side.add(const EdgeInsets.only(top: 4, bottom: 4)),
          child: SegmentedButton<LocalHistoryFilter>(
            key: const ValueKey('local-history-filter'),
            showSelectedIcon: false,
            segments: [
              for (final filter in LocalHistoryFilter.values)
                ButtonSegment(
                  value: filter,
                  label: Text(i18n(filter.labelKey), key: ValueKey('local-history-filter-${filter.name}')),
                ),
            ],
            selected: {_filter},
            onSelectionChanged: (selection) => setState(() {
              _filter = selection.first;
              _shown = LocalHistory.pageSize;
            }),
          ),
        ),
        if (place != null)
          Padding(
            padding: side,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                key: const ValueKey('local-history-room'),
                label: Text(i18n('local_history_this_room')),
                selected: _thisRoom,
                onSelected: (value) => setState(() {
                  _thisRoom = value;
                  _shown = LocalHistory.pageSize;
                }),
              ),
            ),
          ),
        if (shown.isEmpty)
          Padding(
            padding: side.add(const EdgeInsets.symmetric(vertical: 8)),
            child: Text(
              i18n('local_history_empty'),
              key: const ValueKey('local-history-empty'),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (final (index, event) in shown.indexed)
            _HistoryRow(
              key: ValueKey('local-history-row-$index'),
              index: index,
              text: _local.describe(event),
              detail: localHistoryDetail(event, DateTime.now()),
              padding: side,
              onAgain: again && _canAgain(event) ? () => _again(session, event) : null,
            ),
        if (events.length > shown.length)
          Padding(
            padding: side,
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('local-history-more'),
                onPressed: () => setState(() => _shown += LocalHistory.pageSize),
                child: Text(i18n('local_history_more', args: {'count': '${events.length - shown.length}'})),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.fromLTRB(inPanel ? 8 : 0, 6, 0, 0),
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('local-history-clear'),
                onPressed: all.isEmpty && _local.history.isEmpty ? null : () => _clear(context),
                icon: const Icon(AppIcons.localClearHistory, size: 18),
                label: Text(widget.clearLabel),
              ),
              if (widget.exportable)
                TextButton.icon(
                  key: const ValueKey('local-history-export'),
                  onPressed: all.isEmpty ? null : () => unawaited(_export(all)),
                  icon: const Icon(AppIcons.copy, size: 18),
                  label: Text(i18n('local_history_export')),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One entry: what happened, then when and where; "再发一次" at the end
/// when [onAgain] is given.
class _HistoryRow extends StatelessWidget {
  const new({
    required this.index,
    required this.text,
    required this.detail,
    required this.padding,
    required this.onAgain,
    super.key,
  });

  final int index;
  final String text;
  final String detail;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final again = onAgain;
    return Container(
      padding: padding.add(const EdgeInsets.symmetric(vertical: 6)),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  localEmojiText(text),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: localEmojiStyle(theme.textTheme.bodyMedium),
                ),
                Text(
                  detail,
                  key: ValueKey('local-history-detail-$index'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.tabular.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (again != null) ...[
            const SizedBox(width: 8),
            TextButton(
              key: ValueKey('local-history-again-$index'),
              onPressed: again,
              child: Text(i18n('local_history_again')),
            ),
          ],
        ],
      ),
    );
  }
}

/// When and where [event] happened, for its row: "20:05 · 主播" today,
/// "10-08 20:05 · 主播" this year, the year too before; an old line says
/// "旧记录" instead of a time (it never had one).
String localHistoryDetail(LocalEvent event, DateTime now) {
  if (event.kind == LocalEventKind.legacy) return i18n('local_history_legacy');
  final at = event.at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  final clock = '${two(at.hour)}:${two(at.minute)}';
  final time = at.year == now.year && at.month == now.month && at.day == now.day
      ? clock
      : at.year == now.year
      ? '${two(at.month)}-${two(at.day)} $clock'
      : '${at.year}-${two(at.month)}-${two(at.day)} $clock';
  return [time, if (event.roomName.isNotEmpty) event.roomName].join(' · ');
}

/// [event] as one line of the export: "2026-10-09 20:05 · 主播 · 弹幕 · 晚上好".
String localHistoryLine(LocalInteraction interaction, LocalEvent event) {
  final kind = switch (event.kind) {
    LocalEventKind.chat => i18n(LocalHistoryFilter.chat.labelKey),
    LocalEventKind.gift => i18n(LocalHistoryFilter.gift.labelKey),
    LocalEventKind.recharge => i18n(LocalHistoryFilter.coins.labelKey),
    LocalEventKind.level || LocalEventKind.legacy => null,
  };
  final at = event.at.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return [
    if (event.kind == LocalEventKind.legacy)
      i18n('local_history_legacy')
    else
      '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}',
    if (event.roomName.isNotEmpty) event.roomName,
    ?kind,
    interaction.describe(event),
  ].join(' · ');
}

/// A switch row of the panel (the U.2f rows: the whole row switches).
class _SwitchRow extends StatelessWidget {
  const new({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return MergeSemantics(
      child: InkWell(
        key: ValueKey('local-panel-$id'),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 15)),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(key: ValueKey('local-switch-$id'), value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
