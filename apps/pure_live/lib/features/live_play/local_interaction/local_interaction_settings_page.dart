import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/local_interaction_scope.dart';
import 'package:pure_live/features/live_play/local_interaction/local_style_panel.dart';
import 'package:pure_live/features/live_play/local_interaction/logic/local_catalog.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// The widest the settings content grows (UI_PLAN §5.3).
const double _contentMaxWidth = 720;

/// 设置 → 本地用户与互动 (U.2k-g, 3.x `local_interaction_settings_page.dart`),
/// grouped by use (c15): the switch with where it shows in the room; the
/// profile with coins and level; what shows on the picture with the style
/// (#14: the same style panel as the room's); the phrases (D08.2 c4); the
/// platform packs; coins and the history (c12). With the switch off only
/// the first group stays.
///
/// Routes: `RoutePath.kLocalInteraction` (the settings overview links here,
/// U.6d; the room panel's "设置 ›" too).
class LocalInteractionSettingsPage extends ConsumerWidget {
  /// Creates the page.
  const new({this.route, super.key});

  /// How the page was opened.
  final RouteArgs? route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interaction = ref.watch(localInteractionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(i18n('local_interaction_settings'))),
      body: ListenableBuilder(
        listenable: interaction,
        builder: (context, _) => ListView(
          key: const ValueKey('local-settings-list'),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            for (final child in _groups(context, interaction))
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                  child: SizedBox(width: double.infinity, child: child),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _groups(BuildContext context, LocalInteraction local) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hint = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.45);
    if (!local.enabled) return [..._first(context, local, hint)];
    final previewPack = LocalCatalog.packFor(local.previewPlatform);
    return [
      ..._first(context, local, hint),
      _Title(i18n('local_user_profile')),
      _Card(
        children: [
          const SizedBox(height: 10),
          LocalProfileEditor(interaction: local),
          const SizedBox(height: 8),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _Tile(
            id: 'status',
            icon: AppIcons.localCoins,
            title: i18n('local_interaction_status'),
            subtitle: local.statusLine(LocalCatalog.genericPack),
          ),
          // D08.3: the level's progress, as on the identity card, and the
          // switch of what earns it.
          Padding(
            padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
            child: LocalLevelBar(interaction: local),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          _Tile(
            id: 'growth',
            icon: AppIcons.localGrowth,
            title: i18n('local_growth'),
            subtitle: i18n('local_growth_desc'),
            value: local.growthEnabled,
            onChanged: (value) => local.growthEnabled = value,
          ),
        ],
      ),
      _Title(i18n('local_group_on_video')),
      _Card(
        children: [
          _Tile(
            id: 'overlay',
            icon: AppIcons.localOverlay,
            title: i18n('local_overlay_message'),
            subtitle: i18n('local_overlay_message_desc'),
            value: local.showAsDanmaku,
            onChanged: (value) => local.showAsDanmaku = value,
          ),
          _Tile(
            id: 'badge',
            icon: AppIcons.localBadge,
            title: i18n('local_show_platform_badge'),
            subtitle: i18n('local_show_platform_badge_desc'),
            value: local.showPlatformBadge,
            onChanged: (value) => local.showPlatformBadge = value,
          ),
          _Tile(
            id: 'level',
            icon: AppIcons.localLevel,
            title: i18n('local_show_level_badge'),
            subtitle: i18n('local_show_level_badge_desc'),
            value: local.showLevelBadge,
            onChanged: (value) => local.showLevelBadge = value,
          ),
          // D08.1 c6: the chat list of a room entered again.
          _Tile(
            id: 'replay',
            icon: AppIcons.localReplay,
            title: i18n('local_replay_on_enter'),
            subtitle: i18n('local_replay_on_enter_desc'),
            value: local.replayOnEnter,
            onChanged: (value) => local.replayOnEnter = value,
          ),
          // D08.5 c2: the three choices, as in the room's panel.
          LocalGiftEffectsChoice(interaction: local, id: 'local-settings-giftEffects', icon: AppIcons.localGiftEffects),
          _Tile(
            id: 'style',
            icon: AppIcons.localStyle,
            title: i18n('local_danmaku_style'),
            subtitle: i18n('local_danmaku_style_desc'),
            trailing: local.presetLabel,
            onTap: () => unawaited(showLocalDanmakuStyleSheet(context)),
          ),
        ],
      ),
      // D08.2 c4: the composer's chips.
      _Title(i18n('local_phrases')),
      _Card(children: [LocalPhrasesEditor(interaction: local)]),
      _Title(i18n('local_platform_pack')),
      _Card(
        padding: const EdgeInsets.all(14),
        children: [
          Text(i18n('local_platform_pack_desc'), style: hint),
          const SizedBox(height: 10),
          Wrap(
            key: const ValueKey('local-settings-packs'),
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final pack in LocalCatalog.packs)
                ChoiceChip(
                  key: ValueKey('local-pack-${pack.id}'),
                  avatar: local.previewPlatform == pack.id
                      ? null
                      : Text(localEmojiText(pack.badge), style: localEmojiStyle(theme.textTheme.labelSmall)),
                  label: Text(i18n(pack.nameKey)),
                  selected: local.previewPlatform == pack.id,
                  selectedColor: Color(pack.accent).withValues(alpha: 0.18),
                  onSelected: (_) => local.previewPlatform = pack.id,
                ),
            ],
          ),
          const SizedBox(height: 14),
          _PackPreview(interaction: local, pack: previewPack),
        ],
      ),
      _Title(i18n('local_experience_economy')),
      _Card(
        padding: const EdgeInsets.all(14),
        children: [
          Text(i18n('local_experience_economy_desc'), style: hint),
          const SizedBox(height: 10),
          LocalRechargeRow(interaction: local),
          LocalHistory(interaction: local, clearLabel: i18n('local_clear_history'), exportable: true),
        ],
      ),
    ];
  }

  Iterable<Widget> _first(BuildContext context, LocalInteraction local, TextStyle? hint) sync* {
    yield _Title(i18n('local_group_interaction'), first: true);
    yield _Card(
      children: [
        _Tile(
          id: 'enabled',
          icon: AppIcons.localInteraction,
          title: i18n('local_interaction_enable'),
          subtitle: i18n('local_interaction_enable_desc'),
          value: local.enabled,
          onChanged: (value) => local.enabled = value,
        ),
      ],
    );
    // c15: where the room shows it, right under the switch.
    yield Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Text(
        i18n('local_interaction_room_entry_desc'),
        key: const ValueKey('local-settings-entry-desc'),
        style: hint,
      ),
    );
  }
}

