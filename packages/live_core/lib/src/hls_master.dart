import 'dart:convert';

import 'package:meta/meta.dart';

/// An explicit video (and audio) choice in an HLS master playlist, never a
/// guessed ABR choice (3.x's `core/common/hls_master_selection.dart`). The
/// selected master keeps the variant's external audio rather than handing
/// the player a video-only child.
@immutable
final class HlsMasterSelection {
  const new _(this.source, this.video, this.audio);

  /// Parses [text] (the master at [source]) and selects [video], with the
  /// one audio rendition of its group or [audio]; throws [FormatException]
  /// when the master or the choice is not exact.
  factory fromMaster(String text, {required Uri source, required Uri video, Uri? audio}) =>
      HlsMasterPlaylist.parse(source, text).select(video: video, audio: audio);

  /// The master playlist the selection was made in.
  final Uri source;

  /// The selected variant playlist.
  final Uri video;

  /// The selected audio rendition, when the variant has an audio group.
  final Uri? audio;

  /// A fresh copy of the master at the same [source] reduced to the selected
  /// variant (and its audio): the choice is found by URI, never by position,
  /// so a reordered master still selects the same media. Another source or
  /// a master without the selected media throws [FormatException].
  String rewrite(Uri source, String text) {
    if (source != this.source) throw const FormatException('Selected HLS master source changed');
    final master = HlsMasterPlaylist.parse(source, text);
    final (variant, rendition) = master._select(video, audio);
    return [...master._prefix, ?rendition?.line, variant.line, variant.uri.toString(), ''].join('\n');
  }
}

/// One `#EXT-X-STREAM-INF` variant of a master playlist.
@immutable
final class HlsMasterVariant {
  new _(this.uri, this.line, Map<String, String> attributes) : attributes = Map.unmodifiable(attributes);

  /// The variant playlist, resolved against the master.
  final Uri uri;

  /// The `#EXT-X-STREAM-INF` line as written.
  final String line;

  /// Its attributes (`BANDWIDTH`, `RESOLUTION`, `AUDIO`...), quotes removed.
  final Map<String, String> attributes;
}

/// A bounded, ordinary HLS master playlist, for explicit selection only
/// (3.x's `HlsMasterPlaylist`).
///
/// Anything it does not understand fails closed with a [FormatException]
/// instead of being dropped: subtitles, session keys and data, start
/// offsets, closed captions, duplicate or cyclic media, missing audio
/// groups, insecure or credentialed URIs, more than 32 variants or
/// renditions, more than 4 MiB of text. No language, camera, subtitle or
/// encryption semantics are silently discarded.
@immutable
final class HlsMasterPlaylist {
  new _(this.source, this._prefix, List<HlsMasterVariant> variants, this._audio)
    : variants = List.unmodifiable(variants);

