import 'dart:async';

import 'package:pure_live/core/common/hls_source_query_policy.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

import 'playback_proxy_policy.dart';

typedef PlaybackInputFactory = Future<PlaybackInputLease> Function(
  String url,
  Map<String, String> headers,
  HlsSourceQueryPolicy policy,
);
typedef PlaybackNativeOpen = Future<void> Function(
  String url,
  List<String> urls,
  Map<String, String> headers,
  bool privateInput,
);

/// One input resource; closing is idempotent, including pending/late opens.
class PlaybackInputLease {
  PlaybackInputLease(this.uri, Future<void> Function() close) : _close = close;
  final Uri uri;
  final Future<void> Function() _close;
  Future<void>? _closing;
  Future<void> close() => _closing ??= Future<void>.sync(_close);
}

/// Owned by one UnifiedPlayer, not by the route or by a quality label.
/// Native completion can arrive after a manager deadline; its input must not
/// become active again after cancellation, replacement or disposal.
class PlaybackSourceTransport {
  PlaybackSourceTransport({PlaybackInputFactory? createInput}) : _createInput = createInput ?? _createRelay;
  final PlaybackInputFactory _createInput;
  final Set<PlaybackInputLease> _pending = {};
  final Set<PlaybackInputLease> _retiring = {};
  PlaybackInputLease? _active;
  int _generation = 0;
  bool _closed = false;
  Future<void>? _closing;

  static Future<PlaybackInputLease> _createRelay(
    String url,
    Map<String, String> headers,
    HlsSourceQueryPolicy policy,
  ) async {
    // This string is an argument value, never a shell command. Validate before
    // encoding it as CRLF-delimited HTTP fields to preserve the header boundary.
    final name = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
    for (final entry in headers.entries) {
      if (!name.hasMatch(entry.key) || RegExp(r'[\r\n\x00]').hasMatch(entry.value)) {
        throw const FormatException('Invalid playback input header');
      }
    }
    final directive = PlaybackProxyPolicy.currentDirective();
    final relay = await FFmpegHlsInputRelay.startForArguments(
      [
        if (headers.isNotEmpty) ...['-headers', headers.entries.map((e) => '${e.key}: ${e.value}\r\n').join()],
        '-i',
        url,
      ],
      sourceQueryPolicy: policy,
      findProxy: (_) => directive,
    );
    if (relay == null) throw const FormatException('Expected a policy-bound HLS input');
    return PlaybackInputLease(relay.inputUri, relay.close);
  }

  Future<void> open({
    required String url,
    required List<String> urls,
    required Map<String, String> headers,
    required HlsSourceQueryPolicy? policy,
    required PlaybackNativeOpen nativeOpen,
  }) async {
    if (_closed) throw StateError('Playback input owner is closed');
    final generation = ++_generation;
    PlaybackInputLease? input;
    bool current() => !_closed && generation == _generation;
    try {
      if (policy != null) {
        final source = Uri.tryParse(url);
        if (source == null || !policy.matchesSource(source)) {
          throw const FormatException('Playback query policy does not match selected input');
        }
        input = await _createInput(url, Map<String, String>.unmodifiable(headers), policy);
        _pending.add(input);
      }
      if (!current()) throw StateError('Playback input transaction was retired');
      final local = input?.uri.toString();
      await nativeOpen(local ?? url, local == null ? urls : [local], local == null ? headers : const {}, input != null);
      if (!current()) throw StateError('Playback input transaction was retired');
      final previous = _active;
      _active = input;
      _pending.remove(input);
      input = null;
      if (previous != null) await _retire(previous);
    } catch (_) {
      _pending.remove(input);
      if (input != null) await _retire(input);
      rethrow;
    }
  }

  /// Cancel only the pending replacement, retaining the previous input until
  /// its native owner is replaced or disposed. A late factory result is closed
  /// by open() without invoking nativeOpen; never await an unbounded native open.
  Future<void> cancelPending() async {
    _generation++;
    final pending = _pending.toList();
    _pending.clear();
    await Future.wait(pending.map(_retire));
  }

  Future<void> _retire(PlaybackInputLease input) async {
    _retiring.add(input);
    try {
      await input.close();
    } finally {
      _retiring.remove(input);
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    final active = _active;
    _active = null;
    final pending = cancelPending();
    final activeClose = active == null ? Future<void>.value() : _retire(active);
    // A dispatch-time cancellation may already be retiring a native input.
    // Teardown still joins that cleanup instead of merely observing an empty
    // pending set and declaring the owner closed early.
    await Future.wait([pending, activeClose, ..._retiring.map((input) => input.close())]);
  }
}
