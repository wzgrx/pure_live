import 'dart:convert';

import 'package:live_iptv/src/guide/guide_builder.dart';
import 'package:live_iptv/src/guide/xmltv.dart';
import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/text.dart';

/// Parses JSON programme guides (spec/modules/iptv.md §2.2). Accepted shapes:
///
/// - `{"channels": [{"id", "name" | "displayName" | "names", "icon"}],
///    "programmes" | "epg" | "events": [{"channel" | "channelId", "title",
///    "start", "stop" | "end", "desc", …}]}`;
/// - a DIYP day (`{"channel_name", "date": "2026-09-27", "epg_data":
///   [{"start": "08:00", "end": "09:00", "title", "desc"}]}`), whose clock
///   times are local time on that date.
///
/// Times are Unix seconds or milliseconds, ISO 8601 (local when no zone is
/// given) or XMLTV times. A programme without a stop ends after its
/// `duration` (minutes) or at the channel's next programme.
abstract final class JsonGuideParser {
  /// Parses [text]; throws [FormatException] when it is not a JSON object.
  /// [local] turns DIYP wall-clock times (as UTC fields) into UTC; the
  /// default uses this device's time zone.
  static ParsedGuide parse(String text, {DateTime? from, DateTime? to, DateTime Function(DateTime)? local}) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) throw const FormatException('JSON guide must be an object');
    final builder = GuideBuilder(from: from, to: to);
    if (decoded['epg_data'] is List) {
      _diyp(decoded, builder, local ?? _local);
      return builder.build();
    }
    if (decoded['channels'] case final List<Object?> channels) {
      for (final item in channels) {
        if (item is! Map<String, Object?>) continue;
        final id = _text(item, const ['id', 'channelId', 'channel_id', 'tvg-id', 'name']);
        final names = <String>[
          if (item['names'] case final List<Object?> list) ...[for (final name in list) ?nonEmpty(name)],
          ?_text(item, const ['displayName', 'display-name', 'name', 'channel_name']),
        ];
        builder.channel(id, names, _text(item, const ['icon', 'iconUrl', 'logo']));
      }
    }
    final programmes = decoded['programmes'] ?? decoded['programs'] ?? decoded['epg'] ?? decoded['events'];
    if (programmes is List) {
      for (final item in programmes) {
        if (item is! Map<String, Object?>) continue;
        final start = parseGuideTime(item['start'] ?? item['startTime'] ?? item['starttime'] ?? item['time']);
        var stop = parseGuideTime(item['stop'] ?? item['end'] ?? item['endTime'] ?? item['endtime']);
        final minutes = switch (item['duration']) {
          final num number when number > 0 => number,
          final String text => num.tryParse(text.trim()),
          _ => null,
        };
        if (stop == null && start != null && minutes != null && minutes > 0) {
          stop = start.add(Duration(seconds: (minutes * 60).round()));
        }
        builder.programme(
          channelId: _text(item, const ['channel', 'channelId', 'channel_id']),
          start: start,
          stop: stop,
          hasStop: stop != null,
          title: _text(item, const ['title', 'name', 'programme', 'program']),
          subtitle: _text(item, const ['subtitle', 'subTitle', 'sub-title']),
          description: _text(item, const ['desc', 'description', 'summary']),
          catchupId: _text(item, const ['catchupId', 'catchup-id']),
        );
      }
    }
    return builder.build();
  }

  static void _diyp(Map<String, Object?> day, GuideBuilder builder, DateTime Function(DateTime) local) {
    final name = _text(day, const ['channel_name', 'channel', 'name']);
    final date = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(_text(day, const ['date']) ?? '');
    if (name == null || date == null) {
      builder.issue('DIYP guide without channel_name or date');
      return;
    }
    builder.channel(name, [name], null);
    final (year, month, dayOfMonth) = (int.parse(date[1]!), int.parse(date[2]!), int.parse(date[3]!));
    DateTime? at(Object? value) {
      final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(nonEmpty(value) ?? '');
      if (match == null) return null;
      return local(DateTime.utc(year, month, dayOfMonth, int.parse(match[1]!), int.parse(match[2]!)));
    }

    for (final item in day['epg_data']! as List) {
      if (item is! Map<String, Object?>) continue;
      final start = at(item['start']);
      var stop = at(item['end']);
      // "23:30"–"00:00" ends on the next day.
      if (start != null && stop != null && !stop.isAfter(start)) stop = stop.add(const Duration(days: 1));
      builder.programme(
        channelId: name,
        start: start,
        stop: stop,
        hasStop: stop != null,
        title: _text(item, const ['title']),
        description: _text(item, const ['desc', 'description']),
      );
    }
  }

  /// Wall-clock fields (given as UTC fields) of this device's zone → UTC.
  static DateTime _local(DateTime wall) =>
      DateTime(wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second).toUtc();

  static String? _text(Map<String, Object?> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is String || value is num) {
        final text = nonEmpty(value);
        if (text != null) return text;
      }
    }
    return null;
  }
}

/// A guide time from JSON: Unix seconds or milliseconds (number or digits),
/// ISO 8601 (local time when no zone is given), or an XMLTV time. Null when
/// unreadable.
DateTime? parseGuideTime(Object? value) {
  if (value is num) return _epoch(value.toInt());
  final text = nonEmpty(value);
  if (text == null) return null;
  // Ten digits are Unix seconds, thirteen milliseconds; twelve or fourteen
  // are an XMLTV `YYYYMMDDhhmm[ss]`.
  if (RegExp(r'^(\d{10}|\d{13})$').hasMatch(text)) return _epoch(int.parse(text));
  if (RegExp(r'^(\d{12}|\d{14})(\s|$|[+-]|Z)').hasMatch(text)) return parseXmltvTime(text);
  return DateTime.tryParse(text)?.toUtc();
}

DateTime _epoch(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value < 100000000000 ? value * 1000 : value, isUtc: true);
