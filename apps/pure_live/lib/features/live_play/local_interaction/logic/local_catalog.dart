import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:live_core/live_core.dart';
import 'package:live_ui/live_ui.dart' show PlatformLogos;

/// How far an amount of experience is into its level (D08.3): the `level`,
/// the experience gathered in it (`into`) and still `missing` to the next.
typedef LocalLevelProgress = ({int level, int into, int missing});

/// A gift of the local interaction (3.x `LocalGift`): only simulated, it
/// costs local coins and earns experience.
@immutable
final class LocalGift {
  /// Creates a gift.
  const new({
    required this.id,
    required this.nameKey,
    required this.emoji,
    required this.price,
    required this.color,
    this.big = false,
  });

  /// Stable id (recorded in the message).
  final String id;

  /// The name's text key.
  final String nameKey;

  /// The picture (shown with the bundled emoji font, U.2k K4).
  final String emoji;

  /// Price in local coins.
  final int price;

  /// The banner's colour.
  final LiveMessageColor color;

  /// A high-value gift: the bigger banner (3.x `effect: 'full'`).
  final bool big;
}

/// A platform's look and words for the local interaction (3.x
/// `LocalPlatformPack`).
@immutable
final class LocalPlatformPack {
  /// Creates a pack.
  const new({
    required this.id,
    required this.nameKey,
    required this.currencyKey,
    required this.levelKey,
    required this.accent,
    required this.badge,
    this.badgeKey = 'local_badge_generic',
  });

  /// The platform id ([SiteIds]), or `generic`.
  final String id;

  /// The platform's name key.
  final String nameKey;

  /// The coin's name key ("电池").
  final String currencyKey;

  /// The level's name key ("用户等级").
  final String levelKey;

  /// The badge's name key ("舰队等级").
  final String badgeKey;

  /// The theme colour, ARGB: the platform's colour
  /// (`PlatformLogos.colors`, D08.6).
  final int accent;

  /// The badge as text: an emoji, or two letters. The platform's logo
  /// (`PlatformLogos`) shows instead wherever a picture fits (D08.6); the
  /// text stays where only words go (3.x's history line, a message's
  /// sender name) and for a message from before D08.6, which names no
  /// platform.
  final String badge;
}

/// A local danmaku template (3.x `LocalDanmakuPreset`).
@immutable
final class LocalDanmakuPreset {
  /// Creates a template.
  const new({
    required this.id,
    required this.color,
    required this.fontSize,
    required this.speed,
    required this.fontWeight,
    required this.showStroke,
    required this.strokeWidth,
    this.placement = 'scroll',
    this.fontFamily = 'system',
    this.italic = false,
    this.opacity = 1,
    this.letterSpacing = 0,
    this.strokeColor = 0xFF000000,
    this.showShadow = false,
    this.shadowColor = 0xFF000000,
    this.shadowBlur = 2,
    this.shadowOffset = 1,
    this.fixedDurationMs = 4000,
  });

  /// Id, stored in `localInteraction.danmakuPreset`; its name is
  /// `local_danmaku_preset_<id>`.
  final String id;

  /// Colour, ARGB.
  final int color;

  /// Font size.
  final double fontSize;

  /// Speed, pixels per second.
  final double speed;

  /// Font weight.
  final int fontWeight;

  /// Outline.
  final bool showStroke;

  /// Outline width.
  final double strokeWidth;

  /// `scroll`, `top` or `bottom`.
  final String placement;

  /// `system`, `rounded`, `serif` or `mono`.
  final String fontFamily;

  /// Italic.
  final bool italic;

  /// Opacity.
  final double opacity;

  /// Letter spacing.
  final double letterSpacing;

  /// Outline colour, ARGB.
  final int strokeColor;

  /// Shadow or glow.
  final bool showShadow;

  /// Shadow colour, ARGB.
  final int shadowColor;

  /// Shadow blur.
  final double shadowBlur;

  /// Shadow offset.
  final double shadowOffset;

  /// How long a fixed message stays, milliseconds.
  final int fixedDurationMs;
}

/// The local interaction's data, as 3.x had it
/// (`local_interaction_controller.dart:116-724`): templates, colours, fonts,
/// places, titles, the platform packs (3.x's 34 and Kick, D08.6) and the
/// gifts.
abstract final class LocalCatalog {
  /// The templates, "清爽" (the default) first.
  static const presets = <LocalDanmakuPreset>[
    LocalDanmakuPreset(
      id: 'clean',
      color: 0xFFFFFFFF,
      fontSize: 19,
      speed: 130,
      fontWeight: 600,
      showStroke: true,
      strokeWidth: 1.5,
    ),
    LocalDanmakuPreset(
      id: 'highlight',
      color: 0xFFFFE45C,
      fontSize: 22,
      speed: 145,
      fontWeight: 800,
      showStroke: true,
      strokeWidth: 2,
      letterSpacing: .4,
    ),
    LocalDanmakuPreset(
      id: 'neon',
      color: 0xFFFF69D4,
      fontSize: 21,
      speed: 120,
      fontWeight: 700,
      showStroke: true,
      strokeWidth: 2.5,
      showShadow: true,
      shadowColor: 0xFFFF2DC6,
      shadowBlur: 4,
      shadowOffset: 0,
    ),
    LocalDanmakuPreset(
      id: 'minimal',
      color: 0xFF72E6FF,
      fontSize: 17,
      speed: 105,
      fontWeight: 500,
      showStroke: false,
      strokeWidth: 0,
      opacity: .86,
    ),
    LocalDanmakuPreset(
      id: 'caption',
      color: 0xFFFFFFFF,
      fontSize: 20,
      speed: 120,
      fontWeight: 700,
      showStroke: true,
      strokeWidth: 2.5,
      placement: 'bottom',
      fixedDurationMs: 5200,
    ),
    LocalDanmakuPreset(
      id: 'cyber',
      color: 0xFF58F5FF,
      fontSize: 20,
      speed: 150,
      fontWeight: 700,
      showStroke: true,
      strokeWidth: 1.5,
      fontFamily: 'mono',
      letterSpacing: 1.1,
      strokeColor: 0xFF11243A,
      showShadow: true,
      shadowColor: 0xFF00C8FF,
      shadowBlur: 3,
    ),
  ];

