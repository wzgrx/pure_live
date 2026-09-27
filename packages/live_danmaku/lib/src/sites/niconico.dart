import 'dart:async';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_danmaku/src/connector.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_danmaku/src/runtime/base.dart';
import 'package:live_danmaku/src/transport.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// One comment window of the message server (spec/sites/niconico.md §7).
@immutable
final class NiconicoSegment {
  /// Creates a window.
  const new({required this.from, required this.until, required this.uri});

  /// Window start.
  final DateTime from;

  /// Window end.
  final DateTime until;

  /// Where its messages are read.
  final Uri uri;
}

/// One `view` answer: the windows under way or ahead, the finished ones,
/// and when to ask next.
typedef NiconicoView = ({List<NiconicoSegment> segments, List<NiconicoSegment> previous, int? next});

/// One decoded message of a window, with its time.
typedef NiconicoTimedEvent = ({DateTime at, DanmakuEvent event});

/// niconico's comment server ("NDGR", spec/sites/niconico.md §7), without
/// I/O: length-delimited protobuf entries from `view`, length-delimited
/// messages from each window.
abstract final class NiconicoChatProtocol {
  /// Splits varint-length-delimited protobuf messages.
  static List<Uint8List> delimited(List<int> bytes) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final out = <Uint8List>[];
    var offset = 0;
    while (offset < data.length) {
      var length = 0;
      var shift = 0;
      while (true) {
        if (offset >= data.length || shift > 63) throw const FormatException('Truncated length prefix');
        final byte = data[offset++];
        length |= (byte & 0x7F) << shift;
        if (byte < 0x80) break;
        shift += 7;
      }
      if (offset + length > data.length) throw const FormatException('Truncated message');
      out.add(Uint8List.sublistView(data, offset, offset + length));
      offset += length;
    }
    return out;
  }

  static DateTime? _time(ProtoMessage? timestamp) {
    final seconds = timestamp?.integer(1);
    if (seconds == null) return null;
    final nanos = timestamp?.integer(2) ?? 0;
    return DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanos ~/ 1000, isUtc: true);
  }

  static NiconicoSegment? _segment(ProtoMessage? segment) {
    final from = _time(segment?.message(1));
    final until = _time(segment?.message(2));
    final uri = Uri.tryParse(segment?.string(3) ?? '');
    if (from == null || until == null || uri == null || !uri.hasScheme) return null;
    return NiconicoSegment(from: from, until: until, uri: uri);
  }

  /// §7 a `view` answer: entry 1 a window under way or ahead, 3 a finished
  /// window, 4 `next{at}`; 2 (backward and snapshot links) is not used.
  static NiconicoView view(List<int> bytes) {
    final segments = <NiconicoSegment>[];
    final previous = <NiconicoSegment>[];
    int? next;
    for (final entry in delimited(bytes)) {
      final message = ProtoMessage.decode(entry);
      if (_segment(message.message(1)) case final NiconicoSegment segment) segments.add(segment);
      if (_segment(message.message(3)) case final NiconicoSegment segment) previous.add(segment);
      next = message.message(4)?.integer(1) ?? next;
    }
    return (segments: segments, previous: previous, next: next);
  }

  /// §7 a window's messages: `message.chat` becomes a chat line,
  /// `state.statistics.viewers` the online figure; everything else
  /// (notifications, gifts, ads, signals) is left out.
  static List<NiconicoTimedEvent> messages(List<int> bytes, {required DecodeContext context}) {
    final out = <NiconicoTimedEvent>[];
    for (final chunk in delimited(bytes)) {
      final message = ProtoMessage.decode(chunk);
      final meta = message.message(1);
      final at = _time(meta?.message(2));
      if (at == null) continue;
      final chat = message.message(2)?.message(1);
      if (chat != null) {
        final text = (chat.string(1) ?? '').trim();
        if (text.isEmpty) continue;
        final id = meta?.string(1);
        final raw = chat.integer(5);
        out.add((
          at: at,
          event: DanmakuChat(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            id: id == null || id.isEmpty ? null : 'niconico:$id',
            sentAt: at,
            userId: chat.string(6) ?? (raw == null ? '' : '$raw'),
            userName: (chat.string(2) ?? '').trim(),
            text: text,
          ),
        ));
        continue;
      }
      final viewers = message.message(4)?.message(1)?.integer(1);
      if (viewers != null && viewers >= 0) {
        out.add((
          at: at,
          event: DanmakuOnline(
            room: context.room,
            session: context.session,
            receivedAt: context.receivedAt,
            audience: AudienceKind.online,
            value: viewers,
          ),
        ));
      }
    }
    return out;
  }
}

/// niconico chat: a watching seat of its own (the comment server is only
/// announced on a seat, which takes text frames only, so it is opened with
/// `live_core`'s seat over `dart:io` instead of [DanmakuTransport.connect]),
/// then the comment server over HTTP: `view` is long-polled with the last
/// `next.at`, and every window under way is read while it lasts. Messages
/// are released at their own pace, one window behind (§7.4).
final class NiconicoChatConnector extends ConnectorBase {
  /// Creates the connector; the connect function opens the seat socket (tests).
  new({required super.detail, required super.transport, super.session, super.clock, this._connect});

  final TextSocketConnect? _connect;

  /// Consecutive failures before the terminal state.
  static const maxFailures = 6;

  /// Wait after a failed request.
  static const retryDelay = Duration(seconds: 3);

  /// How long the seat may take to name the comment server.
  static const messageServerTimeout = Duration(seconds: 10);

