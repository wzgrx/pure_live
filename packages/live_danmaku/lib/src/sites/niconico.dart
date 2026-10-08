import 'dart:async';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// One comment window of the comment server: its messages are read from
/// [uri], an answer that lasts until the window ends.
@immutable
final class NiconicoCommentWindow {
  /// Creates a window.
  const new({required this.from, required this.until, required this.uri});

  /// Window start.
  final DateTime from;

  /// Window end.
  final DateTime until;

  /// Where its messages are read (the path carries a token).
  final Uri uri;

  @override
  bool operator ==(Object other) =>
      other is NiconicoCommentWindow && other.from == from && other.until == until && other.uri == uri;

  @override
  int get hashCode => Object.hash(from, until, uri);

  /// The window's times only: its address carries a token.
  @override
  String toString() => 'NiconicoCommentWindow(${from.toUtc().toIso8601String()}–${until.toUtc().toIso8601String()})';
}

/// What an entry of a `view` answer is (`ChunkedEntry`).
enum NiconicoViewEntryKind {
  /// A window under way or about to start: read it.
  segment,

  /// A finished window: history, not read.
  previous,

  /// Where older history and a state snapshot are: not read.
  backward,

  /// When to ask `view` again.
  next,

  /// Anything else.
  unknown,
}

/// One entry of a `view` answer.
@immutable
final class NiconicoViewEntry {
  /// Creates an entry.
  const new(this.kind, {this.window, this.next});

  /// What it is.
  final NiconicoViewEntryKind kind;

  /// The window of a [NiconicoViewEntryKind.segment] or
  /// [NiconicoViewEntryKind.previous] entry; null when it is not usable (no
  /// times, or an address that is not the comment server).
  final NiconicoCommentWindow? window;

  /// The `at` of the next `view` request (seconds since the epoch), for a
  /// [NiconicoViewEntryKind.next] entry.
  final int? next;
}

/// A gift (`NicoliveMessage.gift`): the [LiveMessage.data] of a
/// [LiveMessageType.gift] message, whose user is the giver
/// (`advertiser_name`, `advertiser_user_id`), as a [LiveGift] (E05.5): one
/// item worth [point] points, free at 0.
@immutable
final class NiconicoGift extends LiveGift {
  /// Creates the gift; [name] is `item_name`, or empty.
  const new({required this.itemId, required super.name, required this.point, this.message = '', this.contributionRank})
    : super(id: itemId, unitPrice: point, totalValue: point, unit: LiveGiftUnit.point, free: point == 0);

  /// `item_id`, or empty.
  final String itemId;

  /// `point`: what it cost, in niconico points (0 or more).
  final int point;

  /// `message`, or empty.
  final String message;

  /// `contribution_rank`: the giver's place among the program's givers, or
  /// null.
  final int? contributionRank;

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is NiconicoGift &&
      other.itemId == itemId &&
      other.point == point &&
      other.message == message &&
      other.contributionRank == contributionRank;

  @override
  int get hashCode => Object.hash(super.hashCode, itemId, point, message, contributionRank);

  @override
  String toString() => 'NiconicoGift($name, ${point}pt)';
}

/// Who may comment (`NicoliveState.comment_lock`), as the web player reads
/// it: everyone, nobody (`Locked`), or followers only (`Restricted` with a
/// follow restriction; `Restricted` without one is everyone).
@immutable
final class NiconicoCommentLock {
  const new _(this.isLocked, this.followersOnly);

  /// Followers only, once they have followed for [minimumFollow].
  const new followers(Duration minimumFollow) : isLocked = false, followersOnly = minimumFollow;

  /// Everyone may comment.
  static const NiconicoCommentLock none = NiconicoCommentLock._(false, null);

  /// Comments are locked.
  static const NiconicoCommentLock locked = NiconicoCommentLock._(true, null);

  /// Whether comments are locked.
  final bool isLocked;

  /// How long only followers must have followed to comment; null when not
  /// only followers may.
  final Duration? followersOnly;

  /// The notice for a change from [previous] to this, or null when it is no
  /// change:
  ///
  /// - followers only, and the lift of it, in the web player's own lines
  ///   (`FollowerOnlyMode.generateSystemMessage`, usecase.cb7efc6a32.js);
  /// - locked: what the web player's comment field says meanwhile
  ///   (`現在コメントできません`, vc.c3c6c95a6a.js); the web player adds no
  ///   line for the lock, so its lift is a sentence of ours.
  String? noticeFrom(NiconicoCommentLock previous) {
    if (this == previous) return null;
    if (isLocked) return NiconicoDanmakuProtocol.commentLockedNotice;
    if (followersOnly case final minimum?) {
      final seconds = minimum.inSeconds;
      return seconds == 0
          ? '【コメント制限】フォロワーに限定されます'
          : '【コメント制限】${NiconicoDanmakuProtocol.followDuration(seconds)}フォローを継続したユーザーに限定されます';
    }
    return previous.isLocked
        ? NiconicoDanmakuProtocol.commentUnlockedNotice
        : NiconicoDanmakuProtocol.followersOnlyLiftedNotice;
  }

  @override
  bool operator ==(Object other) =>
      other is NiconicoCommentLock && other.isLocked == isLocked && other.followersOnly == followersOnly;

  @override
  int get hashCode => Object.hash(isLocked, followersOnly);

