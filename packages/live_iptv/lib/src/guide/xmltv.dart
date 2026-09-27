import 'package:live_iptv/src/guide/guide_builder.dart';
import 'package:live_iptv/src/model.dart';
import 'package:xml/xml.dart' show XmlException;
import 'package:xml/xml_events.dart';

/// Parses XMLTV programme guides (spec/modules/iptv.md §2.1) with a pull
/// parser, so a guide of tens of megabytes never becomes a DOM.
///
/// Reads `<channel id>` with its `<display-name>`s and `<icon src>`, and
/// `<programme channel start stop catchup-id>` with the first `<title>`,
/// `<sub-title>` and `<desc>`. Programmes outside the window are dropped;
/// a missing `stop` ends at the channel's next programme.
abstract final class XmltvParser {
  /// Malformed markup is skipped; after this many errors the rest is dropped.
  static const maxErrors = 200;

  /// Parses [text] (already decoded; gzip is handled by `decodeIptvText`).
  static ParsedGuide parse(String text, {DateTime? from, DateTime? to}) {
    final builder = GuideBuilder(from: from, to: to);
    final iterator = parseEvents(text).iterator;
    var errors = 0;
    _Channel? channel;
    _Programme? programme;
    String? field;
    final buffer = StringBuffer();
    while (true) {
      try {
        if (!iterator.moveNext()) break;
      } on XmlException {
        if (++errors > maxErrors) {
          builder.issue('Too many XML errors; the rest of the guide is skipped');
          break;
        }
        continue;
      }
      switch (iterator.current) {
        case final XmlStartElementEvent start:
          final name = start.localName;
          if (name == 'channel' && channel == null && programme == null) {
            channel = _Channel(_attribute(start, 'id'));
            if (start.isSelfClosing) {
              builder.channel(channel.id, channel.names, channel.icon);
              channel = null;
            }
          } else if (name == 'programme' && channel == null && programme == null) {
            programme = _Programme(
              channel: _attribute(start, 'channel'),
              start: _attribute(start, 'start'),
              stop: _attribute(start, 'stop'),
              catchupId: _attribute(start, 'catchup-id'),
            );
            if (start.isSelfClosing) {
              builder.issue('Programme without a title');
              programme = null;
            }
          } else if (name == 'icon' && channel != null) {
            channel.icon ??= _attribute(start, 'src');
          } else if (!start.isSelfClosing &&
              ((channel != null && name == 'display-name') ||
                  (programme != null && (name == 'title' || name == 'sub-title' || name == 'desc')))) {
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
              } else if (programme != null) {
                switch (field) {
                  case 'title':
                    programme.title ??= value;
                  case 'sub-title':
                    programme.subtitle ??= value;
                  default:
                    programme.description ??= value;
                }
              }
            }
            field = null;
          } else if (name == 'channel' && channel != null) {
            builder.channel(channel.id, channel.names, channel.icon);
            channel = null;
          } else if (name == 'programme' && programme != null) {
            builder.programme(
              channelId: programme.channel,
              start: parseXmltvTime(programme.start),
              stop: parseXmltvTime(programme.stop),
              hasStop: programme.stop != null,
              title: programme.title,
              subtitle: programme.subtitle,
              description: programme.description,
              catchupId: programme.catchupId,
            );
            programme = null;
          }
        default:
          break;
      }
    }
    return builder.build();
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

final _time = RegExp(
  r'^(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?(\d{2})?(?:\.\d+)?\s*(?:([+-])(\d{2}):?(\d{2})|(Z|UTC|GMT))?$',
  caseSensitive: false,
);

/// An XMLTV time (`20260927200000 +0800`, `202609272000`, `20260927200000Z`)
/// as UTC; a time without a zone is UTC (XMLTV DTD). Null when malformed.
DateTime? parseXmltvTime(String? text) {
  final match = _time.firstMatch(text?.trim() ?? '');
  if (match == null) return null;
  int part(int group) => int.parse(match.group(group) ?? '0');
  final month = part(2);
  final day = part(3);
  if (month < 1 || month > 12 || day < 1 || day > 31 || part(4) > 23 || part(5) > 59 || part(6) > 60) return null;
  var time = DateTime.utc(part(1), month, day, part(4), part(5), part(6));
  if (match.group(7) case final sign?) {
    final offset = Duration(hours: part(8), minutes: part(9));
    time = sign == '+' ? time.subtract(offset) : time.add(offset);
  }
  return time;
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
  String? title;
  String? subtitle;
  String? description;
}
