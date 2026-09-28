import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/follows/follow_refresh.dart';

/// How a list request of the fake platforms answers.
enum ListMode {
  /// A page of rooms.
  rooms,

  /// Never answers (the loading state).
  loading,

  /// A network failure.
  error,

  /// An empty page.
  empty,
}

/// One made-up room: every name and title here is invented.
typedef ShotRoom = ({
  String platform,
  String id,
  String anchor,
  String title,
  int online,
  Duration liveFor,
  String area,
});

/// Invented streamers and titles, long enough to show wrapping and
/// ellipsis; audience figures across the ranges the formatter handles.
const List<ShotRoom> shotRooms = [
  (
    platform: 'bilibili',
    id: '1001',
    anchor: '北岛看海',
    title: '周末深夜档：艾尔登法环 DLC 全 Boss 无伤挑战，今晚不通关不下播',
    online: 1280000,
    liveFor: Duration(hours: 3, minutes: 12),
    area: '单机游戏',
  ),
  (
    platform: 'douyu',
    id: '288016',
    anchor: '夜航星',
    title: '英雄联盟 大师分段冲分',
    online: 355100,
    liveFor: Duration(hours: 1, minutes: 24),
    area: '英雄联盟',
  ),
  (
    platform: 'huya',
    id: '660000',
    anchor: '阿澈Ace',
    title: '户外｜川西自驾第三天 海拔四千米看日出',
    online: 52300,
    liveFor: Duration(minutes: 47),
    area: '户外',
  ),
  (
    platform: 'douyin',
    id: '70010',
    anchor: '橘子汽水',
    title: '【钢琴】听歌识曲，点歌请发弹幕',
    online: 9876,
    liveFor: Duration(hours: 2, minutes: 5),
    area: '音乐',
  ),
  (
    platform: 'kuaishou',
    id: '80010',
    anchor: '山海经',
    title: '空洞骑士 苦痛之路 第 27 次尝试',
    online: 3421,
    liveFor: Duration(minutes: 18),
    area: '单机游戏',
  ),
  (
    platform: 'twitch',
    id: 'kiri',
    anchor: 'Kiri',
    title: 'Chill stream: blind run of a very long metroidvania with chat picks',
    online: 12400,
    liveFor: Duration(hours: 5, minutes: 40),
    area: 'Just Chatting',
  ),
  (
    platform: 'bilibili',
    id: '1002',
    anchor: '雨后的猫',
    title: '聊天电台：深夜陪你说说话',
    online: 8210,
    liveFor: Duration(hours: 1, minutes: 2),
    area: '聊天电台',
  ),
  (
    platform: 'cc',
    id: '361433',
    anchor: '小鹿在跑',
    title: '第五人格 排位上分 带水友',
    online: 523,
    liveFor: Duration(minutes: 9),
    area: '手游',
  ),
  (
    platform: 'douyu',
    id: '5720533',
    anchor: '老K讲历史',
    title: '三国志从头讲 第十二回',
    online: 40210,
    liveFor: Duration(hours: 4, minutes: 1),
    area: '知识',
  ),
  (
    platform: 'huya',
    id: '11342412',
    anchor: '白鹭鸶',
    title: '美食 · 一个人做一桌年夜饭',
    online: 150000,
    liveFor: Duration(hours: 2, minutes: 33),
    area: '美食',
  ),
  (
    platform: 'bilibili',
    id: '1003',
    anchor: '一只大鹅',
    title: 'CS2 职业选手第一视角 天梯',
    online: 67800,
    liveFor: Duration(minutes: 55),
    area: '网络游戏',
  ),
  (
    platform: 'douyu',
    id: '9999',
    anchor: '木子李',
    title: '手工 · 木工桌从零开始',
    online: 1200,
    liveFor: Duration(hours: 6, minutes: 20),
    area: '户外',
  ),
];

