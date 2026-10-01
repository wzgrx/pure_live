import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:live_ui/src/scope.dart';

/// A cached network image the way 3.x's cards and avatars loaded theirs:
/// the cache manager, headers and cache epoch of [LiveUiScope], a decode
/// width, no fade, and the old picture kept while a new address loads.
class LiveNetworkImage extends StatelessWidget {
  /// Loads [url] (non-empty).
  const new({
    required this.url,
    required this.placeholder,
    required this.error,
    this.memCacheWidth,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.low,
    super.key,
  });

  /// Image address.
  final String url;

  /// Shown while loading.
  final WidgetBuilder placeholder;

  /// Shown when loading fails.
  final WidgetBuilder error;

  /// Decoded width in physical pixels.
  final int? memCacheWidth;

  /// How the image fills its box.
  final BoxFit fit;

  /// How the decoded picture is scaled to the box (a tiny decode drawn
  /// large with [FilterQuality.medium] reads as a soft blur).
  final FilterQuality filterQuality;

  @override
  Widget build(BuildContext context) {
    final config = LiveUiScope.of(context);
    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: config.imageCacheKey(url),
      httpHeaders: config.imageHeaders?.call(url),
      cacheManager: config.imageCacheManager,
      fit: fit,
      memCacheWidth: memCacheWidth,
      filterQuality: filterQuality,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: (context, _) => placeholder(context),
      errorWidget: (context, _, _) => error(context),
    );
  }
}
