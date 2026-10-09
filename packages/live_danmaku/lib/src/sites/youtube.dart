import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/codec/protobuf.dart';
import 'package:live_danmaku/src/connection.dart';
import 'package:live_danmaku/src/connection_base.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// What a watch page's `next` answer says about the broadcast's chat
/// ([YouTubeDanmakuProtocol.watch]).
@immutable
final class YouTubeChatEntry {
  /// Creates the entry.
  const new({this.continuation, this.replay = false, this.viewers});

  /// The first continuation of the chat (its default "Top chat" view), or
  /// null when the answer names no chat.
  final String? continuation;

  /// Whether the chat is a replay (`isReplay`): the broadcast is over.
  final bool replay;

  /// Concurrent viewers ("1,250 watching now"), or null when the answer
  /// has no live count.
  final int? viewers;

  /// Whether the broadcast has a live chat to poll.
  bool get live => continuation != null && !replay;
}

/// A gift of a [LiveMessageType.gift] message (`LiveMessage.data`): YouTube's
/// newer gift item, `giftMessageViewModel` ("sent Donut"; M5.F, B-23), as a
/// [LiveGift] (E05.5) of one, with [image] its picture. The item names no
/// price, count, channel or time.
@immutable
final class YouTubeGift extends LiveGift {
  /// Creates the gift.
  ///
  /// [name] is [text] without its leading `sent ` (`Donut`), the requests
  /// asking for English; empty when [text] is not written so.
  const new({required super.name, required this.text, this.image}) : super(iconUrl: image);

  /// `text.content`, trimmed: what the page shows after the sender's name
  /// (`sent Donut`).
  final String text;

  /// The largest `giftImage` source as an https URL, or null.
  final Uri? image;

  @override
  bool operator ==(Object other) =>
      super == other && other is YouTubeGift && other.text == text && other.image == image;

  @override
  int get hashCode => Object.hash(super.hashCode, text, image);

  @override
  String toString() => 'YouTubeGift($text)';
}

/// One `live_chat/get_live_chat` answer ([YouTubeDanmakuProtocol.chat]).
@immutable
final class YouTubeChatPoll {
  /// Creates the answer.
  const new({
    this.messages = const [],
    this.pinned = const [],
    this.continuation,
    this.reload = false,
    this.timeout,
    this.notice = '',
  });

  /// Chat lines, Super Chats, notices, gifts and retractions, in the order
  /// of the actions.
  final List<LiveMessage> messages;

  /// The Super Chats the ticker still pins (B-22), as replayed super chats,
  /// oldest first. The connection reports them from the first answer only,
  /// whose other items are the history it does not report.
  final List<LiveMessage> pinned;

  /// The continuation of the next request; null when the chat is over.
  final String? continuation;

  /// Whether [continuation] is a `reloadContinuationData`: its answer starts
  /// the chat over with the recent history, as the first answer does.
  final bool reload;

  /// The wait the server asks for (`timeoutMs`), or null.
  final Duration? timeout;

  /// When the chat is over: the site's message, such as "Chat is disabled
  /// for this live stream.", or empty.
  final String notice;

  /// Whether the chat is over: no continuation follows.
  bool get ended => continuation == null;
}

/// YouTube's live chat (docs/D-弹幕/D01-平台弹幕协议/D01.20-YouTube弹幕/record.md), without I/O: the
/// archived v4's spec/sites/youtube.md §7. The web client's InnerTube calls,
/// anonymous, as the adapter makes them (`YouTubeApi.webContext`,
/// `YouTubeApi.apiHeaders`):
///
/// 1. `next` for the broadcast names the chat's first continuation (a
///    `reloadContinuationData`) and the live viewer count;
/// 2. `live_chat/get_live_chat` is polled with the continuation of the
///    previous answer. The first answer is the recent history; later answers
///    carry what was said since. Each answer names the next continuation
///    and the wait (`timeoutMs`); an answer without one ends the chat;
/// 3. `updated_metadata` gives the viewer count again (M5.F, B-13).
///
/// Read from each answer (M5.F, B-13):
/// text messages as chat lines; paid messages and Super Stickers (D07.6)
/// as super chats; memberships and gifted memberships as notices; removals as
/// retractions; gifts (`giftMessageViewModel`) as gifts (B-23).
/// Placeholders, replacements, polls and banners are not read. A ticker item
/// names how long the page pins a Super Chat and, in the first answer, the
/// Super Chats still pinned (B-22).
abstract final class YouTubeDanmakuProtocol {
  /// The watch page's `next`.
  static final Uri nextEndpoint = YouTubeApi.apiUrl('next');

  /// The chat's `live_chat/get_live_chat`.
  static final Uri chatEndpoint = YouTubeApi.apiUrl('live_chat/get_live_chat');

  /// The watch page's `updated_metadata`: the live viewer count (B-13).
  static final Uri metadataEndpoint = YouTubeApi.apiUrl('updated_metadata');

  /// Request headers: the adapter's for the web client's InnerTube calls (UA,
  /// JSON, English, `SOCS=CAI`, the site as Referer and Origin); the JSON
  /// content type comes with the request.
  static Map<String, String> get headers => YouTubeApi.apiHeaders;

  /// Longest wait for one answer (v4's request default).
  static const Duration requestTimeout = Duration(seconds: 15);

  /// Shortest wait between two polls.
  static const Duration minimumDelay = Duration(seconds: 1);

  /// Longest wait between two polls, also when the server names none: the
  /// web client waits for pushed invalidations (`timeoutMs` 10 s) that a
  /// poller does not get, so polling sooner keeps the delay near the page's.
  static const Duration maximumDelay = Duration(seconds: 5);