  /// The default template ("清爽"); "恢复默认" applies it.
  static LocalDanmakuPreset get defaultPreset => presets.first;

  /// The template [id], or null (a look of the user's own).
  static LocalDanmakuPreset? presetById(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  /// The twelve danmaku colours.
  static const danmakuColors = <int>[
    0xFFFFFFFF,
    0xFFFFE45C,
    0xFF72E6FF,
    0xFFFF69D4,
    0xFF8CFF98,
    0xFFFF9D66,
    0xFFBCA7FF,
    0xFFFF5C77,
    0xFF4EA1FF,
    0xFF00D8B0,
    0xFFFFB7E7,
    0xFFB8FF67,
  ];

  /// The seven outline and shadow colours.
  static const effectColors = <int>[0xFF000000, 0xFFFFFFFF, 0xFF173A5E, 0xFF6D1F45, 0xFF00C8FF, 0xFFFF2DC6, 0xFFFF8A00];

  /// The fonts (`local_danmaku_font_<id>`).
  static const fontFamilyIds = <String>['system', 'rounded', 'serif', 'mono'];

  /// The places (`local_danmaku_placement_<id>`).
  static const placementIds = <String>['scroll', 'top', 'bottom'];

  /// The titles (`local_title_<id>`).
  static const titles = <String>['listener', 'night_owl', 'supporter', 'guardian'];

  /// The most history lines kept.
  static const historyLimit = 30;

  /// The coins the buttons add.
  static const rechargeAmounts = <int>[500, 2000, 10000];

  /// The longest local nickname.
  static const nameLimit = 20;

  /// The counts a long press on a gift offers (D08.4 c3): 1 (a tap), 10,
  /// and the two the platforms' own count lists all have, 66 ("六六大顺") and
  /// 520 ("我爱你"); 1314 is left out, as the cheapest gift (10) times it is
  /// more than any recharge button adds.
  static const giftCounts = <int>[1, 10, 66, 520];

  /// How long after a gift the same gift joins its combo (D08.4 c1: 3 s,
  /// the banner's time, so a combo's banner is still up when it grows).
  static const Duration giftComboWindow = Duration(seconds: 3);

  /// The most gift banners shown or waiting at once (D08.4 c4): five at 3 s
  /// each is 15 s at most from a send to its banner; a later one would show
  /// long after the tap, so beyond them a gift only joins the chat list.
  static const int giftBannerLimit = 5;

  /// The price of one from which a gift's effect is the banner (D08.5 c1):
  /// below it a gift flies over the top of the picture.
  static const int giftTierMedium = 100;

  /// The price of one from which a gift's effect is the banner with a
  /// vehicle (D08.5 c1); a gift marked [LocalGift.big] has it too.
  static const int giftTierBig = 1000;

  /// The longest local danmaku, in characters (A08.13: the platforms let a
  /// viewer send 20 to 40; 40 still crosses a landscape phone in about one
  /// screen width at the default size).
  static const danmakuLimit = 40;

  /// From this many characters on the composer shows its count (the last
  /// ten before [danmakuLimit]).
  static const int danmakuCountFrom = danmakuLimit - 10;

  /// [text] as a local danmaku may say it: trimmed, the first
  /// [danmakuLimit] characters (an emoji is one, as the composer counts).
  static String clipDanmaku(String text) => text.trim().characters.take(danmakuLimit).toString();

  /// How many of the local danmaku sent last show over a composer (D08.2
  /// c1: "最近").
  static const int recentCount = 5;

  /// The gifts of a platform without its own (3.x `gifts`).
  static const genericGifts = <LocalGift>[
    LocalGift(id: 'heart', nameKey: 'local_gift_heart', emoji: '💗', price: 10, color: LiveMessageColor(255, 105, 180)),
    LocalGift(
      id: 'flower',
      nameKey: 'local_gift_flower',
      emoji: '🌸',
      price: 50,
      color: LiveMessageColor(255, 128, 171),
    ),
    LocalGift(
      id: 'rocket',
      nameKey: 'local_gift_rocket',
      emoji: '🚀',
      price: 500,
      color: LiveMessageColor(255, 165, 0),
    ),
    LocalGift(
      id: 'castle',
      nameKey: 'local_gift_castle',
      emoji: '🏰',
      price: 2000,
      color: LiveMessageColor(138, 43, 226),
    ),
  ];

  /// The pack of a platform without its own.
  static const genericPack = LocalPlatformPack(
    id: 'generic',
    nameKey: 'local_platform_generic',
    currencyKey: 'local_currency_generic',
    levelKey: 'local_level_generic',
    accent: 0xFF607D8B,
    badge: '✨',
  );

  /// A pack of the platform [id]: its colour is the platform's
  /// ([PlatformLogos.colors]); [currency], [level] and [badgeName] name its
  /// own words (`local_currency_<currency>`, `local_level_<level>`,
  /// `local_badge_<badgeName>`), the generic ones when null.
  static LocalPlatformPack _pack(
    String id,
    String nameKey,
    String badge, {
    String? currency,
    String? level,
    String? badgeName,
  }) => LocalPlatformPack(
    id: id,
    nameKey: nameKey,
    currencyKey: currency == null ? genericPack.currencyKey : 'local_currency_$currency',
    levelKey: level == null ? genericPack.levelKey : 'local_level_$level',
    badgeKey: badgeName == null ? genericPack.badgeKey : 'local_badge_$badgeName',
    accent: PlatformLogos.colorOf(id) ?? genericPack.accent,
    badge: badge,
  );

  /// A pack of every platform ([SiteIds.supported], in its order: 3.x's 34
  /// and Kick, D08.6). The eight of 3.x with their own words keep them; the
  /// others name the coin, level and badge the platform has where V03.5 §2
  /// found them (AC币, 钻石, 红豆, 奶酪, Kicks, 星币, 六币, 音符…). A
  /// platform without a gift system of its own (Steam, JD, IPTV) and one
  /// whose gifts are not known (blocked: YY, LiveMe, CC's own are 3.x's)
  /// keeps the generic words.
  static final List<LocalPlatformPack> packs = List.unmodifiable([
    _pack(SiteIds.bilibili, 'site_bilibili', '📺', currency: 'bili', level: 'bili', badgeName: 'bilibili'),
    _pack(SiteIds.douyu, 'site_douyu', '🐟', currency: 'douyu', level: 'douyu', badgeName: 'douyu'),
    _pack(SiteIds.huya, 'site_huya', '🐯', currency: 'huya', level: 'huya', badgeName: 'huya'),
    _pack(SiteIds.douyin, 'site_douyin', '🎵', currency: 'douyin', level: 'douyin', badgeName: 'douyin'),
    _pack(SiteIds.kuaishou, 'site_kuaishou', '🎬', currency: 'kuaishou', level: 'kuaishou', badgeName: 'kuaishou'),
    _pack(SiteIds.cc, 'site_cc', '🎮', currency: 'cc', level: 'cc', badgeName: 'cc'),
    _pack(SiteIds.twitch, 'site_twitch', '💜', currency: 'twitch', level: 'twitch', badgeName: 'twitch'),
    _pack(SiteIds.soop, 'site_soop', '🎈', currency: 'soop', level: 'soop', badgeName: 'soop'),
    _pack(SiteIds.yy, 'site_yy', '🎤'),
    _pack(SiteIds.acfun, 'site_acfun', '🅰️', currency: 'ac_coin', level: 'user', badgeName: 'guard'),
    _pack(SiteIds.picarto, 'site_picarto', '🎨', currency: 'kudos', level: 'sub', badgeName: 'sub'),
    _pack(SiteIds.twitcasting, 'site_twitcasting', '📡', currency: 'coin', level: 'user', badgeName: 'member'),
    _pack(SiteIds.missevan, 'site_missevan', '🎧', currency: 'diamond', level: 'noble', badgeName: 'medal'),
    _pack(SiteIds.inke, 'site_inke', '✨'),
    _pack(SiteIds.kilakila, 'site_kilakila', '💫', currency: 'red_bean', level: 'wealth', badgeName: 'fan_club'),
    _pack(SiteIds.xiaohongshu, 'site_xiaohongshu', '📕'),
    _pack(SiteIds.niconico, 'site_niconico', '📹', currency: 'point', level: 'user', badgeName: 'premium'),
    _pack(SiteIds.weibo, 'site_weibo', '🟠'),
    _pack(SiteIds.showroom, 'site_showroom', '🎟️', currency: 'points', level: 'fans', badgeName: 'fans'),
    _pack(SiteIds.chzzk, 'site_chzzk', '🎮', currency: 'cheese', level: 'sub', badgeName: 'sub'),
    _pack(SiteIds.kick, 'site_kick', '💚', currency: 'kicks', level: 'sub', badgeName: 'sub'),
    _pack(SiteIds.liveMe, 'site_liveme', 'LM'),
    _pack(SiteIds.tiktok, 'site_tiktok', 'TT', currency: 'coin', level: 'gifter', badgeName: 'fan_club'),
    _pack(SiteIds.youtube, 'site_youtube', 'YT', level: 'member', badgeName: 'member'),
    _pack(SiteIds.bigo, 'site_bigo', 'BG', currency: 'diamond', level: 'user', badgeName: 'family'),
    _pack(SiteIds.pandaLive, 'site_pandalive', 'PD', currency: 'heart', level: 'fans', badgeName: 'fans'),
    _pack(SiteIds.fc2Live, 'site_fc2live', 'FC', currency: 'point', level: 'user', badgeName: 'member'),
    _pack(SiteIds.steamBroadcast, 'site_steambroadcast', 'ST'),
    _pack(SiteIds.jdLive, 'site_jdlive', 'JD'),
    _pack(SiteIds.kugouLive, 'site_kugoulive', 'KG', currency: 'star_coin', level: 'wealth', badgeName: 'guard'),
    _pack(SiteIds.baiduLive, 'site_baidulive', 'BD', level: 'user', badgeName: 'fans'),
    _pack(SiteIds.sixRoom, 'site_sixroom', '6R', currency: 'six_coin', level: 'wealth', badgeName: 'guard'),
    _pack(SiteIds.lookLive, 'site_looklive', 'LK', currency: 'note', level: 'noble', badgeName: 'guard'),
    _pack(SiteIds.seventeenLive, 'site_17live', '17', currency: 'baby_coin', level: 'user', badgeName: 'guard'),
    _pack(SiteIds.iptv, 'site_iptv', '🌐'),
  ]);

  /// The gifts of the platforms that have their own; each has one
  /// high-value gift with the big banner ([LocalGift.big]) and a vehicle of
  /// its own (`LocalGiftVehicle.named`).
  ///
  /// The ids are stored (a history entry's `gift_id`, D08.1) and never
  /// change; the first eight platforms' are 3.x's. The others (D08.6) are
  /// the platform's own gifts and paid messages where V03.5 §2 names them
  /// (AcFun's bananas, Missevan's lucky bag and nobles, KilaKila's 豆咖,
  /// niconico's ニコニ広告, Picarto's Kudos, CHZZK's cheese, video and
  /// mission donations, Kick's Kicks and gifted subs, YouTube's Super
  /// Sticker, Super Chat and gifted memberships, 17LIVE's paid barrage,
  /// lucky bag and guard, BIGO's Flower, PandaTV's signature heart,
  /// Six Rooms' fly-screen at its 1000 six coins, LOOK's song request,
  /// Baidu's free 拍拍), else ones like them; each is a small one (< 100,
  /// it flies over the top), a medium one (the banner) and the big one,
  /// priced in the pack's local coin.
  static const _platformGifts = <String, List<LocalGift>>{
    SiteIds.bilibili: [
      LocalGift(
        id: 'bili_snack',
        nameKey: 'local_gift_bili_snack',
        emoji: '🌶️',
        price: 10,
        color: LiveMessageColor(255, 102, 102),
      ),
      LocalGift(
        id: 'bili_tv',
        nameKey: 'local_gift_bili_tv',
        emoji: '📺',
        price: 100,
        color: LiveMessageColor(84, 197, 248),
      ),
      LocalGift(
        id: 'bili_voyage',
        nameKey: 'local_gift_bili_voyage',
        emoji: '⚓',
        price: 1980,
        color: LiveMessageColor(255, 99, 146),
        big: true,
      ),
    ],
    SiteIds.douyu: [
      LocalGift(
        id: 'douyu_ball',
        nameKey: 'local_gift_douyu_ball',
        emoji: '🐟',
        price: 10,
        color: LiveMessageColor(255, 144, 0),
      ),
      LocalGift(
        id: 'douyu_rocket',
        nameKey: 'local_gift_douyu_rocket',
        emoji: '🚀',
        price: 500,
        color: LiveMessageColor(255, 123, 0),
      ),
      LocalGift(
        id: 'douyu_super_rocket',
        nameKey: 'local_gift_douyu_super_rocket',
        emoji: '🛰️',
        price: 2000,
        color: LiveMessageColor(255, 76, 0),
        big: true,
      ),
    ],
    SiteIds.huya: [
      LocalGift(
        id: 'huya_stick',
        nameKey: 'local_gift_huya_stick',
        emoji: '✨',
        price: 10,
        color: LiveMessageColor(255, 202, 40),
      ),
      LocalGift(
        id: 'huya_sword',
        nameKey: 'local_gift_huya_sword',
        emoji: '⚔️',
        price: 300,
        color: LiveMessageColor(255, 174, 0),
      ),
      LocalGift(
        id: 'huya_one',
        nameKey: 'local_gift_huya_one',
        emoji: '🐯',
        price: 1000,
        color: LiveMessageColor(255, 128, 0),
        big: true,
      ),
    ],
    SiteIds.douyin: [
      LocalGift(
        id: 'douyin_heart',
        nameKey: 'local_gift_douyin_heart',
        emoji: '💖',
        price: 10,
        color: LiveMessageColor(254, 44, 85),
      ),
      LocalGift(
        id: 'douyin_badge',
        nameKey: 'local_gift_douyin_badge',
        emoji: '🎖️',
        price: 200,
        color: LiveMessageColor(255, 86, 124),
      ),
      LocalGift(
        id: 'douyin_carnival',
        nameKey: 'local_gift_douyin_carnival',
        emoji: '🎡',
        price: 3000,
        color: LiveMessageColor(254, 44, 85),
        big: true,
      ),
    ],
    SiteIds.kuaishou: [
      LocalGift(
        id: 'ks_beer',
        nameKey: 'local_gift_ks_beer',
        emoji: '🍺',
        price: 10,
        color: LiveMessageColor(255, 98, 0),
      ),
      LocalGift(
        id: 'ks_arrow',
        nameKey: 'local_gift_ks_arrow',
        emoji: '🏹',
        price: 500,
        color: LiveMessageColor(255, 74, 0),
      ),
      LocalGift(
        id: 'ks_guard',
        nameKey: 'local_gift_ks_guard',
        emoji: '🛡️',
        price: 1500,
        color: LiveMessageColor(255, 58, 48),
        big: true,
      ),
    ],
    SiteIds.cc: [
      LocalGift(
        id: 'cc_flower',
        nameKey: 'local_gift_cc_flower',
        emoji: '🌺',
        price: 10,
        color: LiveMessageColor(255, 92, 155),
      ),
      LocalGift(
        id: 'cc_car',
        nameKey: 'local_gift_cc_car',
        emoji: '🏎️',
        price: 500,
        color: LiveMessageColor(255, 66, 80),
      ),
      LocalGift(
        id: 'cc_guard',
        nameKey: 'local_gift_cc_guard',
        emoji: '👑',
        price: 1800,
        color: LiveMessageColor(163, 89, 255),
        big: true,
      ),
    ],
    SiteIds.twitch: [
      LocalGift(
        id: 'twitch_cheer',
        nameKey: 'local_gift_twitch_cheer',
        emoji: '💎',
        price: 10,
        color: LiveMessageColor(145, 70, 255),
      ),
      LocalGift(
        id: 'twitch_sub',
        nameKey: 'local_gift_twitch_sub',
        emoji: '⭐',
        price: 500,
        color: LiveMessageColor(169, 112, 255),
      ),
      LocalGift(
        id: 'twitch_hype_train',
        nameKey: 'local_gift_twitch_hype_train',
        emoji: '🚂',
        price: 2000,
        color: LiveMessageColor(112, 44, 190),
        big: true,
      ),
    ],
    SiteIds.soop: [
      LocalGift(
        id: 'soop_star_balloon',
        nameKey: 'local_gift_soop_star_balloon',
        emoji: '⭐',
        price: 10,
        color: LiveMessageColor(6, 117, 232),
      ),
      LocalGift(
        id: 'soop_sticker',
        nameKey: 'local_gift_soop_sticker',
        emoji: '🎟️',
        price: 300,
        color: LiveMessageColor(52, 147, 245),
      ),
      LocalGift(
        id: 'soop_signature_balloon',
        nameKey: 'local_gift_soop_signature_balloon',
        emoji: '🎈',
        price: 2000,
        color: LiveMessageColor(0, 88, 190),
        big: true,
      ),
    ],
    // ---- D08.6 ----
    SiteIds.acfun: [
      LocalGift(
        id: 'acfun_banana',
        nameKey: 'local_gift_acfun_banana',
        emoji: '🍌',
        price: 10,
        color: LiveMessageColor(255, 200, 0),
      ),
      LocalGift(
        id: 'acfun_good_card',
        nameKey: 'local_gift_acfun_good_card',
        emoji: '🃏',
        price: 100,
        color: LiveMessageColor(253, 76, 93),
      ),
      LocalGift(
        id: 'acfun_guard',
        nameKey: 'local_gift_acfun_guard',
        emoji: '🛡️',
        price: 1200,
        color: LiveMessageColor(222, 40, 60),
        big: true,
      ),
    ],
    SiteIds.picarto: [
      LocalGift(
        id: 'picarto_kudos',
        nameKey: 'local_gift_picarto_kudos',
        emoji: '🎨',
        price: 10,
        color: LiveMessageColor(52, 166, 116),
      ),
      LocalGift(
        id: 'picarto_sub',
        nameKey: 'local_gift_picarto_sub',
        emoji: '⭐',
        price: 500,
        color: LiveMessageColor(36, 140, 96),
      ),
      LocalGift(
        id: 'picarto_big_tip',
        nameKey: 'local_gift_picarto_big_tip',
        emoji: '💰',
        price: 2000,
        color: LiveMessageColor(20, 120, 80),
        big: true,
      ),
    ],
    SiteIds.twitcasting: [
      LocalGift(
        id: 'tc_tea',
        nameKey: 'local_gift_tc_tea',
        emoji: '🍵',
        price: 10,
        color: LiveMessageColor(96, 170, 70),
      ),
      LocalGift(
        id: 'tc_cake',
        nameKey: 'local_gift_tc_cake',
        emoji: '🍰',
        price: 100,
        color: LiveMessageColor(30, 159, 234),
      ),
      LocalGift(
        id: 'tc_fireworks',
        nameKey: 'local_gift_tc_fireworks',
        emoji: '🎇',
        price: 1500,
        color: LiveMessageColor(41, 77, 219),
        big: true,
      ),
    ],
    SiteIds.missevan: [
      LocalGift(
        id: 'missevan_fish',
        nameKey: 'local_gift_missevan_fish',
        emoji: '🐟',
        price: 10,
        color: LiveMessageColor(243, 138, 174),
      ),
      LocalGift(
        id: 'missevan_lucky_bag',
        nameKey: 'local_gift_missevan_lucky_bag',
        emoji: '🧧',
        price: 100,
        color: LiveMessageColor(230, 57, 70),
      ),
      LocalGift(
        id: 'missevan_noble',
        nameKey: 'local_gift_missevan_noble',
        emoji: '👑',
        price: 1500,
        color: LiveMessageColor(180, 100, 240),
        big: true,
      ),
    ],
    SiteIds.kilakila: [
      LocalGift(
        id: 'kila_douka',
        nameKey: 'local_gift_kila_douka',
        emoji: '☕',
        price: 10,
        color: LiveMessageColor(196, 120, 70),
      ),
      LocalGift(
        id: 'kila_heartbeat',
        nameKey: 'local_gift_kila_heartbeat',
        emoji: '💓',
        price: 200,
        color: LiveMessageColor(254, 105, 106),
      ),
      LocalGift(
        id: 'kila_castle',
        nameKey: 'local_gift_kila_castle',
        emoji: '🏰',
        price: 1500,
        color: LiveMessageColor(124, 92, 252),
        big: true,
      ),
    ],
    SiteIds.niconico: [
      LocalGift(
        id: 'nico_bouquet',
        nameKey: 'local_gift_nico_bouquet',
        emoji: '💐',
        price: 10,
        color: LiveMessageColor(255, 128, 171),
      ),
      LocalGift(
        id: 'nico_ad',
        nameKey: 'local_gift_nico_ad',
        emoji: '📢',
        price: 300,
        color: LiveMessageColor(255, 160, 0),
      ),
      LocalGift(
        id: 'nico_fireworks',
        nameKey: 'local_gift_nico_fireworks',
        emoji: '🎆',
        price: 1500,
        color: LiveMessageColor(90, 90, 230),
        big: true,
      ),
    ],
    SiteIds.showroom: [
      LocalGift(
        id: 'showroom_star',
        nameKey: 'local_gift_showroom_star',
        emoji: '⭐',
        price: 10,
        color: LiveMessageColor(255, 196, 0),
      ),
      LocalGift(
        id: 'showroom_rainbow_star',
        nameKey: 'local_gift_showroom_rainbow_star',
        emoji: '🌈',
        price: 100,
        color: LiveMessageColor(255, 43, 103),
      ),
      LocalGift(
        id: 'showroom_tower',
        nameKey: 'local_gift_showroom_tower',
        emoji: '🗼',
        price: 2000,
        color: LiveMessageColor(222, 52, 114),
        big: true,
      ),
    ],
    SiteIds.chzzk: [
      LocalGift(
        id: 'chzzk_cheese',
        nameKey: 'local_gift_chzzk_cheese',
        emoji: '🧀',
        price: 10,
        color: LiveMessageColor(255, 190, 40),
      ),
      LocalGift(
        id: 'chzzk_video',
        nameKey: 'local_gift_chzzk_video',
        emoji: '📹',
        price: 500,
        color: LiveMessageColor(0, 200, 160),
      ),
      LocalGift(
        id: 'chzzk_mission',
        nameKey: 'local_gift_chzzk_mission',
        emoji: '🎯',
        price: 1000,
        color: LiveMessageColor(0, 160, 128),
        big: true,
      ),
    ],
    SiteIds.kick: [
      LocalGift(
        id: 'kick_kicks',
        nameKey: 'local_gift_kick_kicks',
        emoji: '💚',
        price: 10,
        color: LiveMessageColor(83, 252, 24),
      ),
      LocalGift(
        id: 'kick_sub',
        nameKey: 'local_gift_kick_sub',
        emoji: '⭐',
        price: 500,
        color: LiveMessageColor(60, 200, 20),
      ),
      LocalGift(
        id: 'kick_gift_subs',
        nameKey: 'local_gift_kick_gift_subs',
        emoji: '🎁',
        price: 2000,
        color: LiveMessageColor(40, 170, 10),
        big: true,
      ),
    ],
    SiteIds.tiktok: [
      LocalGift(
        id: 'tiktok_rose',
        nameKey: 'local_gift_tiktok_rose',
        emoji: '🌹',
        price: 10,
        color: LiveMessageColor(254, 44, 85),
      ),
      LocalGift(
        id: 'tiktok_doughnut',
        nameKey: 'local_gift_tiktok_doughnut',
        emoji: '🍩',
        price: 300,
        color: LiveMessageColor(255, 128, 171),
      ),
      LocalGift(
        id: 'tiktok_lion',
        nameKey: 'local_gift_tiktok_lion',
        emoji: '🦁',
        price: 3000,
        color: LiveMessageColor(255, 170, 0),
        big: true,
      ),
    ],
    SiteIds.youtube: [
      LocalGift(
        id: 'yt_super_sticker',
        nameKey: 'local_gift_yt_super_sticker',
        emoji: '🏷️',
        price: 50,
        color: LiveMessageColor(30, 136, 229),
      ),
      LocalGift(
        id: 'yt_super_chat',
        nameKey: 'local_gift_yt_super_chat',
        emoji: '💬',
        price: 500,
        color: LiveMessageColor(255, 160, 0),
      ),
      LocalGift(
        id: 'yt_gift_memberships',
        nameKey: 'local_gift_yt_gift_memberships',
        emoji: '🎁',
        price: 2000,
        color: LiveMessageColor(15, 157, 88),
        big: true,
      ),
    ],
    SiteIds.bigo: [
      LocalGift(
        id: 'bigo_flower',
        nameKey: 'local_gift_bigo_flower',
        emoji: '🌷',
        price: 10,
        color: LiveMessageColor(255, 105, 180),
      ),
      LocalGift(
        id: 'bigo_kiss',
        nameKey: 'local_gift_bigo_kiss',
        emoji: '💋',
        price: 100,
        color: LiveMessageColor(230, 30, 90),
      ),
      LocalGift(
        id: 'bigo_supercar',
        nameKey: 'local_gift_bigo_supercar',
        emoji: '🏎️',
        price: 2000,
        color: LiveMessageColor(0, 160, 230),
        big: true,
      ),
    ],
    SiteIds.pandaLive: [
      LocalGift(
        id: 'panda_heart',
        nameKey: 'local_gift_panda_heart',
        emoji: '❤️',
        price: 10,
        color: LiveMessageColor(254, 77, 106),
      ),
      LocalGift(
        id: 'panda_signature_heart',
        nameKey: 'local_gift_panda_signature_heart',
        emoji: '💝',
        price: 500,
        color: LiveMessageColor(240, 60, 120),
      ),
      LocalGift(
        id: 'panda_big_spon',
        nameKey: 'local_gift_panda_big_spon',
        emoji: '💰',
        price: 2000,
        color: LiveMessageColor(210, 40, 80),
        big: true,
      ),
    ],
    SiteIds.fc2Live: [
      LocalGift(
        id: 'fc2_gift',
        nameKey: 'local_gift_fc2_gift',
        emoji: '🎁',
        price: 10,
        color: LiveMessageColor(254, 114, 0),
      ),
      LocalGift(
        id: 'fc2_tip',
        nameKey: 'local_gift_fc2_tip',
        emoji: '💴',
        price: 300,
        color: LiveMessageColor(240, 100, 0),
      ),
      LocalGift(
        id: 'fc2_big_tip',
        nameKey: 'local_gift_fc2_big_tip',
        emoji: '💰',
        price: 2000,
        color: LiveMessageColor(220, 80, 0),
        big: true,
      ),
    ],
    SiteIds.kugouLive: [
      LocalGift(
        id: 'kugou_flowers',
        nameKey: 'local_gift_kugou_flowers',
        emoji: '💐',
        price: 10,
        color: LiveMessageColor(255, 105, 180),
      ),
      LocalGift(
        id: 'kugou_mic',
        nameKey: 'local_gift_kugou_mic',
        emoji: '🎤',
        price: 300,
        color: LiveMessageColor(0, 99, 254),
      ),
      LocalGift(
        id: 'kugou_yacht',
        nameKey: 'local_gift_kugou_yacht',
        emoji: '🛥️',
        price: 3000,
        color: LiveMessageColor(0, 70, 200),
        big: true,
      ),
    ],
    SiteIds.baiduLive: [
      LocalGift(
        id: 'baidu_pat',
        nameKey: 'local_gift_baidu_pat',
        emoji: '👏',
        price: 10,
        color: LiveMessageColor(255, 180, 60),
      ),
      LocalGift(
        id: 'baidu_paw',
        nameKey: 'local_gift_baidu_paw',
        emoji: '🐾',
        price: 300,
        color: LiveMessageColor(41, 50, 225),
      ),
      LocalGift(
        id: 'baidu_rocket',
        nameKey: 'local_gift_baidu_rocket',
        emoji: '🚀',
        price: 1000,
        color: LiveMessageColor(30, 40, 200),
        big: true,
      ),
    ],
    SiteIds.sixRoom: [
      LocalGift(
        id: 'six_rose',
        nameKey: 'local_gift_six_rose',
        emoji: '🌹',
        price: 10,
        color: LiveMessageColor(254, 4, 105),
      ),
      LocalGift(
        id: 'six_crown',
        nameKey: 'local_gift_six_crown',
        emoji: '👑',
        price: 300,
        color: LiveMessageColor(255, 170, 0),
      ),
      LocalGift(
        id: 'six_fly_screen',
        nameKey: 'local_gift_six_fly_screen',
        emoji: '✈️',
        price: 1000,
        color: LiveMessageColor(230, 0, 90),
        big: true,
      ),
    ],
    SiteIds.lookLive: [
      LocalGift(
        id: 'look_note',
        nameKey: 'local_gift_look_note',
        emoji: '🎵',
        price: 10,
        color: LiveMessageColor(255, 44, 85),
      ),
      LocalGift(
        id: 'look_song',
        nameKey: 'local_gift_look_song',
        emoji: '🎶',
        price: 300,
        color: LiveMessageColor(240, 30, 70),
      ),
      LocalGift(
        id: 'look_star',
        nameKey: 'local_gift_look_star',
        emoji: '🌟',
        price: 1500,
        color: LiveMessageColor(255, 180, 0),
        big: true,
      ),
    ],
    SiteIds.seventeenLive: [
      LocalGift(
        id: 'live17_barrage',
        nameKey: 'local_gift_live17_barrage',
        emoji: '💬',
        price: 80,
        color: LiveMessageColor(255, 45, 85),
      ),
      LocalGift(
        id: 'live17_lucky_bag',
        nameKey: 'local_gift_live17_lucky_bag',
        emoji: '🧧',
        price: 300,
        color: LiveMessageColor(230, 40, 60),
      ),
      LocalGift(
        id: 'live17_guard',
        nameKey: 'local_gift_live17_guard',
        emoji: '🛡️',
        price: 1500,
        color: LiveMessageColor(200, 20, 60),
        big: true,
      ),
    ],
  };

  /// The gifts of [platform] (the generic four for one without its own).
  static List<LocalGift> giftsFor(String platform) => _platformGifts[platform.trim().toLowerCase()] ?? genericGifts;

  /// The platforms with gifts of their own.
  static Iterable<String> get platformsWithGifts => _platformGifts.keys;

  /// The gift [id] of any pack (a history entry names it, D08.1), or null.
  static LocalGift? giftById(String id) {
    for (final gift in genericGifts) {
      if (gift.id == id) return gift;
    }
    for (final gifts in _platformGifts.values) {
      for (final gift in gifts) {
        if (gift.id == id) return gift;
      }
    }
    return null;
  }

  /// The pack of [platform] (the generic one when it has none).
  static LocalPlatformPack packFor(String platform) {
    final id = platform.trim().toLowerCase();
    for (final pack in packs) {
      if (pack.id == id) return pack;
    }
    return genericPack;
  }

  /// The badge's name key of [platform] ("舰队等级").
  static String badgeKeyFor(String platform) => packFor(platform).badgeKey;

  /// The weight "粗体" turns [weight] into (A08.13): 200 heavier, at
  /// least 700, so turning it off again with [regularWeight] gives back the
  /// weight the style had (500 ⇄ 700, 600 ⇄ 800).
  static int boldWeight(int weight) => (weight + 200).clamp(700, 900);

  /// The weight turning "粗体" off gives [weight]: 200 lighter, at most 600
  /// (under the 700 that reads as bold) and at least 400.
  static int regularWeight(int weight) => (weight - 200).clamp(400, 600);

  /// The experience of one level (3.x, D-001).
  static const int levelStep = 500;

  /// The level of [experience]: one per [levelStep], from 1.
  static int levelFor(int experience) => (experience < 0 ? 0 : experience) ~/ levelStep + 1;

  /// How far [experience] is into its level: the level, the experience
  /// gathered in it and the experience still missing to the next.
  static LocalLevelProgress progressFor(int experience) {
    final into = (experience < 0 ? 0 : experience) % levelStep;
    return (level: levelFor(experience), into: into, missing: levelStep - into);
  }

  // ---- local growth (D08.3, V03.6 §5.4): the rules, as numbers ----
  //
  // Changing them leaves the stored coins and experience as they are; only
  // what is earned from then on follows the new numbers.

  /// Watching earns once per this much playing time.
  static const Duration watchStep = Duration(minutes: 10);

  /// The experience of a [watchStep].
  static const int watchExperience = 10;

  /// The coins of a [watchStep].
  static const int watchCoins = 20;

  /// The most experience watching earns a day: past it, watching earns
  /// neither experience nor coins until the next day.
  static const int watchExperienceDailyLimit = 300;

  /// The first room of the day: its experience.
  static const int checkInExperience = 20;

  /// The first room of the day: its coins.
  static const int checkInCoins = 100;

  /// A local danmaku's experience.
  static const int chatExperience = 1;

  /// The most experience local danmaku earn a day.
  static const int chatExperienceDailyLimit = 50;

  /// Levels of one tier name.
  static const int levelsPerTier = 10;

  /// The tier names, one per [levelsPerTier] levels: Lv.1–9 the first,
  /// Lv.10–19 the second, …; the last one stays from Lv.90 on.
  static const List<String> tierKeys = [
    'local_level_tier_0',
    'local_level_tier_1',
    'local_level_tier_2',
    'local_level_tier_3',
    'local_level_tier_4',
    'local_level_tier_5',
    'local_level_tier_6',
    'local_level_tier_7',
    'local_level_tier_8',
    'local_level_tier_9',
  ];

  /// The tier name's key of [level].
  static String tierKeyFor(int level) =>
      tierKeys[(level < 1 ? 0 : level ~/ levelsPerTier).clamp(0, tierKeys.length - 1)];

  /// [value] as a nickname: trimmed, at most [nameLimit] characters; empty
  /// when nothing is left (not saved).
  static String normalizeName(String value) {
    final name = value.trim();
    final runes = name.runes.toList();
    return runes.length <= nameLimit ? name : String.fromCharCodes(runes.take(nameLimit));
  }

  /// The font family to draw [id] with (3.x `normalizeFontFamily`).
  static String? fontFamilyOf(String id) => switch (id) {
    'rounded' => 'sans-serif-rounded',
    'serif' => 'serif',
    'mono' => 'monospace',
    _ => null,
  };

  /// The place of [id].
  static LiveMessagePlacement placementOf(String id) => switch (id) {
    'top' => LiveMessagePlacement.top,
    'bottom' => LiveMessagePlacement.bottom,
    _ => LiveMessagePlacement.scroll,
  };
}
