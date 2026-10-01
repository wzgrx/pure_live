import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/pages/tags/tag_editor_dialog.dart';
import 'package:pure_live/pages/tags/tag_tile.dart';
import 'package:pure_live/routes/app_navigator.dart';
import 'package:pure_live/routes/route_args.dart';

/// The tags, in order, again after every change.
final StreamProvider<List<StoreTag>> tagListProvider = StreamProvider.autoDispose<List<StoreTag>>(
  (ref) => ref.watch(storeProvider).tags.watchAll(),
);

/// Every room's tag ids, again after every change.
final StreamProvider<Map<String, List<String>>> tagAssignmentsProvider =
    StreamProvider.autoDispose<Map<String, List<String>>>((ref) => ref.watch(storeProvider).tags.watchAssignments());

/// The followed rooms, again after every change (for the room counts).
final StreamProvider<List<LiveRoom>> tagFollowsProvider = StreamProvider.autoDispose<List<LiveRoom>>(
  (ref) => ref.watch(storeProvider).follows.watchAll(),
);

/// Widest the list grows on a desktop window.
const double _maxContentWidth = 720;

/// Follow groups (tags) (3.x `lib/modules/tags`).
///
/// Routes: `RoutePath.kSettingsTags`.
///
/// The tags live in `LiveStore.tags`: the page adds, renames, deletes,
/// reorders and pins them; rooms get their tags from the room card menu
/// and the follow page filters by them.
class TagsPage extends ConsumerStatefulWidget {
  /// Creates the page for [route].
  const new({required this.route, super.key});

  /// The path and arguments the page was opened with.
  final RouteArgs route;

