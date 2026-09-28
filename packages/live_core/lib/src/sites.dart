import 'package:live_core/src/live_site.dart';

/// Platform ids, in the order 3.x listed its platforms (`Sites`).
abstract final class SiteIds {
  /// Bilibili.
  static const String bilibili = 'bilibili';

  /// Douyu.
  static const String douyu = 'douyu';

  /// Huya.
  static const String huya = 'huya';

  /// Douyin.
  static const String douyin = 'douyin';

  /// Kuaishou.
  static const String kuaishou = 'kuaishou';

  /// NetEase CC.
  static const String cc = 'cc';

  /// Twitch.
  static const String twitch = 'twitch';

  /// SOOP.
  static const String soop = 'soop';

  /// YY.
  static const String yy = 'yy';

  /// AcFun.
  static const String acfun = 'acfun';

  /// Picarto.
  static const String picarto = 'picarto';

  /// TwitCasting.
  static const String twitcasting = 'twitcasting';

  /// Missevan.
  static const String missevan = 'missevan';

  /// Inke.
  static const String inke = 'inke';

  /// Kilakila.
  static const String kilakila = 'kilakila';

  /// Xiaohongshu.
  static const String xiaohongshu = 'xiaohongshu';

  /// niconico.
  static const String niconico = 'niconico';

  /// Weibo.
  static const String weibo = 'weibo';

  /// SHOWROOM.
  static const String showroom = 'showroom';

  /// CHZZK.
  static const String chzzk = 'chzzk';

  /// LiveMe.
  static const String liveMe = 'liveme';

  /// TikTok LIVE.
  static const String tiktok = 'tiktok';

  /// YouTube Live.
  static const String youtube = 'youtube';

  /// Bigo Live.
  static const String bigo = 'bigo';

  /// PandaTV.
  static const String pandaLive = 'pandalive';

  /// FC2 Live.
  static const String fc2Live = 'fc2live';

  /// Steam Broadcasting.
  static const String steamBroadcast = 'steambroadcast';

  /// JD Live.
  static const String jdLive = 'jdlive';

  /// Kugou Live.
  static const String kugouLive = 'kugoulive';

  /// Baidu Live.
  static const String baiduLive = 'baidulive';

  /// Six Rooms.
  static const String sixRoom = 'sixroom';

  /// LOOK Live.
  static const String lookLive = 'looklive';

  /// 17LIVE.
  static const String seventeenLive = '17live';

  /// Custom IPTV sources.
  static const String iptv = 'iptv';

  /// The search page's "all platforms" entry; not a platform.
  static const String all = 'all';

  /// Supported platforms, in display order.
  static const List<String> supported = [
    bilibili,
    douyu,
    huya,
    douyin,
    kuaishou,
    cc,
    twitch,
    soop,
    yy,
    acfun,
    picarto,
    twitcasting,
    missevan,
    inke,
    kilakila,
    xiaohongshu,
    niconico,
    weibo,
    showroom,
    chzzk,
    liveMe,
    tiktok,
    youtube,
    bigo,
    pandaLive,
    fc2Live,
    steamBroadcast,
    jdLive,
    kugouLive,
    baiduLive,
    sixRoom,
    lookLive,
    seventeenLive,
    iptv,
  ];

  /// Platforms retired in 3.2.8 (hard to maintain, niche or unusable) and
  /// 3.2.11 (Kick: Cloudflare blocks it outside Android and Windows TLS).
  /// Stored follows, history and links for them stay readable and are shown
  /// as retired instead of failing as unknown.
  static const Set<String> retired = {
    'huajiao',
    'openrec',
    'ttinglive',
    'popkontv',
    'shopeelive',
    'vkvideolive',
    'nimotv',
    'dailymotion',
    'rumble',
    'goodgame',
    'taobaolive',
    'kick',
  };

  /// Web hosts of the retired platforms, so a shared link is answered with
  /// "retired" instead of being ignored as unrecognised text.
  static const Set<String> retiredHosts = {
    'huajiao.com',
    'openrec.tv',
    'flextv.co.kr',
    'ttinglive.com',
    'popkontv.com',
    'goodgame.ru',
    'vkvideo.ru',
    'vkplay.live',
    'dailymotion.com',
    'dai.ly',
    'rumble.com',
    'nimo.tv',
    'shopee.co.id',
    'taobao.com',
    'm.tb.cn',
    'kick.com',
  };