  /// Parses [text], the master playlist at [source].
  factory parse(Uri source, String text) {
    _resolve(source, source.toString());
    if (text.length > maxBytes || (text.length * 3 > maxBytes && utf8.encode(text).length > maxBytes)) {
      throw const FormatException('HLS master exceeds byte budget');
    }
    final lines = const LineSplitter()
        .convert(text)
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty || lines.first != '#EXTM3U') throw const FormatException('Expected HLS master');
    final prefix = <String>['#EXTM3U'];
    final variants = <HlsMasterVariant>[];
    final audio = <({Uri uri, String line, String group})>[];
    final audioNames = <(String, String)>{};
    final audioUris = <Uri>{};
    final videoUris = <Uri>{};
    String? pending;
    var version = false;
    var independent = false;
    for (final line in lines.skip(1)) {
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        if (pending != null || variants.length >= maxEntries) throw const FormatException('Invalid HLS variant count');
        pending = line;
      } else if (line.startsWith('#EXT-X-MEDIA:')) {
        if (pending != null || audio.length >= maxEntries) {
          throw const FormatException('Invalid HLS rendition placement');
        }
        final attributes = _attributes(line.substring('#EXT-X-MEDIA:'.length));
        if (attributes['TYPE'] != 'AUDIO' ||
            (attributes['GROUP-ID'] ?? '').isEmpty ||
            (attributes['NAME'] ?? '').isEmpty ||
            attributes.keys.any((key) => !_renditionAttributes.contains(key))) {
          throw const FormatException('Unsupported HLS rendition');
        }
        for (final key in const ['DEFAULT', 'AUTOSELECT']) {
          if (attributes.containsKey(key) && !const {'YES', 'NO'}.contains(attributes[key])) {
            throw const FormatException('Invalid HLS audio flags');
          }
        }
        final uri = _resolve(source, attributes['URI'] ?? '');
        if (!audioNames.add((attributes['GROUP-ID']!, attributes['NAME']!)) || !audioUris.add(uri)) {
          throw const FormatException('Ambiguous HLS rendition identity');
        }
        audio.add((uri: uri, line: line, group: attributes['GROUP-ID']!));
      } else if (line.startsWith('#EXT-X-VERSION:')) {
        if (pending != null || version || !RegExp(r'^[1-9]\d*$').hasMatch(line.substring('#EXT-X-VERSION:'.length))) {
          throw const FormatException('Invalid HLS version');
        }
        version = true;
        prefix.add(line);
      } else if (line == '#EXT-X-INDEPENDENT-SEGMENTS') {
        if (pending != null || independent) throw const FormatException('Invalid HLS independence tag');
        independent = true;
        prefix.add(line);
      } else if (line.startsWith('#')) {
        if (line.startsWith('#EXT')) throw const FormatException('Unsupported HLS master tag');
      } else {
        final info = pending;
        if (info == null) throw const FormatException('Unexpected HLS URI');
        final attributes = _variantAttributes(info.substring('#EXT-X-STREAM-INF:'.length));
        final uri = _resolve(source, line);
        if (!videoUris.add(uri)) throw const FormatException('Ambiguous HLS variant identity');
        variants.add(HlsMasterVariant._(uri, info, attributes));
        pending = null;
      }
    }
    if (pending != null || variants.isEmpty) throw const FormatException('Incomplete HLS master');
    if (videoUris.contains(source) || audioUris.contains(source) || videoUris.any(audioUris.contains)) {
      throw const FormatException('Cyclic or overlapping HLS media selection');
    }
    for (final variant in variants) {
      final group = variant.attributes['AUDIO'];
      if (group != null && (group.isEmpty || !audio.any((item) => item.group == group))) {
        throw const FormatException('Missing HLS audio group');
      }
    }
    return HlsMasterPlaylist._(source, prefix, variants, audio);
  }

  /// Where the master was read.
  final Uri source;

  /// Its variants in playlist order.
  final List<HlsMasterVariant> variants;

  final List<String> _prefix;
  final List<({Uri uri, String line, String group})> _audio;

  /// The largest master accepted, in UTF-8 bytes.
  static const int maxBytes = 4 * 1024 * 1024;

  /// The most variants, and the most audio renditions, accepted.
  static const int maxEntries = 32;

  /// Selects [video] (and [audio]) in this master; see
  /// [HlsMasterSelection.fromMaster].
  HlsMasterSelection select({required Uri video, Uri? audio}) {
    final selected = _select(video, audio);
    return HlsMasterSelection._(source, video, selected.$2?.uri);
  }

  (HlsMasterVariant, ({Uri uri, String line, String group})?) _select(Uri video, Uri? selectedAudio) {
    final matches = variants.where((variant) => variant.uri == video).toList();
    if (matches.length != 1) throw const FormatException('Selected HLS video is unavailable');
    final variant = matches.single;
    final group = variant.attributes['AUDIO'];
    if (group == null) {
      if (selectedAudio != null) throw const FormatException('Selected HLS audio is not associated with video');
      return (variant, null);
    }
    // A default rendition is not the user's choice: a group with several
    // renditions needs an explicit one.
    final choices = _audio
        .where((item) => item.group == group && (selectedAudio == null || item.uri == selectedAudio))
        .toList();
    if (choices.length != 1) throw const FormatException('Explicit HLS audio selection required');
    return (variant, choices.single);
  }

  static const Set<String> _renditionAttributes = {
    'TYPE',
    'GROUP-ID',
    'NAME',
    'URI',
    'DEFAULT',
    'AUTOSELECT',
    'LANGUAGE',
    'CHANNELS',
    'CHARACTERISTICS',
  };

  static const Set<String> _streamAttributes = {
    'BANDWIDTH',
    'AVERAGE-BANDWIDTH',
    'RESOLUTION',
    'CODECS',
    'FRAME-RATE',
    'AUDIO',
    'CLOSED-CAPTIONS',
  };

  static const int _maxSafeInteger = 9007199254740991;

  static Map<String, String> _variantAttributes(String text) {
    final attributes = _attributes(text);
    final rate = int.tryParse(attributes['BANDWIDTH'] ?? '');
    if (rate == null ||
        rate <= 0 ||
        rate > _maxSafeInteger ||
        attributes.keys.any((key) => !_streamAttributes.contains(key)) ||
        (attributes.containsKey('CLOSED-CAPTIONS') && attributes['CLOSED-CAPTIONS'] != 'NONE')) {
      throw const FormatException('Unsupported HLS variant');
    }
    if (attributes['AVERAGE-BANDWIDTH'] case final average?) {
      final value = int.tryParse(average);
      if (value == null || value <= 0 || value > _maxSafeInteger) {
        throw const FormatException('Invalid HLS average bandwidth');
      }
    }
    if (attributes['RESOLUTION'] case final resolution?
        when !RegExp(r'^[1-9]\d{0,4}x[1-9]\d{0,4}$').hasMatch(resolution)) {
      throw const FormatException('Invalid HLS resolution');
    }
    if (attributes['FRAME-RATE'] case final rate?) {
      final frames = double.tryParse(rate);
      if (frames == null || !frames.isFinite || frames <= 0 || frames > 1000) {
        throw const FormatException('Invalid HLS frame rate');
      }
    }
    if (attributes['CODECS'] == '') throw const FormatException('Empty HLS codecs');
    return attributes;
  }
}

