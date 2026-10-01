import 'package:meta/meta.dart';

/// Kinds of PGC seasons (`season_type`).
enum PgcType {
  /// 番剧.
  anime(1),

  /// 电影.
  movie(2),

  /// 纪录片.
  documentary(3),

  /// 国创.
  guochuang(4),

  /// 电视剧.
  tv(5),

  /// 综艺.
  variety(7);

  new(this.id);

  /// `season_type`.
  final int id;
}

/// A season card (index, timeline, follow list, search).
@immutable
final class PgcCard {
  /// Creates a card.
  const new({
    required this.seasonId,
    required this.title,
    this.mediaId = 0,
    this.cover = '',
    this.badge = '',
    this.subtitle = '',
    this.indexShow = '',
    this.score = '',
    this.isFinished = false,
    this.firstEpId = 0,
    this.type = 0,
    this.needsVip = false,
  });

  /// `season_id`.
  final int seasonId;

  /// `media_id`.
  final int mediaId;

  /// Title.
  final String title;

  /// Cover.
  final String cover;

  /// Badge text (`大会员`, `独家`, `限时免费`…).
  final String badge;

  /// Subtitle.
  final String subtitle;

  /// Progress text (`全8话`, `更新至第3话`).
  final String indexShow;

  /// Score text, empty when unrated.
  final String score;

  /// Finished airing.
  final bool isFinished;

  /// First episode id.
  final int firstEpId;

  /// `season_type`.
  final int type;

  /// Member-only (`season_status` 13 or a 会员 badge).
  final bool needsVip;
}

/// One day of the release timeline.
@immutable
final class PgcTimelineDay {
  /// Creates a day.
  const new({required this.date, required this.dayOfWeek, required this.isToday, required this.episodes});

  /// The day (local midnight in UTC+8, as `date_ts`).
  final DateTime date;

  /// 1 Monday … 7 Sunday.
  final int dayOfWeek;

  /// Whether it is today.
  final bool isToday;

  /// Releases of the day in time order.
  final List<PgcTimelineEntry> episodes;
}

/// One release in the timeline.
@immutable
final class PgcTimelineEntry {
  /// Creates a release.
  const new({
    required this.seasonId,
    required this.episodeId,
    required this.title,
    this.cover = '',
    this.index = '',
    this.time = '',
    this.releasedAt,
    this.published = false,
    this.delayed = false,
    this.delayReason = '',
  });

  /// Season.
  final int seasonId;

  /// Episode.
  final int episodeId;

  /// Season title.
  final String title;

  /// Cover.
  final String cover;

  /// `pub_index`, e.g. `第5话`.
  final String index;

  /// `pub_time`, e.g. `10:00` (UTC+8).
  final String time;

  /// Release time.
  final DateTime? releasedAt;

  /// Already out.
  final bool published;

  /// Postponed.
  final bool delayed;

  /// Why.
  final String delayReason;
}

/// One episode of a season.
@immutable
final class PgcEpisode {
  /// Creates an episode.
  const new({
    required this.epId,
    required this.cid,
    this.aid = 0,
    this.bvid = '',
    this.title = '',
    this.longTitle = '',
    this.showTitle = '',
    this.cover = '',
    this.duration = Duration.zero,
    this.badge = '',
    this.status = 2,
    this.releasedAt,
    this.opening,
    this.ending,
  });

  /// Episode id.
  final int epId;

  /// Content id (danmaku, subtitles).
  final int cid;

  /// Archive id (comments).
  final int aid;

  /// Archive `BV` id.
  final String bvid;

  /// Short title (`1`, `PV1`).
  final String title;

  /// Long title.
  final String longTitle;

  /// `第2话 水柱·富冈义勇的痛楚`.
  final String showTitle;

  /// Cover.
  final String cover;

  /// Length.
  final Duration duration;

  /// Badge (`会员`, `限免`, `预告`).
  final String badge;

  /// 2 free, 13 member-only, 6/7/8/9/12 paid variants.
  final int status;

  /// Release time.
  final DateTime? releasedAt;

  /// Opening to skip, when the platform marks one.
  final ({Duration start, Duration end})? opening;

  /// Ending to skip, when the platform marks one.
  final ({Duration start, Duration end})? ending;

  /// Whether a non-member only gets a preview: member-only or paid status,
  /// or a `会员`/`付费` badge. Marked as it is; nothing works around it.
  bool get needsVip => status != 2 || badge.contains('会员') || badge.contains('付费');
}

/// A season's detail page.
@immutable
final class PgcSeason {
  /// Creates a season.
  const new({
    required this.seasonId,
    required this.title,
    this.mediaId = 0,
    this.cover = '',
    this.evaluate = '',
    this.score = 0,
    this.scoreCount = 0,
    this.styles = const [],
    this.publishTime = '',
    this.isFinished = false,
    this.status = 2,
    this.paymentTip = '',
    this.episodes = const [],
    this.extras = const [],
    this.relatedSeasons = const [],
  });

  /// `season_id`.
  final int seasonId;

  /// `media_id`.
  final int mediaId;

  /// Title.
  final String title;

  /// Cover.
  final String cover;

  /// Synopsis.
  final String evaluate;

  /// Rating, 0 when unrated.
  final double score;

  /// Number of ratings.
  final int scoreCount;

  /// Style tags.
  final List<String> styles;

  /// `publish.pub_time`.
  final String publishTime;

  /// Finished airing.
  final bool isFinished;

  /// 2 free, 13 member-only.
  final int status;

  /// `payment.tip`, e.g. `大会员专享观看特权哦~`.
  final String paymentTip;

  /// Main episodes.
  final List<PgcEpisode> episodes;

  /// Extras (`section[].episodes`: PVs, specials).
  final List<PgcEpisode> extras;

  /// Other seasons of the series (`seasons`).
  final List<PgcCard> relatedSeasons;
}
