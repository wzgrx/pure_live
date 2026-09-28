import 'dart:io';

import 'package:live_net/src/live_http.dart';
import 'package:live_net/src/request.dart';
import 'package:live_net/src/response.dart';
import 'package:live_net/src/transport_failure.dart';

/// The request shapes 3.x's `HttpClient` offered (`getText`, `getJson`,
/// `postJson`, `head`, `download`), on any [LiveHttp].
///
/// Unlike `send`, these throw [HttpStatusFailure] for a status that is not
/// 2xx (except [head]), and [TransportFailure] when no response arrives.
extension LiveHttpCalls on LiveHttp {
  /// GET [url] for [site] and return the body as UTF-8 text.
  Future<String> getText(
    String site,
    Uri url, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration timeout = defaultRequestTimeout,
    CancelToken? cancel,
  }) async => (await _checked(
    LiveRequest.get(site: site, url: url, query: query, headers: headers, timeout: timeout, cancel: cancel),
  )).text;

  /// GET [url] for [site] and decode the body as JSON; a body that is not
  /// JSON throws [FormatException].
  Future<Object?> getJson(
    String site,
    Uri url, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration timeout = defaultRequestTimeout,
    CancelToken? cancel,
  }) async => (await _checked(
    LiveRequest.get(site: site, url: url, query: query, headers: headers, timeout: timeout, cancel: cancel),
  )).json;

  /// POST to [url] for [site] and decode the answer as JSON. The body is
  /// [form] URL-encoded when given, else [json] as JSON, else empty.
  Future<Object?> postJson(
    String site,
    Uri url, {
    Object? json,
    Map<String, String>? form,
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration timeout = defaultRequestTimeout,
    CancelToken? cancel,
  }) async {
    final request = form != null
        ? LiveRequest.form(
            site: site,
            url: url,
            fields: form,
            query: query,
            headers: headers,
            timeout: timeout,
            cancel: cancel,
          )
        : json != null
        ? LiveRequest.json(
            site: site,
            url: url,
            json: json,
            query: query,
            headers: headers,
            timeout: timeout,
            cancel: cancel,
          )
        : LiveRequest(
            site: site,
            url: LiveRequest.withQuery(url, query),
            method: 'POST',
            headers: headers,
            timeout: timeout,
            cancel: cancel,
          );
    return (await _checked(request)).json;
  }

  /// HEAD [url] for [site]; every status is returned, as in 3.x.
  Future<LiveResponse> head(
    String site,
    Uri url, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
    Duration timeout = defaultRequestTimeout,
    CancelToken? cancel,
  }) => send(
    LiveRequest(
      site: site,
      url: LiveRequest.withQuery(url, query),
      method: 'HEAD',
      headers: headers,
      timeout: timeout,
      cancel: cancel,
    ),
  );

  /// Downloads [request] into [savePath] through `<savePath>.part`, which is
  /// renamed only after a 200 or 206 response was read completely.
  /// [onProgress] gets the bytes received and the total when known.
  ///
  /// On any failure the partial file is deleted (3.x left it behind) and the
  /// failure is rethrown: [HttpStatusFailure] for another status,
  /// [TransportFailure] otherwise.
  Future<File> download(
    LiveRequest request,
    String savePath, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final part = File('$savePath.part');
    await part.parent.create(recursive: true);
    IOSink? sink;
    try {
      final response = await open(request);
      if (response.status != 200 && response.status != 206) {
        final preview = await response.collect();
        throw HttpStatusFailure.of(request.site, preview);
      }
      final total = response.contentLength;
      var received = 0;
      final output = sink = part.openWrite();
      await for (final chunk in response.body) {
        output.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await output.flush();
      await output.close();
      sink = null;
      return await part.rename(savePath);
    } on Object {
      await sink?.close();
      if (part.existsSync()) await part.delete();
      rethrow;
    }
  }

  Future<LiveResponse> _checked(LiveRequest request) async {
    final response = await send(request);
    if (!response.isSuccess) throw HttpStatusFailure.of(request.site, response);
    return response;
  }
}
