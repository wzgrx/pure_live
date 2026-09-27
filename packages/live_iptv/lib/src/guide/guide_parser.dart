import 'package:live_iptv/src/guide/json_guide.dart';
import 'package:live_iptv/src/guide/xmltv.dart';
import 'package:live_iptv/src/model.dart';
import 'package:live_iptv/src/text.dart';

/// How far back and ahead a guide is kept (spec/modules/iptv.md §2.3): the
/// programme sheet shows two days back and one ahead; one more day ahead keeps
/// the sheet full until the next daily sync.
const guideKeepBack = Duration(days: 2);

/// See [guideKeepBack].
const guideKeepAhead = Duration(days: 2);

/// Parses a programme guide of any supported format, detected from the
/// content: `<` → XMLTV, `{` → JSON. Keeps programmes overlapping
/// [from]..[to]. Throws [FormatException] for anything else.
ParsedGuide parseGuide(String text, {DateTime? from, DateTime? to}) {
  final body = text.startsWith('\uFEFF') ? text.substring(1) : text;
  final head = body.trimLeft();
  if (head.startsWith('<')) return XmltvParser.parse(body, from: from, to: to);
  if (head.startsWith('{')) return JsonGuideParser.parse(body, from: from, to: to);
  throw const FormatException('Not an XMLTV or JSON programme guide');
}

/// Parses a guide file's bytes (gzip unpacked by [decodeIptvText]), keeping
/// [guideKeepBack] before and [guideKeepAhead] after [now].
ParsedGuide parseGuideBytes(List<int> bytes, {required DateTime now}) =>
    parseGuide(decodeIptvText(bytes), from: now.subtract(guideKeepBack), to: now.add(guideKeepAhead));
