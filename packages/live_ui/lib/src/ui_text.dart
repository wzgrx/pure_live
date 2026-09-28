import 'package:flutter/foundation.dart';

/// The few words live_ui shows by itself: badges, default buttons, the room
/// card's spoken label and the count and relative-time formats.
///
/// live_ui has no translations of its own (it cannot depend on the app). It
/// starts in Simplified Chinese; the app replaces [current] with the
/// interface language's text whenever the language changes and rebuilds
/// (spec/product.md F-APP-06).
@immutable
final class LiveUiText {
  /// Creates the text set.
  const new({
    required this.live,
    required this.liveFor,
    required this.liveNow,
    required this.offline,
    required this.recording,
    required this.separator,
    required this.retry,
    required this.ok,
    required this.cancel,
    required this.loading,
    required this.justNow,
    required this.minutesAgo,
    required this.hoursAgo,
    required this.daysAgo,
    required this.countBase,
    required this.countUnits,
  }) : assert(countBase > 1, 'a count base is at least 2');

  /// The built-in Simplified Chinese text (the base language).
  static const LiveUiText simplifiedChinese = LiveUiText(
    live: '直播',
    liveFor: _liveForHans,
    liveNow: '直播中',
    offline: '未开播',
    recording: '录制中',
    separator: '，',
    retry: '重试',
    ok: '确定',
    cancel: '取消',
    loading: '正在加载',
    justNow: '刚刚',
    minutesAgo: _minutesAgoHans,
    hoursAgo: _hoursAgoHans,
    daysAgo: _daysAgoHans,
    countBase: 10000,
    countUnits: ['万', '亿'],
  );

  /// The text in use; the app sets it with the interface language.
  static LiveUiText current = simplifiedChinese;

  /// The "live" badge.
  final String live;

  /// The "live" badge with the live duration.
  final String Function(String duration) liveFor;

  /// Spoken state of a live room.
  final String liveNow;

  /// Spoken state of an offline room.
  final String offline;

  /// The recording mark.
  final String recording;

  /// Joins the parts of a spoken label ("，" in Chinese, ", " in English).
  final String separator;

  /// Default label of an error view's action.
  final String retry;

  /// Default label of a primary action.
  final String ok;

  /// Default label of a secondary action.
  final String cancel;

  /// Spoken label of a loading skeleton.
  final String loading;

  /// Less than a minute ago.
  final String justNow;

  /// N minutes ago.
  final String Function(int minutes) minutesAgo;

  /// N hours ago.
  final String Function(int hours) hoursAgo;

  /// N days ago.
  final String Function(int days) daysAgo;

  /// Grouping of short counts: 10000 for 万 / 亿, 1000 for K / M / B.
  final int countBase;

  /// Units of short counts for countBase, countBase², countBase³ …
  final List<String> countUnits;

  static String _liveForHans(String duration) => '直播 $duration';
  static String _minutesAgoHans(int minutes) => '$minutes 分钟前';
  static String _hoursAgoHans(int hours) => '$hours 小时前';
  static String _daysAgoHans(int days) => '$days 天前';
}
