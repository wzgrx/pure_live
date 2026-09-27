/// Text helpers shared by the site parsers.
library;

const Map<String, String> _named = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
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

/// Decodes HTML character references (`&amp;`, `&nbsp;`, `&#39;`, `&#x1F600;`);
/// unknown names stay as written.
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
