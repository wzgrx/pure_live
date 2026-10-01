import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

/// An uploader (UP) as archive rows carry it.
@immutable
final class VodOwner {
  /// Creates an owner.
  const new({required this.mid, required this.name, this.face = ''});

  /// Reads the stored shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => VodOwner(
    mid: jsonInt(json['mid']) ?? 0,
    name: jsonString(json['name']) ?? '',
    face: jsonString(json['face']) ?? '',
  );

  /// User id; 0 when unknown.
  final int mid;

  /// Display name.
  final String name;

  /// Avatar URL (https), or empty.
  final String face;

  /// The stored shape.
  Map<String, Object?> toJson() => {'mid': mid, 'name': name, 'face': face};
}

/// Counters of an archive; 0 when the answer has none.
@immutable
final class VodStat {
  /// Creates the counters.
  const new({this.views = 0, this.danmaku = 0, this.replies = 0, this.likes = 0, this.coins = 0, this.favorites = 0});

  /// Reads the stored shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => VodStat(
    views: jsonInt(json['views']) ?? 0,
    danmaku: jsonInt(json['danmaku']) ?? 0,
    replies: jsonInt(json['replies']) ?? 0,
    likes: jsonInt(json['likes']) ?? 0,
    coins: jsonInt(json['coins']) ?? 0,
    favorites: jsonInt(json['favorites']) ?? 0,
  );

  /// Plays.
  final int views;

  /// Danmaku count.
  final int danmaku;

  /// Comment count.
  final int replies;

  /// Likes.
  final int likes;

  /// Coins.
  final int coins;

  /// Favourites.
  final int favorites;

  /// The stored shape.
  Map<String, Object?> toJson() => {
    'views': views,
    'danmaku': danmaku,
    'replies': replies,
    'likes': likes,
    'coins': coins,
    'favorites': favorites,
  };
}

/// One part (P) of an archive: the unit a player opens and the music queue
/// plays.
@immutable
final class VodPart {
  /// Creates a part.
  const new({required this.cid, this.page = 1, this.title = '', this.duration = Duration.zero});

  /// Reads the stored shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => VodPart(
    cid: jsonInt(json['cid']) ?? 0,
    page: jsonInt(json['page']) ?? 1,
    title: jsonString(json['title']) ?? '',
    duration: Duration(seconds: jsonInt(json['duration']) ?? 0),
  );

  /// Content id of the part's media; 0 when not known yet (list rows).
  final int cid;

  /// 1-based part number.
  final int page;

  /// Part title (the archive title for single-part uploads).
  final String title;

  /// Length.
  final Duration duration;

  /// The stored shape.
  Map<String, Object?> toJson() => {'cid': cid, 'page': page, 'title': title, 'duration': duration.inSeconds};
}

/// A UGC archive (稿件) as grids and the detail page show it.
///
/// List rows (popular, ranking, search, folders, history) carry no part list;
/// [VodPart.cid] of the first part is filled when the row names it. The
/// detail (`view`) fills [parts].
@immutable
final class VodArchive {
  /// Creates an archive.
  const new({
    required this.bvid,
    this.aid = 0,
    this.title = '',
    this.cover = '',
    this.owner = const VodOwner(mid: 0, name: ''),
    this.duration = Duration.zero,
    this.stat = const VodStat(),
    this.typeId = 0,
    this.typeName = '',
    this.description = '',
    this.publishedAt,
    this.cid = 0,
    this.partCount = 1,
    this.parts = const [],
  });

  /// Reads the stored shape written by [toJson] (queue snapshots, the daily
  /// recommendation cache, imported playlists).
  factory fromJson(Map<String, Object?> json) => VodArchive(
    bvid: jsonString(json['bvid']) ?? '',
    aid: jsonInt(json['aid']) ?? 0,
    title: jsonString(json['title']) ?? '',
    cover: jsonString(json['cover']) ?? '',
    owner: switch (json['owner']) {
      final Map<String, Object?> owner => VodOwner.fromJson(owner),
      _ => const VodOwner(mid: 0, name: ''),
    },
    duration: Duration(seconds: jsonInt(json['duration']) ?? 0),
    stat: switch (json['stat']) {
      final Map<String, Object?> stat => VodStat.fromJson(stat),
      _ => const VodStat(),
    },
    typeId: jsonInt(json['typeId']) ?? 0,
    typeName: jsonString(json['typeName']) ?? '',
    description: jsonString(json['description']) ?? '',
    publishedAt: switch (jsonInt(json['publishedAt'])) {
      final int seconds when seconds > 0 => DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
      _ => null,
    },
    cid: jsonInt(json['cid']) ?? 0,
    partCount: jsonInt(json['partCount']) ?? 1,
    parts: [
      for (final part in json['parts'] is List ? json['parts']! as List : const [])
        if (part is Map<String, Object?>) VodPart.fromJson(part),
    ],
  );