  @override
  String toString() => isLocked
      ? 'NiconicoCommentLock.locked'
      : followersOnly == null
      ? 'NiconicoCommentLock.none'
      : 'NiconicoCommentLock.followers(${followersOnly!.inSeconds} s)';
}

/// Reads the window messages of one connection, in order, into
/// [LiveMessage]s ([NiconicoDanmakuProtocol.message] reads one alone). It
/// remembers who may comment, so that only changes of the comment lock are
/// reported, as the web player does; it starts from "everyone", the web
/// player's default before its state snapshot (which is not read here).
final class NiconicoMessageReader {
  /// Creates a reader.
  new();

  NiconicoCommentLock _commentLock = NiconicoCommentLock.none;
  bool _endedProgram = false;

  /// Who may comment, by the last comment lock read.
  NiconicoCommentLock get commentLock => _commentLock;

  /// Whether the last message read said that the program ended
  /// (`program_status` `Ended`).
  bool get endedProgram => _endedProgram;

  /// One window message (`ChunkedMessage`: 1 meta, then one of 2 message,
  /// 4 state, 5 signal) as a [LiveMessage], or null when it is none of the
  /// reported kinds. Throws [FormatException] when it is not protobuf.
  LiveMessage? read(List<int> bytes) {
    _endedProgram = false;
    final chunk = ProtoMessage.decode(bytes);
    final meta = chunk.message(1);
    return switch (NiconicoDanmakuProtocol._lastPayload(chunk)) {
      2 => NiconicoDanmakuProtocol._nicoliveMessage(chunk.message(2)!, meta),
      4 => _state(chunk.message(4)!, meta),
      _ => null,
    };
  }

  /// `NicoliveState`: its fields are not a oneof, though every state
  /// recorded carries one. The web player takes the first it knows in its
  /// order (`subscribeUpdate`, usecase.cb7efc6a32.js); of the reported ones
  /// that is 5 comment_lock, 4 marquee, 9 program_status, 1 statistics. A
  /// field that is not protobuf counts as absent.
  LiveMessage? _state(ProtoMessage state, ProtoMessage? meta) {
    final lock = _readable(() => state.message(5));
    if (lock != null) {
      if (_readable(() => NiconicoDanmakuProtocol.commentLockOf(lock)) case final next?) {
        final notice = next.noticeFrom(_commentLock);
        _commentLock = next;
        if (notice != null) return NiconicoDanmakuProtocol._notice(notice, meta);
      }
    }
    final marquee = _readable(() => state.message(4));
    if (marquee != null) {
      if (_readable(() => NiconicoDanmakuProtocol._operatorComment(marquee, meta)) case final notice?) return notice;
    }
    if (_readable(() => state.message(9)?.integer(1)) == 1) {
      _endedProgram = true;
      return NiconicoDanmakuProtocol.programEnded(
        messageId: meta?.string(1)?.trim() ?? '',
        sentAt: NiconicoDanmakuProtocol.time(meta?.message(2)),
      );
    }
    // NicoliveState.statistics.viewers.
    final viewers = _readable(() => state.message(1)?.integer(1));
    if (viewers == null || viewers < 0) return null;
    return LiveMessage(
      type: LiveMessageType.online,
      userName: '',
      message: '',
      data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.totalViewers, value: viewers),
      color: LiveMessageColor.white,
    );
  }

  /// What [read] gives, or null when it meets bytes that are not protobuf.
  static T? _readable<T>(T? Function() read) {
    try {
      return read();
    } on FormatException {
      return null;
    }
  }
}

/// Splits a varint-length-delimited protobuf stream (the comment server's
/// answers) into its messages as the bytes arrive.
final class NiconicoDelimitedReader {
  /// Creates a reader; a message over [maxLength] bytes is refused.
  new({this.maxLength = NiconicoDanmakuProtocol.maxMessageBytes});

  /// The largest message accepted.
  final int maxLength;

  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  /// Whether bytes of an unfinished message are waiting.
  bool get hasPending => _offset < _buffer.length;

  /// Adds [chunk] and returns the messages it completes, in order. Throws
  /// [FormatException] for a length prefix over ten bytes or a message over
  /// [maxLength]; the stream cannot be read further after that.
  List<Uint8List> add(List<int> chunk) {
    final rest = _buffer.length - _offset;
    final data = Uint8List(rest + chunk.length)
      ..setRange(0, rest, _buffer, _offset)
      ..setRange(rest, rest + chunk.length, chunk);
    final messages = <Uint8List>[];
    var offset = 0;
    while (offset < data.length) {
      var length = 0;
      var cursor = offset;
      var complete = false;
      for (var shift = 0; cursor < data.length; shift += 7) {
        if (shift >= 70) throw const FormatException('Length prefix longer than ten bytes');
        final byte = data[cursor++];
        length |= (byte & 0x7F) << shift;
        if (byte < 0x80) {
          complete = true;
          break;
        }
      }
      if (!complete) {
        if (cursor - offset >= 10) throw const FormatException('Length prefix longer than ten bytes');
        break;
      }
      if (length < 0 || length > maxLength) throw FormatException('Message of $length bytes');
      if (data.length - cursor < length) break;
      messages.add(Uint8List.sublistView(data, cursor, cursor + length));
      offset = cursor + length;
    }
    _buffer = data;
    _offset = offset;
    return messages;
  }

