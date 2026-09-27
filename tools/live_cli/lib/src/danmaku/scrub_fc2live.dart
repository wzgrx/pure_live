import 'dart:convert';

import 'package:live_cli/src/danmaku/frame_scrub.dart';
import 'package:live_cli/src/danmaku/recorder.dart';

/// FC2 Live (spec/sites/fc2live.md §11): the anonymous control grant
/// (`control_token`, `orz`, `orz_raw`, also in the socket URL) and comment
/// authors (`user_name` unless anonymous, `encrypted_user_id`, `orz_token`,
/// `hash`). Comment text stays; the admin NG keyword list is dropped.
class Fc2LiveFrameScrubber extends FrameScrubber {
  /// Creates the scrubber.
  new(super.detail, {super.seed});

  static const _grantKeys = ['control_token', 'orz', 'orz_raw'];

  @override
  Uri scrubUrl(Uri url) {
    final token = url.queryParameters['control_token'];
    if (token == null) return url;
    record('url:control_token', 'secret');
    return url.replace(queryParameters: {...url.queryParameters, 'control_token': names.secret(token)});
  }

  @override
  List<int>? scrubFrame(CapturedFrame frame) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(frame.bytes));
    } on FormatException {
      return frame.bytes;
    }
    if (json is! Map<String, dynamic>) return frame.bytes;
    if (json['name'] == 'ng_comment') return null;
    for (final key in _grantKeys) {
      if (json[key] is String) {
        json[key] = names.secret(json[key] as String);
        record('\$.$key', 'secret');
      }
    }
    final arguments = json['arguments'];
    if (json['name'] == 'comment' && arguments is Map<String, dynamic> && arguments['comments'] is List) {
      for (final comment in (arguments['comments'] as List).whereType<Map<String, dynamic>>()) {
        final name = comment['user_name'];
        if (name is String && name != '[anonymous]') comment['user_name'] = names.person(name);
        for (final key in const ['encrypted_user_id', 'orz_token', 'hash']) {
          if (comment[key] is String) comment[key] = names.secret(comment[key] as String);
        }
      }
      record(r'$.arguments.comments[*]', 'person');
    }
    return utf8.encode(jsonEncode(json));
  }
}