/// Followed streamers that are not live: (platform, id, name, title, last live ago).
const List<(String, String, String, String, Duration?)> shotOfflineFollows = [
  ('douyu', '71415', '青柠不酸', '上次直播：原神 新版本剧情首通', Duration(hours: 3)),
  ('huya', '520520', '深海鱼', '看电影聊电影｜本周新片', Duration(days: 2)),
  ('bilibili', '2233', '晚风 Studio', '周三晚八点 练琴', Duration(days: 9)),
  ('acfun', '10086', '纸飞机', '', null),
];

/// The data the screenshots show, captured relative to one [now] so
/// durations and "3 hours ago" read the same on every run.
final class ShotWorld {
  new({
    this.catalog = ListMode.rooms,
    this.search = ListMode.rooms,
    this.follows = true,
    this.anyoneLive = true,
    this.followsFail = false,
    this.failedPlatforms = const {},
    this.playlists = false,
    DateTime? now,
  }) : now = now ?? DateTime.now().toUtc();

  /// Discover lists.
  final ListMode catalog;

  /// Search results.
  final ListMode search;

  /// Whether there are follows (false: the empty follows page).
  final bool follows;

  /// Whether any follow is live (false: only the offline follows).
  final bool anyoneLive;

  /// Whether reading the follows fails (the follows error state).
  final bool followsFail;

  /// What the follows provider answers.
  Stream<List<FollowedRoom>> get followsStream =>
      followsFail ? Stream.error(StateError('database disk image is malformed')) : Stream.value(followed);

  /// Platforms the last follow refresh could not reach (the banner).
  final Set<String> failedPlatforms;

  /// Whether IPTV playlists and a guide source are set up.
  final bool playlists;

  /// The moment the data is relative to (a little after the test starts,
  /// so a slow run does not tick a minute over).
  final DateTime now;

  /// IPTV playlists: one synced, one whose last sync failed, one local.
  List<IptvPlaylistRecord> get iptvPlaylists => !playlists
      ? const []
      : [
          IptvPlaylistRecord(
            id: 1,
            name: '央视与卫视',
            source: 'https://lists.example.com/cn.m3u',
            order: 0,
            lastSyncAt: now.subtract(const Duration(hours: 2)),
            entryCount: 186,
            channelCount: 172,
          ),
          IptvPlaylistRecord(
            id: 2,
            name: '地方台',
            source: 'https://lists.example.com/local.m3u',
            order: 1,
            lastSyncAt: now.subtract(const Duration(hours: 20)),
            lastError: '网络连接失败，检查网络或代理后重试',
            entryCount: 64,
            channelCount: 60,
          ),
          const IptvPlaylistRecord(
            id: 3,
            name: '本地列表',
            source: '/storage/emulated/0/IPTV/home.txt',
            order: 2,
            entryCount: 12,
            channelCount: 12,
          ),
        ];

  /// IPTV guide sources.
  List<IptvGuideSourceRecord> get iptvGuides => !playlists
      ? const []
      : const [
          IptvGuideSourceRecord(
            id: 1,
            name: 'e.xml',
            source: 'https://epg.example.com/e.xml',
            order: 0,
            selected: true,
          ),
        ];

  /// A live card of [room].
  RoomCard card(ShotRoom room) => RoomCard(
    ref: RoomRef(room.platform, room.id),
    title: room.title,
    anchorName: room.anchor,
    state: LiveState.live,
    area: room.area,
    audience: Audience(online: room.online),
    liveSince: now.subtract(room.liveFor),
  );

  /// Rooms of [platform] for discover: the shared list, starting at a place
  /// that depends on the platform so tabs differ.
  List<RoomCard> catalogRooms(String platform) {
    final start = platform.codeUnits.fold(0, (a, b) => a + b) % shotRooms.length;
    return [
      for (var i = 0; i < shotRooms.length; i++)
        () {
          final room = shotRooms[(start + i) % shotRooms.length];
          return card((
            platform: platform,
            id: room.id,
            anchor: room.anchor,
            title: room.title,
            online: room.online,
            liveFor: room.liveFor,
            area: room.area,
          ));
        }(),
    ];
  }

