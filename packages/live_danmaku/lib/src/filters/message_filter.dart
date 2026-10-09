import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/filters/block_list.dart';
import 'package:live_danmaku/src/filters/message_gate.dart';
import 'package:live_danmaku/src/filters/repeated_filter.dart';
import 'package:live_danmaku/src/filters/similarity_filter.dart';
import 'package:meta/meta.dart';

/// The filter settings of 3.x (danmaku settings and the block lists), with
/// its defaults: both optional filters are off.
@immutable
final class DanmakuFilterSettings {
  /// Creates the settings.
  const new({
    this.collapseRepeated = false,
    this.repeatedWindowSeconds = 5,
    this.similarityEnabled = false,
    this.similarityThreshold = 85,
    this.similarityCacheSeconds = 3,
    this.similarityMaxCacheSize = 100,
    this.blockedUsers = const [],
    this.blockedKeywords = const [],
  });

  /// Collapse repeated text (`collapseRepeatedDanmaku`).
  final bool collapseRepeated;

  /// Window of [collapseRepeated] in seconds, used clamped to 1–30
  /// (`repeatedDanmakuWindowSeconds`).
  final int repeatedWindowSeconds;

  /// Hide similar text (`enableDanmakuSimilarityFilter`).
  final bool similarityEnabled;

  /// Similarity score that hides a text (`danmakuSimilarityThreshold`).
  final int similarityThreshold;

  /// How long a shown text is compared with, in seconds
  /// (`danmakuSimilarityCacheDuration`).
  final int similarityCacheSeconds;

  /// Most texts compared with (`danmakuSimilarityMaxCacheSize`).
  final int similarityMaxCacheSize;

  /// Blocked viewer names as stored (`blockedDanmakuUsers`).
  final List<String> blockedUsers;

  /// Blocked words as stored (`shieldList`).
  final List<String> blockedKeywords;
}

/// Decides which chat messages of one room reach the screen and the list,
/// in 3.x's order (`DanmakuController._installCallbacks`):
///
/// 1. the duplicate gate ([DanmakuMessageGate]), always;
/// 2. the block list ([DanmakuBlockList]), always;
/// 3. repeated-text collapsing ([RepeatedDanmakuFilter]) when enabled;
/// 4. the similarity filter ([DanmakuSimilarityFilter]) when enabled, for
///    platform messages only.
///
/// A platform gift goes through steps 1 and 2 only (D07.1: a gift repeats
/// on purpose, so neither collapsing nor similarity applies; a blocked word
/// in its text, `粉丝荧光棒 ×10`, blocks it). Local gifts and other message
/// types (audience figures, super chats) are not filtered.
final class DanmakuMessageFilter {
  /// Creates the filter with [settings]; [clock] times every step.
  new({DanmakuFilterSettings settings = const DanmakuFilterSettings(), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      similarity = DanmakuSimilarityFilter(clock: clock) {
    this.settings = settings;
  }

  final DateTime Function() _clock;

  /// Step 1.
  final DanmakuMessageGate gate = DanmakuMessageGate();

  /// Step 3.
  final RepeatedDanmakuFilter repeated = RepeatedDanmakuFilter();

  /// Step 4.
  final DanmakuSimilarityFilter similarity;

  late DanmakuBlockList _blockList;

  /// The settings in use.
  DanmakuFilterSettings get settings => _settings;
  late DanmakuFilterSettings _settings;

  /// Applies new settings to the following messages, without reconnecting:
  /// the block list is rebuilt; the similarity filter takes the new values,
  /// or forgets its texts when it is off.
  set settings(DanmakuFilterSettings value) {
    _settings = value;
    _blockList = DanmakuBlockList(users: value.blockedUsers, keywords: value.blockedKeywords);
    if (!value.similarityEnabled) {
      similarity.clear();
      return;
    }
    similarity.updateConfig(
      similarityThreshold: value.similarityThreshold,
      cacheDuration: Duration(seconds: value.similarityCacheSeconds),
      maxCacheSize: value.similarityMaxCacheSize,
    );
  }

  /// Whether [message] should be shown.
  bool accepts(LiveMessage message) {
    if (message.type == LiveMessageType.gift) return _acceptsGift(message);
    if (message.type != LiveMessageType.chat) return true;
    final now = _clock();
    if (!gate.accepts(message, now: now) || _blockList.blocks(message)) return false;
    final window = Duration(seconds: _settings.repeatedWindowSeconds.clamp(1, 30));
    if (!repeated.accepts(message, enabled: _settings.collapseRepeated, window: window, now: now)) return false;
    return message.isLocal || !_settings.similarityEnabled || similarity.shouldDisplay(message.message);
  }

  /// Steps 1 and 2 for a platform gift (D07.1).
  bool _acceptsGift(LiveMessage message) =>
      message.isLocal || (gate.accepts(message, now: _clock()) && !_blockList.blocks(message));

  /// Forgets everything seen (another room).
  void clear() {
    gate.clear();
    repeated.clear();
    similarity.clear();
  }
}