/// D08.2 c4: the phrases, in the order of the composer's chips: a line on
/// what they are, then one row each (the handle to drag it elsewhere, the
/// words, a tap to change them, delete; a delete is undone from its toast
/// for 4 s, docs/specs/UI.md §7) and "添加常用语" (a dialog; at most
/// [Settings.localPhraseLimit], each a local danmaku's 40 characters, no
/// repeats). Without any it says how to save one.
class LocalPhrasesEditor extends StatelessWidget {
  /// Creates the group's content.
  const new({required this.interaction, super.key});

  /// The phrases' owner.
  final LocalInteraction interaction;

  /// Asks for a phrase, [initial] to change one ([index]).
  Future<void> _ask(BuildContext context, {int? index, String initial = ''}) async {
    final local = interaction;
    final words = await showAppInputDialog(
      context: context,
      title: i18n(index == null ? 'local_phrase_add' : 'local_phrase_edit'),
      confirmLabel: i18n('save'),
      initial: initial,
      hint: i18n('local_phrase_hint'),
      maxLength: LocalCatalog.danmakuLimit,
      fieldKey: const ValueKey('local-phrase-input'),
      confirmKey: const ValueKey('local-phrase-confirm'),
      check: (text) => switch (local.phraseProblem(text, replacing: index)) {
        final problem? => i18n(problem.messageKey, args: {'count': '${Settings.localPhraseLimit}'}),
        null => null,
      },
    );
    if (words == null) return;
    if (index == null) {
      local.addPhrase(words);
    } else {
      local.editPhrase(index, words);
    }
  }

