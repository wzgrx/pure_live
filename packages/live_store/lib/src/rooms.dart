import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/src/database/database.dart';
import 'package:meta/meta.dart';

/// What the app knows about a room when it follows, watches or refreshes it.
///
/// Null fields leave the stored value unchanged, so a search result without
/// an avatar does not erase the one saved from the room page.
@immutable
final class RoomSnapshot {
  /// Creates a snapshot.
  const new({
    required this.ref,
    this.anchorName,
    this.title,
    this.avatar,
    this.cover,
    this.area,
    this.userId,
    this.audience = Audience.none,
    this.state,
  });

  /// A snapshot of a room card.
  factory fromCard(RoomCard card) => RoomSnapshot(
    ref: card.ref,
    anchorName: card.anchorName,
    title: card.title,
    avatar: card.avatar,
    cover: card.cover,
    area: card.area,
    audience: card.audience,
    state: card.state,
  );

  /// A snapshot of a room page.
  factory fromDetail(RoomDetail detail) => RoomSnapshot(
    ref: detail.ref,
    anchorName: detail.card.anchorName,
    title: detail.card.title,
    avatar: detail.avatar ?? detail.card.avatar,
    cover: detail.card.cover,
    area: detail.card.area,
    audience: detail.card.audience,
    state: detail.state,
  );

  /// Room identity.
  final RoomRef ref;

  /// Streamer's display name.
  final String? anchorName;

  /// Broadcast title.
  final String? title;

  /// Streamer's avatar.
  final Uri? avatar;

  /// Cover image.
  final Uri? cover;

  /// Area name.
  final String? area;

  /// Streamer's user id on the platform.
  final String? userId;

  /// Audience figures; missing measures keep their stored values.
  final Audience audience;

  /// Live state at the time of the snapshot; null when not checked.
  final LiveState? state;
}

/// A room as stored: identity plus the last known card data.
@immutable
final class StoredRoom {
  /// Creates a stored room.
  const new({
    required this.ref,
    required this.anchorName,
    required this.title,
    required this.updatedAt,
    this.avatar,
    this.cover,
    this.area,
    this.userId,
    this.audience = Audience.none,
    this.lastState,
    this.lastLiveAt,
  });

  /// Room identity.
  final RoomRef ref;

  /// Streamer's display name; empty when never seen.
  final String anchorName;

  /// Last known title; empty when never seen.
  final String title;

  /// Streamer's avatar.
  final Uri? avatar;

  /// Last known cover.
  final Uri? cover;

  /// Last known area name.
  final String? area;

  /// Streamer's user id on the platform.
  final String? userId;

  /// Audience figures at the last refresh.
  final Audience audience;

  /// Last known state; null when unknown. A cache: the follow page shows every
  /// room as unknown until the first refresh after launch (store.md §6.4.10).
  final LiveState? lastState;

  /// When the room was last seen live.
  final DateTime? lastLiveAt;

  /// When this data last changed.
  final DateTime updatedAt;

  @override
  String toString() => 'StoredRoom(${ref.key})';
}

/// Row helpers shared by the stores; not part of the public API.
@internal
abstract final class RoomRows {
  /// Inserts or updates the room of [snapshot] and returns its row id. With
  /// [seenNow] (the default) a live state also records [now] as the last
  /// live time; imports pass false because their state is only a cache.
  static Future<int> upsert(
    StoreDatabase db,
    RoomSnapshot snapshot, {
    DateTime? now,
    Map<String, Object?>? extra,
    bool seenNow = true,
  }) async {
    final at = (now ?? DateTime.now()).toUtc();
    final existing = await find(db, snapshot.ref);
    var companion = _companion(snapshot, at, seenNow: seenNow);
    if (extra != null && extra.isNotEmpty) {
      final merged = {if (existing != null) ...RoomRows.extra(existing), ...extra};
      companion = companion.copyWith(extra: Value(jsonEncode(merged)));
    }
    if (existing == null) {
      return await db
          .into(db.rooms)
          .insert(companion.copyWith(platform: Value(snapshot.ref.platform), roomId: Value(snapshot.ref.roomId)));
    }
    await (db.update(db.rooms)..where((row) => row.id.equals(existing.id))).write(companion);
    return existing.id;
  }

  /// Returns the row id of [ref], creating an identity-only row if needed.
  static Future<int> ensure(StoreDatabase db, RoomRef ref) async {
    final existing = await find(db, ref);
    if (existing != null) return existing.id;
    return await db
        .into(db.rooms)
        .insert(
          RoomsCompanion.insert(
            platform: ref.platform,
            roomId: ref.roomId,
            updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  }

  /// The row of [ref], or null.
  static Future<RoomRow?> find(StoreDatabase db, RoomRef ref) => (db.select(
    db.rooms,
  )..where((row) => row.platform.equals(ref.platform) & row.roomId.equals(ref.roomId))).getSingleOrNull();

  /// Converts a row to the public model.
  static StoredRoom toModel(RoomRow row) => StoredRoom(
    ref: RoomRef(row.platform, row.roomId),
    anchorName: row.nick,
    title: row.title,
    avatar: _uri(row.avatar),
    cover: _uri(row.cover),
    area: row.area,
    userId: row.userId,
    audience: Audience(online: row.onlineViewers, popularity: row.popularity, cumulative: row.totalViewers),
    lastState: stateFromName(row.lastStatus),
    lastLiveAt: _time(row.lastLiveAt),
    updatedAt: _time(row.updatedAt)!,
  );

  /// The stored name of [state].
  static String? stateName(LiveState? state) => state?.name;

  /// Parses a stored state name.
  static LiveState? stateFromName(String? name) {
    for (final state in LiveState.values) {
      if (state.name == name) return state;
    }
    return null;
  }

  /// Parses the `extra` JSON column.
  static Map<String, Object?> extra(RoomRow row) {
    final text = row.extra;
    if (text == null || text.isEmpty) return const {};
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, Object?> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  static RoomsCompanion _companion(RoomSnapshot snapshot, DateTime at, {required bool seenNow}) {
    String? text(String? value) => value == null || value.trim().isEmpty ? null : value.trim();
    Value<T> keep<T>(T? value) => value == null ? const Value.absent() : Value(value);
    final nick = text(snapshot.anchorName);
    final title = snapshot.title;
    final state = snapshot.state;
    return RoomsCompanion(
      nick: nick == null ? const Value.absent() : Value(nick),
      title: title == null ? const Value.absent() : Value(title),
      avatar: keep(text(snapshot.avatar?.toString())),
      cover: keep(text(snapshot.cover?.toString())),
      area: keep(text(snapshot.area)),
      userId: keep(text(snapshot.userId)),
      onlineViewers: keep(snapshot.audience.online),
      popularity: keep(snapshot.audience.popularity),
      totalViewers: keep(snapshot.audience.cumulative),
      lastStatus: keep(stateName(state)),
      lastLiveAt: seenNow && state == LiveState.live ? Value(at.millisecondsSinceEpoch) : const Value.absent(),
      updatedAt: Value(at.millisecondsSinceEpoch),
    );
  }

  static Uri? _uri(String? text) => text == null || text.isEmpty ? null : Uri.tryParse(text);

  static DateTime? _time(int? millis) =>
      millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
}