  /// Ends the stream: [FormatException] when a message was left unfinished.
  void close() {
    if (hasPending) throw const FormatException('Truncated message stream');
  }
}

/// niconico's comment server ("NDGR"), without I/O. The watching seat
/// (`NiconicoSeat.messageServer`) names its `view` address; everything
/// after is HTTP, every answer a varint-length-delimited protobuf stream
/// (`dwango.nicolive.chat`, the definitions n-air-app publishes as
/// nicolive-comment-protobuf; docs/D-弹幕/D01-平台弹幕协议/D01.15-niconico弹幕/record.md):
///
/// - `view?at=now` answers at once with `next`;
/// - `view?at=<next>` streams the history pointers (`backward`), the
///   finished windows (`previous`), the window under way (`segment`), then
///   each next 16-second window as it is about to start, and ends with
///   `next`, about half a minute later;
/// - a window's address streams its messages (`ChunkedMessage`): the ones
///   already sent, a `Flushed` signal, then each one as it is posted, until
///   the window ends.
///
/// Chats (`chat`, and `overflowed_chat`, the chats that overflowed the
/// display) become chat messages; `statistics.viewers`, the program's
/// cumulative visitors (the watch page's `watchCount`), an audience update;
/// gifts, gift messages ([NiconicoGift]); the operator's comments
/// (`marquee`), changes of who may comment (`comment_lock`) and the end of
/// the program (`program_status`), system notices (M5.F, B-11). Ads,
/// notifications (visits, rankings), forwarded chats, the other states and
/// the signals are not reported.
abstract final class NiconicoDanmakuProtocol {
  /// The notice of the program's end: the web player's announcement once it
  /// ended (`この番組は終了しました`, nicolib.37f1064f38.js).
  static const String programEndedNotice = 'この番組は終了しました';

  /// The notice of a comment lock: what the web player's comment field says
  /// while comments are locked.
  static const String commentLockedNotice = '現在コメントできません';

  /// The notice of a lock's lift: the web player only enables its comment
  /// field again, so the sentence is ours.
  static const String commentUnlockedNotice = '评论锁定已解除';

  /// The web player's line when comments are no longer for followers only.
  static const String followersOnlyLiftedNotice = 'フォロワー限定コメントが解除されました';

  /// The most seconds a follow restriction is read as (about 136 years).
  static const int maxFollowSeconds = 1 << 32;

  /// A follow restriction's duration of [seconds] (0 or more) as the web
  /// player writes it: whole days (`2日`, `1日と3時間`) from a day on, else
  /// hours and minutes (`1時間`, `1時間30分`) from an hour on, else minutes
  /// (`10分`, and `0分` under a minute).
  static String followDuration(int seconds) {
    if (seconds >= 86400) {
      final days = '${seconds ~/ 86400}日';
      return seconds % 86400 < 3600 ? days : '$daysと${seconds % 86400 ~/ 3600}時間';
    }
    if (seconds < 3600) return '${seconds ~/ 60}分';
    final hours = '${seconds ~/ 3600}時間';
    return seconds % 3600 < 60 ? hours : '$hours${seconds % 3600 ~/ 60}分';
  }

  /// A system notice of [text], with the window message's id and time.
  static LiveMessage _notice(String text, ProtoMessage? meta, {String userName = '', LiveMessageColor? color}) =>
      LiveMessage(
        type: LiveMessageType.notice,
        data: LiveNoticeKind.system,
        userName: userName,
        message: text,
        messageId: meta?.string(1)?.trim() ?? '',
        sentAt: time(meta?.message(2)),
        color: color ?? LiveMessageColor.white,
      );

  /// The notice that the program ended ([programEndedNotice]), with the
  /// platform's [messageId] and [sentAt] when it has them.
  static LiveMessage programEnded({String messageId = '', DateTime? sentAt}) => LiveMessage(
    type: LiveMessageType.notice,
    data: LiveNoticeKind.system,
    userName: '',
    message: programEndedNotice,
    messageId: messageId,
    sentAt: sentAt,
    color: LiveMessageColor.white,
  );

  /// Who may comment by a `CommentLock` (1 status: 0 Unrestricted,
  /// 1 Locked, 2 Restricted; 2 follow_restriction {1 minimum_follow_duration
  /// {1 seconds}}); null for a status this does not know, which changes
  /// nothing. A follow duration below zero is zero; over
  /// [maxFollowSeconds], that.
  static NiconicoCommentLock? commentLockOf(ProtoMessage lock) {
    switch (lock.integer(1) ?? 0) {
      case 0:
        return NiconicoCommentLock.none;
      case 1:
        return NiconicoCommentLock.locked;
      case 2:
        final restriction = lock.message(2);
        if (restriction == null) return NiconicoCommentLock.none;
        final seconds = restriction.message(1)?.integer(1) ?? 0;
        return NiconicoCommentLock.followers(Duration(seconds: seconds.clamp(0, maxFollowSeconds)));
      default:
        return null;
    }
  }

