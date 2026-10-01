import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// One block list, in the order the entries were added, again after every
/// change.
final StreamProviderFamily<List<String>, BlockKind> blockListProvider = StreamProvider.autoDispose
    .family<List<String>, BlockKind>((ref, kind) => ref.watch(storeProvider).blockLists.watch(kind));

/// Widest the content grows on a desktop window.
const double _maxContentWidth = 720;

/// The words of one tab.
final class _Words {
  const new({
    required this.hint,
    required this.rule,
    required this.countTitle,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.clearConfirm,
    required this.icon,
  });

  factory of(BlockKind kind) => switch (kind) {
    BlockKind.keyword => const _Words(
      hint: 'please_input_keyword',
      rule: 'shield_keyword_rule',
      countTitle: 'shield_count_title',
      emptyTitle: 'empty_shield_title',
      emptySubtitle: 'empty_shield_subtitle',
      clearConfirm: 'shield_clear_keywords_confirm',
      icon: Icons.filter_alt_off_rounded,
    ),
    BlockKind.user => const _Words(
      hint: 'shield_user_hint',
      rule: 'shield_user_rule',
      countTitle: 'blocked_danmaku_users',
      emptyTitle: 'shield_users_empty_title',
      emptySubtitle: 'shield_users_empty_subtitle',
      clearConfirm: 'shield_clear_users_confirm',
      icon: Icons.person_off_rounded,
    ),
  };

  final String hint;
  final String rule;
  final String countTitle;
  final String emptyTitle;
  final String emptySubtitle;
  final String clearConfirm;
  final IconData icon;
}

/// One block list: an input that adds to it, then the entries as chips,
/// newest first; a tap removes one (with undo), "clear" removes all after
/// asking (3.x `DanmuShieldPage`, which had only the keywords).
class BlockListTab extends ConsumerStatefulWidget {
  /// Creates the tab of [kind].
  const new({required this.kind, super.key});

  /// Which list.
  final BlockKind kind;

  @override
  ConsumerState<BlockListTab> createState() => _BlockListTabState();
}