  /// `BV…` id; the identity.
  final String bvid;

  /// Numeric id (comments and interactions use it); 0 when unknown.
  final int aid;

  /// Title without search highlights.
  final String title;

  /// Cover URL (https).
  final String cover;

  /// Uploader.
  final VodOwner owner;

  /// Total length.
  final Duration duration;

  /// Counters.
  final VodStat stat;

  /// Partition (分区) id; 0 when the answer has none.
  final int typeId;

  /// Partition name; empty when the answer has none (`view` sends an empty
  /// `tname` since 2026).
  final String typeName;

  /// Description.
  final String description;

  /// Publish time, when known.
  final DateTime? publishedAt;

  /// Content id of the first part, when the row names it.
  final int cid;

  /// Number of parts the archive says it has.
  final int partCount;

  /// Every part; empty for list rows.
  final List<VodPart> parts;

  /// The parts to play: [parts], or one part made from the row itself.
  List<VodPart> get playableParts => parts.isNotEmpty ? parts : [VodPart(cid: cid, title: title, duration: duration)];

  /// A copy with [parts] (and the first part's cid) from a detail answer.
  VodArchive withParts(List<VodPart> parts) => VodArchive(
    bvid: bvid,
    aid: aid,
    title: title,
    cover: cover,
    owner: owner,
    duration: duration,
    stat: stat,
    typeId: typeId,
    typeName: typeName,
    description: description,
    publishedAt: publishedAt,
    cid: parts.isEmpty ? cid : parts.first.cid,
    partCount: parts.isEmpty ? partCount : parts.length,
    parts: parts,
  );

  /// The stored shape.
  Map<String, Object?> toJson() => {
    'bvid': bvid,
    'aid': aid,
    'title': title,
    'cover': cover,
    'owner': owner.toJson(),
    'duration': duration.inSeconds,
    'stat': stat.toJson(),
    'typeId': typeId,
    'typeName': typeName,
    'description': description,
    if (publishedAt case final at?) 'publishedAt': at.millisecondsSinceEpoch ~/ 1000,
    'cid': cid,
    'partCount': partCount,
    if (parts.isNotEmpty) 'parts': [for (final part in parts) part.toJson()],
  };

  @override
  bool operator ==(Object other) => other is VodArchive && other.bvid == bvid;

  @override
  int get hashCode => bvid.hashCode;

  @override
  String toString() => 'VodArchive($bvid)';
}

/// One page of a list.
@immutable
final class VodPage<T> {
  /// Creates a page.
  const new(this.items, {this.hasMore = false, this.cursor});

  /// Items in platform order.
  final List<T> items;

  /// Whether another page exists.
  final bool hasMore;

  /// The cursor of the next page for cursor-paged lists (comments, dynamics,
  /// history); null for numbered pages.
  final String? cursor;
}

/// One comment (`x/v2/reply/wbi/main` roots and `x/v2/reply/reply` rows).
@immutable
final class VodComment {
  /// Creates a comment.
  const new({
    required this.rpid,
    required this.oid,
    required this.user,
    required this.text,
    this.type = 1,
    this.level = 0,
    this.createdAt,
    this.likes = 0,
    this.replyCount = 0,
    this.liked = false,
    this.pinned = false,
    this.upLiked = false,
    this.location = '',
    this.replies = const [],
  });

  /// Comment id.
  final int rpid;

  /// Subject id (the archive's aid for type 1).
  final int oid;

  /// Subject type (1 = video).
  final int type;

  /// Author.
  final VodOwner user;

  /// Author's level.
  final int level;

  /// Text.
  final String text;

  /// Post time.
  final DateTime? createdAt;

  /// Likes.
  final int likes;

  /// Replies under it.
  final int replyCount;

  /// Whether the signed-in user liked it.
  final bool liked;

  /// Pinned by the uploader (`top_replies`).
  final bool pinned;

  /// Liked by the uploader.
  final bool upLiked;

