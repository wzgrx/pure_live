import 'package:live_core/src/audience.dart';
import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:meta/meta.dart';

/// What a room card shows (ADR 0010, rule 4).
@immutable
final class RoomCard {
  /// Creates a card.
  const new({
    required this.ref,
    required this.title,
    required this.anchorName,
    required this.state,
    this.cover,
    this.area,
    this.audience = Audience.none,
    this.liveSince,
    this.avatar,
  });

  /// Normalised room identity.
  final RoomRef ref;

  /// Broadcast title, with HTML entities decoded.
  final String title;

  /// Streamer's display name.
  final String anchorName;

  /// Live, offline or replay.
  final LiveState state;

  /// Cover image; null when the platform has none (the UI shows a placeholder).
  final Uri? cover;

  /// Category or area name.
  final String? area;

  /// Audience figures.
  final Audience audience;

  /// When the current broadcast started, if the platform says.
  final DateTime? liveSince;

  /// Streamer's avatar when the list provides one (search results, the 3.3.x
  /// bridge); v4 room cards do not show it.
  final Uri? avatar;
}

/// A room's detail page data: the card plus what the room page needs.
@immutable
final class RoomDetail {
  /// Creates a detail.
  const new({
    required this.card,
    required this.link,
    this.avatar,
    this.introduction,
    this.notice,
    this.danmakuKeys = const {},
  });

  /// Card fields.
  final RoomCard card;

  /// The room on the platform's own site.
  final Uri link;

  /// Streamer's avatar.
  final Uri? avatar;

  /// Room introduction.
  final String? introduction;

  /// Pinned notice.
  final String? notice;

  /// Platform-specific values the danmaku connector needs (room id, channel
  /// ids); read only by that platform's connector.
  final Map<String, String> danmakuKeys;

  /// Shortcut for [RoomCard.ref].
  RoomRef get ref => card.ref;

  /// Shortcut for [RoomCard.state].
  LiveState get state => card.state;
}

/// A platform category (top level) with its areas.
@immutable
final class Category {
  /// Creates a category.
  const new({required this.id, required this.name, this.areas = const []});

  /// Platform id.
  final String id;

  /// Display name.
  final String name;

  /// Areas in platform order.
  final List<Area> areas;
}

/// A browsable area inside a category.
@immutable
final class Area {
  /// Creates an area.
  const new({required this.id, required this.name, required this.categoryId, this.icon});

  /// Platform id.
  final String id;

  /// Display name.
  final String name;

  /// Parent category id.
  final String categoryId;

  /// Area icon.
  final Uri? icon;
}
