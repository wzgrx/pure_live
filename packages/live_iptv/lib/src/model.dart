import 'dart:convert';
import 'dart:math';

import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What a playlist entry carries, guessed from its group and URL (3.x's
/// `StreamType`, stored by name).
enum IptvStreamType {
  /// A live channel.
  live,

  /// A film or other on-demand item.
  vod,

  /// An episode of a series.
  series;

  /// The type stored as [name]; unknown names are [live].
  static IptvStreamType fromName(String? name) => values.asNameMap()[name] ?? live;
}

/// One stream line of a playlist as the parsers read it: no storage identity
/// yet (3.x parsed into `Channel` with a throw-away id).
@immutable
final class IptvEntry {
  /// Creates an entry.
  new({
    required this.name,
    required this.streamUrl,
    this.tvgId,
    this.tvgName,
    this.tvgLogo,
    this.groupTitle,
    this.channelNumber,
    this.streamType = IptvStreamType.live,
    this.catchupMode,
    this.catchupSource,
    this.catchupDays,
    this.catchupCorrectionHours,
    Map<String, String> httpHeaders = const {},
  }) : httpHeaders = HttpHeaderPolicy.normalize(httpHeaders);

  /// Display name.
  final String name;

  /// Media URL, without `|header=value` options.
  final String streamUrl;

  /// `tvg-id`.
  final String? tvgId;

  /// `tvg-name`.
  final String? tvgName;

  /// `tvg-logo`.
  final String? tvgLogo;

  /// `group-title` (or the inherited `#EXTGRP`, or the TXT genre).
  final String? groupTitle;

  /// `tvg-chno`.
  final int? channelNumber;

  /// Live, VOD or series.
  final IptvStreamType streamType;

  /// Catch-up mode (`default`, `append`, `shift`, ..., or `disabled`).
  final String? catchupMode;

  /// Catch-up URL template or query.
  final String? catchupSource;

  /// Days the provider keeps.
  final double? catchupDays;

  /// Correction of the provider's clock, in hours.
  final double? catchupCorrectionHours;

  /// Request headers the stream needs, normalized (lower-case names).
  final Map<String, String> httpHeaders;

  /// The best display name: `tvg-name`, else [name].
  String get displayName => tvgName ?? name;

  /// Every field, for de-duplicating identical lines.
  String get contentKey => jsonEncode([
    name,
    tvgId,
    tvgName,
    tvgLogo,
    groupTitle,
    channelNumber,
    streamUrl,
    streamType.name,
    catchupMode,
    catchupSource,
    catchupDays,
    catchupCorrectionHours,
    HttpHeaderPolicy.encode(httpHeaders),
  ]);
}

/// A stored playlist line: an [entry] with the durable id that rooms,
/// follows and guide mappings refer to.
@immutable
final class IptvChannel {
  /// Creates a channel.
  const new({
    required this.id,
    required this.playlistId,
    required this.entry,
    this.favorite = false,
    this.hidden = false,
    this.sortOrder = 0,
    this.autoUpdate = true,
  });

  /// Durable id (3.x: a UUID kept across syncs by the reconciler). This is
  /// the IPTV room id.
  final String id;

  /// Id of the playlist the channel belongs to (3.x's `providerId`).
  final String playlistId;

  /// What the playlist says.
  final IptvEntry entry;

  /// 3.x column, kept across syncs (no 3.x screen sets it).
  final bool favorite;

  /// 3.x column, kept across syncs (no 3.x screen sets it).
  final bool hidden;

  /// 3.x column, kept across syncs.
  final int sortOrder;

  /// When false a sync keeps every field of this channel (3.x column).
  final bool autoUpdate;

  /// Display name.
  String get name => entry.name;

  /// Media URL.
  String get streamUrl => entry.streamUrl;

  /// A copy with another [entry].
  IptvChannel withEntry(IptvEntry entry) => IptvChannel(
    id: id,
    playlistId: playlistId,
    entry: entry,
    favorite: favorite,
    hidden: hidden,
    sortOrder: sortOrder,
    autoUpdate: autoUpdate,
  );
}

/// The format of a playlist file (3.x stored it as the provider `type`).
enum IptvPlaylistFormat {
  /// `#EXTM3U` playlists (`.m3u`, `.m3u8`).
  m3u,

  /// `name,url` lists with `group,#genre#` lines.
  txt;

  /// The format of a stored 3.x type (`m3u`, `.m3u8`, `txt`), or null.
  static IptvPlaylistFormat? fromType(String? type) {
    final value = type?.trim().toLowerCase().replaceFirst('.', '');
    return switch (value) {
      'm3u' || 'm3u8' => m3u,
      'txt' => txt,
      _ => null,
    };
  }

  /// The format of a file name or URL path by its extension, or null.
  static IptvPlaylistFormat? fromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.txt')) return txt;
    if (lower.endsWith('.m3u') || lower.endsWith('.m3u8')) return m3u;
    return null;
  }

  /// The file extension, with the dot.
  String get extension => this == txt ? '.txt' : '.m3u';
}

