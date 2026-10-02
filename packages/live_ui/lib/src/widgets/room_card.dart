import 'package:flutter/material.dart';

/// What an audience figure counts (3.x `AudienceMetricType`).
enum RoomAudienceKind {
  /// Popularity or heat.
  popularity,

  /// Viewers online now.
  onlineViewers,

  /// Total views.
  totalViewers,

  /// Followers.
  followers,

  /// Not known.
  unknown,
}

/// The audience a card shows: its kind and the figure already formatted by
/// the app (`1.2万`); an empty [value] shows "pending" (3.x
/// `audience_waiting`).
@immutable
final class RoomAudience {
  /// Creates the figure.
  const new({required this.kind, required this.value});

  /// What it counts.
  final RoomAudienceKind kind;

  /// The formatted figure.
  final String value;

  @override
  bool operator ==(Object other) => other is RoomAudience && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// What a room card shows, mapped by the app from its room model.
@immutable
final class RoomCardData {
  /// Creates the data.
  const new({
    required this.platformId,
    required this.title,
    required this.anchorName,
    this.avatarUrl,
    this.coverUrl,
    this.isLive = false,
    this.isReplay = false,
    this.audience,
    this.restrictionLabel,
    this.platformName,
    this.isOffline = false,
  });

  /// Platform id; the badge shows it in capitals (3.x).
  final String platformId;

  /// Broadcast title.
  final String title;

  /// Streamer's name.
  final String anchorName;

  /// Avatar address (normalised by the app).
  final String? avatarUrl;

  /// Cover address (normalised by the app); empty or null shows the fallback.
  final String? coverUrl;

  /// Live now: the audience shows only then.
  final bool isLive;

  /// A replay (3.x `isRecord`).
  final bool isReplay;

  /// The audience figure.
  final RoomAudience? audience;

  /// Why the room cannot simply be played (paid, password, app only, region
  /// …), as the words to show; null shows nothing (docs/UPGRADES.md: "卡片
  /// 标出受限类型").
  final String? restrictionLabel;

  /// The platform's name to show beside its logo (`LiveRoomCard`'s platform
  /// chip, U.4a c2); null shows the id in capitals.
  final String? platformName;

  /// The platform says the streamer is off (offline, banned, carousel): the
  /// cover is dimmed and marked (`LiveRoomCard`, U.4a c4).
  final bool isOffline;

  @override
  bool operator ==(Object other) =>
      other is RoomCardData &&
      other.platformId == platformId &&
      other.title == title &&
      other.anchorName == anchorName &&
      other.avatarUrl == avatarUrl &&
      other.coverUrl == coverUrl &&
      other.isLive == isLive &&
      other.isReplay == isReplay &&
      other.audience == audience &&
      other.restrictionLabel == restrictionLabel &&
      other.platformName == platformName &&
      other.isOffline == isOffline;

  @override
  int get hashCode => Object.hash(
    platformId,
    title,
    anchorName,
    avatarUrl,
    coverUrl,
    isLive,
    isReplay,
    audience,
    restrictionLabel,
    platformName,
    isOffline,
  );
}
