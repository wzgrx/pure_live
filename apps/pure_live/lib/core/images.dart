import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart';

/// A cover or avatar decoded at the size it is shown (principles rule 5):
/// widths are rounded up to 128 px steps so nearby sizes share one decode.
ImageProvider? networkImage(Uri? url, {required double logicalWidth, required double devicePixelRatio}) {
  if (url == null) return null;
  final pixels = (logicalWidth * devicePixelRatio / 128).ceil() * 128;
  return ResizeImage(CachedNetworkImageProvider(url.toString()), width: pixels, policy: ResizeImagePolicy.fit);
}
