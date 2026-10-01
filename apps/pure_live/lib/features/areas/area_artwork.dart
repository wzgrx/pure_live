import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:live_core/live_core.dart';
import 'package:live_store/live_store.dart';
import 'package:live_ui/live_ui.dart';

// Missevan's verified two-state category icons (3.x category_artwork.dart).
const _missevanSpriteStems = {
  '/live/catalog/icon/104',
  '/live/catalog/icon/105',
  '/live/catalog/icon/115',
  '/live/catalog/icon/116',
  '/live/catalog/icon/122',
  '/live/tags/icon/001_20210322112121',
};

/// Which part of a category picture to show (3.x
/// `categoryArtworkAlignment`): Missevan's vertical two-state icons show
/// their coloured half (the top of `-web.png`, the bottom of the mobile
/// file); everything else is centred.
Alignment categoryArtworkAlignment(String? source) {
  final uri = Uri.tryParse(normalizeImageUrl(source));
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host != 'static.maoercdn.com' ||
      uri.userInfo.isNotEmpty ||
      uri.port != (uri.scheme == 'https' ? 443 : 80)) {
    return Alignment.center;
  }
  final web = uri.path.endsWith('-web.png');
  final suffix = web ? '-web.png' : '.png';
  if (!uri.path.endsWith(suffix) ||
      !_missevanSpriteStems.contains(uri.path.substring(0, uri.path.length - suffix.length))) {
    return Alignment.center;
  }
  return web ? Alignment.topCenter : Alignment.bottomCenter;
}

/// Whether [source] is a two-state icon, not artwork to lend to other
/// platforms' areas of the same name.
bool isCategoryIconSprite(String? source) => categoryArtworkAlignment(source) != Alignment.center;

/// Pictures of areas by name, lent to areas without one (3.x
/// `AreaPicMapper`): every catalogue that loads teaches its pictures; an
/// area without a picture borrows the one of the same name (case ignored),
/// of a known alias, or of a name containing or contained in it. Kept in the
/// store's meta table so it survives restarts (3.x: `cached_area_pics`).
final class AreaPictures {
  /// Pictures kept in the meta store (null: this run only).
  new(this._meta);

  final MetaStore? _meta;
  final Map<String, String> _byName = {};
  Future<void>? _loading;

  /// Meta key of the saved pictures.
  static const String metaKey = 'areas.pictures';

  // 3.x's hard-coded aliases (category words → an area that has artwork).
  static const Map<String, String> _aliases = {
    '射击游戏': '穿越火线',
    'fps': '穿越火线',
    'cs2': '穿越火线',
    'csgo': '穿越火线',
    'cf': '穿越火线',
    '网游竞技': '英雄联盟',
    '竞技游戏': '英雄联盟',
    'moba': '英雄联盟',
    'dota2': '英雄联盟',
    '休闲益智': '互动组队',
    '文化': '成年教育',
    '娱乐生活': '户外',
    '交友娱乐': '户外',
    '吃喝玩乐': '户外',
    '角色扮演': '原神',
    'rpg': '原神',
    'mmo': '原神',
    '策略卡牌': '金铲铲之战',
    '棋牌策略': '金铲铲之战',
  };

  /// Reads the saved pictures once.
  Future<void> load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      final raw = await _meta?.get(metaKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final MapEntry(:key, :value) in decoded.entries) {
        final picture = '$value';
        if (key is String && picture.isNotEmpty && !isCategoryIconSprite(picture)) {
          _byName.putIfAbsent(key, () => picture);
        }
      }
    } on Object {
      // A broken entry only loses borrowed pictures.
    }
  }

  /// Learns the pictures of [categories]; saves when something changed.
  Future<void> learn(Iterable<LiveCategory> categories) async {
    var changed = false;
    for (final area in categories.expand((category) => category.children)) {
      final name = area.areaName.trim();
      final picture = area.areaPic.trim();
      if (name.isEmpty || picture.isEmpty || isCategoryIconSprite(picture)) continue;
      if (_byName[name] != picture) {
        _byName[name] = picture;
        changed = true;
      }
    }
    if (!changed || _meta == null) return;
    try {
      await _meta.set(metaKey, jsonEncode(_byName));
    } on Object {
      // Kept in memory for this run.
    }
  }

  /// The picture to show for [area]: its own, else a borrowed one, else ''.
  String pictureFor(LiveArea area) {
    final own = area.areaPic.trim();
    if (own.isNotEmpty) return own;
    return borrow(area.areaName);
  }

  /// A picture learned for an area named like [name], or ''.
  String borrow(String name) {
    final wanted = name.trim().toLowerCase();
    if (wanted.isEmpty || _byName.isEmpty) return '';
    String? exact(String lower) {
      for (final MapEntry(:key, :value) in _byName.entries) {
        if (key.trim().toLowerCase() == lower) return value;
      }
      return null;
    }

    final direct = exact(wanted);
    if (direct != null) return direct;
    final alias = _aliases[wanted];
    if (alias != null) {
      final picture = exact(alias.toLowerCase());
      if (picture != null) return picture;
    }
    for (final MapEntry(:key, :value) in _byName.entries) {
      final lower = key.trim().toLowerCase();
      if (lower.isNotEmpty && (wanted.contains(lower) || lower.contains(wanted))) return value;
    }
    for (final MapEntry(:key, :value) in _aliases.entries) {
      if (!wanted.contains(key)) continue;
      final picture = exact(value.toLowerCase());
      if (picture != null) return picture;
    }
    return '';
  }
}

/// A square category picture: Missevan's two-state icons show their
/// coloured half, others fill the square; a TV icon while loading, a broken
/// image icon on failure, a TV icon without a picture (3.x `AreaCard`).
class AreaArtwork extends StatelessWidget {
  /// Shows [url] (any form a platform gives).
  const new({required this.url, super.key});

  /// The picture address.
  final String url;

  @override
  Widget build(BuildContext context) {
    final address = normalizeImageUrl(url);
    final colors = Theme.of(context).colorScheme;
    if (address.isEmpty) {
      return ColoredBox(
        color: colors.surfaceContainerLow,
        child: Center(child: Icon(Icons.live_tv_rounded, color: colors.onSurfaceVariant.withValues(alpha: 0.5))),
      );
    }
    Widget placeholder(BuildContext context) => ColoredBox(
      color: colors.surfaceContainerLow,
      child: Center(child: Icon(Icons.live_tv_rounded, color: Theme.of(context).disabledColor.withValues(alpha: 0.3))),
    );
    Widget error(BuildContext context) => ColoredBox(
      color: colors.surfaceContainerLow,
      child: Center(child: Icon(Icons.broken_image_rounded, color: Theme.of(context).disabledColor)),
    );
    final alignment = categoryArtworkAlignment(address);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 160.0;
        final decodeWidth = (width * MediaQuery.devicePixelRatioOf(context)).round().clamp(160, 512);
        final image = LiveNetworkImage(
          url: address,
          placeholder: placeholder,
          error: error,
          memCacheWidth: decodeWidth,
          fit: alignment == Alignment.center ? BoxFit.cover : BoxFit.fitWidth,
        );
        if (alignment == Alignment.center) return image;
        // A two-state icon is twice as tall as wide: lay it out at full
        // height and let the square show the wanted half.
        return ClipRect(
          child: OverflowBox(
            alignment: alignment,
            minHeight: 0,
            maxHeight: double.infinity,
            child: SizedBox(width: width, child: image),
          ),
        );
      },
    );
  }
}