  @override
  ConsumerState<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends ConsumerState<TagsPage> {
  /// A change is being saved; the actions wait (3.x `_actionPending`).
  bool _busy = false;

  /// A dialog of the page is open (3.x `_dialogActive`).
  bool _dialogOpen = false;

  /// The order shown while a drag's new order is saved, so the list does
  /// not jump back until the store reports it.
  List<StoreTag>? _pendingOrder;
  bool _pendingSaved = false;

  TagStore get _tags => ref.read(storeProvider).tags;

  bool get _locked => _busy || _dialogOpen;

  int _roomsOf(StoreTag tag) =>
      followedTagCounts(
        ref.read(tagAssignmentsProvider).value ?? const {},
        ref.read(tagFollowsProvider).value ?? const [],
      )[tag.id] ??
      0;

  /// Runs [change], telling the user when it was not saved.
  Future<void> _run(Future<void> Function() change) async {
    if (_locked || !mounted) return;
    setState(() => _busy = true);
    try {
      await change();
    } on Object catch (error, stack) {
      log('Changing the tags failed', name: 'TagsPage', error: error, stackTrace: stack);
      if (mounted) AppNavigator.toast(i18n('tag_changes_save_failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows a dialog of the page; one at a time.
  Future<T?> _dialog<T>(Future<T?> Function() show) async {
    if (_locked || !mounted) return null;
    setState(() => _dialogOpen = true);
    try {
      return await show();
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _edit([StoreTag? tag]) async {
    final saved = await _dialog(() => showTagEditor(context, tags: _tags, tag: tag));
    if (saved == null || !mounted) return;
    AppNavigator.toast(i18n(tag == null ? 'tags_added' : 'tags_saved', args: {'name': saved.name}));
  }

  Future<void> _open(StoreTag tag) async {
    final action = await _dialog(() => showTagDetails(context, tag: tag, rooms: _roomsOf(tag)));
    if (action == TagDetailsAction.edit && mounted) await _edit(tag);
  }

  Future<void> _delete(StoreTag tag) async {
    final rooms = _roomsOf(tag);
    final confirmed = await _dialog(
      () => showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final colors = Theme.of(dialogContext).colorScheme;
          final styles = dialogContext.textStyles;
          return AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            title: Text(i18n('delete_tag'), style: styles.t16Bold),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i18n('delete_tag_confirm_named', args: {'name': tag.name}), style: styles.t14),
                  if (rooms > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      i18n('tags_delete_rooms_hint', args: {'count': '$rooms'}),
                      key: const ValueKey('tag-delete-rooms'),
                      style: styles.t13Muted,
                    ),
                  ],
                ],
              ),
            ),
            actionsOverflowDirection: VerticalDirection.down,
            actionsOverflowButtonSpacing: 8,
            actions: [
              TextButton(
                key: const ValueKey('tag-delete-cancel'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(i18n('cancel'), style: styles.t14Muted),
              ),
              FilledButton(
                key: const ValueKey('tag-delete-confirm'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(i18n('delete')),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;
    await _run(() async {
      await _tags.delete(tag.id);
      AppNavigator.toast(i18n('tags_deleted', args: {'name': tag.name}));
    });
  }

  void _reorder(List<StoreTag> shown, int from, int to) {
    if (_locked || from == to) return;
    final next = [...shown];
    next.insert(to, next.removeAt(from));
    setState(() {
      _pendingOrder = next;
      _pendingSaved = false;
    });
    unawaited(
      _run(() async {
        try {
          await _tags.reorder([for (final tag in next) tag.id]);
          _pendingSaved = true;
        } on Object {
          if (mounted) setState(() => _pendingOrder = null);
          rethrow;
        }
      }),
    );
  }

  /// Drops the pending order once the store reports it (or anything after
  /// the save finished).
  void _onTags(List<StoreTag> tags) {
    final pending = _pendingOrder;
    if (pending == null) return;
    var same = tags.length == pending.length;
    for (var i = 0; same && i < tags.length; i++) {
      same = tags[i].id == pending[i].id;
    }
    if (same || _pendingSaved) setState(() => _pendingOrder = null);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tagListProvider, (_, next) {
      if (next.value case final tags?) _onTags(tags);
    });
    final tags = ref.watch(tagListProvider);
    final counts = followedTagCounts(
      ref.watch(tagAssignmentsProvider).value ?? const {},
      ref.watch(tagFollowsProvider).value ?? const [],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n('tag_management')),
        actions: [
          IconButton(
            key: const ValueKey('tags-add'),
            tooltip: i18n('add_tag'),
            icon: const Icon(Icons.add_rounded),
            onPressed: _locked ? null : () => unawaited(_edit()),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: switch (tags) {
              AsyncValue(value: final list?) when list.isEmpty => _empty(context),
              AsyncValue(value: final list?) => _list(context, _pendingOrder ?? list, counts),
              AsyncValue(error: final _?) => AppStatusView(
                type: AppStatusType.error,
                buttonText: i18n('status_retry_button'),
                onButtonPressed: () => ref.invalidate(tagListProvider),
              ),
              _ => const AppStatusView(type: AppStatusType.loading),
            },
          ),
          if (_busy)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(key: ValueKey('tags-busy'), minHeight: 2),
            ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, List<StoreTag> tags, Map<String, int> counts) => LayoutBuilder(
    builder: (context, constraints) {
      final side = math.max(16, (constraints.maxWidth - _maxContentWidth) / 2).toDouble();
      return ReorderableListView.builder(
        key: const ValueKey('tags-list'),
        buildDefaultDragHandles: false,
        physics: const PureLiveScrollPhysics(),
        padding: EdgeInsets.fromLTRB(side, 12, side, 32),
        header: _tip(context),
        itemCount: tags.length,
        onReorderItem: (from, to) => _reorder(tags, from, to),
        proxyDecorator: (child, _, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) => Material(
            elevation: 6 * Curves.easeOut.transform(animation.value),
            color: Colors.transparent,
            shadowColor: Colors.black26,
            borderRadius: BorderRadius.circular(16),
            child: child,
          ),
          child: child,
        ),
        itemBuilder: (context, index) {
          final tag = tags[index];
          return TagTile(
            key: ValueKey('tag-${tag.id}'),
            tag: tag,
            index: index,
            rooms: counts[tag.id] ?? 0,
            enabled: !_locked,
            onOpen: () => unawaited(_open(tag)),
            onPin: () => unawaited(_run(() => _tags.pinToTop(tag.id))),
            onEdit: () => unawaited(_edit(tag)),
            onDelete: () => unawaited(_delete(tag)),
          );
        },
      );
    },
  );

  /// No tags yet: what they are for and a button that adds one (3.x showed
  /// only the hint).
  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    final styles = context.textStyles;
    return Center(
      key: const ValueKey('tags-empty'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sell_outlined, size: 48, color: theme.disabledColor.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              i18n('no_tags_tip'),
              textAlign: TextAlign.center,
              style: styles.t14.copyWith(color: theme.disabledColor),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                i18n('tags_empty_hint'),
                textAlign: TextAlign.center,
                style: styles.t13.copyWith(color: theme.hintColor, height: 1.5),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              key: const ValueKey('tags-empty-add'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _locked ? null : () => unawaited(_edit()),
              icon: const Icon(Icons.add_rounded),
              label: Text(i18n('add_tag')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tip(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: colors.primary.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colors.primary.withValues(alpha: 0.8)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              i18n('tags_sort_tip'),
              style: context.textStyles.t13.copyWith(color: colors.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
