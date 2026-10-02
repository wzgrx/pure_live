import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/sites/bilibili.dart';

/// The user's blocked viewers and words (3.x `DanmakuController._isBlocked`
/// with the lists of `_refreshFilters`).
///
/// - Both lists are trimmed and lower-cased once; empty entries are dropped.
/// - A masked name ([BilibiliDanmakuProtocol.isMaskedName], a guest's view
///   of a Bilibili viewer such as `观***`) blocks nobody: it stands for
///   every viewer whose name starts the same way (audit B-1).
/// - A message is blocked when its trimmed, lower-cased sender name is a
///   blocked name, or when its lower-cased text contains a blocked word.
final class DanmakuBlockList {
  /// Creates the list from the stored names ([users]) and words
  /// ([keywords]), as the user typed them.
  new({Iterable<String> users = const [], Iterable<String> keywords = const []})
    : _users = {
        for (final user in users)
          if (user.trim().toLowerCase() case final name
              when name.isNotEmpty && !BilibiliDanmakuProtocol.isMaskedName(name))
            name,
      },
      _keywords = List.unmodifiable([
        for (final keyword in keywords)
          if (keyword.trim().toLowerCase() case final word when word.isNotEmpty) word,
      ]);

  final Set<String> _users;
  final List<String> _keywords;

  /// Whether nothing is blocked.
  bool get isEmpty => _users.isEmpty && _keywords.isEmpty;

  /// Whether [message] is from a blocked viewer or contains a blocked word.
  bool blocks(LiveMessage message) {
    final user = message.userName.trim().toLowerCase();
    if (user.isNotEmpty && _users.contains(user)) return true;
    if (_keywords.isEmpty) return false;
    final text = message.message.toLowerCase();
    return _keywords.any(text.contains);
  }
}
