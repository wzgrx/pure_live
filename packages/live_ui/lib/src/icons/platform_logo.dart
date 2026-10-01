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