class _BlockListTabState extends ConsumerState<BlockListTab> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _busy = false;

  _Words get _words => _Words.of(widget.kind);

  BlockListStore get _lists => ref.read(storeProvider).blockLists;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Runs [change] unless another one runs, telling the user when it was
  /// not saved.
  Future<void> _run(Future<void> Function() change) async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      await change();
    } on Object catch (error, stack) {
      log('Changing the block list failed', name: 'ShieldPage', error: error, stackTrace: stack);
      if (mounted) AppNavigator.toast(i18n('shield_save_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Adds the input (3.x `DanmuShieldController.add`): empty and repeated
  /// entries are refused where the user typed (3.x showed a toast for empty
  /// ones and silently dropped repeated ones, clearing the input).
  Future<void> _add() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() => _error = i18n(_words.hint));
      _focus.requestFocus();
      return;
    }
    await _run(() async {
      final added = await _lists.add(widget.kind, text);
      if (!mounted) return;
      setState(() => _error = added ? null : i18n('shield_duplicate', args: {'value': text}));
      if (added) _input.clear();
    });
    if (mounted) _focus.requestFocus();
  }

  Future<void> _remove(String value, List<String> before) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final lists = _lists;
    return _run(() async {
      await lists.remove(widget.kind, value);
      _offerUndo(messenger, lists, i18n('shield_removed', args: {'value': value}), before);
    });
  }

  Future<void> _clear(List<String> before) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        final styles = dialogContext.textStyles;
        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Text(i18n('shield_clear'), style: styles.t16Bold),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(i18n(_words.clearConfirm, args: {'count': '${before.length}'}), style: styles.t14),
          ),
          actionsOverflowDirection: VerticalDirection.down,
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(i18n('cancel'), style: styles.t14Muted),
            ),
            FilledButton(
              key: const ValueKey('shield-clear-confirm'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(48, 48),
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(i18n('shield_clear')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    final lists = _lists;
    await _run(() async {
      await lists.replaceAll(widget.kind, const []);
      _offerUndo(messenger, lists, i18n('shield_cleared', args: {'count': '${before.length}'}), before);
    });
  }

  /// Shows [message] with an undo that puts the list back as [before],
  /// keeping entries added since at the end.
  void _offerUndo(ScaffoldMessengerState? messenger, BlockListStore lists, String message, List<String> before) {
    if (messenger == null) {
      AppNavigator.toast(message);
      return;
    }
    final kind = widget.kind;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(label: i18n('shield_undo'), onPressed: () => unawaited(_restore(lists, kind, before))),
        ),
      );
  }

  static Future<void> _restore(BlockListStore lists, BlockKind kind, List<String> before) async {
    try {
      final now = await lists.list(kind);
      await lists.replaceAll(kind, [...before, ...now]);
    } on Object catch (error, stack) {
      log('Undoing a block list change failed', name: 'ShieldPage', error: error, stackTrace: stack);
      AppNavigator.toast(i18n('shield_save_failed'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final values = ref.watch(blockListProvider(widget.kind));
    return switch (values) {
      AsyncValue(value: final list?) => _content(context, list),
      AsyncValue(error: final _?) => AppStatusView(
        type: AppStatusType.error,
        buttonText: i18n('status_retry_button'),
        onButtonPressed: () => ref.invalidate(blockListProvider(widget.kind)),
      ),
      _ => const AppStatusView(type: AppStatusType.loading),
    };
  }

  Widget _content(BuildContext context, List<String> values) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final styles = context.textStyles;
    final name = widget.kind.name;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.max(16, (constraints.maxWidth - _maxContentWidth) / 2).toDouble();
        return ListView(
          physics: const PureLiveScrollPhysics(),
          padding: EdgeInsets.fromLTRB(side, 16, side, 32),
          children: [
            TextField(
              key: ValueKey('shield-input-$name'),
              controller: _input,
              focusNode: _focus,
              maxLength: BlockListStore.maxKeywordLength,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => unawaited(_add()),
              decoration: InputDecoration(
                hintText: i18n(_words.hint),
                errorText: _error,
                filled: true,
                fillColor: colors.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: colors.primary, width: 1.5),
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: TextButton.icon(
                    key: ValueKey('shield-add-$name'),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _busy ? null : () => unawaited(_add()),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(i18n('add'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: colors.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(i18n(_words.rule), style: styles.t12.copyWith(color: colors.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (values.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 32),
                child: EmptyView(
                  key: ValueKey('shield-empty-$name'),
                  icon: _words.icon,
                  title: i18n(_words.emptyTitle),
                  subtitle: i18n(_words.emptySubtitle),
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        i18n(_words.countTitle, args: {'count': '${values.length}'}),
                        style: theme.textTheme.titleSmall?.copyWith(color: colors.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: ValueKey('shield-clear-$name'),
                    style: TextButton.styleFrom(foregroundColor: colors.error, minimumSize: const Size(48, 40)),
                    onPressed: _busy ? null : () => unawaited(_clear(values)),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: Text(i18n('shield_clear')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final value in values.reversed)
                    InputChip(
                      key: ValueKey('shield-chip-$name-$value'),
                      label: Text(value, style: styles.t14Medium),
                      tooltip: '${i18n('click_to_remove')}: $value',
                      deleteButtonTooltipMessage: '${i18n('click_to_remove')}: $value',
                      backgroundColor: colors.primary.withValues(alpha: 0.06),
                      side: BorderSide(color: colors.primary.withValues(alpha: 0.15)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      deleteIcon: const Icon(Icons.close_rounded, size: 16),
                      deleteIconColor: colors.primary.withValues(alpha: 0.7),
                      isEnabled: !_busy,
                      onPressed: () => unawaited(_remove(value, values)),
                      onDeleted: () => unawaited(_remove(value, values)),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
