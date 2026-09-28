import 'package:live_net/src/request.dart';
import 'package:live_net/src/response.dart';
import 'package:live_net/src/streamed_response.dart';

/// What platform adapters and the app use to talk HTTP. Implementations are
/// injected (no global client), so tests replay samples and the app decides
/// proxies and logging in one place.
abstract interface class LiveHttp {
  /// Sends [request] and reads the whole body; throws `TransportFailure` when
  /// no response arrives. Any status, 4xx and 5xx included, is a response.
  Future<LiveResponse> send(LiveRequest request);

  /// Sends [request] and returns as soon as the headers arrive; the body is
  /// streamed (downloads, probes). Throws `TransportFailure` like [send]; the
  /// body stream reports later failures the same way.
  Future<LiveStreamedResponse> open(LiveRequest request);

  /// Releases connections.
  void close();
}
