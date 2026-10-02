import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';

/// Whether [name] is a masked viewer name (a Bilibili guest sees `观***`):
/// it stands for every viewer whose name starts the same way, so it cannot
/// be blocked (audit B-1, task B01).
bool isMaskedViewerName(String name) => BilibiliDanmakuProtocol.isMaskedName(name.trim());

/// The one-time removal of masked names from the blocked viewers (task B01
/// c2): before 4.0.1 a guest could block `观***`, which hid every viewer
/// whose name starts with 观 in every room. The block list now ignores such
/// names; this takes the stored ones out and leaves the block manager a
/// notice of how many went.
abstract final class MaskedNameBlocks {
  /// Set once the cleanup ran (the number it removed).
  static const String doneKey = 'danmaku.maskedUserBlocksCleaned';

  /// The number removed, until the block manager has said so.
  static const String noticeKey = 'danmaku.maskedUserBlocksNotice';

  /// Removes the masked names from [lists]' blocked viewers, once per
  /// install ([meta] remembers it); the number removed, 0 when it ran
  /// before.
  static Future<int> cleanOnce(BlockListStore lists, MetaStore meta) async {
    if (await meta.get(doneKey) != null) return 0;
    final users = await lists.list(BlockKind.user);
    final kept = [
      for (final user in users)
        if (!isMaskedViewerName(user)) user,
    ];
    final removed = users.length - kept.length;
    if (removed > 0) {
      await lists.replaceAll(BlockKind.user, kept);
      await meta.set(noticeKey, '$removed');
    }
    await meta.set(doneKey, '$removed');
    return removed;
  }

  /// The number of the notice still owed, which is then forgotten (shown
  /// once); null when none is owed.
  static Future<int?> takeNotice(MetaStore meta) async {
    final raw = await meta.get(noticeKey);
    if (raw == null) return null;
    await meta.set(noticeKey, null);
    final count = int.tryParse(raw);
    return count != null && count > 0 ? count : null;
  }
}
