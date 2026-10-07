import 'dart:async';

import 'package:live_cli/src/patrol/media.dart';
import 'package:live_cli/src/patrol/result.dart';
import 'package:live_cli/src/patrol/targets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// Reads the first bytes of [line] of [site].
typedef MediaReader = Future<MediaHead> Function(String site, LivePlayLine line);

/// The room [url] leads to on [site] (requests allowed), or null.
typedef LinkReader = Future<String?> Function(LiveSite site, String url);

/// Joins the chat of [room] for [duration] and reports what arrived.
typedef DanmakuProbe = Future<DanmakuSample> Function(LiveSite site, LiveRoom room, Duration duration);

/// What a danmaku connection did during the probe.
@immutable
final class DanmakuSample {
  /// Creates the sample.
  const new({this.ready, this.chats = 0, this.online = 0, this.reconnects = 0, this.closed, this.error});

  /// Time to the first `DanmakuReady`, or null when it never came.
  final Duration? ready;

  /// Chat messages.
  final int chats;

  /// Audience updates.
  final int online;

  /// `DanmakuReconnecting` events.
  final int reconnects;

  /// The `DanmakuClosed` reason, or null.
  final String? closed;

  /// What the start threw, or null.
  final String? error;
}

/// The failure of a check (thrown by its body): [note] goes to the report.
final class CheckFailure implements Exception {
  /// Creates the failure.
  const new(this.note);

  /// What is wrong.
  final String note;

  @override
  String toString() => 'CheckFailure($note)';
}

/// A check that could not run (thrown by its body).
final class CheckSkipped implements Exception {
  /// Creates the skip.
  const new(this.note);

  /// Why.
  final String note;

  @override
  String toString() => 'CheckSkipped($note)';
}

String _short(String text, [int length = 160]) => text.length <= length ? text : '${text.substring(0, length)}…';

/// A thrown error as the report says it: the `SiteError` kind and detail,
/// the transport reason, or the HTTP status.
String describeError(Object error) => switch (error) {
  SiteError(:final kind, :final detail) => detail == null || detail.isEmpty ? kind : '$kind：${_short(detail)}',
  TransportFailure(:final reason, :final detail) =>
    'TransportFailure ${reason.name}${detail == null ? '' : '：${_short(detail)}'}',
  HttpStatusFailure(:final status) => 'HTTP $status',
  TimeoutException() => '超时',
  FormatException(:final message) => 'FormatException：${_short(message)}',
  _ => _short('${error.runtimeType}：$error'),
};

/// Whether two room ids name the same room on [site].
bool sameRoom(String site, String a, String b) =>
    SiteIds.ignoresRoomIdCase(site) ? a.trim().toLowerCase() == b.trim().toLowerCase() : a.trim() == b.trim();

