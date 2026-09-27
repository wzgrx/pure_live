import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_danmaku/live_danmaku.dart' show DanmakuFilterSettings;
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart' show DanmakuBudget, DanmakuStyle;
import 'package:pure_live_app/core/store.dart';

/// The danmaku settings of `live_store` as one snapshot, so the room applies
/// a change in one place (FLT-6: filters without reconnecting; principle 3:
/// style changes act on the playing picture).
@immutable
final class DanmakuPrefs {
  const new({
    required this.enabled,
    required this.hidden,
    required this.style,
    required this.autoFps,
    required this.fps,
    required this.refreshRate,
    required this.tapActions,
    required this.longPressActions,
    required this.filters,
  });

  /// Reads every danmaku setting from [settings].
  factory of(SettingsStore settings) => DanmakuPrefs(
    enabled: settings.get(Settings.danmakuEnabled),
    hidden: settings.get(Settings.danmakuHidden),
    style: DanmakuStyle(
      fontSize: settings.get(Settings.danmakuFontSize),
      fontWeight: settings.get(Settings.danmakuFontWeight),
      opacity: settings.get(Settings.danmakuOpacity),
      speed: settings.get(Settings.danmakuSpeed),
      area: settings.get(Settings.danmakuArea),
      topMargin: settings.get(Settings.danmakuTopArea),
      bottomMargin: settings.get(Settings.danmakuBottomArea),
      stroke: settings.get(Settings.danmakuStroke),
      strokeWidth: settings.get(Settings.danmakuStrokeWidth),
      noEmoji: settings.get(Settings.danmakuNoEmoji),
    ),
    autoFps: settings.get(Settings.danmakuAutoFps),
    fps: settings.get(Settings.danmakuFps),
    refreshRate: settings.get(Settings.refreshRateMode),
    tapActions: settings.get(Settings.danmakuTapInteraction),
    longPressActions: settings.get(Settings.danmakuLongPressInteraction),
    filters: DanmakuFilterSettings(
      mergeRepeats: settings.get(Settings.danmakuCollapseRepeated),
      repeatWindow: Duration(seconds: settings.get(Settings.danmakuRepeatedWindowSeconds)),
      similarity: settings.get(Settings.danmakuSimilarityFilter),
      similarityThreshold: settings.get(Settings.danmakuSimilarityThreshold),
      similarityWindow: Duration(seconds: settings.get(Settings.danmakuSimilarityCacheDuration)),
      similarityCacheSize: settings.get(Settings.danmakuSimilarityMaxCacheSize),
      hideSuspectedBots: settings.get(Settings.danmakuFilterDouyuAutomated),
    ),
  );

  /// "显示弹幕": off hides the danmaku button and disconnects (F-DM-01).
  final bool enabled;

  /// The player's on-video toggle, remembered between rooms.
  final bool hidden;

  /// On-video look.
  final DanmakuStyle style;

  /// Frame rate follows the refresh-rate policy (REN-3).
  final bool autoFps;

  /// Fixed frame rate when [autoFps] is off.
  final int fps;

  /// The app's refresh-rate policy, for [autoFps].
  final RefreshRateMode refreshRate;

  /// Tapping an on-video danmaku opens its actions (F-DM-05).
  final bool tapActions;

  /// Long-pressing an on-video danmaku opens its actions (F-DM-05).
  final bool longPressActions;

  /// FLT-3 to FLT-5, without the block lists (those live in `blockRules`).
  final DanmakuFilterSettings filters;

  /// The room surface's budget (REN-4) at the resolved frame rate (REN-3).
  DanmakuBudget get budget => const DanmakuBudget().withFps(resolveDanmakuFps(this));

  /// A copy with [hidden] replaced.
  DanmakuPrefs withHidden({required bool hidden}) => DanmakuPrefs(
    enabled: enabled,
    hidden: hidden,
    style: style,
    autoFps: autoFps,
    fps: fps,
    refreshRate: refreshRate,
    tapActions: tapActions,
    longPressActions: longPressActions,
    filters: filters,
  );