  /// Wait after a failed request.
  static const Duration retryDelay = Duration(seconds: 2);

  /// Failed requests while joining (`next` and the first poll together)
  /// before the connection ends.
  static const int startAttempts = 3;

  /// Failed polls in a row, once joined, before the connection ends.
  static const int maxFailures = 8;

  /// How often `updated_metadata` is asked for once joined (B-13). The page
  /// asks every 5 s (its `timeoutMs`); a number on screen needs less, and
  /// each answer is about 8 KB.
  static const Duration viewerInterval = Duration(seconds: 30);

  /// How long a Super Chat the page does not pin stays in the super chat
  /// list: the two lowest tiers (blue, light blue: under US$5) are only
  /// highlighted in the chat, and an unknown colour says no tier. A minute,
  /// less than the shortest pin (2 minutes), so a dearer tier never ends
  /// sooner.
  static const Duration unpinnedDisplay = Duration(minutes: 1);

  /// How long the page pins a Super Chat by its tier, the tier told by
  /// `headerBackgroundColor` (ARGB); used when the answer has no ticker item
  /// (`fullDurationSec`) for the message. YouTube's table, in US dollars:
  /// under 2 blue, under 5 light blue (neither pinned), under 10 green
  /// 2 min, under 20 yellow 5 min, under 50 orange 10 min, under 100 magenta
  /// 30 min, from 100 red 1 h (to 5 h at 500; only the ticker tells).
  static const Map<int, Duration> tierDisplay = {
    0xFF1565C0: Duration.zero,
    0xFF00B8D4: Duration.zero,
    0xFF00BFA5: Duration(minutes: 2),
    0xFFFFB300: Duration(minutes: 5),
    0xFFE65100: Duration(minutes: 10),
    0xFFC2185B: Duration(minutes: 30),
    0xFFD00000: Duration(hours: 1),
  };

  /// The largest time `DateTime` holds, in microseconds from the epoch.
  static const int _maxMicros = 8640000000000000000;

  static final RegExp _digits = RegExp(r'^\d+$');

  /// The `next` request body for [videoId].
  static Map<String, Object?> nextBody(String videoId) => {'context': YouTubeApi.webContext, 'videoId': videoId};

  /// The `get_live_chat` request body for [continuation].
  static Map<String, Object?> chatBody(String continuation) => {
    'context': YouTubeApi.webContext,
    'continuation': continuation,
  };

  /// The first `updated_metadata` request body: [videoId], as the adapter
  /// asks.
  static Map<String, Object?> metadataBody(String videoId) => YouTubeApi.metadataBody(videoId);

  /// A later `updated_metadata` request body: the previous answer's
  /// [continuation].
  static Map<String, Object?> metadataContinuationBody(String continuation) =>
      YouTubeApi.continuationBody(continuation);

  /// The wait before the next poll: [timeout] within [minimumDelay] and
  /// [maximumDelay], and [maximumDelay] when there is none.
  static Duration pollDelay(Duration? timeout) => switch (timeout) {
    null => maximumDelay,
    final wait when wait > maximumDelay => maximumDelay,
    final wait when wait < minimumDelay => minimumDelay,
    final wait => wait,
  };

  /// The concurrent viewers as a message.
  static LiveMessage audience(int viewers) => LiveMessage(
    type: LiveMessageType.online,
    userName: '',
    message: '',
    data: LiveAudienceUpdate(kind: LiveAudienceMetricKind.onlineViewers, value: viewers),
    color: LiveMessageColor.white,
  );

  // The chat's view (B-13) -----------------------------------------------------

  static const int _chatField = 119693434;
  static const int _viewField = 16;
  static const int _viewKind = 1;
  static const int _topChat = 4;
  static const int _liveChat = 1;

