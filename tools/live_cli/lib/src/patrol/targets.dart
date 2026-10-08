import 'package:live_core/live_core.dart';
import 'package:meta/meta.dart';

/// The patrol checks, P1 to P13 (docs/E-直播平台/E07-平台巡检/CHECKS.md).
enum CheckId {
  /// Recommendations, pages 1 and 2.
  p1('P1', '推荐'),

  /// Categories and their areas.
  p2('P2', '分类'),

  /// One area, pages 1 and 2.
  p3('P3', '分区'),

  /// Room search.
  p4('P4', '搜索房间'),

  /// Streamer search.
  p5('P5', '搜索主播'),

  /// Details of three live rooms.
  p6('P6', '在播详情'),

  /// Details of the fixed rooms that are not live.
  p7('P7', '未开播详情'),

  /// A room that does not exist.
  p8('P8', '不存在的房间'),

  /// Qualities of the live rooms.
  p9('P9', '清晰度'),

  /// The lines of the default quality and their first bytes.
  p10('P10', '线路'),

  /// The leases of the lines.
  p11('P11', '租期'),

  /// Room links.
  p12('P12', '链接'),

  /// Danmaku (only with `--danmaku`).
  p13('P13', '弹幕');

  new(this.code, this.title);

  /// `P1`.
  final String code;

  /// Chinese name, as in the report.
  final String title;

  /// `P1 推荐`.
  String get label => '$code $title';

  /// The check with [code] (`P4`, case ignored), or null.
  static CheckId? byCode(String code) {
    final wanted = code.trim().toUpperCase();
    for (final id in values) {
      if (id.code == wanted) return id;
    }
    return null;
  }
}

/// What the room search of a platform covers (`search_capability.dart`).
enum SearchKind {
  /// Live and offline rooms by keyword.
  keyword,

  /// Live rooms only: every result must be live.
  liveOnly,

  /// The platform filters its own recommendations: the keyword is the name
  /// of the first recommended streamer.
  recommendFilter,

  /// Only an exact room id: the keyword is the first recommended room's id.
  roomLookup,

  /// Only an exact channel name: the keyword is [PatrolTarget.keyword].
  channelLookup,
}

/// A fixed room and what the patrol expects of it.
@immutable
final class FixedRoom {
  /// Creates the room.
  const new(this.roomId, {this.note = '', this.anyState = false});

  /// Room id as the adapter takes it.
  final String roomId;

  /// What the room is (`轮播`、`靓号`).
  final String note;

  /// Whether any state passes (a short id that may be live).
  final bool anyState;
}

/// A link and the room it must lead to.
@immutable
final class LinkCase {
  /// Creates the case; [expected] null accepts any room.
  const new(this.url, {this.expected, this.note = ''});

  /// The link.
  final String url;

  /// The room it must lead to, or null for any.
  final String? expected;

  /// What the link is (`别名页`).
  final String note;
}

/// One platform's patrol targets: a row of the object table in CHECKS.md.
@immutable
final class PatrolTarget {
  /// Creates the row.
  const new({
    required this.site,
    required this.name,
    this.overseas = false,
    this.keyword = '',
    this.search = SearchKind.keyword,
    this.anchors = false,
    this.area,
    this.fixedRooms = const [],
    this.missingRoom,
    this.links = const [],
    this.roomLink,
    this.interval = Duration.zero,
    this.unsupported = const {},
    this.skip,
    this.requireArea = false,
    this.checkTimeout,
    this.note = '',
  });

  /// Platform id (`SiteIds`).
  final String site;

  /// Chinese display name.
  final String name;

  /// Whether the platform is reached through `--proxy`.
  final bool overseas;

  /// Search keyword (or channel name for [SearchKind.channelLookup]).
  final String keyword;

  /// What the room search covers.
  final SearchKind search;

  /// Whether the platform offers streamer search.
  final bool anchors;

  /// Area name to page (P3); null takes the first area of the category with
  /// the most areas.
  final String? area;

  /// Rooms for P7 (offline, replay, carousel, special ids).
  final List<FixedRoom> fixedRooms;

  /// A room id that does not exist (P8); null when none is known.
  final String? missingRoom;

  /// Extra links for P12 (aliases, short ids, case).
  final List<LinkCase> links;

  /// A room page for a room id (P12, beside the detail's link); null when
  /// the id has none.
  final String? Function(String roomId)? roomLink;

  /// Pause between checks of this platform (and between its requests).
  final Duration interval;

  /// Checks the platform does not offer, with the reason.
  final Map<CheckId, String> unsupported;

  /// Why the whole platform is not patrolled from a PC, or null.
  final String? skip;

  /// Whether a live room's detail must name its area (P6); the area page's
  /// rooms (P3) are then tried first.
  final bool requireArea;

