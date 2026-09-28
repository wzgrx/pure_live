import 'package:live_net/src/response.dart';

/// A response whose body is still arriving (`LiveHttp.open`).
final class LiveStreamedResponse {
  /// Creates a response; header names must be lower case.
  new({required this.status, required this.body, required this.url, this.headers = const {}, this.contentLength});

  /// Status code.
  final int status;

  /// Headers by lower-case name; repeated headers keep every value.
  final Map<String, List<String>> headers;

  /// Body chunks after content decoding. Listen once; cancelling the
  /// subscription closes the connection.
  final Stream<List<int>> body;

  /// Final URL after redirects.
  final Uri url;

  /// Declared body length, or null when unknown.
  final int? contentLength;

  /// First value of [name], or null.
  String? header(String name) {
    final values = headers[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.first;
  }

  /// Whether the status is 2xx.
  bool get isSuccess => status >= 200 && status < 300;

  /// Reads the rest of the body into a [LiveResponse].
  Future<LiveResponse> collect() async {
    final bytes = await body.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
    return LiveResponse(status: status, headers: headers, bytes: bytes, url: url);
  }

  /// Drops the body without reading it.
  Future<void> discard() async {
    await body.listen(null).cancel();
  }
}