  /// `Marquee` (1 display {1 operator_comment, 3 duration}): the operator's
  /// comment (`OperatorComment`: 1 content, 2 name, 3 modifier, 4 link) as
  /// a notice, in its colour; null for a cleared marquee or an empty
  /// comment. The web player pins it and adds it to its comment list; the
  /// link is not kept.
  static LiveMessage? _operatorComment(ProtoMessage marquee, ProtoMessage? meta) {
    final comment = marquee.message(1)?.message(1);
    final text = comment?.string(1)?.trim() ?? '';
    if (comment == null || text.isEmpty) return null;
    return _notice(text, meta, userName: comment.string(2)?.trim() ?? '', color: color(comment.message(3)));
  }

  /// `NicoliveMessage`: one field of its oneof; 1 chat and 20
  /// overflowed_chat are chats, 8 gift a gift, the rest not reported.
  static LiveMessage? _nicoliveMessage(ProtoMessage data, ProtoMessage? meta) =>
      switch (_lastMessage(data, const {1, 7, 8, 9, 13, 17, 18, 19, 20, 22, 23, 24, 25, 26})) {
        final kind? when kind == 1 || kind == 20 => _chat(data.message(kind)!, meta),
        8 => _gift(data.message(8)!, meta),
        _ => null,
      };

