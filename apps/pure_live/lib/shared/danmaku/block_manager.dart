import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/shared/danmaku/masked_blocks.dart';
import 'package:pure_live/shared/danmaku/setting_rows.dart';

/// The longest keyword (3.x `KeywordBlockPage`'s field).
const int blockKeywordMaxLength = 40;

/// How long a removal can be undone (docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页 c15; a SnackBar's
/// own default).
const Duration blockUndoDuration = Duration(seconds: 4);

/// The block list (3.x `KeywordBlockPage`, docs/A-界面设计/A08-弹幕界面/A08.1-弹幕列表和弹幕设置页 c11–c16):
/// the keyword field and the blocked words, the blocked viewers, then the
/// platform's filter and the similarity filter ([showFilters]). Words and
/// viewers are chips removed only by their ×, each removal undoable for
/// [blockUndoDuration]; a word already blocked is said under the field,
/// which keeps it; empty sections say what goes there. The live room's
/// "屏蔽管理" tab and the settings page "弹幕屏蔽" (U.12d, E4) use this
/// same component. The first one opened after [MaskedNameBlocks.cleanOnce]
/// removed masked names says so at the top, once (B01 c2).
class DanmakuBlockManager extends ConsumerStatefulWidget {
  /// Creates the block list.
  const new({
    this.addKeyword,
    this.showFilters = true,
    this.padding = const EdgeInsets.only(bottom: 24),
    this.showUsers = false,
    super.key,
  });

  /// Scrolls to "已屏蔽用户" when it opens (the settings page opened for the
  /// blocked users, U.12d).
  final bool showUsers;

  /// Blocks a word and says whether it was new; the room also takes the
  /// matching messages off its list. Null stores it directly.
  final Future<bool> Function(String word)? addKeyword;

  /// Shows the platform and similarity filters after the lists.
  final bool showFilters;

  /// Around the list.
  final EdgeInsets padding;

  @override
  ConsumerState<DanmakuBlockManager> createState() => _DanmakuBlockManagerState();
}

class _DanmakuBlockManagerState extends ConsumerState<DanmakuBlockManager> {
  final TextEditingController _input = TextEditingController();
  late final Stream<List<String>> _keywords;
  late final Stream<List<String>> _users;
  final GlobalKey _usersSection = GlobalKey();
  String? _error;

  /// How many masked names the one-time cleanup removed, while its notice
  /// shows.
  int? _maskedCleaned;

  @override
  void initState() {
    super.initState();
    final store = ref.read(storeProvider);
    final lists = store.blockLists;
    _keywords = lists.watch(BlockKind.keyword);
    _users = lists.watch(BlockKind.user);
    if (widget.showUsers) unawaited(_revealUsers(lists));
    unawaited(_takeMaskedNotice(store.meta));
  }

  Future<void> _takeMaskedNotice(MetaStore meta) async {
    final int? count;
    try {
      count = await MaskedNameBlocks.takeNotice(meta);
    } on Object {
      return;
    }
    if (count != null && mounted) setState(() => _maskedCleaned = count);
  }

