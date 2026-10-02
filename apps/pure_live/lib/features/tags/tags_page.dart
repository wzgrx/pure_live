import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/features/tags/tag_editor_dialog.dart';
import 'package:pure_live/features/tags/tag_tile.dart';
import 'package:pure_live/i18n/i18n.dart';
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

/// Follow groups (tags) (3.x `lib/modules/tags`, docs/A-界面设计/A09-浏览界面/A09.10-标签管理).
///
/// Routes: `RoutePath.kSettingsTags`.
///
/// The tags live in `LiveStore.tags`: the page adds, renames, deletes,
/// reorders and pins them; rooms get their tags from the room card menu
/// and the follow page filters by them. One tag a row at every width, at
/// most 720 wide (J1 A).
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

  /// Asks first, saying how many followed rooms lose the tag (c4; J2 A:
  /// no undo, "已删除标签“…”" after).
  Future<void> _delete(StoreTag tag) async {
    final rooms = _roomsOf(tag);
    final confirmed = await _dialog(
      () => showAppConfirmDialog(
        context: context,
        key: const ValueKey('tag-delete-dialog'),
        title: i18n('delete_tag'),
        message: i18n('delete_tag_confirm_named', args: {'name': tag.name}),
        content: rooms > 0
            ? Text(
                i18n('tags_delete_rooms_hint', args: {'count': '$rooms'}),
                key: const ValueKey('tag-delete-rooms'),
                style: context.textStyles.t14.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              )
            : null,
        confirmLabel: i18n('delete'),
        danger: true,
        cancelKey: const ValueKey('tag-delete-cancel'),
        confirmKey: const ValueKey('tag-delete-confirm'),
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
    final short = MediaQuery.sizeOf(context).height < 480;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: short ? 48 : null,
        title: Text(i18n('tag_management')),
        actions: [
          IconButton(
            key: const ValueKey('tags-add'),
            tooltip: i18n('add_tag'),
            icon: const Icon(AppIcons.add),
            onPressed: _locked ? null : () => unawaited(_edit()),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: switch (tags) {
              // c5: what tags are for and a button that adds one (3.x
              // showed only a grey line).
              AsyncValue(value: final list?) when list.isEmpty => AppStatusView(
                key: const ValueKey('tags-empty'),
                type: AppStatusType.empty,
                icon: AppIcons.tag,
                title: i18n('tags_empty_title'),
                subtitle: i18n('tags_empty_hint'),
                buttonText: i18n('add_tag'),
                buttonIcon: AppIcons.add,
                onButtonPressed: _locked ? null : () => unawaited(_edit()),
              ),
              AsyncValue(value: final list?) => _list(context, _pendingOrder ?? list, counts),
              AsyncValue(error: final error?) => AppStatusView(
                type: AppStatusType.error,
                details: '$error',
                buttonText: i18n('status_retry_button'),
                onButtonPressed: () => ref.invalidate(tagListProvider),
              ),
              // A list's first load is a static skeleton (U.1c c3).
              _ => const StatusSkeleton(key: ValueKey('tags-skeleton')),
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
      final side = math.max(16, (constraints.maxWidth - readableContentMaxWidth) / 2).toDouble();
      final shadow = Theme.of(context).colorScheme.shadow;
      return ReorderableListView.builder(
        key: const ValueKey('tags-list'),
        buildDefaultDragHandles: false,
        physics: const PureLiveScrollPhysics(),
        padding: EdgeInsets.fromLTRB(side, 4, side, 32),
        header: _tip(context),
        itemCount: tags.length,
        onReorderItem: (from, to) => _reorder(tags, from, to),
        // The lifted card: a shadow under it while it moves (a layer of
        // its own; nothing else repaints).
        proxyDecorator: (child, _, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final lift = Curves.easeOut.transform(animation.value);
            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: shadow.withValues(alpha: 0.18 * lift),
                    blurRadius: 12 * lift,
                    offset: Offset(0, 4 * lift),
                  ),
                ],
              ),
              child: child,
            );
          },
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

  /// c3: how to reorder, one line of small text (3.x: a tinted box with an
  /// icon over the page, and a group title that repeated the page title).
  Widget _tip(BuildContext context) => Padding(
    key: const ValueKey('tags-tip'),
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
    child: Text(
      i18n('tags_sort_tip'),
      style: context.textStyles.t13.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant, height: 1.4),
    ),
  );
}