  /// `Gift`: 1 item_id, 2 advertiser_user_id, 3 advertiser_name, 4 point,
  /// 5 message, 6 item_name, 7 contribution_rank. The text is the shared
  /// `ニコ子 ×1` (E05.5: was the web player's sentence with the giver's name
  /// in it, `eF`, domain.ce2c3387de.js, so the chat line showed the name
  /// twice). Like the web player, a gift of negative points is dropped, and
  /// so is one without an item.
  static LiveMessage? _gift(ProtoMessage gift, ProtoMessage? meta) {
    final itemId = gift.string(1)?.trim() ?? '';
    final name = gift.string(6)?.trim() ?? '';
    final point = gift.integer(4) ?? 0;
    if ((itemId.isEmpty && name.isEmpty) || point < 0) return null;
    final giver = gift.string(3)?.trim() ?? '';
    final giverId = gift.integer(2);
    final rank = gift.integer(7)?.toSigned(32);
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: giver,
      userId: giverId != null && giverId > 0 ? '$giverId' : '',
      message: '${name.isEmpty ? itemId : name} ×1',
      messageId: meta?.string(1)?.trim() ?? '',
      sentAt: time(meta?.message(2)),
      data: NiconicoGift(
        itemId: itemId,
        name: name,
        point: point,
        message: gift.string(5)?.trim() ?? '',
        contributionRank: rank,
      ),
      color: LiveMessageColor.white,
    );
  }

  /// Request headers: the adapter's (referer, user agent) and the site's
  /// origin, as the web player sends from it.
  static const Map<String, String> headers = {...NiconicoApi.headers, 'origin': NiconicoApi.origin};

  /// How long the seat may take to name the comment server after its grant
  /// (it comes with the grant; the archived v4 waited this long).
  static const Duration messageServerTimeout = Duration(seconds: 10);

  /// How often the seat is checked for the comment server meanwhile.
  static const Duration messageServerPoll = Duration(milliseconds: 100);

  /// Longest wait for the `view?at=now` answer, which comes at once.
  static const Duration firstViewTimeout = defaultRequestTimeout;

  /// Longest wait for the headers and between entries of a `view` answer:
  /// the answer lasts about 30 s and its entries come about 16 s apart
  /// (measured 2026-09-29).
  static const Duration viewTimeout = Duration(seconds: 60);

  /// Added to the time left of a window for the longest wait between its
  /// messages (the archived v4's margin).
  static const Duration windowGrace = Duration(seconds: 20);

  /// The most time left a window is granted: a window lasts 16 s and is
  /// announced about 6 s before it starts, so more means a clock that is
  /// off, and a stalled window would be held too long.
  static const Duration maxWindowLeft = Duration(seconds: 60);

  /// The longest wait for the headers and between the messages of a window
  /// ending at [until], asked at [now]: its time left (0–60 s) plus 20 s.
  static Duration windowTimeout(DateTime until, DateTime now) {
    final left = until.difference(now);
    return (left.isNegative ? Duration.zero : (left > maxWindowLeft ? maxWindowLeft : left)) + windowGrace;
  }

  /// Failures in a row that are retried; the next one ends the connection.
  static const int maxFailures = 8;

  /// The largest message accepted from the comment server.
  static const int maxMessageBytes = 1 << 20;

  /// Windows read at the same time at most (normally two or three).
  static const int maxOpenWindows = 8;

  /// Windows remembered as read, per seat.
  static const int rememberedWindows = 64;

  /// Wait after the [failures]-th failure in a row: 1, 2, 4, then 8 s (the
  /// HTTP connection's backoff, M5.5).
  static Duration backoff(int failures) => Duration(seconds: 1 << (failures - 1).clamp(0, 3));

  /// Whether [uri] may be requested as the comment server: https on
  /// `nicovideo.jp` or a subdomain, without credentials, port or fragment.
  static bool isCommentServer(Uri uri) =>
      uri.isScheme('https') &&
      (uri.host == 'nicovideo.jp' || uri.host.endsWith('.nicovideo.jp')) &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      !uri.hasFragment;

  /// The `view` request of [view] for [at] (`now` or a `next`).
  static Uri viewUrl(Uri view, String at) => view.replace(queryParameters: {...view.queryParameters, 'at': at});

  /// A request to the comment server, sent as `niconico` (its proxy route),
  /// without following redirects.
  static LiveRequest request(Uri url, {required Duration timeout, CancelToken? cancel}) => LiveRequest(
    site: SiteIds.niconico,
    url: url,
    headers: headers,
    followRedirects: false,
    timeout: timeout,
    cancel: cancel,
  );

  /// The messages of a streamed answer [body], as they complete. Fails
  /// ([FormatException]) on a bad length prefix or when the answer ends
  /// inside a message.
  static Stream<Uint8List> delimited(Stream<List<int>> body, {int maxLength = maxMessageBytes}) async* {
    final reader = NiconicoDelimitedReader(maxLength: maxLength);
    await for (final chunk in body) {
      for (final message in reader.add(chunk)) {
        yield message;
      }
    }
    reader.close();
  }

  /// The messages of a whole answer [bytes].
  static List<Uint8List> split(List<int> bytes, {int maxLength = maxMessageBytes}) {
    final reader = NiconicoDelimitedReader(maxLength: maxLength);
    final messages = reader.add(bytes);
    reader.close();
    return messages;
  }

  /// One `view` entry (`ChunkedEntry`: 1 segment, 2 backward, 3 previous,
  /// 4 next; the last one wins). Throws [FormatException] when it is not
  /// protobuf.
  static NiconicoViewEntry viewEntry(List<int> bytes) {
    final entry = ProtoMessage.decode(bytes);
    final kind = _lastMessage(entry, const {1, 2, 3, 4});
    return switch (kind) {
      1 => NiconicoViewEntry(NiconicoViewEntryKind.segment, window: _window(entry.message(1))),
      3 => NiconicoViewEntry(NiconicoViewEntryKind.previous, window: _window(entry.message(3))),
      2 => const NiconicoViewEntry(NiconicoViewEntryKind.backward),
      4 => NiconicoViewEntry(NiconicoViewEntryKind.next, next: _positive(entry.message(4)?.integer(1))),
      _ => const NiconicoViewEntry(NiconicoViewEntryKind.unknown),
    };
  }

  /// `MessageSegment`: 1 from, 2 until, 3 uri.
  static NiconicoCommentWindow? _window(ProtoMessage? segment) {
    final from = time(segment?.message(1));
    final until = time(segment?.message(2));
    final uri = Uri.tryParse(segment?.string(3)?.trim() ?? '');
    if (from == null || until == null || uri == null || !isCommentServer(uri)) return null;
    return NiconicoCommentWindow(from: from, until: until, uri: uri);
  }

  static int? _positive(int? value) => value != null && value > 0 ? value : null;

  /// The number of the last length-delimited field of [message] among
  /// [numbers] (a oneof: the last one wins), or null.
  static int? _lastMessage(ProtoMessage message, Set<int> numbers) {
    for (final field in message.fields.reversed) {
      if (field.wireType == ProtoMessage.lengthDelimitedType && numbers.contains(field.number)) return field.number;
    }
    return null;
  }

  /// The largest `Timestamp.seconds` a `DateTime` holds.
  static const int _maxSeconds = 8640000000000;

  /// A `google.protobuf.Timestamp` (1 seconds, 2 nanos) as a local
  /// `DateTime`; null without seconds, or out of range.
  static DateTime? time(ProtoMessage? timestamp) {
    final seconds = timestamp?.integer(1);
    final nanos = timestamp?.integer(2) ?? 0;
    if (seconds == null || seconds.abs() > _maxSeconds || nanos < 0 || nanos > 999999999) return null;
    return DateTime.fromMicrosecondsSinceEpoch(seconds * 1000000 + nanos ~/ 1000);
  }

  /// One window message (`ChunkedMessage`: 1 meta, then one of 2 message,
  /// 4 state, 5 signal) as a [LiveMessage], or null when it is none of the
  /// reported kinds; a comment lock as a change from "everyone" (a
  /// connection reads its messages with one [NiconicoMessageReader]).
  /// Throws [FormatException] when it is not protobuf.
  static LiveMessage? message(List<int> bytes) => NiconicoMessageReader().read(bytes);

  /// The payload of a `ChunkedMessage`: 2 or 4 (messages), 5 (a varint).
  static int? _lastPayload(ProtoMessage chunk) {
    for (final field in chunk.fields.reversed) {
      if (field.number == 5 && field.wireType == ProtoMessage.varintType) return 5;
      if ((field.number == 2 || field.number == 4) && field.wireType == ProtoMessage.lengthDelimitedType) {
        return field.number;
      }
    }
    return null;
  }

  /// `Chat`: 1 content, 2 name, 5 raw_user_id, 6 hashed_user_id, 7 modifier;
  /// the id and time are the meta's (1 id, 2 at).
  static LiveMessage? _chat(ProtoMessage chat, ProtoMessage? meta) {
    final text = chat.string(1)?.trim() ?? '';
    if (text.isEmpty) return null;
    final hashed = chat.string(6)?.trim() ?? '';
    final raw = chat.integer(5);
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: chat.string(2)?.trim() ?? '',
      userId: hashed.isNotEmpty ? hashed : (raw == null ? '' : '$raw'),
      message: text,
      messageId: meta?.string(1)?.trim() ?? '',
      sentAt: time(meta?.message(2)),
      color: color(chat.message(7)),
    );
  }

  /// The colours of `Chat.Modifier.ColorName`, by value: the ten basic
  /// colours and the ten premium ones (`white2` niconicowhite … `black2`),
  /// as niconico's comment commands draw them.
  static const List<LiveMessageColor> namedColors = [
    LiveMessageColor.white,
    LiveMessageColor(0xFF, 0x00, 0x00), // red
    LiveMessageColor(0xFF, 0x80, 0x80), // pink
    LiveMessageColor(0xFF, 0xC0, 0x00), // orange
    LiveMessageColor(0xFF, 0xFF, 0x00), // yellow
    LiveMessageColor(0x00, 0xFF, 0x00), // green
    LiveMessageColor(0x00, 0xFF, 0xFF), // cyan
    LiveMessageColor(0x00, 0x00, 0xFF), // blue
    LiveMessageColor(0xC0, 0x00, 0xFF), // purple
    LiveMessageColor(0x00, 0x00, 0x00), // black
    LiveMessageColor(0xCC, 0xCC, 0x99), // white2 (niconicowhite)
    LiveMessageColor(0xCC, 0x00, 0x33), // red2 (truered)
    LiveMessageColor(0xFF, 0x33, 0xCC), // pink2
    LiveMessageColor(0xFF, 0x66, 0x00), // orange2 (passionorange)
    LiveMessageColor(0x99, 0x99, 0x00), // yellow2 (madyellow)
    LiveMessageColor(0x00, 0xCC, 0x66), // green2 (elementalgreen)
    LiveMessageColor(0x00, 0xCC, 0xCC), // cyan2
    LiveMessageColor(0x33, 0x99, 0xFF), // blue2 (marineblue)
    LiveMessageColor(0x66, 0x33, 0xCC), // purple2 (nobleviolet)
    LiveMessageColor(0x66, 0x66, 0x66), // black2
  ];

  /// The colour of a `Chat.Modifier` (a oneof, the last one wins: 3
  /// named_color, 4 full_color {1 r, 2 g, 3 b}); white without one, or for
  /// a colour name this table does not know. Channels are clamped to 0–255.
  static LiveMessageColor color(ProtoMessage? modifier) {
    if (modifier == null) return LiveMessageColor.white;
    for (final field in modifier.fields.reversed) {
      if (field.number == 3 && field.wireType == ProtoMessage.varintType) {
        final value = field.value as int;
        return value >= 0 && value < namedColors.length ? namedColors[value] : LiveMessageColor.white;
      }
      if (field.number == 4 && field.wireType == ProtoMessage.lengthDelimitedType) {
        final rgb = modifier.message(4)!;
        int channel(int number) => (rgb.integer(number) ?? 0).toSigned(32).clamp(0, 255);
        return LiveMessageColor(channel(1), channel(2), channel(3));
      }
    }
    return LiveMessageColor.white;
  }
}

