import 'package:meta/meta.dart';

/// Catch-up (replay) settings of a playlist entry: the M3U `catchup`,
/// `catchup-source`, `catchup-days` and `catchup-correction` attributes
/// (spec/modules/iptv.md §4).
@immutable
final class IptvCatchup {
  /// Creates the settings; [mode] is stored lower-case.
  const new({this.mode, this.source, this.days, this.correction});

  /// No catch-up attributes: past programmes use the playseek rule.
  static const none = IptvCatchup();

  /// Catch-up turned off (`catchup="disabled"`, `catchup-days="0"`).
  static const disabled = IptvCatchup(mode: 'disabled');

  /// Lower-case mode: `default`, `append`, `shift`, `playseek`, `offset`,
  /// `flussonic`, `xc`, `vod`, `disabled`, or another value a template
  /// handles; null when the playlist names none.
  final String? mode;

  /// URL template (`catchup-source`), or null.
  final String? source;

  /// How many days back the server keeps (`catchup-days`); null when unknown.
  final double? days;

  /// Hours added to programme times before they go into the URL
  /// (`catchup-correction`); null for none.
  final double? correction;

  /// Whether the playlist turned catch-up off for this entry.
  bool get isDisabled => mode == 'disabled';

  /// Whether no attribute was given.
  bool get isEmpty => mode == null && source == null && days == null && correction == null;

  @override
  bool operator ==(Object other) =>
      other is IptvCatchup &&
      other.mode == mode &&
      other.source == source &&
      other.days == days &&
      other.correction == correction;

  @override
  int get hashCode => Object.hash(mode, source, days, correction);

  @override
  String toString() => 'IptvCatchup($mode, $source, $days, $correction)';
}

/// One stream of a channel as a playlist lists it.
///
/// Entries with the same [name] are one channel: each entry is one line of
/// that channel (spec/product.md F-IPTV-11).
@immutable
final class IptvEntry {
  /// Creates an entry.
  const new({
    required this.name,
    required this.url,
    this.group = '',
    this.tvgId,
    this.tvgName,
    this.logo,
    this.catchup = IptvCatchup.none,
    this.headers = const {},
  });

  /// Channel name, whitespace collapsed; the channel's identity.
  final String name;

  /// Stream URL without the `|header=value` suffix.
  final String url;

  /// Group (`group-title`, TXT `#genre#`); empty when the playlist gives none.
  final String group;

  /// `tvg-id`: the programme guide channel id.
  final String? tvgId;

  /// `tvg-name`: the programme guide channel name.
  final String? tvgName;

  /// Channel logo URL.
  final String? logo;

  /// Catch-up settings.
  final IptvCatchup catchup;

  /// Request headers for the stream: lower-case names (`user-agent`,
  /// `referer`, `cookie`, …).
  final Map<String, String> headers;

  @override
  bool operator ==(Object other) =>
      other is IptvEntry &&
      other.name == name &&
      other.url == url &&
      other.group == group &&
      other.tvgId == tvgId &&
      other.tvgName == tvgName &&
      other.logo == logo &&
      other.catchup == catchup &&
      _sameHeaders(other.headers, headers);

  @override
  int get hashCode => Object.hash(name, url, group, tvgId, tvgName, logo, catchup, headers.length);

  @override
  String toString() => 'IptvEntry($name, $url)';

  static bool _sameHeaders(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((entry) => b[entry.key] == entry.value);
}

/// Playlist file formats (spec/product.md F-IPTV-01).
enum IptvFormat {
  /// M3U / M3U8 with `#EXTINF` entries.
  m3u,

  /// `group,#genre#` and `name,url` lines.
  txt,

  /// A JSON array or object of channels.
  json,
}

/// A problem found while parsing; the rest of the file still counts.
@immutable
final class IptvIssue {
  /// Creates an issue at 1-based [line] (null when the format has no lines).
  const new(this.reason, {this.line});

  /// What was wrong, in English, for logs and the import report.
  final String reason;

  /// 1-based line number.
  final int? line;

  @override
  String toString() => line == null ? reason : 'Line $line: $reason';
}

/// The result of parsing a playlist.
@immutable
final class ParsedPlaylist {
  /// Creates a result.
  const new({required this.format, required this.entries, this.guideUrls = const [], this.issues = const []});

  /// Detected format.
  final IptvFormat format;

  /// Entries in file order.
  final List<IptvEntry> entries;

  /// Programme guide URLs the playlist names (`x-tvg-url`, `url-tvg`).
  final List<Uri> guideUrls;

  /// Skipped or questionable lines.
  final List<IptvIssue> issues;
}

/// A channel of a programme guide.
@immutable
final class IptvGuideChannel {
  /// Creates a channel.
  const new({required this.id, this.names = const [], this.icon});

  /// Guide channel id (XMLTV `channel id`).
  final String id;

  /// Display names in guide order.
  final List<String> names;

  /// Channel icon URL.
  final String? icon;

  @override
  bool operator ==(Object other) {
    if (other is! IptvGuideChannel || other.id != id || other.icon != icon || other.names.length != names.length) {
      return false;
    }
    for (var i = 0; i < names.length; i++) {
      if (other.names[i] != names[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(id, icon, names.length);

  @override
  String toString() => 'IptvGuideChannel($id, $names)';
}

/// One programme of a guide. Times are UTC; the interval is half-open: the
/// start instant belongs to this programme, the stop instant to the next.
@immutable
final class IptvProgramme {
  /// Creates a programme.
  const new({
    required this.channelId,
    required this.start,
    required this.stop,
    required this.title,
    this.subtitle,
    this.description,
    this.catchupId,
  });

  /// Guide channel id.
  final String channelId;

  /// Start (UTC).
  final DateTime start;

  /// Stop (UTC), after [start].
  final DateTime stop;

  /// Title.
  final String title;

  /// Episode title.
  final String? subtitle;

  /// Description.
  final String? description;

  /// XMLTV `catchup-id`, for `{catchup-id}` templates and `vod` catch-up.
  final String? catchupId;

  /// Whether [at] falls in this programme.
  bool covers(DateTime at) => !at.isBefore(start) && at.isBefore(stop);

  @override
  bool operator ==(Object other) =>
      other is IptvProgramme &&
      other.channelId == channelId &&
      other.start == start &&
      other.stop == stop &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.description == description &&
      other.catchupId == catchupId;

  @override
  int get hashCode => Object.hash(channelId, start, stop, title);

  @override
  String toString() => 'IptvProgramme($channelId, $start–$stop, $title)';
}

/// The result of parsing a programme guide.
@immutable
final class ParsedGuide {
  /// Creates a result.
  const new({required this.channels, required this.programmes, this.issues = const []});

  /// Channels in guide order.
  final List<IptvGuideChannel> channels;

  /// Programmes, sorted by channel then start.
  final List<IptvProgramme> programmes;

  /// Skipped items.
  final List<IptvIssue> issues;
}
