import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/app/routes.dart';
import 'package:pure_live_app/core/sites.dart';
import 'package:pure_live_app/core/store.dart';
import 'package:pure_live_app/features/alerts/alert_notifier.dart';
import 'package:pure_live_app/features/diagnostics/app_log.dart';
import 'package:pure_live_app/features/diagnostics/diagnostics_page.dart';

/// A followed room's state as one refresh saw it.
@immutable
final class LiveObservation {
  /// Creates an observation.
  const new({required this.ref, required this.state, this.anchorName = '', this.title = '', this.liveSince});

  /// An observation of a fetched room page.
  factory fromDetail(RoomDetail detail) => LiveObservation(
    ref: detail.ref,
    state: detail.state,
    anchorName: detail.card.anchorName,
    title: detail.card.title,
    liveSince: detail.card.liveSince,
  );

  /// The room.
  final RoomRef ref;

  /// Its state now.
  final LiveState state;

  /// Streamer name; empty when the platform gave none.
  final String anchorName;

  /// Broadcast title.
  final String title;

  /// When the broadcast started, if the platform says.
  final DateTime? liveSince;

  @override
  String toString() => 'LiveObservation(${ref.key}, ${state.name})';
}

/// The last alert of a room, kept to alert once per broadcast (meta
/// [LiveAlertRules.recordsKey]; never backed up).
@immutable
final class LiveAlertRecord {
  /// Creates a record.
  const new({required this.notifiedAt, this.liveSince});

  /// When the alert went out.
  final DateTime notifiedAt;

  /// Start of the broadcast it announced, if the platform said.
  final DateTime? liveSince;

  /// JSON form.
  Map<String, Object?> toJson() => {
    'at': notifiedAt.millisecondsSinceEpoch,
    if (liveSince != null) 'since': liveSince!.millisecondsSinceEpoch,
  };

  /// Reads [toJson]; null when malformed.
  static LiveAlertRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final at = json['at'];
    final since = json['since'];
    if (at is! int) return null;
    return LiveAlertRecord(
      notifiedAt: DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
      liveSince: since is int ? DateTime.fromMillisecondsSinceEpoch(since, isUtc: true) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LiveAlertRecord && other.notifiedAt == notifiedAt && other.liveSince == liveSince;

  @override
  int get hashCode => Object.hash(notifiedAt, liveSince);
}

/// Rules of the live alerts (ADR draft-live-alerts).
abstract final class LiveAlertRules {
  /// Meta key of the per-room [LiveAlertRecord]s, a JSON object keyed by
  /// `platform:roomId`.
  static const recordsKey = 'alerts.liveRecords';

  /// Start times this close apart are the same broadcast (platforms round).
  static const sameStartSlack = Duration(minutes: 2);

  /// Without start times, a room announced this recently is not announced
  /// again: a brief "offline" between two refreshes is not a new broadcast.
  static const quietPeriod = Duration(minutes: 30);

  /// Records older than this are dropped.
  static const recordLifetime = Duration(days: 7);

  /// Up to this many rooms get one notification each; more are combined.
  static const maxSingleNotices = 3;

  /// Notification id of the combined notice.
  static const combinedNoticeId = 1;

  /// Names listed in the combined notice's body.
  static const combinedNames = 6;
}

/// What one refresh announces, and the records to store afterwards.
@immutable
final class LiveAlertPlan {
  /// Creates a plan.
  const new({required this.alerts, required this.records});

  /// Rooms that went live, in follow order.
  final List<LiveObservation> alerts;

