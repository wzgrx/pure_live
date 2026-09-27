import 'package:live_net/src/request.dart';
import 'package:live_net/src/response.dart';

/// What platform adapters use to talk HTTP (ADR 0011, rule 2).
abstract interface class LiveHttp {
  /// Sends [request]; throws `TransportFailure` when no response arrives.
  Future<LiveResponse> send(LiveRequest request);

  /// Releases connections.
  void close();
}
