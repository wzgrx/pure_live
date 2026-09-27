import 'dart:convert';
import 'dart:math';

/// How a matched value is replaced (docs/adr/0009-fixture-format.md, rule 4).
enum ScrubRule {
  /// A secret (cookie, token, signature material): replaced by a synthetic value
  /// of the same shape, so format checks in parsers still pass.
  secret,

  /// A viewer's identity: the same original always maps to the same pseudonym
  /// within one scrubber, so "same person" relations survive.
  person,

  /// Public data at a specific JSON path that a key rule would otherwise
  /// scrub (an anchor's id under the same key name as a viewer's).
  keep,

  /// A signature that starts with its Unix time (`<seconds>-<rest>`, the
  /// Aliyun `auth_key` type A, CC `relaySecret`): the leading time and its
  /// separator stay real because lease timing is derived from them; the
  /// rest is replaced like [secret]. Values without the prefix are [secret].
  expiryPrefixed,
}

/// What a platform declares as sensitive.
class ScrubRules {
  /// Creates rules.
  const new({
    this.jsonKeys = const {},
    this.jsonPaths = const {},
    this.queryParams = const {},
    this.responseHeaders = const {},
    this.textPatterns = const {},
  });

  /// JSON object keys (at any depth) whose values are replaced.
  final Map<String, ScrubRule> jsonKeys;

  /// JSON paths that override [jsonKeys]: `$.data.uid`, `$.data.list[*].uid`,
  /// `$.*.sec_uid`; `[*]` matches any index and `*` one key. Response headers
  /// holding JSON are scrubbed under `$header.<name>`.
  final Map<String, ScrubRule> jsonPaths;

  /// URL query and form parameters whose values are replaced; `expire` and
  /// other timing fields are deliberately not listed.
  final Map<String, ScrubRule> queryParams;

  /// Response headers (lower case) whose whole value is replaced; a header
  /// whose value is JSON is scrubbed field by field with [jsonKeys] and
  /// [jsonPaths] instead. Any header still holding a value replaced elsewhere
  /// gets the same synthetic value (a signature echoed back, for example).
  final Map<String, ScrubRule> responseHeaders;

  /// Regular expressions (source text) whose first group is replaced in text
  /// bodies and JSON string values, for values that are neither a JSON key
  /// nor a query parameter: an HLS attribute (`USER-IP="…"`) or a signed
  /// path segment (`/v1/playlist/<token>.m3u8`).
  final Map<String, ScrubRule> textPatterns;
}

/// One replacement, recorded in meta.json without the original value.
class ScrubRecord {
  /// Creates a record.
  const new(this.where, this.rule);

  /// JSON path, header name or parameter name.
  final String where;

  /// Rule that was applied.
  final ScrubRule rule;

  /// JSON form.
  Map<String, String> toJson() => {'where': where, 'rule': rule.name};
}

/// Replaces sensitive values and remembers every original so the result can be
/// checked for leaks.
class Scrubber {
  /// Creates a scrubber; [seed] only makes tests deterministic.
  new(this.rules, {int? seed})
    : _random = Random(seed ?? Random.secure().nextInt(1 << 32)),
      _paths = {
        for (final entry in rules.jsonPaths.entries)
          RegExp('^${RegExp.escape(entry.key).replaceAll(r'\[\*\]', r'\[\d+\]').replaceAll(r'\*', r'[^.\[\]]+')}\$'):
              entry.value,
      },
      _patterns = {for (final entry in rules.textPatterns.entries) RegExp(entry.key): entry.value};

  /// Platform rules.
  final ScrubRules rules;

  final Random _random;
  final Map<RegExp, ScrubRule> _paths;
  final Map<RegExp, ScrubRule> _patterns;
  final Map<String, String> _synthetic = {};
  final Map<String, String> _encoded = {};
  final Map<String, String> _people = {};
  final Set<String> _originals = {};
  final List<ScrubRecord> _records = [];

  /// Replacements made so far, de-duplicated.
  List<ScrubRecord> get records {
    final seen = <String>{};
    return [
      for (final record in _records)
        if (seen.add('${record.where}|${record.rule.name}')) record,
    ];
  }

  /// Original values that must not appear in any written file (length >= 6;
  /// shorter values would match by chance).
  Iterable<String> get originals => _originals.where((value) => value.length >= 6);

