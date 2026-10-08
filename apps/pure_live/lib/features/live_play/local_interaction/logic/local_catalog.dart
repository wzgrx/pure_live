import 'package:flutter/foundation.dart';
import 'package:live_core/live_core.dart';

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
  });

  /// The platform id ([SiteIds]), or `generic`.
  final String id;

  /// The platform's name key.
  final String nameKey;

  /// The coin's name key ("电池").
  final String currencyKey;

  /// The level's name key ("用户等级").
  final String levelKey;

  /// The theme colour, ARGB.
  final int accent;

  /// The badge: an emoji, or two letters.
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
/// places, titles, the 34 platform packs and the gifts.
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

  /// The longest local danmaku, in characters (A08.13: the platforms let a
  /// viewer send 20 to 40; 40 still crosses a landscape phone in about one
  /// screen width at the default size).
  static const danmakuLimit = 40;

  /// From this many characters on the composer shows its count (the last
  /// ten before [danmakuLimit]).
  static const int danmakuCountFrom = danmakuLimit - 10;

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

  static LocalPlatformPack _pack(String id, String nameKey, int accent, String badge, [String? own]) =>
      LocalPlatformPack(
        id: id,
        nameKey: nameKey,
        currencyKey: own == null ? 'local_currency_generic' : 'local_currency_$own',
        levelKey: own == null ? 'local_level_generic' : 'local_level_$own',
        accent: accent,
        badge: badge,
      );

  /// The 34 platform packs in 3.x's order.
  static final List<LocalPlatformPack> packs = List.unmodifiable([
    _pack(SiteIds.bilibili, 'site_bilibili', 0xFF00AEEC, '📺', 'bili'),
    _pack(SiteIds.douyu, 'site_douyu', 0xFFFF6A00, '🐟', 'douyu'),
    _pack(SiteIds.huya, 'site_huya', 0xFFFF9800, '🐯', 'huya'),
    _pack(SiteIds.douyin, 'site_douyin', 0xFFFE2C55, '🎵', 'douyin'),
    _pack(SiteIds.kuaishou, 'site_kuaishou', 0xFFFF4906, '🎬', 'kuaishou'),
    _pack(SiteIds.cc, 'site_cc', 0xFFFF4D7D, '🎮', 'cc'),
    _pack(SiteIds.twitch, 'site_twitch', 0xFF9146FF, '💜', 'twitch'),
    _pack(SiteIds.soop, 'site_soop', 0xFF0675E8, '🎈', 'soop'),
    _pack(SiteIds.yy, 'site_yy', 0xFFFF6B35, '🎤'),
    _pack(SiteIds.acfun, 'site_acfun', 0xFFFD4C5D, '🅰️'),
    _pack(SiteIds.picarto, 'site_picarto', 0xFF25BFA4, '🎨'),
    _pack(SiteIds.twitcasting, 'site_twitcasting', 0xFF294DDB, '📡'),
    _pack(SiteIds.missevan, 'site_missevan', 0xFFF38AAE, '🎧'),
    _pack(SiteIds.inke, 'site_inke', 0xFFFF4F9A, '✨'),
    _pack(SiteIds.kilakila, 'site_kilakila', 0xFF7C5CFC, '💫'),
    _pack(SiteIds.xiaohongshu, 'site_xiaohongshu', 0xFFFF2442, '📕'),
    _pack(SiteIds.niconico, 'site_niconico', 0xFF252525, '📹'),
    _pack(SiteIds.weibo, 'site_weibo', 0xFFFF8200, '🟠'),
    _pack(SiteIds.showroom, 'site_showroom', 0xFFFF2B67, '🎟️'),
    _pack(SiteIds.chzzk, 'site_chzzk', 0xFF00FFA3, '🎮'),
    _pack(SiteIds.seventeenLive, 'site_17live', 0xFFFF2D55, '17'),
    _pack(SiteIds.liveMe, 'site_liveme', 0xFF7C4DFF, 'LM'),
    _pack(SiteIds.tiktok, 'site_tiktok', 0xFFFE2C55, 'TT'),
    _pack(SiteIds.youtube, 'site_youtube', 0xFFFF0000, 'YT'),
    _pack(SiteIds.bigo, 'site_bigo', 0xFF6A5CFF, 'BG'),
    _pack(SiteIds.pandaLive, 'site_pandalive', 0xFFFE4D6A, 'PD'),
    _pack(SiteIds.fc2Live, 'site_fc2live', 0xFFEA4C89, 'FC'),
    _pack(SiteIds.steamBroadcast, 'site_steambroadcast', 0xFF1B2838, 'ST'),
    _pack(SiteIds.jdLive, 'site_jdlive', 0xFFE1251B, 'JD'),
    _pack(SiteIds.kugouLive, 'site_kugoulive', 0xFF19A7FF, 'KG'),
    _pack(SiteIds.baiduLive, 'site_baidulive', 0xFF2932E1, 'BD'),
    _pack(SiteIds.sixRoom, 'site_sixroom', 0xFFFF5A5F, '6R'),
    _pack(SiteIds.lookLive, 'site_looklive', 0xFFFF2C55, 'LK'),
    _pack(SiteIds.iptv, 'site_iptv', 0xFF00A2FF, '🌐'),
  ]);

  /// The gifts of the eight platforms that have their own; each has one
  /// high-value gift with the big banner.
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
  };

  /// The gifts of [platform] (the generic four for most).
  static List<LocalGift> giftsFor(String platform) => _platformGifts[platform.trim().toLowerCase()] ?? genericGifts;

  /// The pack of [platform] (the generic one when it has none).
  static LocalPlatformPack packFor(String platform) {
    final id = platform.trim().toLowerCase();
    for (final pack in packs) {
      if (pack.id == id) return pack;
    }
    return genericPack;
  }

  /// The badge's name key of [platform] ("舰队等级").
  static String badgeKeyFor(String platform) => switch (platform.trim().toLowerCase()) {
    SiteIds.bilibili => 'local_badge_bilibili',
    SiteIds.douyu => 'local_badge_douyu',
    SiteIds.huya => 'local_badge_huya',
    SiteIds.douyin => 'local_badge_douyin',
    SiteIds.kuaishou => 'local_badge_kuaishou',
    SiteIds.cc => 'local_badge_cc',
    SiteIds.twitch => 'local_badge_twitch',
    SiteIds.soop => 'local_badge_soop',
    _ => 'local_badge_generic',
  };

  /// The weight "粗体" turns [weight] into (A08.13): 200 heavier, at
  /// least 700, so turning it off again with [regularWeight] gives back the
  /// weight the style had (500 ⇄ 700, 600 ⇄ 800).
  static int boldWeight(int weight) => (weight + 200).clamp(700, 900);

  /// The weight turning "粗体" off gives [weight]: 200 lighter, at most 600
  /// (under the 700 that reads as bold) and at least 400.
  static int regularWeight(int weight) => (weight - 200).clamp(400, 600);

  /// The level of [experience]: one per 500, from 1.
  static int levelFor(int experience) => (experience < 0 ? 0 : experience) ~/ 500 + 1;

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
