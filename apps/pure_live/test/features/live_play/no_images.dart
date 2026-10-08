import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// An image cache without pictures: every address fails, so a test can
/// read which address a picture asks for without a request or a disk cache.
final class NoImages implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) => Stream.error(HttpExceptionWithStatus(404, 'no pictures in tests', uri: Uri.parse(url)));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
