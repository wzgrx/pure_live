import 'package:meta/meta.dart';

/// The user's filter settings (spec/modules/danmaku.md §3); changes apply to
/// the next message without reconnecting (FLT-6).
@immutable
final class DanmakuFilterSettings {
  /// Creates settings; the defaults are the spec's (repeat merging, the
  /// similarity filter and the Douyu bot filter off: REG-DANMAKU-006, -007).
  const new({
    this.blockedUsers = const [],
    this.blockedWords = const [],
    this.mergeRepeats = false,
    this.repeatWindow = const Duration(seconds: 5),
    this.similarity = false,
    this.similarityThreshold = 85,
    this.similarityWindow = const Duration(seconds: 3),
    this.similarityCacheSize = 100,
    this.hideSuspectedBots = false,
  });

  /// FLT-2 user names, matched exactly after normalisation.
  final List<String> blockedUsers;

  /// FLT-2 words, matched as substrings after normalisation.
  final List<String> blockedWords;

  /// FLT-3 merge repeated text.
  final bool mergeRepeats;

  /// FLT-3 window, 1–30 s.
  final Duration repeatWindow;

  /// FLT-4 similarity filter.
  final bool similarity;

  /// FLT-4 threshold, 50–100.
  final int similarityThreshold;

  /// FLT-4 cache time, 1–60 s.
  final Duration similarityWindow;

  /// FLT-4 cache size, 20–1000.
  final int similarityCacheSize;

  /// FLT-5 hide Douyu's suspected bots.
  final bool hideSuspectedBots;

  /// A copy with the given fields replaced.
  DanmakuFilterSettings copyWith({
    List<String>? blockedUsers,
    List<String>? blockedWords,
    bool? mergeRepeats,
    Duration? repeatWindow,
    bool? similarity,
    int? similarityThreshold,
    Duration? similarityWindow,
    int? similarityCacheSize,
    bool? hideSuspectedBots,
  }) => DanmakuFilterSettings(
    blockedUsers: blockedUsers ?? this.blockedUsers,
    blockedWords: blockedWords ?? this.blockedWords,
    mergeRepeats: mergeRepeats ?? this.mergeRepeats,
    repeatWindow: repeatWindow ?? this.repeatWindow,
    similarity: similarity ?? this.similarity,
    similarityThreshold: similarityThreshold ?? this.similarityThreshold,
    similarityWindow: similarityWindow ?? this.similarityWindow,
    similarityCacheSize: similarityCacheSize ?? this.similarityCacheSize,
    hideSuspectedBots: hideSuspectedBots ?? this.hideSuspectedBots,
  );
}

/// How many screen candidates per second the surface can use (SMP-1, SMP-3):
/// its emit rate times a margin.
@immutable
final class DanmakuScreenBudget {
  /// Creates a budget of [perSecond] candidates.
  const new(this.perSecond);

  /// A surface emitting one message per [interval], with [margin] (SMP-1:
  /// 1.5, to be calibrated on 200 msg/s recordings).
  factory emitting(Duration interval, {double margin = 1.5}) =>
      DanmakuScreenBudget(margin * Duration.microsecondsPerSecond / interval.inMicroseconds);

  /// The room surface: one per 50 ms (REN-4).
  static final room = DanmakuScreenBudget.emitting(const Duration(milliseconds: 50));

  /// Picture-in-picture: one per 350 ms (REN-6).
  static final pip = DanmakuScreenBudget.emitting(const Duration(milliseconds: 350));

  /// No screen (the danmaku layer is off): no candidates.
  static const none = DanmakuScreenBudget(0);

  /// Candidates per second.
  final double perSecond;
}
