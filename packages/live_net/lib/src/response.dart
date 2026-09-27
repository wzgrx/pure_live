import 'dart:convert';

import 'package:meta/meta.dart';

/// One HTTP response; 4xx and 5xx are responses too (ADR 0011, rule 2).
@immutable
final class LiveResponse {
  /// Creates a response; header names must be lower case.
  const new({required this.status, required this.bytes, required this.url, this.headers = const {}});

  /// Status code.
  final int status;

  /// Headers by lower-case name; repeated headers keep every value.
  final Map<String, List<String>> headers;

  /// Body after content decoding (gzip, deflate).
  final List<int> bytes;

  /// Final URL after redirects.
  final Uri url;

  /// First value of [name], or null.
  String? header(String name) {
    final values = headers[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.first;
  }

  /// Body decoded as UTF-8 (the charset every supported platform uses);
  /// malformed bytes become U+FFFD instead of failing.
  String get text => utf8.decode(bytes, allowMalformed: true);

  /// Whether the status is 2xx.
  bool get isSuccess => status >= 200 && status < 300;
}