  /// `IP属地：…` as the platform shows it; empty when absent.
  final String location;

  /// The first replies shown under a root.
  final List<VodComment> replies;
}

/// One page of root comments.
@immutable
final class VodCommentPage {
  /// Creates a page.
  const new({required this.comments, this.pinned = const [], this.total = 0, this.nextOffset, this.isEnd = true});

  /// Comments in the requested order.
  final List<VodComment> comments;

  /// Pinned comments (first page only).
  final List<VodComment> pinned;

  /// Total count the platform reports (`cursor.all_count`).
  final int total;

  /// `pagination_reply.next_offset` to ask for the next page; null at the
  /// end. Guests get only the first few hot comments and no offset.
  final String? nextOffset;

  /// Whether the list ended.
  final bool isEnd;
}

/// A followed uploader's video in the dynamic feed.
@immutable
final class VodDynamic {
  /// Creates an entry.
  const new({required this.id, required this.archive, this.publishedAt, this.publishedLabel = ''});

  /// Dynamic id.
  final String id;

  /// The video (`major.archive`).
  final VodArchive archive;

  /// Publish time (`pub_ts`).
  final DateTime? publishedAt;

  /// Publish label as shown (`pub_time`, e.g. `2小时前`).
  final String publishedLabel;
}

/// An uploader's space header.
@immutable
final class VodUserSpace {
  /// Creates the header.
  const new({
    required this.owner,
    this.sign = '',
    this.level = 0,
    this.followers = 0,
    this.following = 0,
    this.isFollowed = false,
    this.liveRoomId = 0,
  });

  /// The uploader.
  final VodOwner owner;

  /// Signature.
  final String sign;

  /// Level.
  final int level;

  /// Followers (`relation/stat`).
  final int followers;

  /// Users followed (`relation/stat`).
  final int following;

  /// Whether the signed-in user follows them.
  final bool isFollowed;

  /// Their live room id; 0 when none.
  final int liveRoomId;
}

/// A collection on an uploader's space: a season (合集) or a series (系列).
/// Music mode lists them as the uploader's playlists.
@immutable
final class VodUpCollection {
  /// Creates a collection.
  const new({
    required this.id,
    required this.isSeries,
    required this.mid,
    required this.title,
    this.cover = '',
    this.total = 0,
    this.description = '',
  });

  /// `season_id` or `series_id`.
  final int id;

  /// Whether this is a series (系列) rather than a season (合集).
  final bool isSeries;

  /// Owner.
  final int mid;

  /// Title.
  final String title;

  /// Cover.
  final String cover;

  /// Number of archives.
  final int total;

  /// Description.
  final String description;
}

/// A favourite folder.
@immutable
final class VodFavFolder {
  /// Creates a folder.
  const new({
    required this.id,
    required this.title,
    this.mediaCount = 0,
    this.cover = '',
    this.isPublic = true,
    this.ownerMid = 0,
    this.containsTarget = false,
  });

  /// Reads the stored shape written by [toJson].
  factory fromJson(Map<String, Object?> json) => VodFavFolder(
    id: jsonInt(json['id']) ?? 0,
    title: jsonString(json['title']) ?? '',
    mediaCount: jsonInt(json['mediaCount']) ?? 0,
    cover: jsonString(json['cover']) ?? '',
    isPublic: json['isPublic'] != false,
    ownerMid: jsonInt(json['ownerMid']) ?? 0,
  );

  /// `media_id`.
  final int id;

  /// Title.
  final String title;

  /// Number of items.
  final int mediaCount;

  /// Cover.
  final String cover;

  /// Whether others can see it.
  final bool isPublic;

  /// Owner.
  final int ownerMid;

  /// Whether the archive asked about is in it (`list-all` with `rid`).
  final bool containsTarget;

  /// The stored shape.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'mediaCount': mediaCount,
    'cover': cover,
    'isPublic': isPublic,
    'ownerMid': ownerMid,
  };
}

/// An archive in a favourite folder.
@immutable
final class VodFavItem {
  /// Creates an item.
  const new({required this.archive, this.invalid = false, this.favoritedAt});

  /// The archive.
  final VodArchive archive;

  /// Deleted by its uploader (`attr` bit 0 or the `已失效视频` title).
  final bool invalid;

  /// When it was added.
  final DateTime? favoritedAt;
}

