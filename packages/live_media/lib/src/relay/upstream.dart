import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_media/src/relay/flv.dart';
import 'package:meta/meta.dart';

/// Hosts whose media certificate does not verify, accepted by the relay's
/// upstream connections only for exactly these hosts.
///
/// The engine itself (mpv/FFmpeg) does not verify media certificates, so a
/// direct line plays; a relayed one goes through `dart:io`, which does.
/// Baidu (M4.30): `flv-live.bdstatic.com` serves a certificate for another
/// host (the platform layer already turns it into http), and the chain of
/// `*.liveshow.lss-user.baidubce.com` does not verify.
@immutable
final class MediaTlsExemptions {
  /// Creates the exemptions: exact [hosts] and host [suffixes] (with the
  /// leading dot).
  const new({this.hosts = const {}, this.suffixes = const {}});

  /// Baidu's known hosts (M4.30).
  static const MediaTlsExemptions known = MediaTlsExemptions(
    hosts: {'flv-live.bdstatic.com'},
    suffixes: {'.liveshow.lss-user.baidubce.com'},
  );

  /// Exact host names.
  final Set<String> hosts;

  /// Host suffixes, each starting with `.`.
  final Set<String> suffixes;

  /// Whether a bad certificate of [host] is accepted.
  bool accepts(String host) {
    final name = host.toLowerCase();
    return hosts.contains(name) || suffixes.any(name.endsWith);
  }
}

/// A `dart:io` client for media upstreams: TLS verification on except for
/// [tls]'s hosts, [proxyDirective] as `findProxy`'s answer.
HttpClient mediaHttpClient({
  String proxyDirective = 'DIRECT',
  Duration connectTimeout = const Duration(seconds: 15),
  MediaTlsExemptions tls = MediaTlsExemptions.known,
  bool autoUncompress = false,
}) => HttpClient()
  ..connectionTimeout = connectTimeout
  ..autoUncompress = autoUncompress
  ..findProxy = ((_) => proxyDirective)
  ..badCertificateCallback = ((_, host, _) => tls.accepts(host));

/// One upstream FLV connection as packets: the file header first, then tags.
abstract interface class FlvPacketSource {
  /// The next packet, or null once the connection ended (clean close, reset,
  /// idle timeout or a framing error); the splicer decides what follows.
  Future<Uint8List?> next();

  /// Drops the connection.
  Future<void> cancel();
}

/// Opens an upstream connection for [line].
typedef FlvSourceOpener = Future<FlvPacketSource> Function(LivePlayLine line);

/// The upstream request answered with a status other than 200.
final class UpstreamStatusException implements Exception {
  /// Creates the exception.
  const new(this.status, this.url);

  /// HTTP status.
  final int status;

  /// Requested URL.
  final Uri url;

  @override
  String toString() => 'Upstream answered HTTP $status for ${url.host}';
}

/// Opens [line] over `dart:io` (TLS verification as [mediaHttpClient]),
/// with the line's headers and [proxyDirective].
///
/// Reading stops after [idleTimeout] without data while the reader is
/// waiting; while nobody reads, the socket is paused once 2048 packets are
/// queued. With [rewriteLegacyHevc] codec-id-12 HEVC tags come out as
/// Enhanced FLV ([FlvLegacyHevcRewriter]).
Future<FlvPacketSource> openHttpFlv(
  LivePlayLine line, {
  String proxyDirective = 'DIRECT',
  Duration connectTimeout = const Duration(seconds: 15),
  Duration idleTimeout = const Duration(seconds: 15),
  MediaTlsExemptions tls = MediaTlsExemptions.known,
  bool rewriteLegacyHevc = false,
}) async {
  final url = Uri.parse(line.url);
  final client = mediaHttpClient(proxyDirective: proxyDirective, connectTimeout: connectTimeout, tls: tls);
  try {
    final request = await client.getUrl(url).timeout(connectTimeout);
    line.headers.forEach(request.headers.set);
    final response = await request.close().timeout(connectTimeout);
    if (response.statusCode != HttpStatus.ok) {
      unawaited(response.drain<void>().catchError((Object _) {}));
      throw UpstreamStatusException(response.statusCode, url);
    }
    return _HttpFlvSource(client, response, idleTimeout, rewriteLegacyHevc ? FlvLegacyHevcRewriter() : null);
  } on Object {
    client.close(force: true);
    rethrow;
  }
}

final class _HttpFlvSource implements FlvPacketSource {
  new(this._client, Stream<List<int>> body, this._idleTimeout, this._rewriter) {
    _subscription = body.listen(
      _onChunk,
      onError: (Object error, StackTrace _) => _finish(error),
      onDone: _finish,
      cancelOnError: true,
    );
  }

  static const _pauseAbove = 2048;
  static const _resumeBelow = 512;

  final HttpClient _client;
  final Duration _idleTimeout;
  final FlvLegacyHevcRewriter? _rewriter;
  final _framer = FlvFramer();
  final _queue = ListQueue<Uint8List>();
  late final StreamSubscription<List<int>> _subscription;
  Completer<void>? _waiter;
  Timer? _idle;
  var _done = false;

  void _onChunk(List<int> chunk) {
    try {
      final packets = _framer.add(chunk);
      final rewriter = _rewriter;
      _queue.addAll(rewriter == null ? packets : packets.map(rewriter.rewrite));
    } on FormatException catch (error) {
      _finish(error);
      unawaited(_subscription.cancel());
      return;
    }
    _wake();
    if (_queue.length > _pauseAbove && !_subscription.isPaused) _subscription.pause();
  }

  void _finish([Object? reason]) {
    if (_done) return;
    _done = true;
    _idle?.cancel();
    _wake();
  }

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  @override
  Future<Uint8List?> next() async {
    while (_queue.isEmpty) {
      if (_done) return null;
      if (_subscription.isPaused) _subscription.resume();
      _idle ??= Timer(_idleTimeout, () {
        _finish(TimeoutException('No upstream data', _idleTimeout));
        unawaited(_subscription.cancel());
        _client.close(force: true);
      });
      await (_waiter ??= Completer<void>()).future;
      _idle?.cancel();
      _idle = null;
    }
    final packet = _queue.removeFirst();
    if (_queue.length < _resumeBelow && _subscription.isPaused && !_done) _subscription.resume();
    return packet;
  }

  @override
  Future<void> cancel() async {
    _finish();
    _queue.clear();
    _client.close(force: true);
    try {
      await _subscription.cancel();
    } on Object {
      // Already failed.
    }
  }
}
