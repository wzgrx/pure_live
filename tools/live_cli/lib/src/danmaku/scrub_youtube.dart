import 'dart:convert';

import 'package:live_cli/src/danmaku/frame_scrub.dart';
import 'package:live_cli/src/danmaku/recorder.dart';

/// YouTube live chat (spec/sites/youtube.md §7, §11). The InnerTube answers
/// are large and name this visitor; the capture keeps only what the chat
/// reader uses: from `next` the `conversationBar` (the chat's first
/// continuation), from `get_live_chat` the continuations and actions.
/// Chat authors (`authorName`, `authorExternalChannelId`, photos, context
/// menu parameters) are replaced or dropped; tracking parameters are
/// dropped. Chat text stays, with authors' names quoted in it replaced.
class YouTubeFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  static const _dropped = {
    'clickTrackingParams',
    'trackingParams',
    'contextMenuEndpoint',
    'contextMenuAccessibility',
    'authorPhoto',
    'clientId',
    'loggingDirectives',
  };

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(frame.bytes));
    } on FormatException {
      return frame.bytes;
    }
    if (json is! Map<String, dynamic>) return frame.bytes;
    final Object kept;
    final contents = json['contents'];
    if (contents is Map && contents['twoColumnWatchNextResults'] is Map) {
      final bar = (contents['twoColumnWatchNextResults'] as Map)['conversationBar'];
      kept = {
        'contents': {
          'twoColumnWatchNextResults': {'conversationBar': _clean(bar)},
        },
      };
      record(r'next: all but $.contents.twoColumnWatchNextResults.conversationBar', 'dropped');
    } else if (json['continuationContents'] is Map) {
      final chat = (json['continuationContents'] as Map)['liveChatContinuation'];
      kept = {
        'continuationContents': {
          'liveChatContinuation': {
            if (chat is Map) 'continuations': _clean(chat['continuations']),
            if (chat is Map) 'actions': _clean(chat['actions']),
          },
        },
      };
      record('get_live_chat: all but continuations and actions', 'dropped');
    } else {
      kept = _clean(json)!;
    }
    var text = jsonEncode(kept);
    // A name quoted again inside a chat line gets the same pseudonym.
    for (final MapEntry(key: original, value: replacement) in names.pairs) {
      if (original.runes.length >= 3) text = text.replaceAll(original, replacement);
    }
    return utf8.encode(text);
  }

  Object? _clean(Object? node) {
    if (node is List) return [for (final item in node) _clean(item)];
    if (node is! Map) return node;
    final out = <String, Object?>{};
    for (final MapEntry(:key, :value) in node.entries) {
      if (_dropped.contains(key)) {
        record('\$..$key', 'dropped');
        continue;
      }
      switch (key) {
        case 'authorName' when value is Map && value['simpleText'] is String:
          out['authorName'] = {'simpleText': names.person(value['simpleText'] as String)};
          record(r'$..authorName', 'person');
        case 'authorExternalChannelId' || 'externalChannelId' when value is String:
          out[key as String] = names.secret(value);
          record('\$..$key', 'person');
        default:
          out['$key'] = _clean(value);
      }
    }
    return out;
  }
}
