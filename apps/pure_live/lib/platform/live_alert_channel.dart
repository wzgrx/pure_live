import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/shared/rooms/room_texts.dart';

// "开播提醒" on Android (docs/O-Android系统集成/O01-通知和前台服务/O01.1-开播提醒;
// V01.1 L7): `pure_live/live_alerts` `post`, drawn by `LiveAlerts.kt`.

/// What the notification of [room] says (V01.1 L7): "晚风 开播了" (the
/// platform's name for a streamer without one) over the broadcast's title,
/// or "点按进入直播间" when there is none.
({String title, String text}) liveAlertContent(LiveRoom room) {
  final title = room.title.trim();
  return (
    title: i18n('live_alert_title', args: {'name': room.displayNick(platformName(room.platform))}),
    text: title.isEmpty ? i18n('live_alert_text_empty') : title,
  );
}

/// The arguments of `post`: the room to open (`platform`, `roomId`, and
/// `nick`, `roomTitle` for the room page before it loads), the words, the
/// broadcast's start (`since`, milliseconds since the epoch, shown as the
/// notification's time; null when the platform did not say) and the
/// channel's name and description.
Map<String, Object?> liveAlertArguments(LiveRoom room) {
  final content = liveAlertContent(room);
  return {
    'platform': room.platform,
    'roomId': room.roomId,
    'nick': room.nick.trim(),
    'roomTitle': room.title.trim(),
    'title': content.title,
    'text': content.text,
    'since': room.startedAt?.millisecondsSinceEpoch,
    'channel': i18n('live_alert_channel_name'),
    'channelDescription': i18n('live_alert_channel_desc'),
  };
}

/// Android's go-live notifications (`pure_live/live_alerts`).
final class LiveAlertChannel {
  /// Creates the poster over [channel].
  const new({this.channel = const MethodChannel('pure_live/live_alerts')});

  /// The native channel.
  final MethodChannel channel;

  /// Posts [room]'s notification; a missing native side or a refusal is
  /// only logged (notifications off: Android drops it).
  Future<void> post(LiveRoom room) async {
    try {
      await channel.invokeMethod<bool>('post', liveAlertArguments(room));
    } on PlatformException catch (error) {
      log('Live alert failed: ${error.message}', name: 'LiveAlerts');
    } on MissingPluginException {
      // A build without the native side.
    }
  }
}

/// Posts "开播提醒" where the platform can (Android), else null: the switch
/// is not offered and nothing is tracked.
final Provider<Future<void> Function(LiveRoom room)?> liveAlertPosterProvider = Provider(
  (ref) => !kIsWeb && Platform.isAndroid ? const LiveAlertChannel().post : null,
);
