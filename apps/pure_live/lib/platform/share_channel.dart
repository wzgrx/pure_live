import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// What arrived from outside the app (Android): another app's share or
/// "open with" (`SEND`, `SEND_MULTIPLE`, `VIEW`: the text and the files,
/// copied into the app's cache by the native side), or a launcher shortcut
/// or notification that opens a page ([route], the recording centre at a
/// [task]) or a room ([room]).
@immutable
final class SharedPayload {
  /// Creates a payload.
  const new({this.text, this.files = const [], this.route, this.task, this.room});

  /// Reads the channel's map `{text, files: [{path, name}], route, task,
  /// room: {platform, roomId, title, nick}}`; anything else is an empty
  /// payload.
  factory fromChannel(Object? value) {
    if (value is! Map) return const SharedPayload();
    final text = value['text'];
    final files = value['files'];
    final route = value['route'];
    final task = value['task'];
    final room = value['room'];
    return SharedPayload(
      text: text is String && text.trim().isNotEmpty ? text : null,
      files: [
        if (files is List)
          for (final file in files)
            if (file is Map && file['path'] is String && (file['path'] as String).isNotEmpty) file['path'] as String,
      ],
      route: route is String && route.startsWith('/') ? route : null,
      task: task is String && task.trim().isNotEmpty ? task.trim() : null,
      room: room is Map
          ? {
              for (final MapEntry(:key, :value) in room.entries)
                if (key is String && value is String) key: value,
            }
          : null,
    );
  }

  /// The shared text, or null.
  final String? text;

  /// Local copies of the shared files.
  final List<String> files;

  /// A page to open (a shortcut or a notification), or null.
  final String? route;

  /// The recording task the page points at (the "录制已停止" reminder opens
  /// the recording centre at its task, F02 c2), or null.
  final String? task;

  /// A room to open (`platform`, `roomId`, `title`, `nick`; a recent-room
  /// shortcut), or null.
  final Map<String, String>? room;

  /// Whether nothing arrived.
  bool get isEmpty => (text?.trim().isEmpty ?? true) && files.isEmpty && route == null && room == null;
}

/// One recent room of the launcher's shortcuts.
typedef RecentRoomShortcut = ({String platform, String roomId, String title, String nick});

/// The native side of [SharedPayload]s, the clipboard's change time and the
/// launcher's recent-room shortcuts (`pure_live/share_intake`,
/// `ShareIntakePlugin.kt`; 3.x used the share_handler plugin). Android
/// only; elsewhere nothing arrives.
final class ShareChannel {
  /// Creates the channel.
  new({this.channel = const MethodChannel('pure_live/share_intake'), bool? android})
    : _android = android ?? (!kIsWeb && Platform.isAndroid);

  /// The native channel.
  final MethodChannel channel;

  final bool _android;

  /// Whether anything arrives here.
  bool get available => _android;

  /// Hands every payload to [onShared]: first the ones that arrived before
  /// (the share or shortcut that started the app), then each new one.
  Future<void> listen(void Function(SharedPayload payload) onShared) async {
    if (!_android) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'shared') onShared(SharedPayload.fromChannel(call.arguments));
    });
    try {
      final pending = await channel.invokeListMethod<Object?>('listen') ?? const [];
      for (final value in pending) {
        onShared(SharedPayload.fromChannel(value));
      }
    } on PlatformException catch (error) {
      log('Share channel failed: ${error.message}', name: 'ShareChannel');
    } on MissingPluginException {
      // A build without the native side.
    }
  }

  /// When the clipboard last changed (from the clip's description, which
  /// Android does not report as a clipboard access); -1 when it is empty,
  /// null when unknown (other platforms).
  Future<int?> clipboardStamp() async {
    if (!_android) return null;
    try {
      return await channel.invokeMethod<int>('clipboardStamp');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Puts [rooms] (newest first, at most two) behind the launcher icon's
  /// long press (docs/T13/T13a/T13a.1 c15).
  Future<void> setRecentRooms(List<RecentRoomShortcut> rooms) async {
    if (!_android) return;
    try {
      await channel.invokeMethod<void>('setRecentRooms', [
        for (final room in rooms)
          {'platform': room.platform, 'roomId': room.roomId, 'title': room.title, 'nick': room.nick},
      ]);
    } on PlatformException catch (error) {
      log('Recent-room shortcuts failed: ${error.message}', name: 'ShareChannel');
    } on MissingPluginException {
      // A build without the native side.
    }
  }
}

/// Deletes the native side's copy of a shared file (its folder
/// `share_intake/<random>` in the cache); other paths are left alone.
Future<void> releaseSharedFile(String path) async {
  final folder = File(path).parent;
  if (p.basename(folder.parent.path) != 'share_intake') return;
  try {
    await folder.delete(recursive: true);
  } on FileSystemException catch (error) {
    log('Shared file not deleted: ${error.message}', name: 'ShareChannel');
  }
}