  void _delete(BuildContext context, int index) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final local = interaction;
    final removed = local.removePhrase(index);
    if (removed == null) return;
    final toast = AppToast(
      i18n('local_phrase_deleted', args: {'text': removed}),
      key: const ValueKey('local-phrase-undo'),
      actionLabel: i18n('room_undo'),
      onAction: () => local.restorePhrase(index, removed),
    );
    if (messenger == null) {
      AppNavigator.showToast(toast);
    } else {
      showAppToastOn(messenger, toast);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hint = theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.45);
    final phrases = interaction.phrases;
    final full = phrases.length >= Settings.localPhraseLimit;
    return Column(
      key: const ValueKey('local-phrases'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(AppIcons.localPhrases, size: 22, color: scheme.primary),
              const SizedBox(width: 14),
              Expanded(child: Text(withoutOrphan(i18n('local_phrases_desc')), style: hint)),
            ],
          ),
        ),
        if (phrases.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Text(
              withoutOrphan(i18n('local_phrases_empty')),
              key: const ValueKey('local-phrases-empty'),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          )
        else
          ReorderableListView(
            key: const ValueKey('local-phrases-list'),
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            physics: const NeverScrollableScrollPhysics(),
            proxyDecorator: (child, _, _) => Material(color: scheme.surfaceContainerHigh, elevation: 2, child: child),
            onReorderItem: interaction.movePhrase,
            children: [
              for (final (index, words) in phrases.indexed)
                _PhraseRow(
                  key: ValueKey('local-phrase-$words'),
                  index: index,
                  words: words,
                  onEdit: () => unawaited(_ask(context, index: index, initial: words)),
                  onDelete: () => _delete(context, index),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 16, 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              TextButton.icon(
                key: const ValueKey('local-phrase-add'),
                onPressed: full ? null : () => unawaited(_ask(context)),
                icon: const Icon(AppIcons.add, size: 18),
                label: Text(i18n('local_phrase_add')),
              ),
              Text(
                full
                    ? i18n(LocalPhraseProblem.full.messageKey, args: {'count': '${Settings.localPhraseLimit}'})
                    : '${phrases.length} / ${Settings.localPhraseLimit}',
                key: const ValueKey('local-phrases-count'),
                style: theme.textTheme.bodySmall?.tabular.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One phrase: the handle, the words (a tap changes them), delete.
class _PhraseRow extends StatelessWidget {
  const new({required this.index, required this.words, required this.onEdit, required this.onDelete, super.key});

  final int index;
  final String words;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        key: ValueKey('local-phrase-row-$index'),
        onTap: onEdit,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Tooltip(
                  message: i18n('settings_nav_drag'),
                  child: SizedBox(
                    key: ValueKey('local-phrase-handle-$index'),
                    width: 48,
                    height: 48,
                    child: Icon(AppIcons.dragHandle, size: 20, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    localEmojiText(words),
                    style: localEmojiStyle(theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 15)),
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('local-phrase-delete-$index'),
                tooltip: i18n('delete'),
                onPressed: onDelete,
                icon: Icon(AppIcons.delete, size: 20, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// A group title (13 points, primary).
class _Title extends StatelessWidget {
  const new(this.text, {this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(8, first ? 0 : 20, 8, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.emphasis.copyWith(fontSize: 13, color: theme.colorScheme.primary),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const new({required this.children, this.padding = EdgeInsets.zero});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    clipBehavior: Clip.antiAlias,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    ),
  );
}

/// A row: icon, title, a line under it, then a switch ([value]) or a value
/// and chevron ([onTap]).
class _Tile extends StatelessWidget {
  const new({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.onChanged,
    this.trailing,
    this.onTap,
  });

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final String? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = this.value;
    final tap = value != null && onChanged != null ? () => onChanged!(!value) : onTap;
    return MergeSemantics(
      child: InkWell(
        key: ValueKey('local-settings-$id'),
        onTap: tap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Icon(icon, size: 22, color: scheme.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge?.regular.copyWith(fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (value != null)
                  Switch(key: ValueKey('local-settings-switch-$id'), value: value, onChanged: onChanged)
                else if (onTap != null) ...[
                  if (trailing case final text?)
                    Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  Icon(AppIcons.forward, size: 20, color: scheme.onSurfaceVariant),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The chosen pack: badge and name, "用户等级 Lv.1 · 1390 电池" and its gifts
/// (3.x `_buildPackPreview`).
class _PackPreview extends StatelessWidget {
  const new({required this.interaction, required this.pack});

  final LocalInteraction interaction;
  final LocalPlatformPack pack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = Color(pack.accent);
    final ink = localAccentInk(pack.accent, theme.brightness);
    return Container(
      key: const ValueKey('local-pack-preview'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [accent.withValues(alpha: 0.18), accent.withValues(alpha: 0.05)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            localEmojiText('${pack.badge} ${i18n(pack.nameKey)}'),
            style: localEmojiStyle(theme.textTheme.titleMedium?.emphasis.copyWith(fontSize: 15)),
          ),
          const SizedBox(height: 4),
          Text(
            interaction.statusLine(pack),
            key: const ValueKey('local-pack-status'),
            style: theme.textTheme.bodyMedium?.emphasis.tabular.copyWith(fontSize: 13, color: ink),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final gift in LocalCatalog.giftsFor(pack.id))
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      localEmojiText('${gift.emoji} ${i18n(gift.nameKey)} · ${gift.price}'),
                      style: localEmojiStyle(theme.textTheme.labelLarge?.copyWith(fontSize: 13)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