  /// Platforms whose room id is a user name that the platform itself matches
  /// without regard to case, so room identity ignores case there
  /// (`LiveRoom.identityKeyFor`; docs/modules/M2.1-model.md). The room id
  /// keeps the spelling it was stored with; only comparisons fold it.
  ///
  /// - Twitch: the login name. Logins are lower case; the adapter requests
  ///   the lower-case form of any spelling (M4.8).
  /// - SOOP: the streamer id (BJ id). The platform answers it in lower case
  ///   and links are lower-cased (M4.7).
  /// - Picarto: the channel name. The platform finds a channel in any case
  ///   and answers its own spelling (`kaiyote`, `KAIYOTE` → `Kaiyote`, M4.11).
  /// - TwitCasting: the screen id. The adapter requests its lower-case form
  ///   (M4.12).
  /// - TikTok: the user name (`uniqueId`). The answer is matched in any case
  ///   and the adapter already lower-cases the room id (M4.22).
  /// - PandaTV: the login id. 3.x matched the room data in any case (M4.25).
  ///
  /// Not included: numeric ids (case does not apply), YouTube video and
  /// channel ids (case-sensitive), niconico programme ids, CHZZK channel ids
  /// (hex the adapter already lower-cases), and ids whose case rule the
  /// platform has not shown: Douyu and Huya aliases, Kuaishou user ids, Bigo
  /// ids.
  static const Set<String> caseInsensitiveRoomIds = {twitch, soop, picarto, twitcasting, tiktok, pandaLive};

  /// Whether rooms of [platform] are identified without regard to the room
  /// id's case (see [caseInsensitiveRoomIds]).
  static bool ignoresRoomIdCase(String platform) => caseInsensitiveRoomIds.contains(platform.trim().toLowerCase());

  static final Set<String> _supported = supported.toSet();

  /// Whether [id] is a supported platform (case and spaces ignored).
  static bool isSupported(String id) => _supported.contains(id.trim().toLowerCase());

  /// Whether [id] is a retired platform.
  static bool isRetired(String id) => retired.contains(id.trim().toLowerCase());

  /// Whether [text] contains a link to a retired platform.
  static bool isRetiredLink(String text) {
    for (final match in RegExp(r'https?://[^\s]+', caseSensitive: false).allMatches(text)) {
      final host = Uri.tryParse(match.group(0)!)?.host.toLowerCase() ?? '';
      if (retiredHosts.any((root) => host == root || host.endsWith('.$root'))) return true;
    }
    return false;
  }
}

/// One adapter per platform, created on first use and then kept.
///
/// 3.x built all 34 adapters on every read of `Sites.supportSites` and a
/// fresh adapter on every `Sites.of`, which threw away per-platform session
/// caches (Kuaishou's session cookie, for example) on each lookup.
final class SiteRegistry {
  /// A registry that builds adapters with [factories], keyed by platform id.
  /// Only supported ids are listed; the order is [SiteIds.supported].
  new(Map<String, LiveSite Function()> factories) : _factories = Map.unmodifiable(factories);

  final Map<String, LiveSite Function()> _factories;
  final Map<String, LiveSite> _sites = {};

  /// Platform ids with an adapter, in display order.
  List<String> get ids => [
    for (final id in SiteIds.supported)
      if (_factories.containsKey(id)) id,
  ];

  /// Every adapter, in display order.
  List<LiveSite> get sites => [for (final id in ids) of(id)];

  /// The adapter of [id] (case and spaces ignored); throws [ArgumentError]
  /// for a platform without one.
  LiveSite of(String id) => maybeOf(id) ?? (throw ArgumentError.value(id, 'id', 'Unsupported live site'));

  /// The adapter of [id], or null.
  LiveSite? maybeOf(String id) {
    final key = id.trim().toLowerCase();
    final existing = _sites[key];
    if (existing != null) return existing;
    final factory = _factories[key];
    if (factory == null) return null;
    return _sites[key] = factory();
  }

  /// The platforms of the user's platform list [saved] (the "hot areas"
  /// setting) that have an adapter, in the saved order without duplicates.
  List<String> availableIds(Iterable<String> saved) {
    final seen = <String>{};
    return [
      for (final raw in saved)
        if (raw.trim().toLowerCase() case final id when seen.add(id) && _factories.containsKey(id)) id,
    ];
  }
}
