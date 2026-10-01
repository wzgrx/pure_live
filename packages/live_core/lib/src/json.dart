/// JSON and text helpers shared by the platform parsers.
library;

const Map<String, String> _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'ensp': '\u2002',
  'emsp': '\u2003',
  'thinsp': '\u2009',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
  'middot': '·',
  'times': '×',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'yen': '¥',
  'copy': '©',
  'reg': '®',
};

final _entity = RegExp('&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);');

/// Decodes HTML character references (`&amp;`, `&nbsp;`, `&ensp;`, `&#39;`,
/// `&#x1F600;`); unknown names stay as written.
String decodeHtmlEntities(String text) {
  if (!text.contains('&')) return text;
  return text.replaceAllMapped(_entity, (match) {
    final body = match.group(1)!;
    if (body.startsWith('#x') || body.startsWith('#X')) {
      final code = int.tryParse(body.substring(2), radix: 16);
      return code == null || code > 0x10FFFF ? match.group(0)! : String.fromCharCode(code);
    }
    if (body.startsWith('#')) {
      final code = int.tryParse(body.substring(1));
      return code == null || code > 0x10FFFF ? match.group(0)! : String.fromCharCode(code);
    }
    return _named[body] ?? match.group(0)!;
  });
}

/// Characters that a platform leaves in display text where it had something
/// else, and that fonts draw as a box (Kuaishou's titles keep U+FFFC where
/// the app had a picture, shown as "OBJ"): the object replacement character
/// U+FFFC, the interlinear annotation marks U+FFF9–U+FFFB, the
/// noncharacters U+FFFE and U+FFFF, and the C0 and C1 control characters
/// except tab, line feed and carriage return. Format characters that text
/// rendering already treats as invisible and that carry meaning stay: the
/// zero-width space U+200B (a break opportunity), the joiners U+200C,
/// U+200D and U+2060 (emoji sequences, scripts, kaomoji kept on one line),
/// U+FEFF; so does the replacement character U+FFFD, a visible sign of
/// broken text.
final RegExp _invisiblePlaceholders = RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F￹-￼￾￿]');

/// [text] without invisible placeholder characters (see above); the same
/// string when it has none. `LiveRoom` applies it to titles, names,
/// introductions and notices, the danmaku runtime to chat texts and names,
/// so no platform has to.
String stripInvisiblePlaceholders(String text) =>
    _invisiblePlaceholders.hasMatch(text) ? text.replaceAll(_invisiblePlaceholders, '') : text;

/// [stripInvisiblePlaceholders] of a nullable [text].
String? stripInvisiblePlaceholdersOrNull(String? text) => text == null ? null : stripInvisiblePlaceholders(text);

/// An integer from a JSON number or integer string; null for anything else
/// (fractions, negatives are kept as parsed, blank strings are null).
int? jsonInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value == value.truncateToDouble() ? value.toInt() : null;
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// A count from a JSON number or integer string: [jsonInt] when it is zero
/// or more, else null.
int? jsonCount(Object? value) => switch (jsonInt(value)) {
  final int count when count >= 0 => count,
  _ => null,
};

/// A trimmed non-empty string from a JSON value, or null.
String? jsonString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// An http(s) URL from a JSON value, or null.
Uri? jsonUrl(Object? value) {
  final text = jsonString(value);
  if (text == null) return null;
  final uri = Uri.tryParse(text);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty ? uri : null;
}

/// Parses counts written with Chinese units: `353.9万` → 3539000, `1.2亿`
/// → 120000000, `8,902` → 8902; null when it is not a count.
int? parseChineseCount(Object? value) {
  if (value is int) return value;
  final text = jsonString(value)?.replaceAll(',', '');
  if (text == null) return null;
  final match = RegExp(r'^(\d+(?:\.\d+)?)\s*(万|亿)?\+?$').firstMatch(text);
  if (match == null) return null;
  final number = double.parse(match.group(1)!);
  final scale = switch (match.group(2)) {
    '万' => 10000,
    '亿' => 100000000,
    _ => 1,
  };
  return (number * scale).round();
}

/// An image link as platforms return it, made absolute (3.x's
/// `normalizeNetworkImageUrl`): quotes around it removed, protocol-relative
/// `//…` and bare `host/path` made https; empty for `null`, blanks and
/// anything that is not a web address.
String normalizeImageUrl(Object? source) {
  var value = source?.toString().trim() ?? '';
  if (value.isEmpty || value.toLowerCase() == 'null') return '';
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'")))) {
    value = value.substring(1, value.length - 1).trim();
  }
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) return value;
  if (!value.contains(' ') && RegExp(r'^[\w.-]+\.[a-zA-Z]{2,}([/:?#]|$)').hasMatch(value)) return 'https://$value';
  return '';
}