/// niconico's comments (new in v4; 3.x had `EmptyDanmaku`, upgrade 17-3):
/// a watching seat of its own through `NiconicoSite.openSeat` (the watch
/// page, then the seat WebSocket, which names the comment server), then
/// the comment server over HTTP ([NiconicoDanmakuProtocol]): `view` is
/// followed from `at=now` with each `next`, and every window it announces
/// is read as it streams, so a comment comes as it is posted.
///
/// - Joined once a `view` answer gives its first entry; again after every
///   recovery.
/// - A lost window only loses its comments. A failed `view` is asked again
///   on the same seat; one the server refuses (4xx) takes a new seat, as
///   does a seat that ends (the program ended, the server closed it). A new
///   seat reads the watch page again, so a broadcaster's next program is
///   followed, and a room that went offline ends the connection.
/// - The program's end (a window's `program_status`, or the seat's
///   `END_PROGRAM`) is reported once as a notice; the next seat is then
///   taken at once, without a reconnection notice (M5.F, B-11).
/// - Failures in a row wait 1, 2, 4, 8, 8… s; the first reports
///   [DanmakuReconnecting], the ninth ends with
///   [DanmakuCloseReason.reconnectsExhausted]. A room that cannot be
///   watched (offline, restricted, gone) ends with
///   [DanmakuCloseReason.connectionFailed].
/// - No heartbeat of its own: the seat keeps itself.
///
/// The app registers it as `SiteIds.niconico: () =>
/// NiconicoDanmakuConnection(site: niconicoSite)`, with its `NiconicoSite`
/// (the seat's connector and proxy route, and the `LiveHttp` for the
/// comment server).
final class NiconicoDanmakuConnection extends DanmakuConnectionBase<NiconicoDanmakuArgs> {
  /// Creates the connection. Seats come from `site`; the comment server is
  /// read with [http] (default the site's). [now] times the windows' waits;
  /// [retryDelay] is the first backoff step and [messageServerTimeout] the
  /// wait for the seat to name the comment server (tests shorten them).
  new({
    required this._site,
    LiveHttp? http,
    DateTime Function()? now,
    this.retryDelay = const Duration(seconds: 1),
    this.messageServerTimeout = NiconicoDanmakuProtocol.messageServerTimeout,
  }) : _http = http ?? _site.http,
       _now = now ?? DateTime.now;

  final NiconicoSite _site;
  final LiveHttp _http;
  final DateTime Function() _now;

  /// The first backoff step (1 s); the next ones double it up to eight times.
  final Duration retryDelay;

