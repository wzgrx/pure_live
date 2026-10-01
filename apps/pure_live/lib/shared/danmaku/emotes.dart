import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_danmaku/live_danmaku.dart';
import 'package:live_ui/live_ui.dart';

/// One emoticon of a bundled list: its picture in the app
/// (`assets/emo/images/<platform>/<file>`, empty without one) and the
/// platform's address (empty without one).
typedef BundledEmote = ({String asset, String url});

/// The emoticon codes of one platform's bundled list (3.x `assets/emo`): the
/// code a message writes (`[笑哭]`, Huya's `/{dx` too) → its picture.
@immutable
final class EmoteTable {
  const new _(this.codes, this._others);

  /// A table of [codes].
  factory of(Map<String, BundledEmote> codes) {
    final others = [
      for (final code in codes.keys)
        if (!_bracket.hasMatch(code) || _bracket.firstMatch(code)!.group(0) != code) code,
    ]..sort((a, b) => b.length.compareTo(a.length));
    return EmoteTable._(Map.unmodifiable(codes), others.isEmpty ? null : others.map(RegExp.escape).join('|'));
  }

  /// No codes.
  static const EmoteTable empty = EmoteTable._({}, null);

  /// The codes and their pictures.
  final Map<String, BundledEmote> codes;

  /// The codes that are not `[…]`, longest first, as a pattern.
  final String? _others;

  /// A code in brackets (`[笑哭]`, `[dog]`).
  static final RegExp _bracket = RegExp(r'\[[^\[\]\n]{1,16}\]');
}

/// The bundled emoticon lists (3.x `assets/emo`, M13.16): Bilibili, Douyin,
/// Douyu, Huya and Kuaishou, read from the app's assets the first time a
/// room of the platform shows its chat. CC's list is not bundled: its chat
/// is not supported.
final class EmoteLibrary {
  /// A library reading [bundle] (the app's assets by default).
  new({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  final Map<String, EmoteTable> _tables = {};
  final Map<String, Future<EmoteTable>> _loading = {};

  /// The platforms with a bundled list.
  static const Set<String> platforms = {
    SiteIds.bilibili,
    SiteIds.douyin,
    SiteIds.douyu,
    SiteIds.huya,
    SiteIds.kuaishou,
  };

  /// [platform]'s table once loaded, else empty.
  EmoteTable tableOf(String platform) => _tables[platform] ?? EmoteTable.empty;

  /// Loads [platform]'s table (once); empty for a platform without a list
  /// or a list that cannot be read.
  Future<EmoteTable> load(String platform) {
    if (!platforms.contains(platform)) return Future.value(EmoteTable.empty);
    if (_tables[platform] case final table?) return Future.value(table);
    return _loading[platform] ??= _read(platform);
  }

  Future<EmoteTable> _read(String platform) async {
    var table = EmoteTable.empty;
    try {
      final emojis = DanmakuEmoji.parseList(await _bundle.loadString(danmakuEmojiListAsset(platform)), platform);
      final codes = <String, BundledEmote>{};
      for (final emoji in emojis) {
        final asset = emoji.localFile.isEmpty ? '' : 'assets/emo/images/$platform/${emoji.localFile}';
        final url = emoji.url.trim();
        if (asset.isEmpty && url.isEmpty) continue;
        for (final key in emoji.keys) {
          codes.putIfAbsent(key, () => (asset: asset, url: url));
        }
      }
      table = EmoteTable.of(codes);
    } on Object catch (error) {
      debugPrint('Emoticon list of $platform not read: $error');
    } finally {
      unawaited(_loading.remove(platform));
    }
    return _tables[platform] = table;
  }
}

/// The app's [EmoteLibrary].
final Provider<EmoteLibrary> emoteLibraryProvider = Provider((ref) => EmoteLibrary());

/// The pieces of [message] for `EmoteText` (M13.16, UPGRADES B-12, B-13):
/// the codes the message names ([LiveMessage.emotes]: CHZZK, YouTube,
/// Bilibili, Kuaishou) and the codes of the platform's bundled list [table]
/// become pictures, the bundled picture first and the address as its
/// fallback; anything else stays text.
List<ChatSegment> chatSegments(LiveMessage message, [EmoteTable table = EmoteTable.empty]) {
  final text = message.message;
  final named = {
    for (final emote in message.emotes)
      if (emote.code.isNotEmpty) emote.code: emote.url,
  };
  if (named.isEmpty && table.codes.isEmpty) return [ChatTextSegment(text)];
  final pattern = RegExp(
    [
      if (named.isNotEmpty)
        ([...named.keys]..sort((a, b) => b.length.compareTo(a.length))).map(RegExp.escape).join('|'),
      if (table.codes.isNotEmpty) EmoteTable._bracket.pattern,
      ?table._others,
    ].join('|'),
  );
  final segments = <ChatSegment>[];
  var start = 0;
  for (final match in pattern.allMatches(text)) {
    final code = match.group(0)!;
    final bundled = table.codes[code];
    final url = named[code] ?? bundled?.url ?? '';
    if (bundled == null && !named.containsKey(code)) continue;
    if (match.start > start) segments.add(ChatTextSegment(text.substring(start, match.start)));
    segments.add(ChatEmoteSegment(url: url, alt: code, asset: bundled?.asset ?? ''));
    start = match.end;
  }
  if (segments.isEmpty) return [ChatTextSegment(text)];
  if (start < text.length) segments.add(ChatTextSegment(text.substring(start)));
  return segments;
}