/// [text] resolved against [source]: both http(s) with a host, without
/// credentials, fragments or control characters, and never a downgrade from
/// https.
Uri _resolve(Uri source, String text) {
  final uri = source.resolve(text);
  if (!const {'http', 'https'}.contains(source.scheme) ||
      source.host.isEmpty ||
      source.userInfo.isNotEmpty ||
      source.hasFragment ||
      text.isEmpty ||
      text.length > 65536 ||
      text.contains(RegExp(r'[\x00-\x20\x7f]')) ||
      !const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      (source.scheme == 'https' && uri.scheme != 'https')) {
    throw const FormatException('Invalid HLS master URI');
  }
  return uri;
}

/// An attribute list (`KEY=value,KEY="quoted"`); a repeated key, a
/// malformed pair or a trailing comma throws.
Map<String, String> _attributes(String text) {
  final values = HlsStreamInf.attributesOf(text, strict: true);
  if (text.endsWith(',')) throw const FormatException('Incomplete HLS attributes');
  return values;
}

/// One `#EXT-X-STREAM-INF` of a master playlist read leniently: the
/// reading YouTube and PandaTV share (M7.1 notes; each used to have its
/// own). Unlike [HlsMasterPlaylist] nothing is validated here: the
/// platform decides what a missing URI or odd attributes mean (YouTube
/// refuses the whole master, PandaTV only loses that variant).
@immutable
final class HlsStreamInf {
  const new _(this.attributeText, this.uri);

  /// The tag's attribute list as written (after `#EXT-X-STREAM-INF:`).
  final String attributeText;

  /// The URI line this variant names, trimmed and not yet resolved: the
  /// first line after the tag that is not a tag or a comment (other tags in
  /// between are skipped); null when the next `#EXT-X-STREAM-INF` or the
  /// end comes first.
  final String? uri;

  /// [attributeText] read by [attributesOf].
  Map<String, String> attributes({bool strict = false}) => attributesOf(attributeText, strict: strict);

  /// Every `#EXT-X-STREAM-INF` of the master [text], in order. Lines are
  /// trimmed and blank ones skipped; the first must be `#EXTM3U`, else
  /// [FormatException]. A URI line without a tag before it is skipped.
  static List<HlsStreamInf> read(String text) {
    final lines = const LineSplitter().convert(text).map((line) => line.trim()).where((line) => line.isNotEmpty);
    final iterator = lines.iterator;
    if (!iterator.moveNext() || iterator.current != '#EXTM3U') throw const FormatException('Expected HLS master');
    final result = <HlsStreamInf>[];
    String? pending;
    while (iterator.moveNext()) {
      final line = iterator.current;
      if (line.startsWith(_tag)) {
        if (pending != null) result.add(HlsStreamInf._(pending, null));
        pending = line.substring(_tag.length);
      } else if (!line.startsWith('#') && pending != null) {
        result.add(HlsStreamInf._(pending, line));
        pending = null;
      }
    }
    if (pending != null) result.add(HlsStreamInf._(pending, null));
    return result;
  }

  static const String _tag = '#EXT-X-STREAM-INF:';

  static final RegExp _strictPair = RegExp(r'([A-Z0-9-]+)=("[^"\r\n\x00]*"|[^,\s"]+)(?:,|$)');
  static final RegExp _lenientPair = RegExp('([A-Z0-9-]+)=("[^"]*"|[^,]*)');

  /// An attribute list as names and values, quotes removed. [strict] (the
  /// RFC grammar, as YouTube and [HlsMasterPlaylist] read it): one
  /// comma-separated `NAME=value` after another, each name once, a value
  /// quoted or a token without spaces; anything else is a
  /// [FormatException]. Otherwise (PandaTV): every `NAME=value` found, a
  /// repeated name keeping its last value, the rest ignored.
  static Map<String, String> attributesOf(String text, {bool strict = false}) {
    String unquote(String value) => value.length >= 2 && value.startsWith('"') && value.endsWith('"')
        ? value.substring(1, value.length - 1)
        : value;
    if (!strict) {
      return {for (final match in _lenientPair.allMatches(text)) match[1]!: unquote(match[2]!)};
    }
    final values = <String, String>{};
    var offset = 0;
    while (offset < text.length) {
      final match = _strictPair.matchAsPrefix(text, offset);
      if (match == null || values.containsKey(match[1])) throw const FormatException('Malformed HLS attributes');
      values[match[1]!] = unquote(match[2]!);
      offset = match.end;
    }
    return values;
  }
}