  /// Longest wait for the seat to name the comment server.
  final Duration messageServerTimeout;

  _NiconicoComments? _comments;

  Duration _backoff(int failures) => retryDelay * NiconicoDanmakuProtocol.backoff(failures).inSeconds;

  @override
  Future<void> start(NiconicoDanmakuArgs args, DanmakuRun run) async {
    final comments = _comments = _NiconicoComments(this, args, run);
    await comments.start();
  }

  @override
  Future<void> stop() async {
    final comments = _comments;
    _comments = null;
    await comments?.close();
  }
}

/// A window said that the program ended.
final class _ProgramEnded implements Exception {
  const new();

  @override
  String toString() => 'the program ended';
}

/// The comment server answered a request with [status].
final class _Refused implements Exception {
  const new(this.status);

  final int status;

  @override
  String toString() => 'the comment server answered HTTP $status';
}

/// One run: its seats and requests, cancelled when the run ends.
final class _NiconicoComments {
  new(this._owner, this._args, this._run) {
    unawaited(_run.ended.then((_) => _cancel.cancel()));
  }

  final NiconicoDanmakuConnection _owner;
  final NiconicoDanmakuArgs _args;
  final DanmakuRun _run;
  final CancelToken _cancel = CancelToken();
  final Completer<void> _firstAttempt = Completer();
  NiconicoSeat? _seat;
  NiconicoMessageReader _reader = NiconicoMessageReader();
  int _failures = 0;
  int _openWindows = 0;
  int? _lastViewers;

  /// A program ended and no `view` of a later seat answered yet: another
  /// end now is a seat that could not follow (the watch page still showed
  /// the ended program), a failure like any other.
  bool _programJustEnded = false;

  /// Starts following; completes once the first attempt joined or failed.
  Future<void> start() {
    unawaited(_follow());
    return _firstAttempt.future;
  }

  /// Cancels the requests and closes the seat.
  Future<void> close() async {
    _cancel.cancel();
    await _seat?.close();
  }

  void _settle() {
    if (!_firstAttempt.isCompleted) _firstAttempt.complete();
  }

  /// Seats one after another until the run ends.
  Future<void> _follow() async {
    try {
      while (_run.isActive) {
        final NiconicoSeat seat;
        try {
          seat = await _owner._site.openSeat(_args.roomId, cancel: _cancel);
        } on Object catch (error) {
          if (!await _failed(error, permanent: _unwatchable(error))) return;
          continue;
        }
        if (!_run.isActive) {
          await seat.close();
          return;
        }
        _seat = seat;
        final Object? end;
        try {
          end = await _read(seat);
        } finally {
          _seat = null;
          await seat.close();
        }
        if (end == null) return;
        if (_endsProgram(end)) continue;
        if (!await _failed(end)) return;
      }
    } finally {
      _settle();
    }
  }

  /// Whether [end], why a seat stopped, is its program's end (a window's
  /// `program_status`, or the seat's `END_PROGRAM`, which come within
  /// milliseconds of each other): the notice is reported once, and the next
  /// seat is taken at once without a reconnection notice. Its watch page
  /// ends the connection when the room is offline, as other platforms end
  /// theirs when the broadcast ends, and follows the broadcaster's next
  /// program if one already started (M5.14 difference 14). An end before a
  /// later seat answered is not one (see [_programJustEnded]).
  bool _endsProgram(Object end) {
    if (end is! _ProgramEnded && !NiconicoApi.isProgramEnd(end)) return false;
    if (_programJustEnded) return false;
    if (end is! _ProgramEnded) _run.message(NiconicoDanmakuProtocol.programEnded());
    _programJustEnded = true;
    _reader = NiconicoMessageReader();
    _lastViewers = null;
    return true;
  }

  /// What `openSeat` throws for a room that cannot be watched now: it is
  /// offline, restricted or gone. Anything else may pass.
  static bool _unwatchable(Object error) =>
      error is StreamUnavailable || error is NeedsLogin || error is RegionBlocked || error is NotFound;

  /// Counts a failure: ends the run when [permanent] or when too many came
  /// in a row, else reports the first of a series and waits. True when the
  /// run goes on.
  Future<bool> _failed(Object error, {bool permanent = false}) async {
    if (!_run.isActive) return false;
    final detail = '$error';
    if (permanent) {
      _run.closed(DanmakuCloseReason.connectionFailed, detail: detail);
      return false;
    }
    _failures++;
    if (_failures > NiconicoDanmakuProtocol.maxFailures) {
      _run.closed(DanmakuCloseReason.reconnectsExhausted, detail: detail);
      return false;
    }
    if (_failures == 1) _run.reconnecting(DanmakuInterruption.disconnected, detail: detail);
    _settle();
    return await _run.delay(_owner._backoff(_failures));
  }

  /// The comment server answered: the failures in a row are over.
  void _joined() {
    _failures = 0;
    _programJustEnded = false;
    if (!_run.isConnected) _run.ready();
    _settle();
  }