/// One row of the cloud history (`history/cursor`).
@immutable
final class VodHistoryEntry {
  /// Creates a row.
  const new({
    required this.archive,
    required this.business,
    this.cid = 0,
    this.page = 1,
    this.progress = Duration.zero,
    this.finished = false,
    this.viewedAt,
    this.epId = 0,
    this.seasonId = 0,
  });

  /// The archive (title is the row's `show_title`).
  final VodArchive archive;

  /// `archive`, `pgc`, `live`, `article`…
  final String business;

  /// The part watched.
  final int cid;

  /// Its page number.
  final int page;

  /// How far it was watched.
  final Duration progress;

  /// Watched to the end (`progress` = -1).
  final bool finished;

  /// When.
  final DateTime? viewedAt;

  /// PGC episode id; 0 for UGC.
  final int epId;

  /// PGC season id; 0 for UGC.
  final int seasonId;
}

/// A search hit of type `bili_user`.
@immutable
final class VodSearchUser {
  /// Creates a hit.
  const new({
    required this.owner,
    this.sign = '',
    this.fans = 0,
    this.videos = 0,
    this.level = 0,
    this.liveRoomId = 0,
    this.isLive = false,
  });

  /// The user.
  final VodOwner owner;

  /// Signature.
  final String sign;

  /// Followers.
  final int fans;

  /// Uploads.
  final int videos;

  /// Level.
  final int level;

  /// Live room id; 0 when none.
  final int liveRoomId;

  /// Whether they are live now.
  final bool isLive;
}

/// A trending search word.
@immutable
final class VodHotword {
  /// Creates a word.
  const new({required this.keyword, this.label = '', this.icon = ''});

  /// What to search.
  final String keyword;

  /// What to show (`show_name`).
  final String label;

  /// Badge icon URL, or empty.
  final String icon;
}

/// A subtitle track of a part.
@immutable
final class VodSubtitleTrack {
  /// Creates a track.
  const new({required this.language, required this.label, required this.url, this.aiGenerated = false});

  /// `lan`, e.g. `zh-CN`, `ai-zh`.
  final String language;

  /// `lan_doc`, e.g. `中文（中国）`.
  final String label;

  /// The cue file (JSON), https.
  final String url;

  /// Machine generated (`ai-` languages or `ai_type` > 0).
  final bool aiGenerated;
}

/// One subtitle cue.
@immutable
final class VodSubtitleCue {
  /// Creates a cue.
  const new({required this.start, required this.end, required this.text});

  /// When it shows.
  final Duration start;

  /// When it hides.
  final Duration end;

  /// Text.
  final String text;
}

/// What `x/player/wbi/v2` says about one part.
@immutable
final class VodPlayerInfo {
  /// Creates the info.
  const new({
    this.subtitles = const [],
    this.bgmMusicId = '',
    this.bgmTitle = '',
    this.lastPlayCid = 0,
    this.lastPlayTime = Duration.zero,
    this.onlineCount = 0,
  });

  /// Subtitle tracks (guests usually get none).
  final List<VodSubtitleTrack> subtitles;

  /// Background music id (`bgm_info.music_id`), or empty.
  final String bgmMusicId;

  /// What the BGM claims to be (`《…》` stripped), or empty.
  final String bgmTitle;

  /// Resume point of the signed-in user: the part.
  final int lastPlayCid;

  /// Resume point of the signed-in user: the position.
  final Duration lastPlayTime;

  /// Viewers now (`online_count`).
  final int onlineCount;
}

/// One on-demand danmaku.
@immutable
final class VodDanmaku {
  /// Creates a danmaku.
  const new({
    required this.progress,
    required this.text,
    this.id = '',
    this.mode = 1,
    this.fontSize = 25,
    this.color = 0xFFFFFF,
    this.weight = 0,
    this.pool = 0,
  });

  /// Position in the part.
  final Duration progress;

  /// Text.
  final String text;

  /// `idStr` / dmid.
  final String id;

  /// 1–3 scrolling, 4 bottom, 5 top, 6 reverse, 7 advanced, 8 code, 9 BAS.
  final int mode;

  /// Font size (25 normal).
  final int fontSize;

  /// RGB colour.
  final int color;

  /// Shield weight 0–10 (the web player hides low weights by setting).
  final int weight;

  /// 0 normal, 1 subtitle, 2 special.
  final int pool;

  /// Whether a plain overlay can draw it (scrolling, top, bottom); advanced,
  /// code and BAS danmaku need their own renderer.
  bool get isPlain => mode >= 1 && mode <= 6;
}