/// P1–P13 for one platform (docs/E-直播平台/E07-平台巡检/CHECKS.md): each
/// check is one method returning a [CheckResult]; errors become notes, each
/// check is limited to [checkTimeout], and a `RiskControl` stops the
/// platform (the rest is "没测到", no retries).
final class PlatformPatrol {
  /// Creates the patrol of [site] with the row [target].
  new({
    required this.site,
    required this.target,
    required this.media,
    required this.links,
    this.danmaku,
    this.danmakuDuration = Duration.zero,
    this.checkTimeout = const Duration(seconds: 30),
    this.network = '直连',
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The adapter.
  final LiveSite site;

  /// Its row of the object table.
  final PatrolTarget target;

  /// Reads line heads (P10).
  final MediaReader media;

  /// Parses links (P12).
  final LinkReader links;

  /// Joins a chat (P13); null when the platform has none.
  final DanmakuProbe? danmaku;

  /// How long P13 listens; zero skips it.
  final Duration danmakuDuration;

  /// Limit per check.
  final Duration checkTimeout;

  /// `直连` or `代理`.
  final String network;

  final DateTime Function() _now;

  String? _stopped;
  String _step = '';
  final List<LiveRoom> _recommended = [];
  final List<LiveRoom> _areaRooms = [];
  final List<LiveRoom> _searched = [];
  List<LiveCategory>? _categories;
  final List<LiveRoom> _live = [];
  final Map<String, List<LivePlayQuality>> _qualities = {};
  final List<LivePlayLine> _lines = [];
  bool _resolved = false;

  /// Runs every check in order.
  Future<SiteRun> run() async {
    final watch = Stopwatch()..start();
    final results = <CheckResult>[];
    if (target.skip case final reason?) {
      results.addAll([for (final id in CheckId.values) CheckResult(id, Outcome.notRun, reason)]);
    } else {
      results
        ..add(await _check(CheckId.p1, _recommend))
        ..add(await _check(CheckId.p2, _categoriesCheck))
        ..add(await _check(CheckId.p3, _area))
        ..add(await _check(CheckId.p4, _searchRooms))
        ..add(await _check(CheckId.p5, _searchAnchors))
        ..add(await _check(CheckId.p6, _liveDetails))
        ..add(await _check(CheckId.p7, _fixedRooms))
        ..add(await _check(CheckId.p8, _missingRoom))
        ..add(await _check(CheckId.p9, _qualitiesCheck))
        ..add(await _check(CheckId.p10, _linesCheck, timeout: checkTimeout * 3))
        ..add(await _check(CheckId.p11, _leases))
        ..add(await _check(CheckId.p12, _links))
        ..add(await _check(CheckId.p13, _danmaku, timeout: danmakuDuration + checkTimeout));
    }
    return SiteRun(site: target.site, name: target.name, network: network, results: results, elapsed: watch.elapsed);
  }

  /// Results of a platform that is not reached (no proxy): every check
  /// "没测到" with [reason].
  static SiteRun notReached(PatrolTarget target, String reason, {String network = '代理'}) => SiteRun(
    site: target.site,
    name: target.name,
    network: network,
    results: [for (final id in CheckId.values) CheckResult(id, Outcome.notRun, reason)],
    elapsed: Duration.zero,
  );

  Future<CheckResult> _check(CheckId id, Future<String> Function() body, {Duration? timeout}) async {
    final limit = timeout ?? target.checkTimeout ?? checkTimeout;
    final unsupported = target.unsupported[id] ?? (id == CheckId.p5 && !target.anchors ? '平台不提供搜索主播' : null);
    if (unsupported != null) return CheckResult(id, Outcome.unsupported, unsupported);
    if (_stopped case final reason?) return CheckResult(id, Outcome.notRun, reason);
    final watch = Stopwatch()..start();
    _step = '';
    try {
      final note = await body().timeout(limit);
      return CheckResult(id, Outcome.ok, note, elapsed: watch.elapsed);
    } on CheckSkipped catch (skip) {
      return CheckResult(id, Outcome.notRun, skip.note, elapsed: watch.elapsed);
    } on CheckFailure catch (failure) {
      return CheckResult(id, Outcome.failed, failure.note, elapsed: watch.elapsed);
    } on TimeoutException {
      return CheckResult(id, Outcome.failed, '超过 ${limit.inSeconds} 秒${_at()}', elapsed: watch.elapsed);
    } on RiskControl catch (error) {
      _stopped = '风控：${id.code} 遇到 RiskControl 后本平台停止（不重试）';
      return CheckResult(id, Outcome.failed, '${describeError(error)}${_at()}', elapsed: watch.elapsed);
    } on Object catch (error) {
      return CheckResult(id, Outcome.failed, '${describeError(error)}${_at()}', elapsed: watch.elapsed);
    }
  }

  String _at() => _step.isEmpty ? '' : '（步骤：$_step）';

  // P1 ----------------------------------------------------------------------

  Future<String> _recommend() async {
    final first = await _directory(page: 1);
    final rooms = first.rooms;
    if (rooms.isEmpty) throw const CheckFailure('第 1 页为空');
    _checkCards(rooms, '第 1 页');
    _recommended.addAll(rooms);
    final second = await _secondPage(first, (cursor) => _directory(page: 2, cursor: cursor));
    return '第 1 页 ${rooms.length} 个；$second';
  }

  Future<_Page> _directory({required int page, String? cursor, LiveArea? area}) async {
    final pager = switch (site) {
      final LiveSiteCategoryDirectoryProvider provider when area != null => provider.categoryDirectory,
      final LiveSiteDirectoryPager pager => pager,
      _ => null,
    };
    final what = area == null ? '推荐' : '分区“${area.areaName}”';
    _step = '$what第 $page 页';
    if (pager != null) {
      final LiveDirectoryPage result;
      if (page > 1 && pager is LiveSiteCursorDirectoryPager) {
        result = await pager.getDirectoryPageAtCursor(page: page, cursor: cursor, category: area);
      } else {
        result = await pager.getDirectoryPage(page: page, category: area);
      }
      return _Page(result.rooms, hasMore: result.hasMore, cursor: result.nextCursor);
    }
    final rooms = area == null
        ? await site.getRecommendRooms(page: page)
        : await site.getCategoryRooms(area, page: page);
    return _Page(rooms);
  }

  Future<String> _secondPage(_Page first, Future<_Page> Function(String? cursor) next) async {
    if (first.hasMore == false) return '没有第 2 页（平台说没有更多）';
    final second = await next(first.cursor);
    if (second.rooms.isEmpty) return '第 2 页为空（没有更多）';
    final firstIds = {for (final room in first.rooms) room.roomId};
    final repeated = second.rooms.where((room) => firstIds.contains(room.roomId)).length;
    final note = '第 2 页 ${second.rooms.length} 个，和第 1 页重复 $repeated 个';
    if (repeated * 2 > second.rooms.length) throw CheckFailure('$note（超过一半）');
    return note;
  }

  void _checkCards(List<LiveRoom> rooms, String where) {
    final bad = rooms.where((room) => room.roomId.trim().isEmpty || (room.title.trim().isEmpty && !room.hasNick));
    if (bad.isNotEmpty) throw CheckFailure('$where ${rooms.length} 个里 ${bad.length} 个没有房间号，或标题和主播名都空');
  }

  // P2 ----------------------------------------------------------------------

  Future<String> _categoriesCheck() async {
    _step = 'getCategories';
    final categories = await site.getCategories(1, 30);
    if (categories.isEmpty) throw const CheckFailure('没有分类');
    final areas = categories.fold<int>(0, (sum, category) => sum + category.children.length);
    final empty = categories.where((category) => category.children.isEmpty).map((category) => category.name).toList();
    final note = '${categories.length} 类、$areas 个分区';
    if (empty.isNotEmpty) throw CheckFailure('$note；${empty.length} 类没有分区（${empty.take(3).join('、')}）');
    _categories = categories;
    return note;
  }

  // P3 ----------------------------------------------------------------------

  Future<String> _area() async {
    final categories = _categories;
    if (categories == null || categories.isEmpty) throw const CheckSkipped('P2 没拿到分类');
    final area = _pickArea(categories);
    final first = await _directory(page: 1, area: area);
    if (first.rooms.isEmpty) throw CheckFailure('“${area.areaName}”第 1 页为空');
    _checkCards(first.rooms, '“${area.areaName}”第 1 页');
    _areaRooms.addAll(first.rooms);
    final head = '“${area.areaName}”第 1 页 ${first.rooms.length} 个';
    try {
      return '$head；${await _secondPage(first, (cursor) => _directory(page: 2, cursor: cursor, area: area))}';
    } on CheckFailure catch (failure) {
      throw CheckFailure('$head；${failure.note}');
    }
  }

  LiveArea _pickArea(List<LiveCategory> categories) {
    if (target.area case final wanted?) {
      for (final category in categories) {
        for (final area in category.children) {
          if (area.areaName == wanted) return area;
        }
      }
    }
    final largest = categories.reduce((a, b) => b.children.length > a.children.length ? b : a);
    return largest.children.first;
  }

  // P4, P5 ------------------------------------------------------------------

  String? get _keyword => switch (target.search) {
    SearchKind.keyword ||
    SearchKind.liveOnly ||
    SearchKind.channelLookup => target.keyword.isEmpty ? null : target.keyword,
    SearchKind.recommendFilter => _recommended.where((room) => room.hasNick).firstOrNull?.nick,
    SearchKind.roomLookup => _recommended.firstOrNull?.roomId,
  };

  Future<String> _searchRooms() async {
    final keyword = _keyword;
    if (keyword == null) throw const CheckSkipped('没有关键词（推荐为空）');
    _step = 'searchRooms';
    final rooms = await site.searchRooms(keyword);
    final live = rooms.where((room) => room.isLiveNow).length;
    final note = '“$keyword”${rooms.length} 个（在播 $live）';
    if (rooms.isEmpty) throw CheckFailure('$note，结果为空');
    if (target.search == SearchKind.liveOnly && live < rooms.length) {
      throw CheckFailure('$note：只搜直播中的平台搜出 ${rooms.length - live} 个未开播');
    }
    _searched.addAll(rooms);
    return note;
  }

  Future<String> _searchAnchors() async {
    final keyword = _keyword;
    if (keyword == null) throw const CheckSkipped('没有关键词');
    _step = 'searchAnchors';
    final anchors = await site.searchAnchors(keyword);
    final live = anchors.where((anchor) => anchor.liveStatus).length;
    final note = '“$keyword”${anchors.length} 个（在播 $live）';
    if (anchors.isEmpty) throw CheckFailure('$note，结果为空');
    return note;
  }

  // P6 ----------------------------------------------------------------------

  Future<String> _liveDetails() async {
    final seen = <String>{};
    final candidates = [
      // A platform that must name the area takes the area page's rooms
      // first (Douyin: P3's game area, where the detail names the game).
      for (final room
          in target.requireArea
              ? [..._areaRooms, ..._recommended, ..._searched]
              : [..._recommended, ..._areaRooms, ..._searched])
        if (room.roomId.trim().isNotEmpty && (room.liveStatus == null || room.isLiveNow) && seen.add(room.roomId)) room,
    ];
    if (candidates.isEmpty) throw const CheckSkipped('推荐、分区和搜索里没有在播房间');
    final notes = <String>[];
    final problems = <String>[];
    var tried = 0;
    for (final candidate in candidates.take(6)) {
      if (_live.length >= 3) break;
      tried++;
      _step = 'getRoomDetail ${candidate.roomId}';
      final LiveRoom fetched;
      try {
        fetched = await site.getRoomDetail(roomId: candidate.roomId);
      } on RiskControl {
        rethrow;
      } on Object catch (error) {
        problems.add('${candidate.roomId}：${describeError(error)}');
        continue;
      }
      if (!fetched.isLiveNow) {
        notes.add('${candidate.roomId} 已经${fetched.effectiveLiveStatus.name}（跳过）');
        continue;
      }
      // As the room page does (`room_controller.dart`): what the detail
      // lacks comes from the card it was entered from (Kuaishou's page has
      // no broadcast title, A-3). The area rule reads the detail itself.
      final detail = fetched.fillFromDetail(candidate);
      final fromCard = fetched.title.trim().isEmpty && detail.title.trim().isNotEmpty;
      final missing = [
        if (detail.title.trim().isEmpty) '标题',
        if (!detail.hasNick) '主播名',
        if (target.requireArea && (fetched.area?.trim().isEmpty ?? true)) '分区',
      ];
      final started = detail.startedAt;
      if (started != null && started.isAfter(_now().add(const Duration(minutes: 2)))) missing.add('开播时间（晚于现在）');
      if (missing.isNotEmpty) problems.add('${detail.roomId} 缺${missing.join('、')}');
      _live.add(detail);
      notes.add(
        '${detail.roomId}${detail.area == null || detail.area!.isEmpty ? '' : '（${detail.area}）'}'
        '${fromCard ? ' 标题取自卡片' : ''}'
        '${started == null ? '' : ' 开播于 ${started.toUtc().toIso8601String().substring(0, 16)}Z'}',
      );
    }
    final note = '试了 $tried 个，在播 ${_live.length} 个：${notes.join('；')}';
    if (problems.isNotEmpty) throw CheckFailure('$note；问题：${problems.join('；')}');
    if (_live.isEmpty) throw CheckSkipped('$note；没拿到在播房间');
    return note;
  }

  // P7 ----------------------------------------------------------------------

  static const Set<LiveStatus> _notLive = {LiveStatus.offline, LiveStatus.replay, LiveStatus.carousel};

  Future<String> _fixedRooms() async {
    if (target.fixedRooms.isEmpty) throw const CheckSkipped('没有固定的未开播房间（CHECKS.md 待补）');
    final notes = <String>[];
    var failed = false;
    var passed = 0;
    for (final room in target.fixedRooms) {
      _step = 'getRoomDetail ${room.roomId}';
      try {
        final detail = await site.getRoomDetail(roomId: room.roomId);
        final state = detail.effectiveLiveStatus;
        final label =
            '${room.roomId}（${room.note}）→ ${state.name}'
            '${sameRoom(target.site, detail.roomId, room.roomId) ? '' : '，房间号 ${detail.roomId}'}';
        if (room.anyState || _notLive.contains(state)) {
          passed++;
          notes.add(label);
        } else if (state == LiveStatus.live) {
          notes.add('$label（正在直播，这次没测到）');
        } else {
          failed = true;
          notes.add('$label（状态不对）');
        }
      } on RiskControl {
        rethrow;
      } on Object catch (error) {
        failed = true;
        notes.add('${room.roomId}（${room.note}）→ ${describeError(error)}');
      }
    }
    final note = notes.join('；');
    if (failed) throw CheckFailure(note);
    if (passed == 0) throw CheckSkipped(note);
    return note;
  }

  // P8 ----------------------------------------------------------------------

  Future<String> _missingRoom() async {
    final roomId = target.missingRoom;
    if (roomId == null) throw const CheckSkipped('没有固定的不存在房间号（CHECKS.md 待补）');
    _step = 'getRoomDetail $roomId';
    try {
      final detail = await site.getRoomDetail(roomId: roomId);
      throw CheckFailure('$roomId 没有报错，状态 ${detail.effectiveLiveStatus.name}（应报 NotFound）');
    } on NotFound {
      return '$roomId → NotFound';
    } on CheckFailure {
      rethrow;
    } on Object catch (error) {
      throw CheckFailure('错误类型不对：$roomId → ${describeError(error)}（应报 NotFound）');
    }
  }

  // P9 ----------------------------------------------------------------------

  Future<String> _qualitiesCheck() async {
    if (_live.isEmpty) throw const CheckSkipped('P6 没拿到在播房间');
    final notes = <String>[];
    final problems = <String>[];
    for (final room in _live) {
      _step = 'discoverPlayQualities ${room.roomId}';
      final qualities = await site.discoverPlayQualities(detail: room);
      final names = [for (final quality in qualities) quality.quality.trim()];
      if (qualities.isEmpty) {
        problems.add('${room.roomId} 没有清晰度');
        continue;
      }
      if (names.any((name) => name.isEmpty)) problems.add('${room.roomId} 有空名字');
      if (names.toSet().length != names.length) problems.add('${room.roomId} 名字重复');
      _qualities[room.roomId] = qualities;
      notes.add('${room.roomId} ${qualities.length} 档（${names.take(4).join('、')}${names.length > 4 ? '…' : ''}）');
    }
    final note = notes.join('；');
    if (problems.isNotEmpty) throw CheckFailure([note, ...problems].where((text) => text.isNotEmpty).join('；'));
    return note;
  }

  // P10 ---------------------------------------------------------------------

  Future<String> _linesCheck() async {
    if (_qualities.isEmpty) throw const CheckSkipped('P9 没拿到清晰度');
    final notes = <String>[];
    var failed = false;
    for (final room in _live) {
      final qualities = _qualities[room.roomId];
      if (qualities == null) continue;
      final quality = qualities.first;
      _step = 'resolvePlayUrls ${room.roomId} ${quality.quality}';
      final resolution = await site.resolvePlayUrls(detail: room, quality: quality);
      final applied = resolution.appliedQualityData;
      final downgraded = applied != null && '$applied' != '${quality.selectionId}' ? '，实际给 $applied' : '';
      final head = '${room.roomId}“${quality.quality}”$downgraded';
      if (resolution.inputRecipe != null) {
        notes.add('$head：配方，未打开');
        continue;
      }
      if (resolution.lines.isEmpty) {
        failed = true;
        notes.add('$head：没有线路');
        continue;
      }
      final kinds = <String, int>{};
      final bad = <String>[];
      for (final line in resolution.lines) {
        _lines.add(line);
        final url = Uri.parse(line.url);
        _step = '读线路 ${url.host}';
        final answer = await media(target.site, line);
        final found = container(answer.bytes);
        if (answer.ok && containerMatches(line.format, url, found)) {
          kinds.update(found.label, (count) => count + 1, ifAbsent: () => 1);
        } else {
          final why = answer.error ?? (answer.ok ? '开头是${found.label}' : 'HTTP ${answer.status}');
          bad.add('${url.host}/${url.pathSegments.take(2).join('/')}（${line.format?.name ?? '?'}，$why）');
        }
      }
      final good = resolution.lines.length - bad.length;
      if (good == 0 || bad.length * 2 > resolution.lines.length) failed = true;
      notes.add(
        '$head：${resolution.lines.length} 条，'
        '${kinds.entries.map((entry) => '${entry.key} ${entry.value}').join('、')}'
        '${bad.isEmpty ? '' : '；不通 ${bad.length} 条：${bad.join('、')}'}',
      );
    }
    _resolved = true;
    final note = notes.join('；');
    if (failed) throw CheckFailure(note);
    return note;
  }

  // P11 ---------------------------------------------------------------------

  Future<String> _leases() async {
    if (!_resolved) throw const CheckSkipped('P10 没拿到线路');
    final leases = [for (final line in _lines) ?line.lease];
    if (leases.isEmpty) return '线路没有租期（${_lines.length} 条）';
    final now = _now();
    final bad = <String>[];
    var shortest = const Duration(days: 365);
    for (final lease in leases) {
      final left = lease.refreshAt.difference(now);
      if (left < shortest) shortest = left;
      if (!lease.refreshAt.isAfter(now)) bad.add('refreshAt 已过');
      if (lease.expiresAt case final expires? when expires.isBefore(lease.refreshAt)) bad.add('expiresAt 早于 refreshAt');
    }
    final cuts = leases.where((lease) => lease.cutsConnection).length;
    final note =
        '${leases.length}/${_lines.length} 条有租期，最短 ${shortest.inMinutes} 分钟后续期'
        '${cuts == 0 ? '' : '，$cuts 条到期断开'}';
    if (bad.isNotEmpty) throw CheckFailure('$note；${bad.toSet().join('、')}');
    return note;
  }

  // P12 ---------------------------------------------------------------------

  Future<String> _links() async {
    final cases = <LinkCase>[];
    if (_live.firstOrNull case final room?) {
      if (room.link case final link? when link.trim().isNotEmpty) {
        cases.add(LinkCase(link, expected: room.roomId, note: '详情的链接'));
      }
      if (target.roomLink case final build?) {
        final url = build(room.roomId);
        if (!cases.any((item) => item.url == url)) cases.add(LinkCase(url, expected: room.roomId, note: '房间页'));
      }
    }
    cases.addAll(target.links);
    if (cases.isEmpty) throw const CheckSkipped('没有在播房间的链接，也没有固定的链接');
    final notes = <String>[];
    var failed = false;
    for (final item in cases) {
      _step = '解析 ${item.note}';
      final found = await links(site, item.url);
      final expected = item.expected;
      final label = Uri.tryParse(item.url)?.host ?? item.url;
      if (found == null) {
        failed = true;
        notes.add('${item.note}（$label）认不出');
      } else if (expected != null && !sameRoom(target.site, found, expected)) {
        failed = true;
        notes.add('${item.note}（$label）→ $found，应为 $expected');
      } else {
        notes.add('${item.note}（$label）→ $found');
      }
    }
    final note = notes.join('；');
    if (failed) throw CheckFailure(note);
    return note;
  }

  // P13 ---------------------------------------------------------------------

  Future<String> _danmaku() async {
    if (danmakuDuration <= Duration.zero) throw const CheckSkipped('没加 --danmaku');
    final probe = danmaku;
    if (probe == null) throw const CheckSkipped('工具没有这个平台的弹幕连接');
    final room = _live.firstOrNull;
    if (room == null) throw const CheckSkipped('P6 没拿到在播房间');
    _step = '连弹幕 ${room.roomId}';
    final sample = await probe(site, room, danmakuDuration);
    final ready = sample.ready;
    final note =
        '${room.roomId} ${danmakuDuration.inSeconds} 秒：'
        '${ready == null ? '没有就绪' : '就绪 ${ready.inMilliseconds} ms'}，'
        '聊天 ${sample.chats} 条，人数 ${sample.online} 次，重连 ${sample.reconnects} 次'
        '${sample.closed == null ? '' : '，关闭（${sample.closed}）'}'
        '${sample.error == null ? '' : '，${sample.error}'}';
    if (ready == null || sample.closed != null || sample.error != null) throw CheckFailure(note);
    return note;
  }
}

final class _Page {
  new(this.rooms, {this.hasMore, this.cursor});

  final List<LiveRoom> rooms;
  final bool? hasMore;
  final String? cursor;
}
