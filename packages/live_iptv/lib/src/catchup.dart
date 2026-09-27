import 'package:live_iptv/src/model.dart';
import 'package:meta/meta.dart';

/// Where a programme stands at a moment. Intervals are half-open: the start
/// instant is [live], the stop instant is [past].
enum ProgrammePhase {
  /// Not started.
  upcoming,

  /// On air.
  live,

  /// Over; may be replayed (catch-up).
  past,
}

/// The phase of [programme] at [now].
ProgrammePhase programmePhase(IptvProgramme programme, DateTime now) {
  if (now.isBefore(programme.start)) return ProgrammePhase.upcoming;
  return now.isBefore(programme.stop) ? ProgrammePhase.live : ProgrammePhase.past;
}

/// Whether a past programme can be replayed.
enum CatchupAvailability {
  /// A catch-up URL can be built.
  available,

  /// The playlist turned catch-up off for the channel.
  disabled,

  /// Older than the channel's `catchup-days`.
  expired,

  /// The playlist's catch-up settings cannot produce a URL for it.
  unsupported,
}

/// Why no catch-up URL could be built.
@immutable
final class CatchupError implements Exception {
  /// Creates the error.
  const new(this.reason);

  /// English reason, for logs.
  final String reason;

  @override
  String toString() => 'CatchupError: $reason';
}

const _knownModes = {
  'default',
  'append',
  'shift',
  'timeshift',
  'playseek',
  'offset',
  'flussonic',
  'flussonic-hls',
  'flussonic-ts',
  'fs',
  'xc',
  'vod',
};

/// Whether a past [programme] of a channel with [catchup] can be replayed at
/// [now] (spec/modules/iptv.md §4.1).
CatchupAvailability catchupAvailability(IptvCatchup catchup, IptvProgramme programme, DateTime now) {
  if (catchup.isDisabled) return CatchupAvailability.disabled;
  final hasId = programme.catchupId?.trim().isNotEmpty ?? false;
  final source = catchup.source;
  if ((source?.contains('{catchup-id}') ?? false) && !hasId) return CatchupAvailability.unsupported;
  if (catchup.mode == 'vod' && source == null && !hasId) return CatchupAvailability.unsupported;
  final mode = catchup.mode;
  if (mode != null && !_knownModes.contains(mode) && source == null) return CatchupAvailability.unsupported;
  final days = catchup.days;
  if (days != null && days > 0) {
    final window = Duration(microseconds: (days * Duration.microsecondsPerDay).round());
    if (programme.stop.isBefore(now.subtract(window))) return CatchupAvailability.expired;
  }
  return CatchupAvailability.available;
}