  /// Records to store (pruned and updated).
  final Map<String, LiveAlertRecord> records;
}

/// Decides which rooms to announce after a refresh (F-NEW-01): a room is
/// announced when its stored state before the refresh ([before]) was known
/// and not live and the refresh saw it live; rooms in [optedOut] never are;
/// a broadcast already in [records] is not announced twice.
///
/// The stored state is what the previous refresh saw — in this run or, on
/// the first refresh after a cold start, in the last one — so both cases use
/// the same rule. Unknown (never checked) rooms are not announced, nor are
/// IPTV channels: they are always on air and have programme reminders.
LiveAlertPlan planLiveAlerts({
  required List<FollowedRoom> before,
  required Iterable<LiveObservation> observed,
  required Set<RoomRef> optedOut,
  required Map<String, LiveAlertRecord> records,
  required DateTime now,
}) {
  final seen = {for (final observation in observed) observation.ref: observation};
  final followed = {for (final follow in before) follow.ref.key};
  final kept = <String, LiveAlertRecord>{
    for (final MapEntry(:key, :value) in records.entries)
      if (followed.contains(key) && now.difference(value.notifiedAt) < LiveAlertRules.recordLifetime) key: value,
  };
  final alerts = <LiveObservation>[];
  for (final follow in before) {
    final observation = seen[follow.ref];
    if (observation == null || observation.state != LiveState.live) continue;
    if (follow.ref.platform == IptvSite.platformId) continue;
    final previous = follow.room.lastState;
    if (previous == null || previous == LiveState.live) continue;
    if (optedOut.contains(follow.ref)) continue;
    final record = kept[follow.ref.key];
    if (record != null && _sameBroadcast(record, observation, now)) continue;
    alerts.add(
      LiveObservation(
        ref: observation.ref,
        state: observation.state,
        // The page may omit the name; the stored card has it.
        anchorName: observation.anchorName.trim().isEmpty ? follow.room.anchorName : observation.anchorName,
        title: observation.title,
        liveSince: observation.liveSince,
      ),
    );
    kept[follow.ref.key] = LiveAlertRecord(notifiedAt: now, liveSince: observation.liveSince);
  }
  return LiveAlertPlan(alerts: alerts, records: kept);
}

bool _sameBroadcast(LiveAlertRecord record, LiveObservation observation, DateTime now) {
  final since = observation.liveSince;
  final recorded = record.liveSince;
  if (since != null && recorded != null) {
    return since.difference(recorded).abs() <= LiveAlertRules.sameStartSlack;
  }
  return now.difference(record.notifiedAt) < LiveAlertRules.quietPeriod;
}

/// The notifications for [alerts]: one each up to
/// [LiveAlertRules.maxSingleNotices], otherwise one combined notice that
/// opens the follows page's live tab.
List<AlertNotice> liveAlertNotices(List<LiveObservation> alerts) {
  String name(LiveObservation alert) => alert.anchorName.trim().isEmpty ? alert.ref.roomId : alert.anchorName.trim();
  if (alerts.isEmpty) return const [];
  if (alerts.length <= LiveAlertRules.maxSingleNotices) {
    return [
      for (final alert in alerts)
        AlertNotice(
          id: alertIdOf('live:${alert.ref.key}'),
          channel: AlertChannel.live,
          title: '${name(alert)} 开播了',
          body: [
            platformNames[alert.ref.platform] ?? alert.ref.platform,
            if (alert.title.trim().isNotEmpty) alert.title.trim(),
          ].join(' · '),
          payload: roomLocation(alert.ref),
        ),
    ];
  }
  final names = alerts.map(name).toList();
  final listed = names.take(LiveAlertRules.combinedNames).join('、');
  return [
    AlertNotice(
      id: LiveAlertRules.combinedNoticeId,
      channel: AlertChannel.live,
      title: '${names.first}等 ${alerts.length} 位主播开播了',
      body: names.length > LiveAlertRules.combinedNames ? '$listed 等' : listed,
      payload: followsLiveLocation,
    ),
  ];
}

/// Announces rooms that went live after each follow refresh (F-NEW-01).
final class LiveAlertService {
  /// Creates the service.
  new({required this.store, required this.notifier, required this.log, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// The database: settings, opt-outs and records.
  final LiveStore store;

  /// Where notifications go.
  final AlertNotifier notifier;

  /// Failures are logged, never thrown into the refresh.
  final AppLog log;

  final DateTime Function() _now;
  Future<void> _tail = Future.value();

  /// Plans and shows the alerts for one refresh: [before] are the follows as
  /// stored before it, [observed] what it saw. Returns the notices shown.
  /// Calls run one after another, so two overlapping refreshes see each
  /// other's records.
  Future<List<AlertNotice>> afterRefresh(List<FollowedRoom> before, List<LiveObservation> observed) {
    final result = _tail.then((_) => _afterRefresh(before, observed));
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<List<AlertNotice>> _afterRefresh(List<FollowedRoom> before, List<LiveObservation> observed) async {
    if (!store.settings.get(Settings.liveAlerts) || !notifier.supported || observed.isEmpty) return const [];
    final records = await readRecords();
    final plan = planLiveAlerts(
      before: before,
      observed: observed,
      optedOut: await store.roomPrefs.liveAlertsOff(),
      records: records,
      now: _now().toUtc(),
    );
    // Stored before the notices go out: a crash in between never repeats one.
    if (!mapEquals(plan.records, records)) await writeRecords(plan.records);
    final notices = liveAlertNotices(plan.alerts);
    for (final notice in notices) {
      try {
        await notifier.show(notice);
      } on Object catch (error) {
        log.warning('alerts', 'notification failed', error);
      }
    }
    return notices;
  }

  /// The stored records; empty when none or unreadable.
  Future<Map<String, LiveAlertRecord>> readRecords() async {
    final text = await store.meta.get(LiveAlertRules.recordsKey);
    if (text == null) return {};
    try {
      final json = jsonDecode(text);
      if (json is! Map) return {};
      return {
        for (final MapEntry(:key, :value) in json.entries)
          if (key is String) key: ?LiveAlertRecord.fromJson(value),
      };
    } on FormatException {
      return {};
    }
  }

  /// Replaces the stored records.
  Future<void> writeRecords(Map<String, LiveAlertRecord> records) => store.meta.set(
    LiveAlertRules.recordsKey,
    records.isEmpty ? null : jsonEncode({for (final MapEntry(:key, :value) in records.entries) key: value.toJson()}),
  );
}

/// The live alert service of the app.
final liveAlertServiceProvider = Provider<LiveAlertService>(
  (ref) => LiveAlertService(
    store: ref.watch(storeProvider),
    notifier: ref.watch(alertNotifierProvider),
    log: ref.watch(appLogProvider),
  ),
);

/// The global live alert switch.
final liveAlertsSetting = NotifierProvider<SettingNotifier<bool>, bool>(() => SettingNotifier(Settings.liveAlerts));

/// Rooms that opted out of live alerts, live.
final liveAlertsOffProvider = StreamProvider<Set<RoomRef>>(
  (ref) => ref.watch(storeProvider).roomPrefs.watchLiveAlertsOff(),
);