  /// [continuation] in the "Live chat" view (every message) instead of the
  /// default "Top chat" (B-13). The token is a protobuf message in base64url
  /// (`=` written `%3D`); the view is field 1 of field 16 of its field
  /// 119693434: 4 for "Top chat", 1 for "Live chat". The two short
  /// continuations of `next`'s `viewSelector` differ only there, and they
  /// are refused on their own (400), so the chat's own continuation is
  /// rewritten; the server keeps the view in the continuations it answers
  /// with.
  ///
  /// Returns [continuation] itself when it already names "Live chat", and
  /// null when it cannot be rewritten: not such a message (a replay's
  /// continuation, a broken token), another view, the field more than once,
  /// or a fixed-width field or group on the way (not copied here).
  static String? allChatContinuation(String continuation) {
    final Uint8List bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(continuation.replaceAll('%3D', '=')));
    } on FormatException {
      return null;
    }
    final chat = _single(bytes, _chatField);
    final viewMessage = chat == null ? null : _single(chat, _viewField);
    final view = viewMessage == null ? null : _viewOf(viewMessage);
    if (view == _liveChat) return continuation;
    if (view != _topChat) return null;
    final rewritten = _rewrite(bytes, const [_chatField, _viewField, _viewKind], _topChat, _liveChat);
    return rewritten == null ? null : base64Url.encode(rewritten).replaceAll('=', '%3D');
  }

  /// The view (field 1, a varint) of a view message, or null.
  static int? _viewOf(Uint8List view) {
    final fields = _decode(view)?.where((field) => field.number == _viewKind).toList();
    if (fields == null || fields.length != 1 || fields.single.wireType != ProtoMessage.varintType) return null;
    return fields.single.value as int;
  }

  /// The only length-delimited field [number] of [bytes], or null.
  static Uint8List? _single(Uint8List bytes, int number) {
    final fields = _decode(bytes)?.where((field) => field.number == number).toList();
    if (fields == null || fields.length != 1 || fields.single.wireType != ProtoMessage.lengthDelimitedType) {
      return null;
    }
    return fields.single.value as Uint8List;
  }

  static List<ProtoField>? _decode(Uint8List bytes) {
    try {
      return ProtoMessage.decode(bytes).fields;
    } on FormatException {
      return null;
    }
  }

  /// [bytes] with the varint at [path] (field numbers, outermost first)
  /// changed from [from] to [to]; the other fields are copied as they were.
  /// Null when a message on the path holds the field more than once, a
  /// field that is not a varint or length-delimited, or the varint is not
  /// [from].
  static Uint8List? _rewrite(Uint8List bytes, List<int> path, int from, int to) {
    final fields = _decode(bytes);
    if (fields == null) return null;
    final [number, ...rest] = path;
    if (fields.where((field) => field.number == number).length != 1) return null;
    final writer = ProtoWriter();
    for (final ProtoField(number: current, :wireType, :value) in fields) {
      switch (wireType) {
        case ProtoMessage.varintType:
          if (current == number) {
            if (rest.isNotEmpty || value != from) return null;
            writer.integer(current, to);
          } else {
            writer.integer(current, value as int);
          }
        case ProtoMessage.lengthDelimitedType:
          if (current == number) {
            if (rest.isEmpty) return null;
            final inner = _rewrite(value as Uint8List, rest, from, to);
            if (inner == null) return null;
            writer.bytes(current, inner);
          } else {
            writer.bytes(current, value as Uint8List);
          }
        default:
          return null;
      }
    }
    return writer.toBytes();
  }

  // Answers ---------------------------------------------------------------------

  /// Reads a decoded `next` answer: the first `liveChatRenderer` in it (its
  /// `isReplay` and its first continuation) and the first live
  /// `videoViewCountRenderer` (the digits of "1,250 watching now", as the
  /// adapter reads them). Throws [FormatException] when [answer] is not a
  /// JSON object.
  static YouTubeChatEntry watch(Object? answer) {
    if (answer is! Map<String, Object?>) throw const FormatException('YouTube next: not a JSON object');
    Map<Object?, Object?>? chat;
    void walk(Object? node) {
      if (chat != null) return;
      if (node is Map) {
        if (node['liveChatRenderer'] case final Map<Object?, Object?> renderer) {
          chat = renderer;
          return;
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(answer);
    final renderer = chat;
    return YouTubeChatEntry(
      continuation: renderer == null ? null : _continuation(renderer['continuations'])?.token,
      replay: renderer?['isReplay'] == true,
      viewers: _liveViewers(answer),
    );
  }

  /// Reads a decoded `updated_metadata` answer (B-13): the live viewers, as
  /// [watch] reads them (null once the broadcast is over: "N views"), and
  /// the continuation of the next request (`continuation`'s first entry
  /// with a text `continuation`, a `timedContinuationData`). Throws
  /// [FormatException] when [answer] is not a JSON object.
  static ({int? viewers, String? continuation}) metadata(Object? answer) {
    if (answer is! Map<String, Object?>) throw const FormatException('YouTube updated_metadata: not a JSON object');
    String? token;
    if (answer['continuation'] case final Map<Object?, Object?> next) {
      for (final value in next.values) {
        if (value case {'continuation': final String continuation}) {
          token = continuation;
          break;
        }
      }
    }
    return (viewers: _liveViewers(answer), continuation: token);
  }

  /// The digits of the first `videoViewCountRenderer` with `isLive` true.
  static int? _liveViewers(Object? root) {
    int? walk(Object? node) {
      if (node is Map) {
        if (node['videoViewCountRenderer'] case final Map<Object?, Object?> count when count['isLive'] == true) {
          if (_viewers(count['viewCount']) case final viewers?) return viewers;
        }
        for (final value in node.values) {
          if (walk(value) case final viewers?) return viewers;
        }
      } else if (node is List) {
        for (final value in node) {
          if (walk(value) case final viewers?) return viewers;
        }
      }
      return null;
    }

    return walk(root);
  }

  static int? _viewers(Object? text) {
    final digits = _plain(text).replaceAll(RegExp('[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  /// Reads a decoded `get_live_chat` answer. Without
  /// `continuationContents.liveChatContinuation` the chat is over (the
  /// `contents` message, when there is one, is the notice). A Super Chat
  /// without a platform time starts [now] (default: the current time), the
  /// time the answer came; a pinned one ([YouTubeChatPoll.pinned]) ends the
  /// ticker's time left after it. Throws [FormatException] when [answer] is
  /// not a JSON object.
  static YouTubeChatPoll chat(Object? answer, {DateTime? now}) {
    if (answer is! Map<String, Object?>) throw const FormatException('YouTube get_live_chat: not a JSON object');
    final contents = answer['continuationContents'];
    final chat = contents is Map ? contents['liveChatContinuation'] : null;
    if (chat is! Map) {
      final message = answer['contents'];
      return YouTubeChatPoll(notice: message is Map ? _plain(_map(message['messageRenderer'])['text']) : '');
    }
    final actions = chat['actions'] is List ? chat['actions'] as List : const <Object?>[];
    final pinned = _pinned(actions);
    final received = now ?? DateTime.now();
    final next = _continuation(chat['continuations']);
    return YouTubeChatPoll(
      messages: List.unmodifiable([for (final action in actions) ?_message(action, pinned, received)]),
      pinned: List.unmodifiable(_stillPinned(actions, received)),
      continuation: next?.token,
      reload: next?.kind == 'reloadContinuationData',
      timeout: next?.timeout,
    );
  }

  /// The Super Chats the ticker items in [actions] still pin (B-22), as the
  /// page shows them when it opens: each `liveChatTickerPaidMessageItemRenderer`
  /// with time left (`durationSec`, a whole number above zero) carries the
  /// paid message it stands for (`showItemEndpoint.showLiveChatItemEndpoint
  /// .renderer.liveChatPaidMessageRenderer`, the same id as the message).
  ///
  /// Each is a replayed super chat ([_superChat]) from its own time to
  /// `durationSec` after [received]: `durationSec` is the time left when the
  /// server answered (S10: `fullDurationSec` less the time since
  /// `timestampUsec`, a few seconds less still), which the page counts down
  /// from when it gets the answer (`startCountdown(durationSec,
  /// fullDurationSec)`; `fullDurationSec` only scales its bar). Oldest first,
  /// the order they were sent in; an id seen before is left out.
  static List<LiveMessage> _stillPinned(List<Object?> actions, DateTime received) {
    final ids = <String>{};
    final found = <LiveMessage>[];
    for (final action in actions) {
      if (action case {
        'addLiveChatTickerItemAction': {
          'item': {'liveChatTickerPaidMessageItemRenderer': final Map<Object?, Object?> item},
        },
      }) {
        final left = item['durationSec'];
        if (left is! int || left <= 0) continue;
        if (item['showItemEndpoint'] case {
          'showLiveChatItemEndpoint': {'renderer': {'liveChatPaidMessageRenderer': final Map<Object?, Object?> paid}},
        }) {
          final message = _superChat(
            paid,
            const {},
            received,
            end: received.add(Duration(seconds: left)),
            replayed: true,
          );
          if (message == null || (message.messageId.isNotEmpty && !ids.add(message.messageId))) continue;
          found.add(message);
        }
      }
    }
    DateTime start(LiveMessage message) => (message.data! as LiveSuperChatMessage).startTime;
    final order = [...found.indexed]
      ..sort(
        (a, b) => switch (start(a.$2).compareTo(start(b.$2))) {
          0 => a.$1.compareTo(b.$1),
          final by => by,
        },
      );
    return [for (final (_, message) in order) message];
  }

  /// The first continuation of `continuations[0]`: its kind, token and
  /// `timeoutMs` (a whole number of zero or more).
  static ({String kind, String token, Duration? timeout})? _continuation(Object? continuations) {
    if (continuations is! List || continuations.isEmpty) return null;
    final first = continuations.first;
    if (first is! Map) return null;
    for (final MapEntry(:key, :value) in first.entries) {
      if (value case {'continuation': final String token}) {
        final timeout = value['timeoutMs'];
        return (
          kind: '$key',
          token: token,
          timeout: timeout is int && timeout >= 0 ? Duration(milliseconds: timeout) : null,
        );
      }
    }
    return null;
  }

  /// How long the page pins each item of the ticker items in [actions]
  /// (`addLiveChatTickerItemAction`): the item's `id` (the message's) and
  /// its `fullDurationSec`, when positive. The ticker item of a Super Chat
  /// follows it in the same answer.
  static Map<String, Duration> _pinned(List<Object?> actions) => {
    for (final action in actions)
      if (action case {'addLiveChatTickerItemAction': {'item': final Map<Object?, Object?> item}})
        for (final ticker in item.values)
          if (ticker case {'id': final String id, 'fullDurationSec': final int seconds}
              when id.isNotEmpty && seconds > 0)
            id: Duration(seconds: seconds),
  };

  /// One action as a message: an added item ([_item]), or a removal as a
  /// retraction; null for anything else.
  ///
  /// The page takes a message out of the list for `removeChatItemAction`
  /// and hides its text for `markChatItemAsDeletedAction` (both name it by
  /// `targetItemId`); `removeChatItemByAuthorAction` and
  /// `markChatItemsByAuthorAsDeletedAction` do so for every item whose
  /// `authorExternalChannelId` is their `externalChannelId`.
  static LiveMessage? _message(Object? action, Map<String, Duration> pinned, DateTime received) {
    if (action is! Map) return null;
    if (action['addChatItemAction'] case {'item': final Map<Object?, Object?> item}) {
      return _item(item, pinned, received);
    }
    for (final kind in const ['removeChatItemAction', 'markChatItemAsDeletedAction']) {
      if (action[kind] case {'targetItemId': final String id} when id.isNotEmpty) {
        return _retraction(LiveRetraction.message(id));
      }
    }
    for (final kind in const ['removeChatItemByAuthorAction', 'markChatItemsByAuthorAsDeletedAction']) {
      if (action[kind] case {'externalChannelId': final String id} when id.isNotEmpty) {
        return _retraction(LiveRetraction.user(id));
      }
    }
    return null;
  }

  /// A retraction: no id of its own (the removal has none), no sender.
  static LiveMessage _retraction(LiveRetraction target) => LiveMessage(
    type: LiveMessageType.retraction,
    userName: '',
    message: '',
    color: LiveMessageColor.white,
    data: target,
  );

  /// One added item: a text message as a chat line; a paid message and a
  /// Super Sticker (D07.6) as a super chat; a membership (joined, a
  /// milestone), gifted memberships and a received gift membership as a
  /// notice; a gift as a gift (B-23). Null for anything else and for items
  /// without text.
  static LiveMessage? _item(Map<Object?, Object?> item, Map<String, Duration> pinned, DateTime received) {
    if (item['liveChatTextMessageRenderer'] case final Map<Object?, Object?> text) return _chatLine(text);
    if (item['liveChatPaidMessageRenderer'] case final Map<Object?, Object?> paid) {
      return _superChat(paid, pinned, received);
    }
    if (item['giftMessageViewModel'] case final Map<Object?, Object?> gift) return _gift(gift);
    if (item['liveChatPaidStickerRenderer'] case final Map<Object?, Object?> sticker) {
      return _sticker(sticker, pinned, received);
    }
    if (item['liveChatMembershipItemRenderer'] case final Map<Object?, Object?> member) return _membership(member);
    if (item['liveChatSponsorshipsGiftPurchaseAnnouncementRenderer'] case final Map<Object?, Object?> gift) {
      final header = _map(_map(gift['header'])['liveChatSponsorshipsHeaderRenderer']);
      return _notice(gift, _plain(header['authorName']), _plain(header['primaryText']).trim());
    }
    if (item['liveChatSponsorshipsGiftRedemptionAnnouncementRenderer'] case final Map<Object?, Object?> gift) {
      return _notice(gift, _plain(gift['authorName']), _runs(gift['message']));
    }
    return null;
  }

  static LiveMessage? _chatLine(Map<Object?, Object?> renderer) {
    final text = _runs(renderer['message']);
    if (text.isEmpty) return null;
    return LiveMessage(
      type: LiveMessageType.chat,
      userName: _plain(renderer['authorName']),
      userId: _string(renderer['authorExternalChannelId']),
      message: text,
      messageId: _string(renderer['id']),
      sentAt: _time(renderer['timestampUsec']),
      color: LiveMessageColor.white,
      emotes: customEmoji(renderer['message']),
    );
  }

  /// A paid message (Super Chat) as a super chat: the amount as the page
  /// shows it (`purchaseAmountText`, in the buyer's currency, not
  /// converted) and a price of 0 (the answer has no number for it, only
  /// that text); the header and body colours; shown from the platform time
  /// (or [received]) for as long as the page pins it: the ticker item's
  /// `fullDurationSec`, else [tierDisplay] by the header colour, else
  /// [unpinnedDisplay]; or until [end] when given (a Super Chat still pinned
  /// on joining, [replayed]: B-22). Null without amount and text.
  static LiveMessage? _superChat(
    Map<Object?, Object?> paid,
    Map<String, Duration> pinned,
    DateTime received, {
    DateTime? end,
    bool replayed = false,
  }) {
    final amount = _plain(paid['purchaseAmountText']).trim();
    final text = _runs(paid['message']);
    if (amount.isEmpty && text.isEmpty) return null;
    final id = _string(paid['id']);
    final name = _plain(paid['authorName']);
    final time = _time(paid['timestampUsec']);
    final start = time ?? received;
    final tier = tierDisplay[paid['headerBackgroundColor']] ?? Duration.zero;
    final display = pinned[id] ?? (tier > Duration.zero ? tier : unpinnedDisplay);
    return LiveMessage(
      type: LiveMessageType.superChat,
      userName: name,
      userId: _string(paid['authorExternalChannelId']),
      message: text,
      messageId: id,
      sentAt: time,
      color: LiveMessageColor.white,
      replayed: replayed,
      emotes: customEmoji(paid['message']),
      data: LiveSuperChatMessage(
        messageId: id,
        userName: name,
        face: _photo(paid['authorPhoto']),
        message: text,
        price: 0,
        priceText: amount,
        startTime: start,
        endTime: end ?? start.add(display),
        backgroundColor: _color(paid['headerBackgroundColor']),
        backgroundBottomColor: _color(paid['bodyBackgroundColor']),
      ),
    );
  }

  /// A Super Sticker as a super chat (D07.6; was a notice): the page shows
  /// the name, the amount and the sticker. The amount is the page's
  /// (`purchaseAmountText`, in the buyer's currency) with a price of 0, as a
  /// Super Chat's; the text is the sticker's description
  /// (`sticker.accessibility`), the picture its largest thumbnail
  /// ([LiveSuperChatMessage.image]); both colours the card's
  /// `backgroundColor`; shown as long as the ticker pins it, else by the
  /// colour's tier ([tierDisplay]), else [unpinnedDisplay]. Null without an
  /// amount, a description or a picture.
  static LiveMessage? _sticker(Map<Object?, Object?> sticker, Map<String, Duration> pinned, DateTime received) {
    final amount = _plain(sticker['purchaseAmountText']).trim();
    final picture = _map(sticker['sticker']);
    final label = _accessibility(picture);
    final image = _largest(picture['thumbnails']);
    if (amount.isEmpty && label.isEmpty && image.isEmpty) return null;
    final id = _string(sticker['id']);
    final name = _plain(sticker['authorName']);
    final time = _time(sticker['timestampUsec']);
    final start = time ?? received;
    final tier = tierDisplay[sticker['backgroundColor']] ?? Duration.zero;
    final display = pinned[id] ?? (tier > Duration.zero ? tier : unpinnedDisplay);
    final colour = _color(sticker['backgroundColor']);
    return LiveMessage(
      type: LiveMessageType.superChat,
      userName: name,
      userId: _string(sticker['authorExternalChannelId']),
      message: label,
      messageId: id,
      sentAt: time,
      color: LiveMessageColor.white,
      data: LiveSuperChatMessage(
        messageId: id,
        userName: name,
        face: _photo(sticker['authorPhoto']),
        message: label,
        price: 0,
        priceText: amount,
        startTime: start,
        endTime: start.add(display),
        backgroundColor: colour,
        backgroundBottomColor: colour,
        image: image,
      ),
    );
  }

  /// A membership as a notice: a new member's `headerSubtext` ("Welcome to
  /// …!"), or a milestone's `headerPrimaryText` ("Member for 15 months")
  /// with the level (`headerSubtext`, in full-width brackets) and the
  /// member's message (after a full-width colon), all as the platform wrote
  /// them. Null without a header.
  static LiveMessage? _membership(Map<Object?, Object?> member) {
    final primary = _plain(member['headerPrimaryText']).trim();
    final subtext = _plain(member['headerSubtext']).trim();
    final header = primary.isEmpty ? subtext : (subtext.isEmpty ? primary : '$primary（$subtext）');
    if (header.isEmpty) return null;
    final text = _runs(member['message']);
    return _notice(
      member,
      _plain(member['authorName']),
      text.isEmpty ? header : '$header：$text',
      emotes: customEmoji(member['message']),
    );
  }

  /// A gift (`giftMessageViewModel`, B-23) as the page shows it: the
  /// sender's name (`authorName.content`, trimmed) and the text after it
  /// (`text.content`, trimmed: `sent Donut`), with the gift's image
  /// (`giftImage.sources`); the item's id. The text is the shared
  /// `Donut ×1` (E05.5: was the page's English `sent Donut`), or the page's
  /// text when it is not written `sent <name>`. The recorded items have no
  /// channel id or time; they are read when present. Null without text.
  static LiveMessage? _gift(Map<Object?, Object?> gift) {
    final text = _content(gift['text']);
    if (text.isEmpty) return null;
    final image = _largest(_map(gift['giftImage'])['sources']);
    final present = YouTubeGift(
      name: text.startsWith(_giftVerb) ? text.substring(_giftVerb.length).trim() : '',
      text: text,
      image: image.isEmpty ? null : Uri.tryParse(image),
    );
    return LiveMessage(
      type: LiveMessageType.gift,
      userName: _content(gift['authorName']),
      userId: _string(gift['authorExternalChannelId']),
      message: present.name.isEmpty ? text : present.plainText,
      messageId: _string(gift['id']),
      sentAt: _time(gift['timestampUsec']),
      color: LiveMessageColor.white,
      data: present,
    );
  }

  /// How the page's English text starts a gift's name (`sent Donut`).
  static const String _giftVerb = 'sent ';

  /// The `content` of a view model's text, trimmed, or empty.
  static String _content(Object? node) => switch (node) {
    {'content': final String content} => content.trim(),
    _ => '',
  };

  /// A notice of kind [LiveNoticeKind.subscription]: [name] and [text] as
  /// one line, the item's id, time and sender. Null without [text].
  static LiveMessage? _notice(
    Map<Object?, Object?> renderer,
    String name,
    String text, {
    List<LiveEmote> emotes = const [],
  }) {
    if (text.isEmpty) return null;
    return LiveMessage(
      type: LiveMessageType.notice,
      userName: name,
      userId: _string(renderer['authorExternalChannelId']),
      message: name.trim().isEmpty ? text : '${name.trim()} $text',
      messageId: _string(renderer['id']),
      sentAt: _time(renderer['timestampUsec']),
      color: LiveMessageColor.white,
      data: LiveNoticeKind.subscription,
      emotes: emotes,
    );
  }

  /// The text of a message's runs, trimmed: text runs as written; an emoji
  /// as the character it is (`emojiId`), a channel's custom emoji as its
  /// shortcut (`:name:`), which is what the page shows as its text.
  static String _runs(Object? message) {
    final runs = message is Map ? message['runs'] : null;
    if (runs is! List) return '';
    final out = StringBuffer();
    for (final run in runs) {
      if (run is! Map) continue;
      if (run['text'] case final String text) {
        out.write(text);
      } else if (run['emoji'] case final Map<Object?, Object?> emoji) {
        out.write(_emoji(emoji));
      }
    }
    return out.toString().trim();
  }

  /// The channel's custom emoji among a message's runs (M13.16, B-13): each
  /// shortcut ([_runs] writes it into the text) with its largest picture
  /// (`image.thumbnails`), once per shortcut. Standard emoji are characters
  /// in the text and need no picture.
  static List<LiveEmote> customEmoji(Object? message) {
    final runs = message is Map ? message['runs'] : null;
    if (runs is! List) return const [];
    final seen = <String>{};
    return [
      for (final run in runs)
        if (run case {'emoji': final Map<Object?, Object?> emoji} when emoji['isCustomEmoji'] == true)
          if ((_emoji(emoji), _largest(_map(emoji['image'])['thumbnails'])) case (final code, final url)
              when code.isNotEmpty && url.isNotEmpty && seen.add(code))
            LiveEmote(code: code, url: url),
    ];
  }

  static String _emoji(Map<Object?, Object?> emoji) {
    final shortcuts = emoji['shortcuts'];
    final shortcut = shortcuts is List && shortcuts.isNotEmpty ? _string(shortcuts.first) : '';
    if (emoji['isCustomEmoji'] == true) return shortcut;
    final id = _string(emoji['emojiId']);
    return id.isNotEmpty ? id : shortcut;
  }

  /// `{simpleText}` as written, or `{runs}` joined.
  static String _plain(Object? node) {
    if (node is! Map) return '';
    if (node['simpleText'] case final String text) return text;
    final runs = node['runs'];
    if (runs is! List) return '';
    return [
      for (final run in runs)
        if (run is Map && run['text'] is String) run['text']! as String,
    ].join();
  }

  /// `accessibility.accessibilityData.label`, trimmed, or empty.
  static String _accessibility(Object? node) => switch (node) {
    {'accessibility': {'accessibilityData': {'label': final String label}}} => label.trim(),
    _ => '',
  };

  /// The last (largest) thumbnail of an `authorPhoto` as an https URL (a
  /// protocol-relative one made https), or empty.
  static String _photo(Object? photo) => _largest(photo is Map ? photo['thumbnails'] : null);

  /// The last (largest) of [images] (`[{url, width, height}]`) as an https
  /// URL (a protocol-relative one made https), or empty.
  static String _largest(Object? images) {
    if (images is! List || images.isEmpty) return '';
    final url = switch (images.last) {
      {'url': final String url} => url.trim(),
      _ => '',
    };
    if (url.startsWith('https://')) return url;
    if (url.startsWith('//')) return 'https:$url';
    return '';
  }

  /// An ARGB colour (a whole number of 32 bits) as `#rrggbb`, or empty.
  static String _color(Object? value) =>
      value is int && value >= 0 && value <= 0xFFFFFFFF ? '${LiveMessageColor.numberToColor(value)}' : '';

  static String _string(Object? value) => value is String ? value : '';

  static Map<Object?, Object?> _map(Object? value) => value is Map<Object?, Object?> ? value : const {};

  /// `timestampUsec` (decimal text or a whole number) as a time; null when
  /// it is not positive or out of `DateTime`'s range.
  static DateTime? _time(Object? value) {
    final micros = switch (value) {
      final int number => number,
      final String text when _digits.hasMatch(text.trim()) => int.tryParse(text.trim()),
      _ => null,
    };
    if (micros == null || micros <= 0 || micros > _maxMicros) return null;
    return DateTime.fromMicrosecondsSinceEpoch(micros);
  }
}

/// YouTube's danmaku connection: the live chat of the broadcast on air
/// (`YouTubeDanmakuArgs.videoId`), polled over [LiveHttp]; no socket, no
/// heartbeat.
///
/// - `connect` joins: `next` for the first continuation and the viewer count,
///   then the first poll, whose answer (the recent history) is not reported.
///   A failed request is tried again 2 s later; the third failure while
///   joining ends the run with [DanmakuCloseReason.connectionFailed], as
///   does a broadcast without a live chat (not live, chat off, a replay) or
///   an argument that is not a video id. Joined, it reports [DanmakuReady],
///   the viewers of `next` and the Super Chats the first answer's ticker
///   still pins, replayed (B-22).
/// - With `allChat`, the chat is read in the page's "Live chat" view (every
///   message) instead of "Top chat" (B-13): the first continuation, and any
///   reload continuation later, is asked for rewritten
///   ([YouTubeDanmakuProtocol.allChatContinuation]). A continuation that
///   cannot be rewritten is asked for as it came; one the server refuses
///   (a 4xx, or an answer without a chat) is asked for again as it came,
///   and the run stays with "Top chat". Neither is a failure.
/// - Each poll waits for the previous one, then the wait the answer asked
///   for (`timeoutMs`, within 1–5 s, 5 s when none). An answer to a reload
///   continuation is history again and is not reported.
/// - A failed poll is tried again 2 s later with the same continuation; the
///   first failure in a row reports [DanmakuReconnecting], the eighth ends
///   with [DanmakuCloseReason.reconnectsExhausted], and an answer after
///   failures reports [DanmakuReady] again.
/// - An answer without a continuation ends with
///   [DanmakuCloseReason.connectionFailed] (the chat is over: the broadcast
///   ended); the room detail names the channel's next broadcast.
/// - Every 30 s once joined, `updated_metadata` gives the viewer count
///   again (B-13): first by video id, then with the continuation of the
///   previous answer. A failed request is not reported (the next turn asks
///   by video id again) and does not touch the chat.
///
/// The app registers it as `SiteIds.youtube: () =>
/// YouTubeDanmakuConnection(http: …, allChatOf: …)`, with the `LiveHttp` it
/// gives `YouTubeSite` (the `youtube` proxy route and throttle) and the
/// "show all chat" setting (default off, as the page).
final class YouTubeDanmakuConnection extends DanmakuConnectionBase<YouTubeDanmakuArgs> {
  /// Creates the connection; `http` sends the chat requests, `allChat` reads
  /// the "Live chat" view instead of "Top chat" (default off, as the page);
  /// `allChatOf`, when given, is asked instead at every start, so a changed
  /// setting applies to the next connect (C01.6); [now] is the clock a
  /// Super Chat without a platform time starts at.
  new({required this._http, this._allChat = false, this._allChatOf, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final LiveHttp _http;
  final bool _allChat;
  final bool Function()? _allChatOf;
  final DateTime Function() _now;

  @override
  @protected
  Future<void> start(YouTubeDanmakuArgs args, DanmakuRun run) async {
    final videoId = args.videoId.trim();
    if (!YouTubeApi.isVideoId(videoId)) {
      throw const DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: 'No broadcast');
    }
    final chat = _YouTubeChat(_http, run, allChat: _allChatOf?.call() ?? _allChat, now: _now);
    YouTubeChatEntry? entry;
    YouTubeChatPoll? history;
    for (var failures = 0; history == null;) {
      try {
        final watch = entry ??= YouTubeDanmakuProtocol.watch(
          await chat.post(YouTubeDanmakuProtocol.nextEndpoint, YouTubeDanmakuProtocol.nextBody(videoId)),
        );
        if (!run.isActive) return;
        if (!watch.live) {
          throw DanmakuStartFailure(
            DanmakuCloseReason.connectionFailed,
            detail: watch.replay ? 'Chat replay only' : 'No live chat',
          );
        }
        history = await chat.poll(watch.continuation!, restart: true);
      } on DanmakuStartFailure {
        rethrow;
      } on Object catch (error) {
        if (!run.isActive) return;
        if (++failures >= YouTubeDanmakuProtocol.startAttempts) {
          throw DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: '$error');
        }
        if (!await run.delay(YouTubeDanmakuProtocol.retryDelay)) return;
      }
    }
    if (!run.isActive) return;
    if (history.ended) throw DanmakuStartFailure(DanmakuCloseReason.connectionFailed, detail: _ended(history));
    run.ready();
    if (entry?.viewers case final viewers?) run.message(YouTubeDanmakuProtocol.audience(viewers));
    // The history is not reported, but the Super Chats still pinned are, as
    // the page shows them on opening (B-22).
    history.pinned.forEach(run.message);
    unawaited(chat.follow(history));
    unawaited(chat.viewers(videoId));
  }

  static String _ended(YouTubeChatPoll poll) => poll.notice.isEmpty ? 'Chat ended' : 'Chat ended: ${poll.notice}';
}

/// The chat of one run: its requests, cancelled when the run ends.
final class _YouTubeChat {
  new(this._http, this._run, {required this._allChat, required this._now}) {
    unawaited(_run.ended.then((_) => _cancel.cancel()));
  }

  final LiveHttp _http;
  final DanmakuRun _run;
  final DateTime Function() _now;
  final CancelToken _cancel = CancelToken();

  /// Whether a continuation that starts the chat over is asked for in the
  /// "Live chat" view; off once the server refused it.
  bool _allChat;

  /// Sends [body] to [url] and returns the answer decoded; throws
  /// `HttpStatusFailure`, `TransportFailure` or [FormatException].
  Future<Object?> post(Uri url, Map<String, Object?> body) => _http.postJson(
    SiteIds.youtube,
    url,
    json: body,
    headers: YouTubeDanmakuProtocol.headers,
    timeout: YouTubeDanmakuProtocol.requestTimeout,
    cancel: _cancel,
  );

  /// Asks for [continuation]. One that starts the chat over ([restart]: the
  /// first, or a reload) is asked for in the "Live chat" view first when
  /// that is on; a refusal (a 4xx, or an answer without a chat) turns it off
  /// and asks for [continuation] as it came.
  Future<YouTubeChatPoll> poll(String continuation, {required bool restart}) async {
    if (_allChat && restart) {
      final live = YouTubeDanmakuProtocol.allChatContinuation(continuation);
      if (live != null && live != continuation) {
        try {
          final answer = await _chat(live);
          if (!answer.ended) return answer;
        } on HttpStatusFailure catch (failure) {
          if (failure.status < 400 || failure.status >= 500) rethrow;
        }
        _allChat = false;
        if (!_run.isActive) throw const TransportFailure(SiteIds.youtube, TransportReason.cancelled);
      }
    }
    return await _chat(continuation);
  }

  Future<YouTubeChatPoll> _chat(String continuation) async {
    final answer = await post(YouTubeDanmakuProtocol.chatEndpoint, YouTubeDanmakuProtocol.chatBody(continuation));
    return YouTubeDanmakuProtocol.chat(answer, now: _now());
  }

  /// Polls after [previous] until the chat is over, the failures run out or
  /// the run ends.
  Future<void> follow(YouTubeChatPoll previous) async {
    var last = previous;
    var wait = YouTubeDanmakuProtocol.pollDelay(last.timeout);
    var failures = 0;
    while (await _run.delay(wait)) {
      final YouTubeChatPoll poll;
      try {
        poll = await this.poll(last.continuation!, restart: last.reload);
      } on Object catch (error) {
        if (!_run.isActive) return;
        if (++failures >= YouTubeDanmakuProtocol.maxFailures) {
          _run.closed(DanmakuCloseReason.reconnectsExhausted, detail: '$error');
          return;
        }
        if (failures == 1) _run.reconnecting(DanmakuInterruption.disconnected, detail: '$error');
        wait = YouTubeDanmakuProtocol.retryDelay;
        continue;
      }
      if (!_run.isActive) return;
      if (failures > 0) {
        failures = 0;
        _run.ready();
      }
      // The answer to a reload continuation starts over with the history.
      if (!last.reload) poll.messages.forEach(_run.message);
      if (poll.ended) {
        _run.closed(DanmakuCloseReason.connectionFailed, detail: YouTubeDanmakuConnection._ended(poll));
        return;
      }
      last = poll;
      wait = YouTubeDanmakuProtocol.pollDelay(poll.timeout);
    }
  }

  /// Every [YouTubeDanmakuProtocol.viewerInterval] until the run ends, the
  /// live viewer count of `updated_metadata` (B-13): first by [videoId],
  /// then with the previous answer's continuation. A failure is not
  /// reported; the next turn asks by [videoId] again.
  Future<void> viewers(String videoId) async {
    String? continuation;
    while (await _run.delay(YouTubeDanmakuProtocol.viewerInterval)) {
      try {
        final update = YouTubeDanmakuProtocol.metadata(
          await post(
            YouTubeDanmakuProtocol.metadataEndpoint,
            continuation == null
                ? YouTubeDanmakuProtocol.metadataBody(videoId)
                : YouTubeDanmakuProtocol.metadataContinuationBody(continuation),
          ),
        );
        if (!_run.isActive) return;
        continuation = update.continuation;
        if (update.viewers case final viewers?) _run.message(YouTubeDanmakuProtocol.audience(viewers));
      } on Object {
        if (!_run.isActive) return;
        continuation = null;
      }
    }
  }
}