/// The catch-up URL of [programme] on the stream [url] (spec/modules/iptv.md
/// §4.2). Throws [CatchupError] when the settings cannot produce one.
///
/// - No attributes, `default` / `playseek` / `append` without a source: the
///   playseek rule, `playseek=<start>-<stop>` in local time
///   (`yyyyMMddHHmmss`), replacing an existing `playseek`.
/// - A source template: an absolute result replaces the URL (not for
///   `append`); a relative one (`?…`, `&…`) is appended to it.
/// - `shift` / `timeshift`: appends `utc={utc}&lutc={lutc}`.
/// - `offset`: sets `catchup=default&offset=<seconds since the start>`.
/// - `flussonic*` / `fs`, `xc`: rewrites the path the way those servers
///   expect; `vod`: the programme's `catchup-id` is the URL.
///
/// Times are shifted by `catchup-correction` hours first. Local times use
/// [utcOffset] when given (tests), else this device's time zone.
Uri catchupUrl({
  required String url,
  required IptvCatchup catchup,
  required IptvProgramme programme,
  required DateTime now,
  Duration? utcOffset,
}) {
  if (catchup.isDisabled) throw const CatchupError('Catch-up is disabled for this channel');
  final original = Uri.tryParse(url.trim());
  if (original == null || !original.hasScheme) throw const CatchupError('Stream URL has no scheme');
  if (!programme.stop.isAfter(programme.start)) throw const CatchupError('Programme stop is not after its start');
  final shift = switch (catchup.correction) {
    final hours? when hours.isFinite && hours != 0 => Duration(
      microseconds: (hours * Duration.microsecondsPerHour).round(),
    ),
    _ => Duration.zero,
  };
  final times = _Times(
    start: programme.start.toUtc().add(shift),
    stop: programme.stop.toUtc().add(shift),
    now: now.toUtc(),
    utcOffset: utcOffset,
    catchupId: programme.catchupId?.trim(),
  );
  final source = catchup.source?.trim().isEmpty ?? true ? null : catchup.source!.trim();
  Uri fromSource(String template, {required bool appendOnly}) {
    final expanded = times.expand(template);
    final absolute = Uri.tryParse(expanded);
    if (!appendOnly && absolute != null && absolute.hasScheme && absolute.host.isNotEmpty) return absolute;
    if (RegExp('^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(expanded)) {
      throw const CatchupError('Catch-up source is not a valid URL');
    }
    return _append(original, expanded);
  }

  switch (catchup.mode) {
    case null || 'default' || 'playseek' || 'append':
      if (source == null) return _setQuery(original, {'playseek': times.playseek});
      return fromSource(source, appendOnly: catchup.mode == 'append');
    case 'shift' || 'timeshift':
      return _append(original, times.expand('utc={utc}&lutc={lutc}'));
    case 'offset':
      if (source != null) return fromSource(source, appendOnly: false);
      return _setQuery(original, {'catchup': 'default', 'offset': '${times.offset}'});
    case final String mode when const {'flussonic', 'flussonic-hls', 'flussonic-ts', 'fs'}.contains(mode):
      return Uri.parse(times.expand(_flussonic(original, mode)));
    case 'xc':
      return Uri.parse(times.expand(_xtream(original)));
    case 'vod':
      if (source != null) return fromSource(source, appendOnly: false);
      final id = Uri.tryParse(times.catchupId ?? '');
      if (id == null || !id.hasScheme) throw const CatchupError('Catch-up id is not a URL');
      return id;
    default:
      if (source != null) return fromSource(source, appendOnly: false);
      throw CatchupError('Unsupported catch-up mode: ${catchup.mode}');
  }
}

/// Appends a query [suffix] (`?a=1`, `&a=1` or `a=1`) before the fragment.
Uri _append(Uri original, String suffix) {
  var query = suffix.trim();
  while (query.startsWith('?') || query.startsWith('&')) {
    query = query.substring(1);
  }
  if (query.isEmpty) throw const CatchupError('Catch-up source is empty');
  final text = original.toString();
  final base = original.hasFragment ? text.substring(0, text.lastIndexOf('#')) : text;
  final separator = original.hasQuery && original.query.isNotEmpty ? '&' : '?';
  final fragment = original.hasFragment ? '#${original.fragment}' : '';
  return Uri.parse('$base$separator$query$fragment');
}

/// Replaces [values] in the query, keeping every other (repeated) parameter.
Uri _setQuery(Uri original, Map<String, String> values) {
  final query = <String, List<String>>{
    for (final MapEntry(:key, :value) in original.queryParametersAll.entries) key: [...value],
  };
  for (final MapEntry(:key, :value) in values.entries) {
    query[key] = [value];
  }
  return original.replace(queryParameters: query);
}

/// Flussonic archive paths: `…/mpegts` → `timeshift_abs-${start}.ts`;
/// `…/index.m3u8` → `timeshift_rel-{offset:1}.m3u8`; `…/name.m3u8` →
/// `name-timeshift_rel-{offset:1}.m3u8`.
String _flussonic(Uri uri, String mode) {
  if (!(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
    throw const CatchupError('Flussonic catch-up needs an HTTP stream URL');
  }
  final path = uri.path;
  final slash = path.lastIndexOf('/');
  if (slash <= 0 || slash == path.length - 1) throw const CatchupError('Flussonic stream path is incomplete');
  final directory = path.substring(0, slash);
  final file = path.substring(slash + 1);
  final String archive;
  if (file == 'mpegts' || mode == 'fs' || mode == 'flussonic-ts') {
    archive = '$directory/timeshift_abs-{utc}.ts';
  } else if (file.endsWith('.m3u8') && file != 'index.m3u8') {
    archive = '$directory/${file.substring(0, file.length - 5)}-timeshift_rel-{offset:1}.m3u8';
  } else {
    archive = '$directory/timeshift_rel-{offset:1}.m3u8';
  }
  return _withPath(uri, archive);
}

/// Xtream Codes: `/live/user/pass/id.ts` → `/timeshift/user/pass/{duration:60}/
/// {Y}-{m}-{d}:{H}-{M}/id.ts`.
String _xtream(Uri uri) {
  if (!(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty || uri.query.isNotEmpty) {
    throw const CatchupError('Xtream Codes stream URL is invalid');
  }
  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  if (parts.firstOrNull == 'live') parts.removeAt(0);
  if (parts.length != 3) throw const CatchupError('Xtream Codes stream path is invalid');
  final [user, password, file] = parts;
  final dot = file.lastIndexOf('.');
  final extension = dot > 0 ? file.substring(dot) : '.ts';
  final id = dot > 0 ? file.substring(0, dot) : file;
  if (id.isEmpty) throw const CatchupError('Xtream Codes channel id is missing');
  return _withPath(uri, '/timeshift/$user/$password/{duration:60}/{Y}-{m}-{d}:{H}-{M}/$id$extension');
}

String _withPath(Uri uri, String path) {
  final query = uri.query.isEmpty ? '' : '?${uri.query}';
  final fragment = uri.fragment.isEmpty ? '' : '#${uri.fragment}';
  return '${uri.scheme}://${uri.authority}$path$query$fragment';
}

final _placeholder = RegExp(r'\$?\{([^{}]+)\}');
final _javaPattern = RegExp('yyyy|MM|dd|HH|mm|ss');
final _kodiPattern = RegExp('[YmdHMS]');

/// Programme times and the template placeholders of §4.3.
final class _Times {
  new({required this.start, required this.stop, required this.now, required this.utcOffset, this.catchupId});

  final DateTime start;
  final DateTime stop;
  final DateTime now;
  final Duration? utcOffset;
  final String? catchupId;

  int _epoch(DateTime time) => time.millisecondsSinceEpoch ~/ 1000;

  int get duration => stop.difference(start).inSeconds;

  /// Seconds from the programme start to now; never negative.
  int get offset {
    final seconds = now.difference(start).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  /// Wall-clock fields in local time, carried in a UTC [DateTime].
  DateTime _local(DateTime time) {
    final offset = utcOffset;
    if (offset != null) return time.add(offset);
    final local = time.toLocal();
    return DateTime.utc(local.year, local.month, local.day, local.hour, local.minute, local.second);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _compact(DateTime wall) =>
      '${wall.year.toString().padLeft(4, '0')}${_two(wall.month)}${_two(wall.day)}'
      '${_two(wall.hour)}${_two(wall.minute)}${_two(wall.second)}';

  /// `yyyyMMddHHmmss-yyyyMMddHHmmss` in local time.
  String get playseek => '${_compact(_local(start))}-${_compact(_local(stop))}';

  static String _java(DateTime wall, String pattern) => pattern.replaceAllMapped(_javaPattern, (match) {
    return switch (match[0]) {
      'yyyy' => wall.year.toString().padLeft(4, '0'),
      'MM' => _two(wall.month),
      'dd' => _two(wall.day),
      'HH' => _two(wall.hour),
      'mm' => _two(wall.minute),
      _ => _two(wall.second),
    };
  });

  static String _kodi(DateTime time, String pattern) => pattern.replaceAllMapped(_kodiPattern, (match) {
    return switch (match[0]) {
      'Y' => time.year.toString().padLeft(4, '0'),
      'm' => _two(time.month),
      'd' => _two(time.day),
      'H' => _two(time.hour),
      'M' => _two(time.minute),
      _ => _two(time.second),
    };
  });

  /// Expands every `{…}` / `${…}` placeholder; an unknown one is an error,
  /// so an ambiguous URL is never requested.
  String expand(String template) => template.replaceAllMapped(_placeholder, (match) {
    final body = match[1]!;
    final local = _local(start);
    if (body.startsWith('(b)') || body.startsWith('(e)')) {
      final time = body.startsWith('(b)') ? start : stop;
      final pattern = body.substring(3);
      return pattern == 'timestamp' ? '${_epoch(time)}' : _java(_local(time), pattern);
    }
    final colon = body.indexOf(':');
    final name = colon < 0 ? body : body.substring(0, colon);
    final argument = colon < 0 ? null : body.substring(colon + 1);
    DateTime? instant(String name) => switch (name) {
      'utc' || 'start' => start,
      'utcend' || 'end' => stop,
      'lutc' || 'now' || 'timestamp' => now,
      _ => null,
    };
    if (argument == null) {
      if (instant(name) case final time?) return '${_epoch(time)}';
      switch (name) {
        case 'duration':
          return '$duration';
        case 'offset':
          return '$offset';
        case 'catchup-id':
          final id = catchupId;
          if (id == null || id.isEmpty) throw const CatchupError('Programme has no catch-up id');
          return id;
        case 'Y':
          return local.year.toString().padLeft(4, '0');
        case 'm':
          return _two(local.month);
        case 'd':
          return _two(local.day);
        case 'H':
          return _two(local.hour);
        case 'M':
          return _two(local.minute);
        case 'S':
          return _two(local.second);
      }
      throw CatchupError('Unsupported catch-up template field: $body');
    }
    if (name == 'duration' || name == 'offset') {
      final divisor = int.tryParse(argument);
      if (divisor == null || divisor <= 0) throw CatchupError('Invalid divisor in $body');
      return '${(name == 'duration' ? duration : offset) ~/ divisor}';
    }
    if (instant(name) case final time?) return _kodi(time, argument);
    throw CatchupError('Unsupported catch-up template field: $body');
  });
}
