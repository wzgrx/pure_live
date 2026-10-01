import 'dart:convert';

import 'package:live_iptv/src/model.dart';
import 'package:meta/meta.dart';
import 'package:xml/xml.dart' show XmlException;
import 'package:xml/xml_events.dart';

/// What a programme guide parser read.
@immutable
final class ParsedGuide {
  /// Creates a result.
  new({required List<GuideChannel> channels, required List<EpgProgramme> programmes})
    : channels = List.unmodifiable(channels),
      programmes = List.unmodifiable(programmes);

  /// Channels in file order.
  final List<GuideChannel> channels;

  /// Programmes in file order, without a source id.
  final List<EpgProgramme> programmes;

  /// Whether nothing was read (3.x rejected such a file as unsupported).
  bool get isEmpty => channels.isEmpty && programmes.isEmpty;
}

/// The guide formats.
enum GuideFormat {
  /// XMLTV (`.xml`, `.xml.gz`).
  xmltv,

  /// The JSON guide 3.x read.
  json;

  /// The format of decoded [text]: a JSON object or array is [json],
  /// everything else XMLTV (3.x chose by file extension, `.json` or not).
  static GuideFormat detect(String text) {
    final start = text.trimLeft();
    return start.startsWith('{') || start.startsWith('[') ? json : xmltv;
  }
}

/// Parses decoded guide [text] in [format] (detected when null). Malformed
/// XML or JSON throws [FormatException], so a broken download never replaces
/// a saved guide.
ParsedGuide parseGuide(String text, {GuideFormat? format}) => switch (format ?? GuideFormat.detect(text)) {
  GuideFormat.xmltv => XmltvParser.parse(text),
  GuideFormat.json => JsonGuideParser.parse(text),
};

/// Parses XMLTV with a pull parser (3.x built a DOM of the whole guide).
///
/// Reads `<channel id>` with its `<display-name>`s and first `<icon src>`,
/// and `<programme channel start stop catchup-id>` with the first `<title>`,
/// `<sub-title>`, `<desc>`, `<category>` and `<episode-num>`. Programmes
/// without channel, start, stop or title, or with a bad time, are skipped.
abstract final class XmltvParser {
  static const Set<String> _programmeFields = {'title', 'sub-title', 'desc', 'category', 'episode-num'};

  /// Parses [text].
  static ParsedGuide parse(String text) {
    final channels = <GuideChannel>[];
    final programmes = <EpgProgramme>[];
    _Channel? channel;
    _Programme? programme;
    String? field;
    final buffer = StringBuffer();
    try {
      for (final event in parseEvents(text, validateNesting: true, validateDocument: true)) {
        switch (event) {
          case final XmlStartElementEvent start:
            final name = start.localName;
            if (name == 'channel' && channel == null && programme == null) {
              final id = _attribute(start, 'id');
              if (start.isSelfClosing) {
                if (id != null) channels.add(GuideChannel(id: id));
              } else {
                channel = _Channel(id);
              }
            } else if (name == 'programme' && channel == null && programme == null) {
              if (!start.isSelfClosing) {
                programme = _Programme(
                  channel: _attribute(start, 'channel'),
                  start: _attribute(start, 'start'),
                  stop: _attribute(start, 'stop'),
                  catchupId: _attribute(start, 'catchup-id'),
                );
              }
            } else if (name == 'icon' && channel != null) {
              channel.icon ??= _attribute(start, 'src');
            } else if (!start.isSelfClosing &&
                ((channel != null && name == 'display-name') ||
                    (programme != null && _programmeFields.contains(name)))) {
              field = name;
              buffer.clear();
            }
          case final XmlTextEvent text when field != null:
            buffer.write(text.value);
          case final XmlCDATAEvent data when field != null:
            buffer.write(data.value);
          case final XmlEndElementEvent end:
            final name = end.localName;
            if (field != null && name == field) {
              final value = buffer.toString().trim();
              if (value.isNotEmpty) {
                if (channel != null) {
                  channel.names.add(value);
                } else {
                  programme?.fields.putIfAbsent(name, () => value);
                }
              }
              field = null;
            } else if (name == 'channel' && channel != null) {
              if (channel.id case final id?) {
                channels.add(GuideChannel(id: id, displayNames: channel.names, iconUrl: channel.icon));
              }
              channel = null;
            } else if (name == 'programme' && programme != null) {
              if (programme.build() case final parsed?) programmes.add(parsed);
              programme = null;
            }
          default:
            break;
        }
      }
    } on XmlException catch (e) {
      throw FormatException('Invalid XMLTV: $e');
    }
    return ParsedGuide(channels: channels, programmes: programmes);
  }

  static String? _attribute(XmlStartElementEvent event, String name) {
    for (final attribute in event.attributes) {
      if (attribute.localName == name) {
        final value = attribute.value.trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }
}

final _xmltvTime = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?(\d{2})?\s*(?:([+-])(\d{2}):?(\d{2})|(Z))?$',
  caseSensitive: false,
);

/// An XMLTV time (`20260927200000 +0800`, `202609272000`, `+08:00`, `Z`) as
/// UTC; without a zone it is UTC. Null when malformed (3.x read only
/// `±hhmm` and treated `+08:00` as a bad time, dropping the programme).
DateTime? parseXmltvTime(String? text) {
  final match = _xmltvTime.firstMatch(text?.trim() ?? '');
  if (match == null) return null;
  int part(int group) => int.parse(match.group(group) ?? '0');
  final month = part(2);
  final day = part(3);
  if (month < 1 || month > 12 || day < 1 || day > 31 || part(4) > 23 || part(5) > 59 || part(6) > 59) return null;
  final time = DateTime.utc(part(1), month, day, part(4), part(5), part(6));
  final sign = match.group(7);
  if (sign == null) return time;
  final offset = Duration(hours: part(8), minutes: part(9));
  return sign == '+' ? time.subtract(offset) : time.add(offset);
}

final class _Channel {
  new(this.id);

