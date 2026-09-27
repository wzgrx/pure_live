import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/stream.dart';

/// What a platform adapter offers (ADR 0010, rule 7).
abstract interface class LiveSite {
  /// Platform id, lower case (`douyu`).
  String get id;

  /// Display name (`斗鱼`).
  String get name;
}

/// Browsing: categories, area rooms, recommendations.
abstract interface class CatalogSource {
  /// Top-level categories with their areas.
  Future<List<Category>> categories();

  /// Rooms in [area]; pass the previous page's cursor for the next page.
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor});

  /// The platform's recommended rooms.
  Future<Page<RoomCard>> recommended({PageCursor? cursor});
}

/// Keyword search.
abstract interface class SearchSource {
  /// Rooms and streamers matching [keyword].
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor});
}

/// Room details.
abstract interface class RoomSource {
  /// Detail for [ref]; throws `NotFound` for a room that does not exist.
  Future<RoomDetail> detail(RoomRef ref);
}

/// Stream URLs.
abstract interface class StreamSource {
  /// Qualities and lines for a live room; [quality] null means the best offered.
  Future<StreamSet> streams(RoomDetail room, {Quality? quality});
}

/// Links and share codes.
abstract interface class LinkResolver {
  /// The room a link or share text points to, or null when it is not this
  /// platform's; throws `NotFound` when it is but the room does not exist.
  Future<RoomRef?> resolve(String input);
}