/// A saved playlist (3.x's `Providers` row).
@immutable
final class IptvPlaylist {
  /// Creates a playlist.
  const new({
    required this.id,
    required this.name,
    required this.format,
    required this.source,
    this.sortOrder = 0,
    this.lastRefresh,
    this.createdAt,
    this.autoUpdate = true,
  });

  /// The built-in "hot" playlist behind the recommendations (3.x
  /// `FileUtils.systemHotProviderId`).
  static const String hotId = '88888';

  /// Id (a UUID, or [hotId]).
  final String id;

  /// Display name; the category name in the IPTV directory.
  final String name;

  /// File format.
  final IptvPlaylistFormat format;

  /// Where the playlist comes from: an http(s) URL, or the path of the copy
  /// the importer keeps.
  final String source;

  /// 3.x column, kept.
  final int sortOrder;

  /// Last successful import or sync.
  final DateTime? lastRefresh;

  /// When the playlist was first imported.
  final DateTime? createdAt;

  /// Whether automatic sync may refresh it.
  final bool autoUpdate;

  /// Whether [source] is a network URL.
  bool get isRemote => isHttpUrl(source);

  /// Whether this is the built-in hot playlist.
  bool get isHot => id == hotId;

  /// A copy with the given fields replaced.
  IptvPlaylist copyWith({
    String? name,
    IptvPlaylistFormat? format,
    String? source,
    DateTime? lastRefresh,
    bool? autoUpdate,
  }) => IptvPlaylist(
    id: id,
    name: name ?? this.name,
    format: format ?? this.format,
    source: source ?? this.source,
    sortOrder: sortOrder,
    lastRefresh: lastRefresh ?? this.lastRefresh,
    createdAt: createdAt,
    autoUpdate: autoUpdate ?? this.autoUpdate,
  );

  @override
  bool operator ==(Object other) =>
      other is IptvPlaylist &&
      other.id == id &&
      other.name == name &&
      other.format == format &&
      other.source == source &&
      other.sortOrder == sortOrder &&
      other.lastRefresh == lastRefresh &&
      other.createdAt == createdAt &&
      other.autoUpdate == autoUpdate;

  @override
  int get hashCode => Object.hash(id, name, format, source, sortOrder, lastRefresh, createdAt, autoUpdate);
}

/// A saved programme guide source (3.x's `EpgSources` row).
@immutable
final class EpgSource {
  /// Creates a source.
  const new({
    required this.id,
    required this.name,
    required this.source,
    this.lastRefresh,
    this.createdAt,
    this.autoUpdate = true,
  });

  /// Id (a UUID).
  final String id;

  /// Display name.
  final String name;

  /// An http(s) URL, or the path of the imported file.
  final String source;

  /// Last successful import or sync.
  final DateTime? lastRefresh;

  /// When the source was first imported.
  final DateTime? createdAt;

  /// Whether automatic sync may refresh it.
  final bool autoUpdate;

  /// Whether [source] is a network URL.
  bool get isRemote => isHttpUrl(source);

  /// A copy with the given fields replaced.
  EpgSource copyWith({String? name, String? source, DateTime? lastRefresh, bool? autoUpdate}) => EpgSource(
    id: id,
    name: name ?? this.name,
    source: source ?? this.source,
    lastRefresh: lastRefresh ?? this.lastRefresh,
    createdAt: createdAt,
    autoUpdate: autoUpdate ?? this.autoUpdate,
  );

  @override
  bool operator ==(Object other) =>
      other is EpgSource &&
      other.id == id &&
      other.name == name &&
      other.source == source &&
      other.lastRefresh == lastRefresh &&
      other.createdAt == createdAt &&
      other.autoUpdate == autoUpdate;

  @override
  int get hashCode => Object.hash(id, name, source, lastRefresh, createdAt, autoUpdate);
}

