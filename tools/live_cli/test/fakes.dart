import 'dart:async';

import 'package:live_cli/live_cli.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';

/// A live room card or detail.
LiveRoom room(
  String id, {
  String platform = 'bilibili',
  LiveStatus? status = LiveStatus.live,
  String title = '标题',
  String nick = '主播',
  String? area = '分区',
  String? link,
  DateTime? startedAt,
}) => LiveRoom(
  roomId: id,
  platform: platform,
  title: title,
  nick: nick,
  area: area,
  link: link,
  watching: '1',
  liveStatus: status,
  startedAt: startedAt,
);

/// A recipe without a URL (session-type sources).
final class FakeRecipe implements LiveInputRecipe {
  @override
  String get identity => 'recipe';
}

/// A [LiveSite] answering from fields; a field that is a [Object] error is
/// thrown instead.
class FakeSite extends LiveSite {
  /// Creates the site.
  new({this.id = 'bilibili'});

  @override
  final String id;

  @override
  String get name => id;

  /// Recommendation pages by number (`Object` errors are thrown).
  Map<int, Object> recommend = {};

  /// Categories, or an error.
  Object categories = <LiveCategory>[];

  /// Area pages by number.
  Map<int, Object> areaPages = {};

  /// Room search results.
  Object rooms = <LiveRoom>[];

  /// Streamer search results.
  Object anchors = <LiveAnchorItem>[];

  /// Details by room id; missing ids are `NotFound`.
  Map<String, Object> details = {};

  /// Qualities by room id.
  Map<String, List<LivePlayQuality>> qualities = {};

  /// Errors listing the qualities throws, by room id.
  Map<String, Exception> qualityErrors = {};

  /// Resolutions by room id.
  Map<String, LivePlayUrlResolution> resolutions = {};

  /// Keywords searched.
  final List<String> keywords = [];

  /// A future that never completes, for timeouts.
  Completer<List<LiveRoom>>? hang;

  T _answer<T>(Object value) => value is T ? value as T : throw value as Exception;

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    if (hang case final completer?) return await completer.future;
    return _answer<List<LiveRoom>>(recommend[page] ?? const <LiveRoom>[]);
  }

  @override
  Future<List<LiveCategory>> getCategories(int page, int pageSize) async => _answer<List<LiveCategory>>(categories);

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async =>
      _answer<List<LiveRoom>>(areaPages[page] ?? const <LiveRoom>[]);

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    keywords.add(keyword);
    return _answer<List<LiveRoom>>(rooms);
  }

  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async =>
      _answer<List<LiveAnchorItem>>(anchors);

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async =>
      _answer<LiveRoom>(details[roomId] ?? NotFound(id, roomId));

  @override
  Future<List<LivePlayQuality>> getPlayQualities({required LiveRoom detail}) async {
    if (qualityErrors[detail.roomId] case final error?) throw error;
    return qualities[detail.roomId] ?? const [];
  }
}

/// A [FakeSite] whose recommendations are native directory pages.
final class FakePagerSite extends FakeSite implements LiveSiteDirectoryPager {
  /// Creates the site.
  new({super.id});

  /// Pages by number.
  Map<int, LiveDirectoryPage> pages = {};

  @override
  Future<LiveDirectoryPage> getDirectoryPage({int page = 1, LiveArea? category, CancelToken? cancel}) async =>
      pages[page] ?? LiveDirectoryPage(rooms: const [], page: page, hasMore: false);
}

/// A [FakeSite] that confirms qualities and lines.
final class FakeResolverSite extends FakeSite implements LivePlayUrlResolver {
  /// Creates the site.
  new({super.id});

  @override
  Future<LivePlayUrlResolution> resolvePlayUrlsRaw({
    required LiveRoom detail,
    required LivePlayQuality quality,
  }) async => resolutions[detail.roomId] ?? LivePlayUrlResolution.lines(const []);
}

/// FLV header bytes.
final List<int> flvBytes = [0x46, 0x4C, 0x56, 0x01, 0x05, 0, 0, 0, 9];

/// A playlist.
final List<int> m3u8Bytes = '#EXTM3U\n#EXT-X-VERSION:3\n'.codeUnits;

/// A patrol of [site] with [target]; media answers [head] for every line.
PlatformPatrol patrolOf(
  FakeSite site,
  PatrolTarget target, {
  MediaHead? head,
  Map<String, String?> links = const {},
  DanmakuProbe? danmaku,
  Duration danmakuDuration = Duration.zero,
  Duration checkTimeout = const Duration(seconds: 30),
  DateTime? now,
}) => PlatformPatrol(
  site: site,
  target: target,
  media: (_, _) async => head ?? MediaHead(status: 200, bytes: flvBytes),
  links: (_, url) async => links[url],
  danmaku: danmaku,
  danmakuDuration: danmakuDuration,
  checkTimeout: checkTimeout,
  now: () => now ?? DateTime.utc(2026, 10, 8, 12),
);

/// The result of [check] in [run].
CheckResult resultOf(SiteRun run, CheckId check) => run.results.singleWhere((result) => result.check == check);