  /// Search results of [platform]: three platforms answer, the others have
  /// nothing.
  List<RoomCard> searchRooms(String platform) => switch (platform) {
    'bilibili' || 'douyu' || 'huya' => [
      for (final room in shotRooms.where((room) => room.platform == platform)) card(room),
      if (platform == 'douyu')
        RoomCard(ref: RoomRef('douyu', '71415'), title: '原神 新版本剧情首通', anchorName: '青柠不酸', state: LiveState.offline),
    ],
    _ => const [],
  };

  /// The follows list.
  List<FollowedRoom> get followed => !follows
      ? const []
      : [
          for (final (index, room) in shotRooms.take(anyoneLive ? 8 : 0).indexed)
            FollowedRoom(
              room: StoredRoom(
                ref: RoomRef(room.platform, room.id),
                anchorName: room.anchor,
                title: room.title,
                area: room.area,
                updatedAt: now.subtract(const Duration(minutes: 5)),
                audience: Audience(online: room.online),
                lastState: LiveState.live,
                lastLiveAt: now,
              ),
              followedAt: now.subtract(Duration(days: 30 + index)),
              order: index,
            ),
          for (final (index, (platform, id, name, title, ago)) in shotOfflineFollows.indexed)
            FollowedRoom(
              room: StoredRoom(
                ref: RoomRef(platform, id),
                anchorName: name,
                title: title,
                updatedAt: now.subtract(const Duration(minutes: 5)),
                lastState: LiveState.offline,
                lastLiveAt: ago == null ? null : now.subtract(ago),
              ),
              followedAt: now.subtract(Duration(days: 60 + index)),
              order: 8 + index,
            ),
        ];

  /// The first refresh of this launch, finished a minute ago.
  FollowRefreshResult get refresh => FollowRefreshResult(
    checked: followed.length,
    failedPlatforms: failedPlatforms,
    liveSince: {
      for (final room in shotRooms.take(anyoneLive ? 8 : 0))
        RoomRef(room.platform, room.id).key: now.subtract(room.liveFor),
    },
    at: now.subtract(const Duration(minutes: 1)),
  );

  /// The room opened in the room screenshots.
  RoomDetail get roomDetail {
    final room = shotRooms[1];
    return RoomDetail(
      card: card(room),
      link: Uri.parse('https://www.douyu.com/${room.id}'),
      introduction: '每晚八点开播，周末加更。冲分期间不接双排，谢谢理解。',
      notice: '本周六晚有水友赛，报名看置顶动态。',
    );
  }

  /// A batch of chat for the room of [roomDetail].
  DanmakuBatch chat({int session = 1}) {
    final key = roomDetail.ref.key;
    var micros = 0;
    DanmakuChat line(String user, String text, {int? medal, String? medalName, int color = DanmakuColors.white}) =>
        DanmakuChat(
          room: key,
          session: session,
          receivedAt: ++micros,
          userName: user,
          text: text,
          medalLevel: medal,
          medalName: medalName,
          color: color,
        );
    final lines = [
      line('路人甲', '来了来了'),
      line('今天也要早睡', '主播这波操作可以的', medal: 12, medalName: '航星'),
      line('Tom', 'gg wp'),
      line('一条咸鱼', '这把能上大师吗'),
      line('夏天的风', '前排围观', medal: 5, medalName: '航星'),
      line('匿名用户', '6666666'),
      line('月亮不睡我不睡', '上一把的团战太精彩了，回放在哪里看？'),
      line('阿白', '主播什么时候开始直播的？'),
      line('小透明', '弹幕护体'),
      line('北方的狼', '这个英雄现在版本强吗', medal: 20, medalName: '航星'),
    ];
    return DanmakuBatch(
      room: key,
      session: session,
      list: lines,
      screen: lines,
      gifts: [DanmakuGift(room: key, session: session, receivedAt: ++micros, userName: '今天也要早睡', giftName: '火箭')],
      online: const {AudienceKind.online: 355100},
      system: [DanmakuSystem(room: key, session: session, receivedAt: ++micros, status: DanmakuStatus.connected)],
    );
  }
}

