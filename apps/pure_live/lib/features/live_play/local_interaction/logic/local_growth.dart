import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Starts a periodic timer ([Timer.periodic] by default; tests hand in their
/// own, D-017).
typedef LocalTimerFactory = Timer Function(Duration period, void Function(Timer timer) tick);

/// What local growth gave on one local day (D08.3): stored as JSON in
/// `localInteraction.growthDay`, read against the day of now, so the counts
/// start from nothing on the next day without anything having to run at
/// midnight.
///
/// The day is the device's own calendar day (its time zone, midnight to
/// midnight): the one the user sees on the clock. Another day stored reads
/// as nothing given, whichever way the clock moved.
@immutable
final class LocalGrowthDay {
  /// Creates the counts of [day] (`yyyy-MM-dd`, [dayOf]).
  const new({
    required this.day,
    this.watched = Duration.zero,
    this.watchExperience = 0,
    this.checkedIn = false,
    this.chatExperience = 0,
  });

  /// The counts of [day] in [json]: what it holds when it is [day]'s,
  /// nothing given otherwise.
  factory read(String json, String day) {
    final stored = parse(json);
    return stored != null && stored.day == day ? stored : LocalGrowthDay(day: day);
  }

  /// The counts stored in [json], whatever their day; null when there are
  /// none or they cannot be read (a hand-edited backup). Numbers below zero
  /// read as zero.
  static LocalGrowthDay? parse(String json) {
    final decoded = _decode(json);
    if (decoded is! Map) return null;
    final Map<Object?, Object?> data = decoded;
    final day = data['day'];
    if (day is! String || day.isEmpty) return null;
    int number(String key) => switch (data[key]) {
      final num value when value > 0 => value.toInt(),
      _ => 0,
    };
    return LocalGrowthDay(
      day: day,
      watched: Duration(milliseconds: number('watchedMs')),
      watchExperience: number('watchExp'),
      checkedIn: data['checkedIn'] == true,
      chatExperience: number('chatExp'),
    );
  }

  static Object? _decode(String json) {
    if (json.isEmpty) return null;
    try {
      return jsonDecode(json);
    } on FormatException {
      return null;
    }
  }

  /// The local day of [at]: `yyyy-MM-dd`, which sorts as the days do.
  static String dayOf(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-${two(local.day)}';
  }

  /// The local midnight that ends the day of [at].
  static DateTime endOfDay(DateTime at) {
    final local = at.toLocal();
    return DateTime(local.year, local.month, local.day + 1);
  }

  /// The local day these are the counts of.
  final String day;

  /// How long a room played that day (whole steps or not).
  final Duration watched;

  /// The experience watching gave that day.
  final int watchExperience;

  /// Whether the first room of the day gave its check-in.
  final bool checkedIn;

  /// The experience local danmaku gave that day.
  final int chatExperience;

  /// A copy with the counts given.
  LocalGrowthDay copyWith({Duration? watched, int? watchExperience, bool? checkedIn, int? chatExperience}) =>
      LocalGrowthDay(
        day: day,
        watched: watched ?? this.watched,
        watchExperience: watchExperience ?? this.watchExperience,
        checkedIn: checkedIn ?? this.checkedIn,
        chatExperience: chatExperience ?? this.chatExperience,
      );

  /// The stored form.
  String encode() => jsonEncode({
    'day': day,
    'watchedMs': watched.inMilliseconds,
    'watchExp': watchExperience,
    'checkedIn': checkedIn,
    'chatExp': chatExperience,
  });

  @override
  bool operator ==(Object other) => other is LocalGrowthDay && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;

  @override
  String toString() => 'LocalGrowthDay(${encode()})';
}

/// The clock of watch time (D08.3 c2): while [update] says it counts, the
/// time passing is handed to [onWatched] once a [tick] and when it stops
/// counting; [onSettle] then stores what was handed over (the owner keeps
/// it in memory meanwhile, so nothing is written every minute).
///
/// The tick is a minute (D-017: never under a second) and runs only while
/// counting; nothing runs in the background. A gap longer than
/// [longestGap] between two looks at the clock (the clock set forward, a
/// device asleep without telling the app) counts as [longestGap] only, and
/// a clock set back counts nothing.
final class LocalWatchTime {
  /// Creates the clock, not counting; `now` tells the time (a fake one in
  /// tests), [periodic] starts the tick.
  new({required this.onWatched, required this.onSettle, required this._now, LocalTimerFactory? periodic})
    : _periodic = periodic ?? Timer.periodic;

  /// How often the time is handed over while counting.
  static const Duration tick = Duration(minutes: 1);

  /// The most one look at the clock counts.
  static const Duration longestGap = Duration(minutes: 5);

  /// Takes the time watched from `from` to `to`.
  final void Function(DateTime from, DateTime to) onWatched;

  /// Stores what [onWatched] took (counting stopped).
  final void Function() onSettle;

  final DateTime Function() _now;
  final LocalTimerFactory _periodic;
  Timer? _timer;
  DateTime? _since;
  bool _disposed = false;

  /// Whether the time counts now.
  bool get counting => _since != null;

  /// Starts or stops counting; stopping hands over the time since the last
  /// tick and settles.
  void update({required bool counting}) {
    if (_disposed || counting == this.counting) return;
    if (counting) {
      _since = _now();
      _timer = _periodic(tick, (_) => _handOver());
      return;
    }
    _handOver();
    _timer?.cancel();
    _timer = null;
    _since = null;
    onSettle();
  }

  void _handOver() {
    final since = _since;
    if (since == null) return;
    final now = _now();
    _since = now;
    if (!now.isAfter(since)) return;
    final from = now.difference(since) > longestGap ? now.subtract(longestGap) : since;
    onWatched(from, now);
  }

  /// Stops counting (settling what counted) and the tick.
  void dispose() {
    if (_disposed) return;
    update(counting: false);
    _disposed = true;
  }
}
