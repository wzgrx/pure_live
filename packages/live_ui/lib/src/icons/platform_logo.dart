import 'package:flutter/widgets.dart';

/// The logos of the live platforms (3.x `Sites.logoForId`, artwork from
/// liuchuancong/pure_live), stored in this package as
/// `assets/platforms/<platform id>.png`.
abstract final class PlatformLogos {
  /// The package that holds the images (for [Image.asset]'s `package`).
  static const String package = 'live_ui';

  /// Platforms with a logo of their own: the 33 platforms of 3.x, Kick and
  /// IPTV.
  static const Set<String> ids = {
    'bilibili', 'douyu', 'huya', 'douyin', 'kuaishou', 'cc', 'iptv', 'twitch', 'soop', 'yy', 'acfun', //
    'picarto', 'twitcasting', 'missevan', 'inke', 'kilakila', 'xiaohongshu', 'niconico', 'weibo', 'showroom',
    'chzzk', 'kick', 'pandalive', 'fc2live', 'steambroadcast', 'jdlive', 'kugoulive', 'baidulive', 'looklive', '17live',
    'sixroom', 'youtube', 'bigo', 'liveme', 'tiktok',
  };

  /// The app logo, shown for any other id.
  static const String fallback = 'assets/platforms/app.png';

  /// Each platform's colour, ARGB: the one place the app takes a platform's
  /// colour from (the local interaction's platform packs, a precious gift's
  /// name in the chat list). It is the main colour of the logo above, so a
  /// logo and the tint around it agree (D08.6): the platform's own brand
  /// value where it has the logo's hue (Twitch's 9146FF, Douyin's FE2C55),
  /// the logo's sampled colour where 3.x's table had another hue (Bilibili's
  /// pink, not its blue; CC's blue, not pink; YY's and LiveMe's yellow…).
  /// A logo without a colour of its own (niconico, Missevan, IPTV) keeps
  /// 3.x's value.
  static const Map<String, int> colors = {
    'bilibili': 0xFFFB7299,
    'douyu': 0xFFFF6A00,
    'huya': 0xFFFF9800,
    'douyin': 0xFFFE2C55,
    'kuaishou': 0xFFFF4906,
    'cc': 0xFF1E7DFD,
    'twitch': 0xFF9146FF,
    'soop': 0xFF0675E8,
    'yy': 0xFFFFD800,
    'acfun': 0xFFFD4C5D,
    'picarto': 0xFF34A674,
    'twitcasting': 0xFF1E9FEA,
    'missevan': 0xFFF38AAE,
    'inke': 0xFF00D8C9,
    'kilakila': 0xFFFE696A,
    'xiaohongshu': 0xFFFF2442,
    'niconico': 0xFF252525,
    'weibo': 0xFFFF8200,
    'showroom': 0xFFFF2B67,
    'chzzk': 0xFF00E1B4,
    'kick': 0xFF53FC18,
    'liveme': 0xFFFFD60A,
    'tiktok': 0xFFFE2C55,
    'youtube': 0xFFFF0000,
    'bigo': 0xFF00C3FE,
    'pandalive': 0xFFFE4D6A,
    'fc2live': 0xFFFE7200,
    'steambroadcast': 0xFF1B2838,
    'jdlive': 0xFFE1251B,
    'kugoulive': 0xFF0063FE,
    'baidulive': 0xFF2932E1,
    'sixroom': 0xFFFE0469,
    'looklive': 0xFFFF2C55,
    '17live': 0xFFFF2D55,
    'iptv': 0xFF00A2FF,
  };

  /// The colour of [platformId] (trimmed, any case), ARGB, or null for an
  /// id without a logo of its own.
  static int? colorOf(String platformId) => colors[platformId.trim().toLowerCase()];

  /// The asset of [platformId] (trimmed, any case) inside [package].
  ///
  /// 3.x threw for an id it did not know, so a saved follow of a platform
  /// removed later broke the card menu; here every other id gets the app logo
  /// (3.x already did that for retired platforms).
  static String assetFor(String platformId) {
    final id = platformId.trim().toLowerCase();
    return ids.contains(id) ? 'assets/platforms/$id.png' : fallback;
  }
}

/// A platform's logo.
class PlatformLogo extends StatelessWidget {
  /// The logo of [platformId] at [size] × [size].
  const new(this.platformId, {this.size = 28, super.key});

  /// Platform id (`douyu`).
  final String platformId;

  /// Width and height.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(PlatformLogos.assetFor(platformId), package: PlatformLogos.package, width: size, height: size);
  }
}
