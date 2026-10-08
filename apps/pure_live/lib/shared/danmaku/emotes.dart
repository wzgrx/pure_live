import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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
  const new _(this.codes, this._others, this._pattern);

  /// A table of [codes].
  factory of(Map<String, BundledEmote> codes) {
    final others = [
      for (final code in codes.keys)
        if (!_bracket.hasMatch(code) || _bracket.firstMatch(code)!.group(0) != code) code,
    ]..sort((a, b) => b.length.compareTo(a.length));
    final pattern = others.isEmpty ? null : others.map(RegExp.escape).join('|');
    return EmoteTable._(
      Map.unmodifiable(codes),
      pattern,
      codes.isEmpty ? null : RegExp([_bracket.pattern, ?pattern].join('|')),
    );
  }

  /// No codes.
  static const EmoteTable empty = EmoteTable._({}, null, null);

  /// The codes and their pictures.
  final Map<String, BundledEmote> codes;

  /// The codes that are not `[…]`, longest first, as a pattern.
  final String? _others;

  /// The table's codes compiled once (B09 c7: every message compiled them
  /// again); null without codes.
  final RegExp? _pattern;

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

/// Builds with [platform]'s bundled emoticons for a flying layer: the table
/// at once when it is loaded, else empty until it is (then again). The
/// multi-view cells (N01.2 c3) and the mini windows (D03.3 c2) read it the
/// way the room's picture does; a new [platform] reads its own.
class EmoteTableBuilder extends ConsumerStatefulWidget {
  /// Creates the builder.
  const new({required this.platform, required this.builder, super.key});

  /// The platform whose table is read; null for none.
  final String? platform;

  /// Builds with the table.
  final Widget Function(BuildContext context, EmoteTable emotes) builder;

  @override
  ConsumerState<EmoteTableBuilder> createState() => _EmoteTableBuilderState();
}

class _EmoteTableBuilderState extends ConsumerState<EmoteTableBuilder> {
  EmoteTable _emotes = EmoteTable.empty;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(EmoteTableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.platform != widget.platform) _read();
  }

  void _read() {
    final platform = widget.platform;
    if (platform == null) {
      _emotes = EmoteTable.empty;
      return;
    }
    final library = ref.read(emoteLibraryProvider);
    _emotes = library.tableOf(platform);
    if (_emotes.codes.isNotEmpty) return;
    unawaited(
      library.load(platform).then((table) {
        // Not after the page closed or the cell changed platform.
        if (mounted && widget.platform == platform && table.codes.isNotEmpty) setState(() => _emotes = table);
      }),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _emotes);
}

/// Each message's pieces with the table they were made with: the chat list
/// and the flying layer get the same message and share one parse (B09 c7).
final Expando<(EmoteTable, List<ChatSegment>)> _parsed = Expando('chat segments');

/// The pieces of [message] for `EmoteText` (M13.16, UPGRADES B-12, B-13):
/// the codes the message names ([LiveMessage.emotes]: CHZZK, YouTube,
/// Bilibili, Kuaishou) and the codes of the platform's bundled list [table]
/// become pictures, the bundled picture first and the address as its
/// fallback; anything else stays text.
///
/// Parsed once per message and table (B09 c7: the chat list and the flying
/// danmaku each parsed it); the list is shared and cannot be changed.
List<ChatSegment> chatSegments(LiveMessage message, [EmoteTable table = EmoteTable.empty]) {
  if (_parsed[message] case (final of, final segments) when identical(of, table)) return segments;
  final segments = List<ChatSegment>.unmodifiable(_parse(message, table));
  _parsed[message] = (table, segments);
  return segments;
}

List<ChatSegment> _parse(LiveMessage message, EmoteTable table) {
  final text = message.message;
  final named = {
    for (final emote in message.emotes)
      if (emote.code.isNotEmpty) emote.code: emote.url,
  };
  if (named.isEmpty && table.codes.isEmpty) return [ChatTextSegment(text)];
  // The table's own pattern, compiled once; a message naming its own codes
  // puts them first.
  final pattern = named.isEmpty
      ? table._pattern!
      : RegExp(
          [
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
