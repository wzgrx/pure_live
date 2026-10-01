import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
        LocalHistory(interaction: local, clearLabel: i18n('local_clear_history_short'), inPanel: true),
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

/// "本地互动记录" with its count, the lines (newest first, up to 30) and
/// clearing them (c12: in the panel and on the settings page).
class LocalHistory extends StatelessWidget {
  /// Creates the history.
  const new({required this.interaction, required this.clearLabel, this.inPanel = false, super.key});

  /// The history's owner.
  final LocalInteraction interaction;

  /// The clear button's words.
  final String clearLabel;

  /// In the room panel: the title is a group title.
  final bool inPanel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final history = interaction.history;
    final count = i18n('local_history_count', args: {'count': '${history.length}'});
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
        if (history.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inPanel ? 16 : 0, vertical: 8),
            child: Text(
              i18n('local_history_empty'),
              key: const ValueKey('local-history-empty'),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          for (final line in history)
            Container(
              padding: EdgeInsets.symmetric(horizontal: inPanel ? 16 : 0, vertical: 7),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6))),
              ),
              child: Text(
                localEmojiText(line),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: localEmojiStyle(theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            ),
        Padding(
          padding: EdgeInsets.fromLTRB(inPanel ? 8 : 0, 6, 0, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('local-history-clear'),
              onPressed: history.isEmpty ? null : interaction.clearHistory,
              icon: const Icon(AppIcons.localClearHistory, size: 18),
              label: Text(clearLabel),
            ),
          ),
        ),
      ],
    );
  }
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
