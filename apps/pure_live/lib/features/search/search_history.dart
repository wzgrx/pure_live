import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';
import 'package:pure_live_app/features/settings/setting_tiles.dart';
import 'package:pure_live_app/features/settings/settings_search.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// Recent searches, newest first (spec/product.md F-SRC-06). Changes go
/// through the notifier, which reads the list again after each; the search
/// page also reloads it whenever the list comes into view, so a restored
/// backup shows. A one-shot query rather than a table stream: nothing stays
/// subscribed while the list is hidden.
class SearchHistoryNotifier extends AsyncNotifier<List<SearchHistoryEntry>> {
  @override
  Future<List<SearchHistoryEntry>> build() => ref.watch(storeProvider).searchHistory.all();

  Future<T> _change<T>(Future<T> Function(SearchHistoryStore history) change) async {
    final history = ref.read(storeProvider).searchHistory;
    final result = await change(history);
    final entries = await history.all();
    if (ref.mounted) state = AsyncData(entries);
    return result;
  }

  /// Remembers a searched keyword; see [SearchHistoryStore.record].
  Future<bool> record(String keyword) => _change((history) => history.record(keyword));

  /// Removes one keyword and returns it for undo.
  Future<SearchHistoryEntry?> remove(String keyword) => _change((history) => history.remove(keyword));

  /// Removes [shown] (everything when null) and returns them for undo.
  Future<List<SearchHistoryEntry>> clear([Iterable<SearchHistoryEntry>? shown]) =>
      _change((history) => history.clear(shown));

  /// Puts back what [remove] or [clear] returned.
  Future<void> restore(Iterable<SearchHistoryEntry> entries) => _change((history) => history.restore(entries));
}

/// Recent searches, newest first (F-SRC-06).
final searchHistoryProvider = AsyncNotifierProvider<SearchHistoryNotifier, List<SearchHistoryEntry>>(
  SearchHistoryNotifier.new,
);

/// 记录搜索历史 (F-SRC-06; on by default).
final recordSearchHistorySetting = NotifierProvider<SettingNotifier<bool>, bool>(
  () => SettingNotifier(Settings.recordSearchHistory),
);

/// Remembers a searched [keyword] (F-SRC-06). The store ignores it while
/// recording is off; a failed write only goes to the log.
void rememberSearch(WidgetRef ref, String keyword) {
  final log = ref.read(appLogProvider);
  unawaited(
    ref
        .read(searchHistoryProvider.notifier)
        .record(keyword)
        .then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            log.error('search', 'recording the search history failed', error, stack);
          },
        ),
  );
}

void _undoable(ScaffoldMessengerState messenger, String text, Future<void> Function() undo) {
  messenger.showSnackBar(
    SnackBar(
      content: Text(text),
      action: SnackBarAction(label: t.common.undo, onPressed: () => unawaited(undo())),
    ),
  );
}

/// Turns 记录搜索历史 on or off. Off clears the history at once, with undo
/// (the app's rule for removals, spec/product.md F-HIS-01): undo puts the
/// entries back and turns recording on again.
Future<void> setSearchHistoryRecording(BuildContext context, WidgetRef ref, {required bool on}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final settings = ref.read(storeProvider).settings;
  // Read now: the undo may run after this tile is gone.
  final history = ref.read(searchHistoryProvider.notifier);
  await settings.set(Settings.recordSearchHistory, on);
  if (on) return;
  final removed = await history.clear();
  if (removed.isEmpty || messenger == null) return;
  _undoable(messenger, t.search.historyOffCleared, () async {
    await settings.set(Settings.recordSearchHistory, true);
    await history.restore(removed);
  });
}

/// The recent searches under a focused, empty search box (principles §4.1):
/// a tap searches again; each entry can be removed, and 清空 removes them
/// all, both with undo. Taps here do not take the focus from the box.
class SearchHistoryList extends ConsumerWidget {
  const new({required this.entries, required this.onPick, this.width = Sizes.readingWidth, super.key});

  /// Entries, newest first.
  final List<SearchHistoryEntry> entries;

  /// Searches the chosen keyword.
  final ValueChanged<String> onPick;

  /// The widest the rows get between the page margins: the search box's
  /// width, so the list lines up under it.
  final double width;

  Future<void> _remove(BuildContext context, WidgetRef ref, SearchHistoryEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    // Read now: the undo may run after this list is gone.
    final history = ref.read(searchHistoryProvider.notifier);
    final removed = await history.remove(entry.keyword);
    if (removed == null) return;
    _undoable(messenger, t.search.historyRemoved(keyword: removed.keyword), () => history.restore([removed]));
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final history = ref.read(searchHistoryProvider.notifier);
    final removed = await history.clear(entries);
    if (removed.isEmpty) return;
    _undoable(messenger, t.search.historyCleared, () => history.restore(removed));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final margin = PageMargin.of(context);
    final start = PageMargin.tilePadding(margin).start;
    // The glyphs of 清空 and the remove buttons end on the page margin.
    final end = math.max(0, margin - Space.s3).toDouble();
    return TextFieldTapRegion(
      child: PageBody(
        child: Align(
          alignment: AlignmentDirectional.topStart,
          // Rows start on the page's left line and are no wider than the
          // search box above them (principles §4.3).
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width + 2 * margin),
            child: ListView(
              padding: const EdgeInsets.only(bottom: Space.s4),
              children: [
                Padding(
                  padding: EdgeInsetsDirectional.only(start: start, end: end),
                  child: Row(
                    children: [
                      Expanded(
                        child: Semantics(header: true, child: Text(t.search.recent, style: theme.textTheme.titleSmall)),
                      ),
                      TextButton(onPressed: () => _clear(context, ref), child: Text(t.search.clearHistory)),
                    ],
                  ),
                ),
                for (final entry in entries)
                  ListTile(
                    key: ValueKey(entry.folded),
                    leading: const Icon(Icons.history),
                    title: Text(entry.keyword, maxLines: 1, overflow: TextOverflow.ellipsis),
                    contentPadding: EdgeInsetsDirectional.only(start: start, end: end),
                    trailing: IconButton(
                      tooltip: t.search.removeFromHistory,
                      icon: const Icon(Icons.close),
                      onPressed: () => _remove(context, ref, entry),
                    ),
                    onTap: () => onPick(entry.keyword),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 设置 › 数据与同步 › 记录搜索历史 (F-SRC-06): turning it off clears the
/// history, with undo.
class SearchHistorySettingTile extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => SettingAnchor(
    id: Settings.recordSearchHistory.id,
    child: SettingBuilder<bool>(
      setting: Settings.recordSearchHistory,
      builder: (context, value, _) => SwitchListTile(
        title: Text(t.settings.data.searchHistory),
        subtitle: Text(t.settings.data.searchHistorySubtitle),
        value: value,
        onChanged: (on) => unawaited(setSearchHistoryRecording(context, ref, on: on)),
      ),
    ),
  );
}
