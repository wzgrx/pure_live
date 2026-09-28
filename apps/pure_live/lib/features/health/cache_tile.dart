import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pure_live_app/features/settings/settings_search.dart';
import 'package:pure_live_app/i18n/strings.g.dart';

/// 清理缓存 (spec/product.md F-SET-09): covers and avatars cached on disk and
/// decoded in memory. Follows, history, settings and recordings are untouched.
class CacheTile extends StatefulWidget {
  const new({super.key});

  @override
  State<CacheTile> createState() => _CacheTileState();
}

class _CacheTileState extends State<CacheTile> {
  int? _bytes;

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  Future<Directory> _cacheDirectory() async =>
      Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}${DefaultCacheManager.key}');

  Future<void> _measure() async {
    var total = 0;
    final directory = await _cacheDirectory();
    if (directory.existsSync()) {
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) total += await entity.length();
      }
    }
    if (mounted) setState(() => _bytes = total);
  }

  Future<void> _clear() async {
    await DefaultCacheManager().emptyCache();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    await _measure();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.health.imageCacheCleared)));
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return SettingAnchor(
      id: cacheAnchor,
      child: ListTile(
        leading: const Icon(Icons.cleaning_services_outlined),
        title: Text(t.health.clearImageCache),
        subtitle: Text(
          bytes == null
              ? t.health.calculating
              : t.health.imageCacheSize(size: (bytes / 1024 / 1024).toStringAsFixed(1)),
        ),
        onTap: bytes == null ? null : _clear,
      ),
    );
  }
}
