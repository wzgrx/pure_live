import 'package:live_iptv/src/model.dart';
import 'package:meta/meta.dart';

/// A playlist as the IPTV source shows it (a category in 发现).
@immutable
final class IptvPlaylistInfo {
  /// Creates the info.
  const new({required this.id, required this.name});

  /// Storage id; opaque to this package, never contains `/`.
  final String id;

  /// Display name.
  final String name;
}

/// A channel in a list: the first entry of its name in the listed scope.
@immutable
final class IptvChannelInfo {
  /// Creates the info.
  const new({required this.name, this.group = '', this.logo, this.tvgId, this.tvgName});

  /// Channel name (identity).
  final String name;

  /// Group of that first entry.
  final String group;

  /// Logo URL.
  final String? logo;

  /// `tvg-id` of that first entry.
  final String? tvgId;

  /// `tvg-name` of that first entry.
  final String? tvgName;
}

/// One source of a channel with the playlist it comes from.
@immutable
final class IptvSource {
  /// Creates the source.
  const new({required this.entry, required this.playlistId, this.userAgent});

  /// The playlist entry.
  final IptvEntry entry;

  /// Playlist storage id.
  final String playlistId;

  /// The playlist's own User-Agent, if the user set one.
  final String? userAgent;
}

/// The programme guide the user selected.
@immutable
final class IptvGuideInfo {
  /// Creates the info.
  const new({required this.id, required this.revision});

  /// Storage id of the guide source.
  final String id;

  /// Changes whenever the guide's channels change (its last sync time), so
  /// cached matches can be dropped.
  final int revision;

  @override
  bool operator ==(Object other) => other is IptvGuideInfo && other.id == id && other.revision == revision;

  @override
  int get hashCode => Object.hash(id, revision);
}

/// What the IPTV source reads; implemented over the app's database, so this
/// package stays storage-free (spec/modules/iptv.md §5).
abstract interface class IptvRepository {
  /// Playlists in the user's order.
  Future<List<IptvPlaylistInfo>> playlists();

  /// Groups of a playlist in the order they first appear; `''` for entries
  /// without a group.
  Future<List<String>> groups(String playlistId);

  /// Distinct channel names in playlist order (playlists in the user's order,
  /// then file order), each with its first entry, filtered by [playlistId],
  /// [group] and a case-insensitive name [search]; [offset] and [limit] page
  /// through the names.
  Future<List<IptvChannelInfo>> channels({
    required int offset,
    required int limit,
    String? playlistId,
    String? group,
    String? search,
  });

  /// Every entry named [name] across all playlists, in playlist order then
  /// file order.
  Future<List<IptvSource>> sources(String name);

  /// The selected programme guide, or null when none is selected or synced.
  Future<IptvGuideInfo?> selectedGuide();

  /// Channels of guide [guideId].
  Future<List<IptvGuideChannel>> guideChannels(String guideId);

  /// Programmes of [channelId] in guide [guideId] overlapping [from]..[to],
  /// by start.
  Future<List<IptvProgramme>> programmes(
    String guideId,
    String channelId, {
    required DateTime from,
    required DateTime to,
  });

  /// The programme on air at [at] for each of [channelIds] that has one.
  Future<Map<String, IptvProgramme>> programmesAt(String guideId, Set<String> channelIds, DateTime at);
}