  final String? id;
  final names = <String>[];
  String? icon;
}

final class _Programme {
  new({required this.channel, required this.start, required this.stop, required this.catchupId});

  final String? channel;
  final String? start;
  final String? stop;
  final String? catchupId;
  final fields = <String, String>{};

  EpgProgramme? build() {
    final startTime = parseXmltvTime(start);
    final stopTime = parseXmltvTime(stop);
    final title = fields['title'];
    if (channel == null || startTime == null || stopTime == null || title == null) return null;
    return EpgProgramme(
      channelId: channel!,
      start: startTime,
      stop: stopTime,
      title: title,
      subtitle: fields['sub-title'],
      description: fields['desc'],
      category: fields['category'],
      episodeNum: fields['episode-num'],
      catchupId: catchupId,
    );
  }
}

/// Parses the JSON guide 3.x read (`JsonEpgParser`): an object with
/// `channels` (`id`/`channelId`/`name`, `displayName`/`name`,
/// `icon`/`iconUrl`/`logo`) and `programmes`/`epg`/`events`
/// (`channelId`/`channel`, `title`/`name`/`programme`,
/// `startTime`/`start`/`starttime`/`time`, `endTime`/`end`/`endtime`/`stop`
/// or `duration` minutes (30 by default), `description`/`desc`/`summary`,
/// `subtitle`/`subTitle`, `episodeNum`/`episode`, `category`/`genre`,
/// `catchupId`/`catchup-id`). Times are ISO 8601 (no zone: local), or Unix
/// seconds or milliseconds.
abstract final class JsonGuideParser {
  /// Parses [text].
  static ParsedGuide parse(String text) {
    final decoded = jsonDecode(text);
    final channels = <GuideChannel>[];
    final programmes = <EpgProgramme>[];
    if (decoded is Map<String, Object?>) {
      if (decoded['channels'] case final List<Object?> list) {
        for (final item in list) {
          if (_channel(item) case final channel?) channels.add(channel);
        }
      }
      if (decoded['programmes'] ?? decoded['epg'] ?? decoded['events'] case final List<Object?> list) {
        for (final item in list) {
          if (_programme(item) case final programme?) programmes.add(programme);
        }
      }
    }
    return ParsedGuide(channels: channels, programmes: programmes);
  }

  static String? _text(Map<String, Object?> item, List<String> keys) {
    for (final key in keys) {
      if (item[key] case final value?) return value.toString();
    }
    return null;
  }

  static GuideChannel? _channel(Object? item) {
    if (item is! Map<String, Object?>) return null;
    final id = _text(item, const ['id', 'channelId', 'name']);
    if (id == null || id.isEmpty) return null;
    return GuideChannel(
      id: id,
      displayNames: [
        _text(item, const ['displayName', 'name']) ?? id,
      ],
      iconUrl: _text(item, const ['icon', 'iconUrl', 'logo']),
    );
  }

  static EpgProgramme? _programme(Object? item) {
    if (item is! Map<String, Object?>) return null;
    final channel = _text(item, const ['channelId', 'channel']);
    final title = _text(item, const ['title', 'name', 'programme']);
    if (channel == null || channel.isEmpty || title == null || title.isEmpty) return null;
    final start = _time(item['startTime'] ?? item['start'] ?? item['starttime'] ?? item['time']);
    if (start == null) return null;
    final duration = item['duration'];
    final stop =
        _time(item['endTime'] ?? item['end'] ?? item['endtime'] ?? item['stop']) ??
        start.add(Duration(minutes: duration is int ? duration : 30));
    return EpgProgramme(
      channelId: channel,
      start: start,
      stop: stop,
      title: title,
      description: _text(item, const ['description', 'desc', 'summary']),
      subtitle: _text(item, const ['subtitle', 'subTitle']),
      episodeNum: _text(item, const ['episodeNum', 'episode']),
      category: _text(item, const ['category', 'genre']),
      catchupId: _text(item, const ['catchupId', 'catchup-id']),
    );
  }

  static DateTime? _time(Object? value) {
    DateTime epoch(int number) =>
        DateTime.fromMillisecondsSinceEpoch(number < 10000000000 ? number * 1000 : number, isUtc: true);
    return switch (value) {
      final int number => epoch(number),
      // Unix digits first: DateTime.tryParse reads `1790000000` as year
      // 179000 (3.x stored such programmes there).
      final String text when RegExp(r'^(\d{10}|\d{13})$').hasMatch(text.trim()) => epoch(int.parse(text.trim())),
      final String text => DateTime.tryParse(text) ?? (int.tryParse(text) == null ? null : epoch(int.parse(text))),
      _ => null,
    };
  }
}
