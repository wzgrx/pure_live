/// The action represented by an IPTV programme at a specific wall-clock time.
///
/// Programme intervals are half-open: the start instant belongs to the live
/// programme, while the stop instant belongs to catch-up/history. Keeping this
/// rule in one pure helper prevents the schedule highlight and tap action from
/// disagreeing at exact EPG boundaries.
enum IptvProgrammePhase { scheduled, live, catchup }

enum CatchupUrlType { default_, playseek, offset }

enum IptvProgrammeSelectionResult { scheduled, live, catchupStarted, busy, invalidUrl, failed }

IptvProgrammePhase classifyIptvProgramme({required DateTime start, required DateTime stop, required DateTime now}) {
  if (now.isBefore(start)) return IptvProgrammePhase.scheduled;
  if (now.isBefore(stop)) return IptvProgrammePhase.live;
  return IptvProgrammePhase.catchup;
}

/// Builds the three legacy catch-up URL shapes without losing an existing
/// fragment or repeated query parameter.
///
/// [now] is injectable so offset URLs and their tests use one deterministic
/// clock snapshot. A future programme produces a zero offset rather than a
/// negative provider request.
String buildIptvCatchupUrl({
  required String originalUrl,
  required DateTime start,
  required DateTime stop,
  CatchupUrlType type = CatchupUrlType.default_,
  DateTime? now,
}) {
  if (!stop.isAfter(start)) {
    throw ArgumentError.value(stop, 'stop', 'Programme stop must be after its start');
  }
  final uri = Uri.parse(originalUrl.trim());
  if (uri.toString().isEmpty || !uri.hasScheme) {
    throw ArgumentError.value(originalUrl, 'originalUrl', 'Playback URL must include a scheme');
  }
  final startText = _compactDateTime(start);
  final stopText = _compactDateTime(stop);

  return switch (type) {
    CatchupUrlType.playseek => _replaceQueryValue(uri, 'playseek', '$startText-$stopText'),
    CatchupUrlType.offset => _replaceQueryValues(uri, <String, String>{
      'catchup': 'default',
      'offset': _nonNegativeOffset(now ?? DateTime.now(), start).toString(),
    }),
    CatchupUrlType.default_ => _replaceQueryValue(uri, 'timeshift', startText),
  };
}

int _nonNegativeOffset(DateTime now, DateTime start) {
  final seconds = now.difference(start).inSeconds;
  return seconds < 0 ? 0 : seconds;
}

String _compactDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}'
      '${two(value.month)}${two(value.day)}'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}';
}

String _replaceQueryValue(Uri uri, String key, String value) {
  return _replaceQueryValues(uri, <String, String>{key: value});
}

String _replaceQueryValues(Uri uri, Map<String, String> replacements) {
  final values = <String, dynamic>{
    for (final entry in uri.queryParametersAll.entries) entry.key: List<String>.from(entry.value),
  };
  for (final entry in replacements.entries) {
    values[entry.key] = entry.value;
  }
  return uri.replace(queryParameters: values).toString();
}
