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
}

/// What a platform declares as sensitive.
class ScrubRules {
  /// Creates rules.
  const new({this.jsonKeys = const {}, this.queryParams = const {}});

  /// JSON object keys (at any depth) whose values are replaced.
  final Map<String, ScrubRule> jsonKeys;

  /// URL query and form parameters whose values are replaced; `expire` and
  /// other timing fields are deliberately not listed.
  final Map<String, ScrubRule> queryParams;
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
  new(this.rules, {int? seed}) : _random = Random(seed ?? Random.secure().nextInt(1 << 32));

  /// Platform rules.
  final ScrubRules rules;

  final Random _random;
  final Map<String, String> _synthetic = {};
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
    if (value.isEmpty) return value;
    _records.add(ScrubRecord(where, rule));
    _originals.add(value);
    if (rule == ScrubRule.person && value.runes.any((rune) => rune > 0x7f)) {
      return _people.putIfAbsent(value, () => '观众${_people.length + 1}');
    }
    return _synthetic.putIfAbsent(value, () => _sameShape(value));
  }

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
        final rule = rules.jsonKeys[key];
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

  Object? _scrubLeaf(Object? value, ScrubRule rule, String path) {
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
    return scrubQuery(value, path);
  }

  static final _queryPair = RegExp(r'([?&;]|^)([A-Za-z0-9_.\-]+)=([^&#"\s\\;]*)');

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
      _originals.add(encoded);
      return '${match.group(1)}$name=${Uri.encodeQueryComponent(replace(decoded, rule, '$where:$name'))}';
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

  /// Scrubs a non-JSON text body (HTML or script with embedded JSON): listed
  /// keys in `"key":"value"` or `"key":123` form, then listed URL parameters.
  String scrubText(String text) {
    final pairs = text.replaceAllMapped(_textPair, (match) {
      final key = match.group(2)!;
      final rule = rules.jsonKeys[key];
      if (rule == null) return match.group(0)!;
      final quoted = match.group(4);
      if (quoted != null) {
        final replaced = replace(quoted, rule, 'text:$key');
        return match.group(0)!.replaceFirst('"$quoted', '"$replaced');
      }
      return '${match.group(1)}${replace(match.group(3)!, rule, 'text:$key')}';
    });
    return scrubQuery(pairs, 'text');
  }

  /// Originals (length >= 6) still present in [text]; empty means no leak.
  List<String> leaks(String text) => [
    for (final original in originals)
      if (text.contains(original)) original,
  ];
}