  /// Replaces [value] according to [rule], remembering where it was.
  String replace(String value, ScrubRule rule, String where) {
    // A single character (uid 0, an empty flag) identifies nobody.
    if (value.length <= 1 || rule == ScrubRule.keep) return value;
    _records.add(ScrubRecord(where, rule));
    _originals.add(value);
    if (rule == ScrubRule.person && value.runes.any((rune) => rune > 0x7f)) {
      return _people.putIfAbsent(value, () => '观众${_people.length + 1}');
    }
    if (rule == ScrubRule.expiryPrefixed) {
      final prefixed = _expiryPrefix.firstMatch(value);
      if (prefixed != null) {
        final tail = prefixed.group(2)!;
        final synthetic = _synthetic.putIfAbsent(tail, () => _sameShape(tail));
        if (tail.length > 1) _originals.add(tail);
        return _synthetic.putIfAbsent(value, () => '${prefixed.group(1)}$synthetic');
      }
    }
    return _synthetic.putIfAbsent(value, () => _sameShape(value));
  }

  /// `<9 to 11 digit Unix seconds><separator>` and the rest.
  static final _expiryPrefix = RegExp(r'^(\d{9,11}[-_])(.+)$');

  String _sameShape(String value) {
    for (var attempt = 0; attempt < 8; attempt++) {
      final buffer = StringBuffer();
      for (final unit in value.codeUnits) {
        if (unit >= 0x30 && unit <= 0x39) {
          buffer.writeCharCode(0x30 + _random.nextInt(10));
        } else if (unit >= 0x61 && unit <= 0x66 && _isHex(value)) {
          buffer.writeCharCode(0x61 + _random.nextInt(6));
        } else if (unit >= 0x61 && unit <= 0x7a) {
          buffer.writeCharCode(0x61 + _random.nextInt(26));
        } else if (unit >= 0x41 && unit <= 0x5a) {
          buffer.writeCharCode(0x41 + _random.nextInt(26));
        } else {
          buffer.writeCharCode(unit);
        }
      }
      final candidate = buffer.toString();
      if (candidate != value) return candidate;
    }
    return 'x$value'.hashCode.toRadixString(16);
  }

  static bool _isHex(String value) => RegExp(r'^[0-9a-f]+$').hasMatch(value);

  /// Scrubs a decoded JSON value in place and returns it.
  Object? scrubJson(Object? node, [String path = r'$']) {
    if (node is Map) {
      for (final key in node.keys.toList()) {
        final childPath = '$path.$key';
        final rule = _pathRule(childPath) ?? rules.jsonKeys[key];
        final value = node[key];
        node[key] = rule == null ? scrubJson(value, childPath) : _scrubLeaf(value, rule, childPath);
      }
      return node;
    }
    if (node is List) {
      for (var index = 0; index < node.length; index++) {
        node[index] = scrubJson(node[index], '$path[$index]');
      }
      return node;
    }
    if (node is String) return _scrubString(node, path);
    return node;
  }

  ScrubRule? _pathRule(String path) {
    for (final entry in _paths.entries) {
      if (entry.key.hasMatch(path)) return entry.value;
    }
    return null;
  }

  Object? _scrubLeaf(Object? value, ScrubRule rule, String path) {
    if (rule == ScrubRule.keep) return value;
    if (value is String) return replace(value, rule, path);
    if (value is int) return int.parse(replace('$value', rule, path));
    if (value is Map || value is List) {
      if (value is Map) {
        for (final key in value.keys.toList()) {
          value[key] = _scrubLeaf(value[key], rule, '$path.$key');
        }
      } else if (value is List) {
        for (var index = 0; index < value.length; index++) {
          value[index] = _scrubLeaf(value[index], rule, '$path[$index]');
        }
      }
      return value;
    }
    return value;
  }

