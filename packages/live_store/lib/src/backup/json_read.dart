import 'dart:convert';

import 'package:meta/meta.dart';

/// Lenient readers for backup JSON.
@internal
abstract final class JsonRead {
  /// Trimmed text of a string or number; null otherwise.
  static String? text(Object? value) => switch (value) {
    final String text => text.trim(),
    final int number => '$number',
    final double number when number.isFinite && number == number.roundToDouble() => '${number.toInt()}',
    _ => null,
  };

  /// Non-empty trimmed text, or null.
  static String? nonEmpty(Object? value) {
    final result = text(value);
    return result == null || result.isEmpty ? null : result;
  }

  /// A non-negative integer from a number or digit string, or null.
  static int? count(Object? value) {
    final number = switch (value) {
      final int whole => whole,
      final double real when real.isFinite => real.round(),
      final String text => int.tryParse(text.trim()),
      _ => null,
    };
    return number == null || number < 0 ? null : number;
  }

  /// A UTC time from epoch milliseconds, or null.
  static DateTime? millis(Object? value) {
    final number = count(value);
    if (number == null || number == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(number, isUtc: true);
  }

  /// A URI from non-empty text, or null.
  static Uri? uri(Object? value) {
    final result = nonEmpty(value);
    return result == null ? null : Uri.tryParse(result);
  }

  /// A JSON object from a map or a JSON string holding one, or null.
  static Map<String, Object?>? object(Object? value) {
    final decoded = value is String ? _tryDecode(value) : value;
    if (decoded is! Map) return null;
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (key is String) key: value,
    };
  }

  /// Items of a 3.x collection (store.md §6.4.5): a list, a JSON string
  /// holding a list, or `{"list": [...]}` either way. Throws
  /// [FormatException] for anything else. Items stay raw; see [item].
  static List<Object?> collection(Object? value, String name) {
    final decoded = value is String ? _tryDecode(value) : value;
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['list'] is List) return decoded['list'] as List;
    if (decoded is Map && decoded['list'] is String) return collection(decoded['list'], name);
    throw FormatException('Invalid backup collection: $name');
  }

  /// One collection item: a map, or a JSON string holding one; null when it
  /// cannot be read.
  static Map<String, Object?>? item(Object? value) => object(value);

  static Object? _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