  TextSocketConnect _socket(Uri url) {
    final connect = _connect;
    if (connect != null) return connect;
    final io = transport;
    return ioTextSocketConnect(io is IoDanmakuTransport ? io.proxy.routeFor('niconico', url) : const DirectRoute());
  }

  @override
  Future<void> run(int generation) async {
    status(generation, DanmakuStatus.connecting);
    final Uri socket;
    try {
      socket = await NiconicoSite(transport.http).seatSocket(room);
    } on StreamUnavailable catch (error) {
      if (!isStale(generation)) terminal(generation, 'offline', error.detail);
      return;
    } on NeedsLogin catch (error) {
      if (!isStale(generation)) terminal(generation, 'credentials', error.detail);
      return;
    } on Object catch (error) {
      if (!isStale(generation)) terminal(generation, 'failed', '$error');
      return;
    }
    var failures = 0;
    var joinedOnce = false;
    while (!isStale(generation)) {
      final NiconicoSeat seat;
      try {
        seat = await NiconicoSeat.open(socket, connect: _socket(socket));
      } on Object catch (error) {
        if (isStale(generation)) return;
        if (++failures >= maxFailures || !joinedOnce) {
          terminal(generation, joinedOnce ? 'maxRetries' : 'failed', '$error');
          return;
        }
        if (!await pause(generation, retryDelay)) return;
        continue;
      }
      final removeStop = onStop(() => unawaited(seat.close()));
      try {
        final end = await _follow(
          generation,
          seat,
          onJoin: () {
            if (!joinedOnce) {
              joinedOnce = true;
              status(generation, DanmakuStatus.connected);
              joined(generation);
            } else {
              status(generation, DanmakuStatus.connected);
            }
            failures = 0;
          },
        );
        if (end == null || isStale(generation)) return;
        if (end.contains('END_PROGRAM')) {
          terminal(generation, 'offline', end);
          return;
        }
        if (++failures >= maxFailures) {
          terminal(generation, 'maxRetries', end);
          return;
        }
        status(generation, DanmakuStatus.reconnecting, [end]);
        if (!await pause(generation, retryDelay)) return;
      } finally {
        removeStop();
        await seat.close();
      }
    }
  }

  /// Reads the comment server while [seat] lasts; returns why it stopped,
  /// or null when the connector was stopped.
  Future<String?> _follow(int generation, NiconicoSeat seat, {required void Function() onJoin}) async {
    var waited = Duration.zero;
    while (seat.messageServer == null && seat.isOpen) {
      if (waited >= messageServerTimeout) return 'no messageServer';
      if (!await pause(generation, const Duration(milliseconds: 100))) return null;
      waited += const Duration(milliseconds: 100);
    }
    final view = seat.messageServer;
    if (view == null) return seat.endReason ?? 'seat closed';
    var at = 'now';
    var failures = 0;
    var joinedHere = false;
    final seen = <Uri>{};
    while (!isStale(generation)) {
      if (!seat.isOpen) return seat.endReason ?? 'seat closed';
      final NiconicoView answer;
      try {
        answer = NiconicoChatProtocol.view(
          await _get(view.replace(queryParameters: {...view.queryParameters, 'at': at}), const Duration(seconds: 60)),
        );
      } on Object catch (error) {
        if (isStale(generation)) return null;
        if (++failures >= maxFailures) return 'view: $error';
        if (!await pause(generation, retryDelay)) return null;
        continue;
      }
      failures = 0;
      if (!joinedHere) {
        joinedHere = true;
        onJoin();
        // Finished windows are history; only windows under way are read.
        seen.addAll(answer.previous.map((segment) => segment.uri));
      }
      for (final segment in answer.segments) {
        if (seen.add(segment.uri)) unawaited(_window(generation, segment));
      }
      if (seen.length > 64) seen.remove(seen.first);
      final next = answer.next;
      if (next == null) return 'view: no next';
      at = '$next';
    }
    return null;
  }

  /// §7.4 reads one window (the answer ends when the window does) and
  /// releases its messages at their own pace from then on.
  Future<void> _window(int generation, NiconicoSegment segment) async {
    final List<NiconicoTimedEvent> events;
    try {
      final left = segment.until.difference(clock.now());
      final limit = (left.isNegative ? Duration.zero : left) + const Duration(seconds: 20);
      events = NiconicoChatProtocol.messages(await _get(segment.uri, limit), context: context());
    } on Object {
      // A lost window only loses its comments.
      return;
    }
    if (isStale(generation) || events.isEmpty) return;
    events.sort((a, b) => a.at.compareTo(b.at));
    final start = clock.micros();
    for (final (:at, :event) in events) {
      final offset = at.difference(segment.from);
      final due = Duration(microseconds: offset.inMicroseconds - (clock.micros() - start));
      if (!due.isNegative && due > Duration.zero && !await pause(generation, due)) return;
      if (isStale(generation)) return;
      emit(generation, event);
    }
  }

  Future<List<int>> _get(Uri url, Duration timeout) async {
    final cancel = CancelToken();
    final removeStop = onStop(cancel.cancel);
    try {
      final response = await transport.http.send(
        LiveRequest(
          site: 'niconico',
          url: url,
          headers: const {'origin': 'https://live.nicovideo.jp', 'referer': 'https://live.nicovideo.jp/'},
          timeout: timeout,
          cancel: cancel,
        ),
      );
      if (!response.isSuccess) throw FormatException('HTTP ${response.status} ${url.path}');
      return response.bytes;
    } finally {
      removeStop();
    }
  }
}
