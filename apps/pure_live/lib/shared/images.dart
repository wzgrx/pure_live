import 'package:flutter/foundation.dart';

/// The request headers of a cover or avatar at [url] (3.x
/// `networkImageHeaders`): Bilibili's image hosts (`hdslb.com`) check the
/// Referer, so it is sent there only; every image is asked for with a
/// desktop browser's User-Agent.
Map<String, String>? networkImageHeaders(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  if (host == 'hdslb.com' || host.endsWith('.hdslb.com')) return _bilibiliHeaders;
  return _browserHeaders;
}

const String _browserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/151.0.0.0 Safari/537.36';

const Map<String, String> _bilibiliHeaders = {'Referer': 'https://live.bilibili.com/', 'User-Agent': _browserAgent};

const Map<String, String> _browserHeaders = {'User-Agent': _browserAgent};

/// Bumped when the image cache is cleared (3.x `CacheController.imageCacheEpoch`):
/// the app passes it to `LiveUiConfig.imageCacheEpoch`, so covers and
/// avatars on screen are fetched again under a new cache key.
final ValueNotifier<int> imageCacheEpoch = ValueNotifier(0);