  /// Follows the comment server while [seat] lasts. Returns why it stopped
  /// (the seat ended, a window said the program ended, the server refused
  /// the view, no comment server), or null when the run ended.
  Future<Object?> _read(NiconicoSeat seat) async {
    final view = await _messageServer(seat);
    if (!_run.isActive) return null;
    if (view == null) {
      return seat.isClosed
          ? (await seat.done ?? const StreamUnavailable(SiteIds.niconico, 'the seat was closed'))
          : FormatException('the seat named no comment server within ${_owner.messageServerTimeout.inMilliseconds} ms');
    }
    if (!NiconicoDanmakuProtocol.isCommentServer(view)) {
      return const FormatException('the seat named an unexpected comment server');
    }
    final cancel = CancelToken();
    Object? seatEnd;
    void end(Object reason) {
      seatEnd ??= reason;
      cancel.cancel();
    }

    unawaited(_cancel.whenCancelled.then((_) => cancel.cancel()));
    unawaited(
      seat.done.then((reason) => end(reason ?? const StreamUnavailable(SiteIds.niconico, 'the seat was closed'))),
    );
    final windows = <String>{};
    var at = 'now';
    try {
      while (_run.isActive) {
        if (seatEnd case final reason?) return reason;
        try {
          at = '${await _view(view, at, cancel, windows, end)}';
        } on Object catch (error) {
          if (!_run.isActive) return null;
          if (seatEnd case final reason?) return reason;
          if (error is _Refused && error.status >= 400 && error.status < 500) return error;
          if (!await _failed(error)) return null;
        }
      }
      return null;
    } finally {
      cancel.cancel();
    }
  }

  /// The seat's comment server once named; null when the seat ended, the run
  /// ended or it took too long.
  Future<Uri?> _messageServer(NiconicoSeat seat) async {
    for (var waited = Duration.zero; ; waited += NiconicoDanmakuProtocol.messageServerPoll) {
      final view = seat.messageServer;
      if (view != null || seat.isClosed) return view;
      if (waited >= _owner.messageServerTimeout) return null;
      if (!await _run.delay(NiconicoDanmakuProtocol.messageServerPoll)) return null;
    }
  }

  /// Reads one `view` answer for [at], opening each new window it announces
  /// (a window that says the program ended calls [end]); returns its `next`.
  Future<int> _view(Uri view, String at, CancelToken cancel, Set<String> windows, void Function(Object) end) async {
    final response = await _owner._http.open(
      NiconicoDanmakuProtocol.request(
        NiconicoDanmakuProtocol.viewUrl(view, at),
        timeout: at == 'now' ? NiconicoDanmakuProtocol.firstViewTimeout : NiconicoDanmakuProtocol.viewTimeout,
        cancel: cancel,
      ),
    );
    if (!response.isSuccess) {
      await _discard(response);
      throw _Refused(response.status);
    }
    int? next;
    await for (final bytes in NiconicoDanmakuProtocol.delimited(response.body)) {
      final NiconicoViewEntry entry;
      try {
        entry = NiconicoDanmakuProtocol.viewEntry(bytes);
      } on FormatException {
        continue;
      }
      if (!_run.isActive) break;
      _joined();
      switch (entry.kind) {
        case NiconicoViewEntryKind.segment:
          if (entry.window case final window?) _open(window, cancel, windows, end);
        case NiconicoViewEntryKind.next:
          next = entry.next ?? next;
        case NiconicoViewEntryKind.previous || NiconicoViewEntryKind.backward || NiconicoViewEntryKind.unknown:
          break;
      }
    }
    if (next == null) throw const FormatException('the view answer ended without next');
    return next;
  }

  /// Reads [window] unless it was read on this seat or too many are open.
  void _open(NiconicoCommentWindow window, CancelToken cancel, Set<String> windows, void Function(Object) end) {
    final key = '${window.uri}';
    if (windows.contains(key) || _openWindows >= NiconicoDanmakuProtocol.maxOpenWindows) return;
    windows.add(key);
    if (windows.length > NiconicoDanmakuProtocol.rememberedWindows) windows.remove(windows.first);
    _openWindows++;
    unawaited(_window(window, cancel, end).whenComplete(() => _openWindows--));
  }

  /// Reports the messages of [window] as they stream; a failure loses only
  /// the rest of this window. The program's end is reported, then ends the
  /// seat ([end]).
  Future<void> _window(NiconicoCommentWindow window, CancelToken cancel, void Function(Object) end) async {
    try {
      final response = await _owner._http.open(
        NiconicoDanmakuProtocol.request(
          window.uri,
          timeout: NiconicoDanmakuProtocol.windowTimeout(window.until, _owner._now()),
          cancel: cancel,
        ),
      );
      if (!response.isSuccess) {
        await _discard(response);
        return;
      }
      await for (final bytes in NiconicoDanmakuProtocol.delimited(response.body)) {
        if (!_run.isActive || cancel.isCancelled) return;
        final reader = _reader;
        final LiveMessage? message;
        try {
          message = reader.read(bytes);
        } on FormatException {
          continue;
        }
        if (message != null) _report(message);
        if (reader.endedProgram) {
          end(const _ProgramEnded());
          return;
        }
      }
    } on Object {
      // A lost window only loses its comments.
    }
  }

  /// Reports [message]; an audience figure only when it changed.
  void _report(LiveMessage message) {
    if (message.data case LiveAudienceUpdate(:final value)) {
      if (value == _lastViewers) return;
      _lastViewers = value;
    }
    _run.message(message);
  }

  static Future<void> _discard(LiveStreamedResponse response) async {
    try {
      await response.discard();
    } on Object {
      // Already closed.
    }
  }
}