  /// A copy with [enabled] replaced.
  DanmakuPrefs withEnabled({required bool enabled}) => DanmakuPrefs(
    enabled: enabled,
    hidden: hidden,
    style: style,
    autoFps: autoFps,
    fps: fps,
    refreshRate: refreshRate,
    tapActions: tapActions,
    longPressActions: longPressActions,
    filters: filters,
  );
}

/// REN-3 for the room surface: power saving and balanced cap the layer at
/// 60 fps, performance follows the display (null); a manual rate wins.
int? resolveDanmakuFps(DanmakuPrefs prefs) {
  if (!prefs.autoFps) return prefs.fps;
  return switch (prefs.refreshRate) {
    RefreshRateMode.powerSaving || RefreshRateMode.balanced => 60,
    RefreshRateMode.performance => null,
  };
}

/// Ids of every setting [DanmakuPrefs] reads.
final Set<String> _danmakuSettingIds = {
  for (final setting in Settings.all)
    if (setting.id.startsWith('danmaku.')) setting.id,
  Settings.refreshRateMode.id,
};

/// The current [DanmakuPrefs]; follows setting changes. The two switches the
/// room flips ([setHidden], [setEnabled]) apply at once and are stored in the
/// background, so a toggle never waits for the database.
class DanmakuPrefsNotifier extends Notifier<DanmakuPrefs> {
  @override
  DanmakuPrefs build() {
    final settings = ref.watch(storeProvider).settings;
    final subscription = settings.changes
        .where(_danmakuSettingIds.contains)
        .listen((_) => state = DanmakuPrefs.of(settings));
    ref.onDispose(subscription.cancel);
    return DanmakuPrefs.of(settings);
  }

  /// Shows or hides danmaku on the video (the D key, the player button).
  void setHidden({required bool hidden}) {
    state = state.withHidden(hidden: hidden);
    unawaited(ref.read(storeProvider).settings.set(Settings.danmakuHidden, hidden));
  }

  /// Turns danmaku on or off altogether ("显示弹幕").
  void setEnabled({required bool enabled}) {
    state = state.withEnabled(enabled: enabled);
    unawaited(ref.read(storeProvider).settings.set(Settings.danmakuEnabled, enabled));
  }
}

/// The danmaku settings as one value.
final NotifierProvider<DanmakuPrefsNotifier, DanmakuPrefs> danmakuPrefsProvider =
    NotifierProvider<DanmakuPrefsNotifier, DanmakuPrefs>(DanmakuPrefsNotifier.new);

/// Blocked words and users (`store.blockRules`), re-emitted after changes.
final StreamProvider<List<BlockRule>> blockRulesProvider = StreamProvider<List<BlockRule>>(
  (ref) => ref.watch(storeProvider).blockRules.watchAll(),
);

/// Adds and removes block rules; tests replace it.
abstract interface class BlockRuleWriter {
  /// Blocks [value]; false when it is blank or already blocked.
  Future<bool> add(BlockKind kind, String value);

  /// Unblocks [value]; false when it was not blocked.
  Future<bool> remove(BlockKind kind, String value);
}

final class _StoreBlockRuleWriter implements BlockRuleWriter {
  new(this._rules);

  final BlockRuleStore _rules;

  @override
  Future<bool> add(BlockKind kind, String value) => _rules.add(kind, value);

  @override
  Future<bool> remove(BlockKind kind, String value) => _rules.remove(kind, value);
}

/// Writes block rules to the store.
final Provider<BlockRuleWriter> blockRuleWriterProvider = Provider<BlockRuleWriter>(
  (ref) => _StoreBlockRuleWriter(ref.watch(storeProvider).blockRules),
);

/// The pipeline's filter settings: [prefs]' filters plus [rules] (FLT-2).
DanmakuFilterSettings filterSettingsFor(DanmakuPrefs prefs, List<BlockRule> rules) => prefs.filters.copyWith(
  blockedUsers: [
    for (final rule in rules)
      if (rule.kind == BlockKind.user) rule.value,
  ],
  blockedWords: [
    for (final rule in rules)
      if (rule.kind == BlockKind.keyword) rule.value,
  ],
);