  String _scrubString(String value, String path) {
    final trimmed = value.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return jsonEncode(scrubJson(jsonDecode(value), path));
      } on FormatException {
        // Not embedded JSON; fall through to URL scrubbing.
      }
    }
    return scrubPatterns(scrubQuery(value, path), path);
  }

  /// Replaces the first group of every [ScrubRules.textPatterns] match in
  /// [text].
  String scrubPatterns(String text, [String where = 'text']) {
    var result = text;
    for (final MapEntry(key: pattern, value: rule) in _patterns.entries) {
      result = result.replaceAllMapped(pattern, (match) {
        final value = match.group(1);
        if (value == null || value.isEmpty) return match.group(0)!;
        final whole = match.group(0)!;
        // The group's first occurrence inside the match (RegExpMatch has no
        // group offsets).
        final offset = match.input.indexOf(value, match.start) - match.start;
        final replaced = replace(value, rule, '$where:/${pattern.pattern}/');
        return offset < 0
            ? whole.replaceFirst(value, replaced)
            : '${whole.substring(0, offset)}$replaced${whole.substring(offset + value.length)}';
      });
    }
    return result;
  }

  // Separators: ? & ; (so &amp; works) and the JSON escape \u0026.
  static final _queryPair = RegExp(r'([?&;]|\\u0026|^)([A-Za-z0-9_.\-]+)=([^&#"\s\\;]*)');

  /// Replaces listed query/form parameter values inside [text] (a URL, a form
  /// body or any text containing URLs).
  String scrubQuery(String text, [String where = 'query']) {
    if (rules.queryParams.isEmpty || !text.contains('=')) return text;
    return text.replaceAllMapped(_queryPair, (match) {
      final name = match.group(2)!;
      final rule = rules.queryParams[name];
      if (rule == null || match.group(3)!.isEmpty) return match.group(0)!;
      final encoded = match.group(3)!;
      String decoded;
      try {
        decoded = Uri.decodeQueryComponent(encoded);
      } on Object {
        // Malformed percent-encoding: treat the raw text as the value.
        decoded = encoded;
      }
      final replaced = Uri.encodeQueryComponent(replace(decoded, rule, '$where:$name'));
      if (encoded.length > 1 && rule != ScrubRule.keep) {
        _originals.add(encoded);
        _encoded[encoded] = replaced;
      }
      return '${match.group(1)}$name=$replaced';
    });
  }

  /// Replaces every cookie value in a `Cookie` header, keeping the names.
  String scrubCookieHeader(String header) => header
      .split(';')
      .map((part) {
        final separator = part.indexOf('=');
        if (separator < 0) return part;
        final name = part.substring(0, separator).trim();
        final value = part.substring(separator + 1).trim();
        return '${part.substring(0, part.indexOf(name))}$name=${replace(value, ScrubRule.secret, 'cookie:$name')}';
      })
      .join(';');

  /// Replaces the value of one `Set-Cookie` header, keeping its attributes.
  String scrubSetCookie(String header) {
    final end = header.indexOf(';');
    final pair = end < 0 ? header : header.substring(0, end);
    final separator = pair.indexOf('=');
    if (separator < 0) return header;
    final name = pair.substring(0, separator).trim();
    final value = pair.substring(separator + 1).trim();
    final rest = end < 0 ? '' : header.substring(end);
    return '$name=${replace(value, ScrubRule.secret, 'set-cookie:$name')}$rest';
  }

  static final _textPair = RegExp(r'(\\?"([A-Za-z0-9_]+)\\?"\s*:\s*)(\\?"([^"\\]*)\\?"|-?\d+)');
  static final _htmlPair = RegExp(r'(&quot;([A-Za-z0-9_]+)&quot;\s*:\s*)(&quot;((?:(?!&quot;)[^"<>])*)&quot;|-?\d+)');

  /// Scrubs a non-JSON text body (HTML or script with embedded JSON): listed
  /// keys in `"key":"value"` or `"key":123` form, then listed URL parameters.
  String scrubText(String text) {
    String pairs(String input, RegExp pattern, String quote) => input.replaceAllMapped(pattern, (match) {
      final key = match.group(2)!;
      final rule = rules.jsonKeys[key];
      if (rule == null) return match.group(0)!;
      final quoted = match.group(4);
      if (quoted != null) {
        final replaced = replace(quoted, rule, 'text:$key');
        return match.group(0)!.replaceFirst('$quote$quoted', '$quote$replaced');
      }
      return '${match.group(1)}${replace(match.group(3)!, rule, 'text:$key')}';
    });
    return scrubPatterns(scrubQuery(pairs(pairs(text, _textPair, '"'), _htmlPair, '&quot;'), 'text'));
  }

  /// Records that [where] was cleaned by [replaceKnown] rather than a rule.
  void note(String where) => _records.add(ScrubRecord(where, ScrubRule.secret));

  /// Replaces every value already replaced elsewhere (length >= 6) wherever it
  /// appears in [text], with the same synthetic value.
  String replaceKnown(String text) {
    final known = <String, String>{
      ..._synthetic,
      ..._people,
      ..._encoded,
    }.entries.where((entry) => entry.key.length >= 6).toList()..sort((a, b) => b.key.length - a.key.length);
    var result = text;
    for (final entry in known) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }

  /// Scrubs one response header value by the rules; see [ScrubRules.responseHeaders].
  String scrubResponseHeader(String name, String value) {
    final rule = rules.responseHeaders[name.toLowerCase()];
    if (rule == null) return scrubQuery(value, 'header:$name');
    final trimmed = value.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return jsonEncode(scrubJson(jsonDecode(value), '\$header.${name.toLowerCase()}'));
      } on FormatException {
        // Not JSON after all: replace the whole value.
      }
    }
    return replace(value, rule, 'header:$name');
  }

  /// Originals (length >= 6) still present in [text]; empty means no leak.
  List<String> leaks(String text) => [
    for (final original in originals)
      if (text.contains(original)) original,
  ];
}
