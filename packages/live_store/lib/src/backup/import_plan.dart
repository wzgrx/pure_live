import 'package:live_core/live_core.dart';
import 'package:live_store/src/backup/import_report.dart';
import 'package:live_store/src/backup/record_tasks.dart';
import 'package:live_store/src/block_rules.dart';
import 'package:live_store/src/follow_areas.dart';
import 'package:live_store/src/rooms.dart';
import 'package:live_store/src/tags.dart';
import 'package:meta/meta.dart';

/// A room read from a backup: card data plus rarely used fields.
@internal
@immutable
final class ImportedRoom {
  /// Creates a room.
  const new(this.snapshot, {this.extra = const {}});

  /// Card data.
  final RoomSnapshot snapshot;

  /// Fields kept in `rooms.extra` (notice, introduction, IPTV data).
  final Map<String, Object?> extra;

  /// Room identity.
  RoomRef get ref => snapshot.ref;

  /// This room with empty fields filled from [other] (store.md §6.4.7).
  ImportedRoom fillFrom(ImportedRoom other) {
    final a = snapshot;
    final b = other.snapshot;
    String? pick(String? first, String? second) => first == null || first.isEmpty ? second : first;
    return ImportedRoom(
      RoomSnapshot(
        ref: a.ref,
        anchorName: pick(a.anchorName, b.anchorName),
        title: pick(a.title, b.title),
        avatar: a.avatar ?? b.avatar,
        cover: a.cover ?? b.cover,
        area: pick(a.area, b.area),
        userId: pick(a.userId, b.userId),
        audience: Audience(
          online: a.audience.online ?? b.audience.online,
          popularity: a.audience.popularity ?? b.audience.popularity,
          cumulative: a.audience.cumulative ?? b.audience.cumulative,
        ),
        state: a.state ?? b.state,
      ),
      extra: {...other.extra, ...extra},
    );
  }
}

/// A follow to restore.
@internal
@immutable
final class PlannedFollow {
  /// Creates a follow.
  const new(this.room, {required this.followedAt});

  /// The room.
  final ImportedRoom room;

  /// When it was followed.
  final DateTime followedAt;
}

/// A history entry to restore.
@internal
@immutable
final class PlannedHistory {
  /// Creates an entry.
  const new(this.room, {this.lastWatchedAt});

  /// The room.
  final ImportedRoom room;

  /// When it was last watched.
  final DateTime? lastWatchedAt;
}

/// A room preference to restore.
@internal
@immutable
final class PlannedRoomPref {
  /// Creates a preference.
  const new(this.ref, this.key, this.value);

  /// The room.
  final RoomRef ref;

  /// Preference key.
  final String key;

  /// JSON value.
  final Object value;
}

/// A URL playlist or guide source to restore (store.md §7.1 `iptv`).
@internal
@immutable
final class PlannedIptvSource {
  /// Creates a source.
  const new({required this.name, required this.url, this.userAgent, this.autoSync = true, this.selected = false});

  /// Display name.
  final String name;

  /// http(s) URL.
  final String url;

  /// Playlist User-Agent (playlists only).
  final String? userAgent;

  /// Whether automatic sync includes it.
  final bool autoSync;

  /// Whether it is the selected guide (guides only).
  final bool selected;
}

/// The IPTV section to restore: URL playlists and URL guide sources, in
/// order. File-imported ones are never in a backup and stay on restore.
@internal
@immutable
final class PlannedIptv {
  /// Creates the section.
  const new({this.playlists = const [], this.guides = const []});

  /// Playlists.
  final List<PlannedIptvSource> playlists;

  /// Guide sources.
  final List<PlannedIptvSource> guides;
}

/// Everything an import will write, validated before anything is written
/// (store.md §7.2). A null section is absent from the source and leaves the
/// local data unchanged.
final class ImportPlan {
  /// Starts an empty plan.
  new() : report = ImportReport();

  /// What was read and discarded.
  final ImportReport report;

  /// Whether the source is a follows-only backup.
  bool followsOnlySource = false;

  /// Settings by id (already validated).
  @internal
  Map<String, Object>? settings;

  /// Whether [settings] replaces every local setting of the restored scopes
  /// (v4) instead of only the keys it contains (3.x).
  @internal
  bool replaceSettings = false;

  /// Whether device-scope settings are restored (same platform family).
  @internal
  bool includeDeviceSettings = false;

  /// Follows in order.
  @internal
  List<PlannedFollow>? follows;

  /// Followed areas in order.
  @internal
  List<FollowedArea>? followAreas;

  /// Tags in order.
  @internal
  List<Tag>? tags;

  /// Tag membership by room.
  @internal
  Map<RoomRef, Set<String>>? roomTags;

  /// History, newest first.
  @internal
  List<PlannedHistory>? history;

  /// Block rules by the kinds they replace.
  @internal
  Map<BlockKind, List<BlockRule>>? blockRules;

  /// Room preferences.
  @internal
  List<PlannedRoomPref>? roomPrefs;

  /// Secrets to store by reference name; null values remove.
  @internal
  Map<String, String?>? secrets;

  /// IPTV playlists and guide sources.
  @internal
  PlannedIptv? iptv;

  /// Recording tasks in order, for the app's recorder (store.md §7.1).
  @internal
  List<BackupRecordTask>? recordTasks;

  /// Keeps only follows and followed areas (follows-only restore).
  @internal
  void restrictToFollows() {
    settings = null;
    tags = null;
    roomTags = null;
    history = null;
    blockRules = null;
    roomPrefs = null;
    secrets = null;
    iptv = null;
    recordTasks = null;
  }
}

/// Room de-duplication shared by the importers (store.md §6.4.7): the first
/// occurrence keeps its position, later ones only fill its empty fields.
@internal
List<T> dedupeRooms<T>(
  Iterable<T> items,
  RoomRef Function(T item) refOf,
  T Function(T first, T later) merge, {
  required ImportReport report,
  required String section,
}) {
  final positions = <RoomRef, int>{};
  final result = <T>[];
  for (final item in items) {
    final ref = refOf(item);
    final index = positions[ref];
    if (index == null) {
      positions[ref] = result.length;
      result.add(item);
    } else {
      result[index] = merge(result[index], item);
      report.drop(section, 'duplicate', ref.key);
    }
  }
  return result;
}