  /// Limit per check when the platform is slow on purpose (request
  /// interval); null keeps the patrol's 30 seconds.
  final Duration? checkTimeout;

  /// Notes for the report.
  final String note;
}

String _bilibiliRoom(String id) => 'https://live.bilibili.com/$id';
String _douyuRoom(String id) => 'https://www.douyu.com/$id';
String _huyaRoom(String id) => 'https://www.huya.com/$id';
String _douyinRoom(String id) => 'https://live.douyin.com/$id';
String _kuaishouRoom(String id) => 'https://live.kuaishou.com/u/$id';
String? _nicoShort(String id) => id.startsWith('lv') ? 'https://nico.ms/$id' : null;

const String _noDanmaku = '平台不提供弹幕（platforms.dart 没登记）';
const String _noAnchors = '平台不提供搜索主播（search_capability.dart）';
const String _noAreas = '平台没有分区';

/// The 34 platforms of CHECKS.md (IPTV is the user's own list and is not
/// patrolled), in `SiteIds.supported` order.
final List<PatrolTarget> patrolTargets = List.unmodifiable(<PatrolTarget>[
  const PatrolTarget(
    site: SiteIds.bilibili,
    name: '哔哩哔哩',
    keyword: '英雄联盟',
    anchors: true,
    area: '英雄联盟',
    fixedRooms: [
      FixedRoom('21987615', note: '未开播'),
      FixedRoom('5440', note: '轮播或回放'),
      FixedRoom('6', note: '短号（可能在播）', anyState: true),
    ],
    missingRoom: '999999999',
    links: [LinkCase('https://live.bilibili.com/6', expected: '6', note: '短号')],
    roomLink: _bilibiliRoom,
    note: '游客请求 400 实际给 250（P9、P10 记实际档）',
  ),
  const PatrolTarget(
    site: SiteIds.douyu,
    name: '斗鱼',
    keyword: '英雄联盟',
    anchors: true,
    area: '英雄联盟',
    fixedRooms: [
      FixedRoom('71415', note: '未开播'),
      FixedRoom('93976', note: '轮播'),
      FixedRoom('1', note: '靓号'),
    ],
    missingRoom: '999999999',
    links: [
      LinkCase('https://www.douyu.com/lpl', expected: '288016', note: '别名页'),
      LinkCase('https://www.douyu.com/LPL', expected: '288016', note: '别名页（大写）'),
    ],
    roomLink: _douyuRoom,
  ),
  const PatrolTarget(
    site: SiteIds.huya,
    name: '虎牙',
    keyword: '英雄联盟',
    search: SearchKind.liveOnly,
    anchors: true,
    area: '英雄联盟',
    fixedRooms: [
      FixedRoom('333003', note: '未开播'),
      FixedRoom('102411', note: '回放'),
    ],
    missingRoom: '999999999',
    links: [LinkCase('https://www.huya.com/lpl', note: '字母别名')],
    roomLink: _huyaRoom,
  ),
  const PatrolTarget(
    site: SiteIds.douyin,
    name: '抖音',
    keyword: '王者荣耀',
    search: SearchKind.liveOnly,
    fixedRooms: [FixedRoom('745964462470', note: '未开播')],
    missingRoom: '999999999999',
    roomLink: _douyinRoom,
    unsupported: {CheckId.p5: _noAnchors},
    requireArea: true,
    note: '用 web_rid 进房；游戏直播间的分区要非空',
  ),
  const PatrolTarget(
    site: SiteIds.kuaishou,
    name: '快手',
    keyword: '王者荣耀',
    anchors: true,
    fixedRooms: [
      FixedRoom('tianci666', note: '未开播'),
      FixedRoom('kpl704668133', note: '小写的用户 id（平台答 KPL704668133）', anyState: true),
    ],
    missingRoom: 'purelive_fixture_404',
    links: [LinkCase('https://live.kuaishou.com/u/kpl704668133', expected: 'KPL704668133', note: '大小写不同的用户 id')],
    roomLink: _kuaishouRoom,
    interval: Duration(milliseconds: 2500),
    // About 20 category requests 2.5 s apart (E01.5).
    checkTimeout: Duration(seconds: 90),
  ),
  const PatrolTarget(
    site: SiteIds.cc,
    name: '网易 CC',
    keyword: '王者荣耀',
    anchors: true,
    fixedRooms: [
      FixedRoom('376267758', note: '未开播'),
      FixedRoom('732923115', note: '回放'),
    ],
    missingRoom: '88888888888',
    unsupported: {CheckId.p13: '匿名加入不回应（C-22），没登记弹幕'},
  ),
  const PatrolTarget(
    site: SiteIds.twitch,
    name: 'Twitch',
    overseas: true,
    keyword: 'league of legends',
    fixedRooms: [FixedRoom('minecraft', note: '未开播（官方频道，可能在播）', anyState: true)],
    missingRoom: 'zxqvnochannelfixture',
    unsupported: {CheckId.p5: _noAnchors},
    note: '电脑上没有 Android 系统 TLS 后备，GraphQL 被拒时单独标“电脑上被拒”',
  ),
  const PatrolTarget(
    site: SiteIds.soop,
    name: 'SOOP',
    overseas: true,
    keyword: '리그 오브 레전드',
    search: SearchKind.liveOnly,
    fixedRooms: [FixedRoom('phonics1', note: '未开播')],
    missingRoom: 'zzzqqqxxxnotexist1',
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.yy,
    name: 'YY',
    // 英雄联盟 finds nothing on YY (entertainment rooms), 2026-10-08.
    keyword: '王者荣耀',
    search: SearchKind.liveOnly,
    anchors: true,
    fixedRooms: [
      FixedRoom('85520900', note: '未开播'),
      FixedRoom('2149', note: '短号', anyState: true),
    ],
    missingRoom: '999999999999',
    note: 'FLV 优先没打开（E06.3），P10 是移动 HLS',
  ),
  const PatrolTarget(
    site: SiteIds.acfun,
    name: 'AcFun',
    keyword: '游戏',
    anchors: true,
    fixedRooms: [FixedRoom('1', note: '未开播')],
    missingRoom: '99999999999',
  ),
  const PatrolTarget(
    site: SiteIds.picarto,
    name: 'Picarto',
    overseas: true,
    keyword: 'art',
    fixedRooms: [FixedRoom('Kaiyote', note: '未开播', anyState: true)],
    missingRoom: 'zxqvnochannelfixture',
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.twitcasting,
    name: 'TwitCasting',
    overseas: true,
    keyword: 'ゲーム',
    search: SearchKind.liveOnly,
    fixedRooms: [FixedRoom('twitcasting_jp', note: '未开播', anyState: true)],
    missingRoom: 'zxqvnochannelfixture',
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.missevan,
    name: '猫耳 FM',
    keyword: '电台',
    fixedRooms: [FixedRoom('507069668', note: '未开播', anyState: true)],
    missingRoom: '1',
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.inke,
    name: '映客',
    search: SearchKind.recommendFilter,
    fixedRooms: [FixedRoom('1', note: '未开播')],
    unsupported: {CheckId.p5: _noAnchors, CheckId.p13: _noDanmaku},
  ),
  const PatrolTarget(
    site: SiteIds.kilakila,
    name: '克拉克拉',
    keyword: '唱歌',
    fixedRooms: [FixedRoom('1775178981381', note: '未开播', anyState: true)],
    missingRoom: '1',
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.xiaohongshu,
    name: '小红书',
    search: SearchKind.roomLookup,
    fixedRooms: [FixedRoom('570305058583373361', note: '已结束的场次')],
    missingRoom: '569865232324657152',
    unsupported: {CheckId.p2: _noAreas, CheckId.p3: _noAreas, CheckId.p5: _noAnchors, CheckId.p13: _noDanmaku},
  ),
  const PatrolTarget(
    site: SiteIds.niconico,
    name: 'niconico',
    overseas: true,
    keyword: 'ゲーム',
    search: SearchKind.liveOnly,
    missingRoom: 'lv1',
    roomLink: _nicoShort,
    unsupported: {CheckId.p5: _noAnchors},
    note: '会话型取流（P10 记配方）；P12 另试 nico.ms 链接',
  ),
  const PatrolTarget(
    site: SiteIds.weibo,
    name: '微博直播',
    search: SearchKind.roomLookup,
    fixedRooms: [FixedRoom('1022:2321325269875509035102', note: '已结束（回放）')],
    missingRoom: '1022:2321320000000000000001',
    unsupported: {CheckId.p5: _noAnchors, CheckId.p13: _noDanmaku},
  ),
  const PatrolTarget(
    site: SiteIds.showroom,
    name: 'SHOWROOM',
    overseas: true,
    keyword: 'アイドル',
    search: SearchKind.liveOnly,
    fixedRooms: [FixedRoom('61576', note: '未开播', anyState: true)],
    missingRoom: 'zxqvnoroomfixture',
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.chzzk,
    name: 'CHZZK',
    overseas: true,
    keyword: '리그 오브 레전드',
    fixedRooms: [FixedRoom('12bba8d480ba0ffaf85656afd76fa792', note: '未开播', anyState: true)],
    missingRoom: '00000000000000000000000000000000',
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.kick,
    name: 'Kick',
    overseas: true,
    skip: '要 Android 原生通道（Cloudflare 按 TLS 指纹拒绝 dart:io），电脑上不测，不算失败',
  ),
  const PatrolTarget(
    site: SiteIds.liveMe,
    name: 'LiveMe',
    overseas: true,
    keyword: 'music',
    fixedRooms: [FixedRoom('17709377', note: '未开播', anyState: true)],
    missingRoom: '999999999',
    unsupported: {CheckId.p2: _noAreas, CheckId.p3: _noAreas, CheckId.p5: _noAnchors, CheckId.p13: '受阻：要登录 IM'},
  ),
  const PatrolTarget(
    site: SiteIds.tiktok,
    name: 'TikTok',
    overseas: true,
    keyword: 'cnn',
    search: SearchKind.channelLookup,
    fixedRooms: [FixedRoom('cnn', note: '未开播', anyState: true)],
    missingRoom: 'zxqvnochannelfixture',
    unsupported: {
      CheckId.p1: '受阻（22-8）：没有推荐',
      CheckId.p2: '受阻（22-8）：没有分区',
      CheckId.p3: '受阻（22-8）：没有分区',
      CheckId.p5: _noAnchors,
      CheckId.p13: '受阻：要签名',
    },
  ),
  const PatrolTarget(
    site: SiteIds.youtube,
    name: 'YouTube',
    overseas: true,
    keyword: 'live',
    search: SearchKind.liveOnly,
    fixedRooms: [FixedRoom('UCX6OQ3DkcsbYNE6H8uQQuVA', note: '频道（通常未开播）', anyState: true)],
    unsupported: {CheckId.p2: _noAreas, CheckId.p3: _noAreas, CheckId.p5: _noAnchors},
    note: '推荐是“直播”频道页（目录分页）',
  ),
  const PatrolTarget(
    site: SiteIds.bigo,
    name: 'BIGO LIVE',
    overseas: true,
    search: SearchKind.recommendFilter,
    fixedRooms: [FixedRoom('qashia305', note: '未开播', anyState: true)],
    missingRoom: 'zzqxnomatch',
    unsupported: {CheckId.p5: _noAnchors},
    note: '会话型取流；搜索是推荐里筛选',
  ),
  const PatrolTarget(
    site: SiteIds.pandaLive,
    name: 'PandaTV',
    overseas: true,
    keyword: '노래',
    fixedRooms: [FixedRoom('flffl369', note: '未开播', anyState: true)],
    missingRoom: 'zxqvnouserfix',
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.fc2Live,
    name: 'FC2 LIVE',
    overseas: true,
    keyword: 'game',
    fixedRooms: [FixedRoom('10608314', note: '未开播', anyState: true)],
    missingRoom: '99999999',
    unsupported: {CheckId.p5: _noAnchors},
    note: '会话型取流（P10 记配方）',
  ),
  const PatrolTarget(
    site: SiteIds.steamBroadcast,
    name: 'Steam 直播',
    overseas: true,
    // Broadcaster names: dota finds nothing (2026-10-08).
    keyword: 'game',
    fixedRooms: [FixedRoom('76561197960287930', note: '未开播')],
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.jdLive,
    name: '京东直播',
    // Shop names: 手机 finds nothing, 京东 the 京东自营 shops (2026-10-08).
    keyword: '京东',
    fixedRooms: [FixedRoom('48378944', note: '已结束', anyState: true)],
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.kugouLive,
    name: '酷狗直播',
    keyword: '唱歌',
    fixedRooms: [FixedRoom('1014306', note: '未开播', anyState: true)],
    missingRoom: '999',
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.baiduLive,
    name: '百度直播',
    search: SearchKind.roomLookup,
    missingRoom: '99999999999',
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.sixRoom,
    name: '六间房',
    keyword: '唱歌',
    fixedRooms: [FixedRoom('191111', note: '未开播', anyState: true)],
    missingRoom: '99999999999',
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.lookLive,
    name: 'LOOK 直播',
    search: SearchKind.roomLookup,
    fixedRooms: [FixedRoom('325808387', note: '未开播', anyState: true)],
    unsupported: {CheckId.p5: _noAnchors},
  ),
  const PatrolTarget(
    site: SiteIds.seventeenLive,
    name: '17LIVE',
    overseas: true,
    // Streamer names: music finds nothing (2026-10-08).
    keyword: 'a',
    search: SearchKind.liveOnly,
    fixedRooms: [FixedRoom('28371376', note: '未开播', anyState: true)],
    missingRoom: '999999999',
    unsupported: {CheckId.p5: _noAnchors},
  ),
]);

/// The domestic platforms (direct), in order.
List<PatrolTarget> get domesticTargets => [
  for (final target in patrolTargets)
    if (!target.overseas) target,
];

/// The overseas platforms (through `--proxy`), in order.
List<PatrolTarget> get overseasTargets => [
  for (final target in patrolTargets)
    if (target.overseas) target,
];

/// The target of [site] (case ignored), or null.
PatrolTarget? targetOf(String site) {
  final id = site.trim().toLowerCase();
  for (final target in patrolTargets) {
    if (target.site == id) return target;
  }
  return null;
}