  /// B01 c2: "已清理 N 个打码昵称的屏蔽", with × to put it away.
  Widget _maskedNotice(BuildContext context, int count) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: DecoratedBox(
        key: const ValueKey('block-masked-cleaned'),
        decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Icon(AppIcons.info, size: 20, color: scheme.onSecondaryContainer),
            ),
            Expanded(
              child: Text(
                i18n('danmaku_masked_blocks_cleaned', args: {'count': '$count'}),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSecondaryContainer, height: 1.4),
              ),
            ),
            IconButton(
              key: const ValueKey('block-masked-cleaned-close'),
              tooltip: i18n('close'),
              onPressed: () => setState(() => _maskedCleaned = null),
              icon: Icon(AppIcons.close, size: 18, color: scheme.onSecondaryContainer),
            ),
          ],
        ),
      ),
    );
  }

  /// Brings "已屏蔽用户" into view once the lists have arrived.
  Future<void> _revealUsers(BlockListStore lists) async {
    await lists.list(BlockKind.keyword);
    await lists.list(BlockKind.user);
    // Two frames: the lists build, then the section has its place.
    for (var i = 0; i < 2; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final section = _usersSection.currentContext;
    if (section == null || !section.mounted) return;
    await Scrollable.ensureVisible(section, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final word = _input.text.trim();
    if (word.isEmpty) {
      AppNavigator.toast(i18n('please_enter_keyword'));
      return;
    }
    final add = widget.addKeyword ?? (word) => ref.read(storeProvider).blockLists.add(BlockKind.keyword, word);
    final added = await add(word);
    if (!mounted) return;
    if (!added) {
      // c13: 3.x cleared the field and said nothing.
      setState(() => _error = i18n('keyword_already_blocked', args: {'word': word}));
      return;
    }
    _input.clear();
    setState(() => _error = null);
  }

  Future<void> _remove(BlockKind kind, String value, int index) async {
    final lists = ref.read(storeProvider).blockLists;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await lists.remove(kind, value);
    final message = i18n('shield_removed', args: {'value': value});
    if (messenger == null) {
      AppNavigator.toast(message);
      return;
    }
    showAppToastOn(
      messenger,
      AppToast(
        message,
        key: const ValueKey('block-undo-snack'),
        actionLabel: i18n('room_undo'),
        onAction: () => unawaited(restoreBlockEntry(lists, kind, value, index)),
      ),
    );
  }

  Widget _chips(List<String> values, BlockKind kind) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Wrap(
      spacing: 8,
      children: [
        for (final (index, value) in values.indexed)
          BlockChip(
            key: ValueKey('block-chip-${kind.name}-$value'),
            label: value,
            icon: kind == BlockKind.user ? AppIcons.blockUser : null,
            onRemove: () => unawaited(_remove(kind, value, index)),
          ),
      ],
    ),
  );

  Widget _note(String text, {String? title}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) Text(title, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.5)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.read(storeProvider).settings;
    void set<T extends Object>(Setting<T> setting, T value) => unawaited(settings.set(setting, value));
    final similarity = watchSetting(ref, Settings.enableDanmakuSimilarityFilter);
    final threshold = watchSetting(ref, Settings.danmakuSimilarityThreshold);
    final cache = watchSetting(ref, Settings.danmakuSimilarityCacheDuration);
    final size = watchSetting(ref, Settings.danmakuSimilarityMaxCacheSize);
    // A short page of four groups, built at once so the users' group can
    // be scrolled to (showUsers).
    return SingleChildScrollView(
      key: const ValueKey('live-play-block-list'),
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_maskedCleaned case final count?) _maskedNotice(context, count),
          // c11 (E3): adding a word comes first, its list right under it.
          PanelGroupTitle(i18n('danmaku_keyword_block')),
          PanelCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        key: const ValueKey('live-play-block-input'),
                        controller: _input,
                        maxLength: blockKeywordMaxLength,
                        // A01.4 c6: the count sits at the box's bottom-right
                        // corner, not inset like the text (which left it
                        // floating towards "添加").
                        buildCounter: (context, {required currentLength, required isFocused, maxLength}) =>
                            Transform.translate(
                              key: const ValueKey('live-play-block-counter'),
                              offset: Offset(Directionality.of(context) == TextDirection.rtl ? -14 : 14, 0),
                              child: Text(
                                '$currentLength/$maxLength',
                                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant).tabular,
                              ),
                            ),
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                        onSubmitted: (_) => unawaited(_add()),
                        decoration: InputDecoration(
                          hintText: i18n('please_enter_keyword'),
                          errorText: _error,
                          filled: true,
                          fillColor: scheme.surface,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        key: const ValueKey('live-play-block-add'),
                        onPressed: () => unawaited(_add()),
                        icon: const Icon(AppIcons.add, size: 18),
                        label: Text(i18n('add')),
                      ),
                    ),
                  ],
                ),
              ),
              StreamBuilder<List<String>>(
                stream: _keywords,
                builder: (context, snapshot) {
                  final values = snapshot.data ?? const <String>[];
                  if (values.isEmpty) {
                    // c14: 3.x hid the section.
                    return KeyedSubtree(
                      key: const ValueKey('block-keywords-empty'),
                      child: _note(i18n('empty_shield_subtitle'), title: i18n('empty_shield_title')),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        child: Text(
                          i18n('keyword_added_count', args: {'count': '${values.length}'}),
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      _chips(values, BlockKind.keyword),
                    ],
                  );
                },
              ),
            ],
          ),
          StreamBuilder<List<String>>(
            stream: _users,
            builder: (context, snapshot) {
              final values = snapshot.data ?? const <String>[];
              return Column(
                key: _usersSection,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PanelGroupTitle(i18n('blocked_danmaku_users', args: {'count': '${values.length}'})),
                  PanelCard(
                    children: [
                      if (values.isEmpty)
                        KeyedSubtree(
                          key: const ValueKey('block-users-empty'),
                          child: _note(i18n('live_play_no_blocked_users')),
                        )
                      else ...[
                        const SizedBox(height: 8),
                        _chips(values, BlockKind.user),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
          if (widget.showFilters) ...[
            PanelGroupTitle(i18n('platform_danmaku_filter')),
            PanelCard(
              children: [
                SettingSwitchRow(
                  settingKey: 'douyuFilter',
                  title: i18n('douyu_suspected_automated_filter'),
                  subtitle: i18n('douyu_suspected_automated_filter_desc'),
                  value: watchSetting(ref, Settings.filterDouyuSuspectedAutomatedMessages),
                  onChanged: (value) => set(Settings.filterDouyuSuspectedAutomatedMessages, value),
                ),
              ],
            ),
            PanelGroupTitle(i18n('danmaku_similarity_filter')),
            PanelCard(
              children: [
                SettingSwitchRow(
                  settingKey: 'similarity',
                  title: i18n('danmaku_similarity_filter_enable'),
                  value: similarity,
                  onChanged: (value) => set(Settings.enableDanmakuSimilarityFilter, value),
                ),
                // c16: greyed out while the filter is off (3.x hid them).
                SettingSliderRow(
                  settingKey: 'similarityThreshold',
                  title: i18n('danmaku_similarity_threshold'),
                  value: threshold.clamp(50, 100).toDouble(),
                  min: 50,
                  max: 100,
                  divisions: 50,
                  display: '$threshold%',
                  onChanged: similarity ? (value) => set(Settings.danmakuSimilarityThreshold, value.round()) : null,
                ),
                SettingSliderRow(
                  settingKey: 'similarityCache',
                  title: i18n('danmaku_similarity_cache_duration'),
                  value: cache.clamp(1, 60).toDouble(),
                  min: 1,
                  max: 60,
                  divisions: 59,
                  display: i18n('danmaku_similarity_cache_seconds', args: {'seconds': '$cache'}),
                  onChanged: similarity ? (value) => set(Settings.danmakuSimilarityCacheDuration, value.round()) : null,
                ),
                SettingSliderRow(
                  settingKey: 'similaritySize',
                  title: i18n('danmaku_similarity_max_cache_size'),
                  value: size.clamp(20, 1000).toDouble(),
                  min: 20,
                  max: 1000,
                  divisions: 98,
                  display: '$size',
                  onChanged: similarity ? (value) => set(Settings.danmakuSimilarityMaxCacheSize, value.round()) : null,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Undoes the removal of [value] from [kind]'s list: it goes back at
/// [index] (or the end, when the list got shorter meanwhile); nothing when
/// it is back already.
Future<void> restoreBlockEntry(BlockListStore lists, BlockKind kind, String value, int index) async {
  final current = await lists.list(kind);
  final folded = value.trim().toLowerCase();
  if (current.any((entry) => entry.toLowerCase() == folded)) return;
  await lists.replaceAll(kind, [...current]..insert(index.clamp(0, current.length), value));
}

/// A blocked word or viewer (U.2e c12): the label, and × to remove it (a
/// 40 × 48 target; the label itself does nothing, so a tap does not remove
/// by mistake). On a computer the × says "点击移除: 词" when hovered.
class BlockChip extends StatelessWidget {
  /// Creates the chip.
  const new({required this.label, required this.onRemove, this.icon, super.key});

  /// The word or the viewer's name.
  final String label;

  /// Before the label (a viewer).
  final IconData? icon;

  /// Removes it.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      height: kMinInteractiveDimension,
      child: Stack(
        children: [
          Positioned.fill(
            top: 6,
            bottom: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border.all(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 12),
              if (icon != null) ...[Icon(icon, size: 16, color: scheme.primary), const SizedBox(width: 4)],
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 220),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.regular,
                ),
              ),
              Tooltip(
                message: '${i18n('click_to_remove')}: $label',
                child: InkResponse(
                  key: ValueKey('block-chip-remove-$label'),
                  radius: 20,
                  onTap: onRemove,
                  child: SizedBox(
                    width: 40,
                    height: kMinInteractiveDimension,
                    child: Icon(AppIcons.chipRemove, size: 18, color: scheme.onSurfaceVariant),
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