/// A platform adapter with the made-up rooms of a [ShotWorld].
final class ShotSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  new(this.id, this.world);

  @override
  final String id;

  /// The data.
  final ShotWorld world;

  @override
  String get name => id;

  Future<Page<RoomCard>> _answer(ListMode mode, List<RoomCard> Function() rooms) {
    return switch (mode) {
      ListMode.rooms => Future.value(Page(rooms())),
      ListMode.loading => Completer<Page<RoomCard>>().future,
      ListMode.error => Future.error(NetworkFailure(id, 'connection reset')),
      ListMode.empty => Future.value(const Page.empty()),
    };
  }

  @override
  Future<List<Category>> categories() async => const [
    Category(
      id: 'game',
      name: '网游竞技',
      areas: [
        Area(id: 'lol', name: '英雄联盟', categoryId: 'game'),
        Area(id: 'cs2', name: 'CS2', categoryId: 'game'),
        Area(id: 'dota2', name: 'DOTA2', categoryId: 'game'),
        Area(id: 'wow', name: '魔兽世界', categoryId: 'game'),
      ],
    ),
    Category(
      id: 'single',
      name: '单机热游',
      areas: [
        Area(id: 'elden', name: '艾尔登法环', categoryId: 'single'),
        Area(id: 'hollow', name: '空洞骑士', categoryId: 'single'),
        Area(id: 'indie', name: '独立游戏', categoryId: 'single'),
      ],
    ),
    Category(
      id: 'fun',
      name: '娱乐天地',
      areas: [
        Area(id: 'music', name: '音乐', categoryId: 'fun'),
        Area(id: 'chat', name: '聊天电台', categoryId: 'fun'),
        Area(id: 'outdoor', name: '户外', categoryId: 'fun'),
        Area(id: 'food', name: '美食', categoryId: 'fun'),
      ],
    ),
  ];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) =>
      _answer(world.catalog, () => world.catalogRooms(id));

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) =>
      cursor != null ? Future.value(const Page.empty()) : _answer(world.catalog, () => world.catalogRooms(id));

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) =>
      cursor != null ? Future.value(const Page.empty()) : _answer(world.search, () => world.searchRooms(id));

  @override
  Future<RoomDetail> detail(RoomRef ref) async {
    final detail = world.roomDetail;
    if (ref == detail.ref) return detail;
    final room = shotRooms.where((room) => room.id == ref.roomId).firstOrNull;
    return RoomDetail(
      card: room == null
          ? RoomCard(ref: ref, title: '', anchorName: ref.roomId, state: LiveState.live)
          : world.card((
              platform: ref.platform,
              id: room.id,
              anchor: room.anchor,
              title: room.title,
              online: room.online,
              liveFor: room.liveFor,
              area: room.area,
            )),
      link: Uri.parse('https://example.com/${ref.roomId}'),
    );
  }

  /// Qualities every room offers, best first.
  static const qualities = [
    Quality(id: 'origin', label: '原画', rank: 3),
    Quality(id: 'hd', label: '超清', rank: 2),
    Quality(id: 'sd', label: '高清', rank: 1),
  ];

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final chosen = quality ?? qualities.first;
    return StreamSet(
      qualities: qualities,
      selected: chosen,
      lines: [
        for (final line in ['a', 'b'])
          StreamLine(
            url: Uri.parse('https://cdn-$line.example.com/${room.ref.roomId}/${chosen.id}.m3u8'),
            format: StreamFormat.hls,
            lineId: line,
            requested: chosen,
          ),
      ],
    );
  }

  @override
  Future<RoomRef?> resolve(String input) async => null;
}
