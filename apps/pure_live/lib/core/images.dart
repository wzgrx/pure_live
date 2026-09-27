import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// A cover or avatar decoded at the size it is shown (principles rule 5):
/// widths are rounded up to 128 px steps so nearby sizes share one decode.
///
/// [period] (F-FAV-04 cover refresh) goes into the cache key, so a new period
/// downloads the image again instead of reusing the cached copy.
ImageProvider? networkImage(Uri? url, {required double logicalWidth, required double devicePixelRatio, int? period}) {
  if (url == null) return null;
  final pixels = (logicalWidth * devicePixelRatio / 128).ceil() * 128;
  final key = url.toString();
  return ResizeImage(
    CachedNetworkImageProvider(key, cacheKey: period == null ? null : '$key#$period'),
    width: pixels,
    policy: ResizeImagePolicy.fit,
  );
}
