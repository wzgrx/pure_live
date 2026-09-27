import 'dart:convert';

import 'package:live_cli/src/danmaku/frame_scrub.dart';
import 'package:live_cli/src/danmaku/recorder.dart';

/// Steam broadcasts (spec/sites/steambroadcast.md §11): chat authors
/// (`steamid`, `persona_name`, `instance_id`), moderator ids and the
/// per-viewer `viewertoken` of `getbroadcastmpd`. Chat text stays.
class SteamBroadcastFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(frame.bytes));
    } on FormatException {
      return frame.bytes;
    }
    if (json is Map<String, dynamic>) {
      if (json['viewertoken'] != null) {
        json['viewertoken'] = names.secret('${json['viewertoken']}');
        record(r'$.viewertoken', 'secret');
      }
      final moderators = json['moderators_steamid'];
      if (moderators is List) {
        json['moderators_steamid'] = [for (final id in moderators) names.digits('$id')];
        if (moderators.isNotEmpty) record(r'$.moderators_steamid', 'person');
      }
      final messages = json['messages'];
      if (messages is List) {
        for (final message in messages.whereType<Map<String, dynamic>>()) {
          if (message['steamid'] != null) message['steamid'] = names.digits('${message['steamid']}');
          if (message['persona_name'] is String) {
            message['persona_name'] = names.person(message['persona_name'] as String);
          }
          final instance = message['instance_id'];
          if (instance is int) message['instance_id'] = int.parse(names.digits('$instance'));
        }
        if (messages.isNotEmpty) record(r'$.messages[*]', 'person');
      }
    }
    var text = jsonEncode(json);
    // A name quoted again inside a chat line gets the same pseudonym.
    for (final MapEntry(key: original, value: replacement) in names.pairs) {
      if (RegExp(r'^\d+$').hasMatch(original)) {
        if (original.length >= 5) text = text.replaceAll(RegExp('(?<![0-9])$original(?![0-9])'), replacement);
      } else if (original.runes.length >= 2) {
        text = text.replaceAll(original, replacement);
      }
    }
    return utf8.encode(text);
  }
}