/// The storage key of guide channel [channelId] in source [sourceId]: the
/// same raw id in two sources never collides, and delimiters inside either
/// id cannot fake another key (3.x `epgChannelKey`, kept byte for byte so
/// 3.x rooms' `epgId` values stay valid).
String epgChannelKey(String sourceId, String channelId) => 'epg:${jsonEncode([sourceId, channelId])}';

/// A guide channel as the parsers read it.
@immutable
final class GuideChannel {
  /// Creates a channel.
  new({required this.id, List<String> displayNames = const [], this.iconUrl})
    : displayNames = List.unmodifiable(displayNames);

  /// The guide's channel id.
  final String id;

  /// Every `display-name`, in order.
  final List<String> displayNames;

  /// Icon URL.
  final String? iconUrl;

  /// The first display name, else [id] (what 3.x stored).
  String get primaryName => displayNames.isNotEmpty ? displayNames.first : id;
}

/// A stored guide channel (3.x's `EpgChannels` row).
@immutable
final class EpgChannel {
  /// Creates a channel.
  const new({required this.sourceId, required this.channelId, required this.displayName, this.iconUrl});

  /// Guide source id.
  final String sourceId;

  /// The guide's own channel id (`tvg-id` matches it).
  final String channelId;

  /// The first display name.
  final String displayName;

  /// Icon URL.
  final String? iconUrl;

  /// Storage key ([epgChannelKey]); the IPTV room's `epgId`.
  String get key => epgChannelKey(sourceId, channelId);
}

/// A programme of a guide channel.
@immutable
final class EpgProgramme {
  /// Creates a programme.
  const new({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.sourceId = '',
    this.subtitle,
    this.description,
    this.category,
    this.episodeNum,
    this.catchupId,
  });

  /// The guide's channel id.
  final String channelId;

  /// Guide source id (empty while parsing).
  final String sourceId;

  /// Start.
  final DateTime start;

  /// End (exclusive).
  final DateTime stop;

  /// Title.
  final String title;

  /// `sub-title`.
  final String? subtitle;

  /// `desc`.
  final String? description;

  /// First `category`.
  final String? category;

  /// First `episode-num`.
  final String? episodeNum;

  /// `catchup-id`, for catch-up templates.
  final String? catchupId;

  /// The storage key of its channel.
  String get channelKey => epgChannelKey(sourceId, channelId);

  /// This programme in source [sourceId].
  EpgProgramme inSource(String sourceId) => EpgProgramme(
    channelId: channelId,
    sourceId: sourceId,
    start: start,
    stop: stop,
    title: title,
    subtitle: subtitle,
    description: description,
    category: category,
    episodeNum: episodeNum,
    catchupId: catchupId,
  );
}

/// How a playlist channel maps to a guide channel (3.x's `EpgMappings`).
@immutable
final class EpgMapping {
  /// Creates a mapping.
  const new({
    required this.channelId,
    required this.playlistId,
    required this.epgChannelKey,
    required this.epgSourceId,
    this.origin = autoOrigin,
    this.locked = false,
  });

  /// [origin] of mappings the importer made and may replace.
  static const String autoOrigin = 'auto';

  /// Playlist channel id.
  final String channelId;

  /// Playlist id.
  final String playlistId;

  /// Guide channel key ([epgChannelKey]); 3.x rows from before its schema 7
  /// may hold a raw guide id instead.
  final String epgChannelKey;

  /// Guide source id.
  final String epgSourceId;

  /// `auto`, `manual`, `suggested` or `imported` (3.x's `source` column).
  final String origin;

  /// A locked mapping is never replaced.
  final bool locked;

  @override
  bool operator ==(Object other) =>
      other is EpgMapping &&
      other.channelId == channelId &&
      other.playlistId == playlistId &&
      other.epgChannelKey == epgChannelKey &&
      other.epgSourceId == epgSourceId &&
      other.origin == origin &&
      other.locked == locked;

  @override
  int get hashCode => Object.hash(channelId, playlistId, epgChannelKey, epgSourceId, origin, locked);
}

/// Whether [value] is an http or https URL.
bool isHttpUrl(String value) {
  final scheme = Uri.tryParse(value.trim())?.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

final Random _random = Random.secure();

/// A random version 4 UUID (3.x used `package:uuid`).
String randomUuid() {
  final bytes = [for (var i = 0; i < 16; i++) _random.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}
