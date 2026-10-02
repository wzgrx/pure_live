import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:live_core/live_core.dart';
import 'package:live_iptv/live_iptv.dart';
import 'package:path/path.dart' as p;
import 'package:pure_live/features/iptv/iptv_data.dart';
import 'package:pure_live/features/iptv/iptv_import.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/platform/share_channel.dart';
import 'package:pure_live/routes/route_path.dart';
import 'package:pure_live/shared/rooms/room_prompt.dart';
import 'package:pure_live/shared/rooms/share_code.dart';

/// How a payload was handled.
enum ShareOutcome {
  /// A page or room opened, or the share code was offered.
  opened,

  /// Files went to IPTV (some may have failed).
  imported,

  /// A room link that could not be opened.
  notFound,

  /// Nothing usable.
  unsupported,
}

/// What other apps share with Pure Live and what the launcher shortcuts and
/// notifications open (3.x `SharedMediaIntake` with `SharedLiveLinkOpener`;
/// M12.5 → F.0a, docs/ui/compare/U.14), one payload at a time, in 3.x's
/// order:
///
/// 1. a shortcut's or notification's page or room opens; only the pages of
///    [openableRoutes] (the launcher's and the recording notification's),
///    since any app can send the intent;
/// 2. a share code asks "打开分享的直播间" (U.3d's dialog, as 3.x);
/// 3. playlists (`.m3u`, `.m3u8`, `.txt`) and guides (`.xml`, `.gz`,
///    `.json`) are imported into IPTV: shared files, or a shared text that
///    is such a file's path or http(s) address;
/// 4. a platform link or share text opens its room: "正在打开分享的直播间…"
///    first (U.14 c11; short links take a request), a retired platform and
///    a link that does not resolve say so (3.x);
/// 5. anything else: "分享的内容里没有能打开的直播间链接", or for files
///    3.x's "不支持的文件格式，仅限 M3U 或 TXT" (U.14 c10).
///
/// The copies of shared files are deleted afterwards.
final class ShareIntake {
  /// Creates the intake.
  new({
    required this.links,
    required this.importer,
    required this.navigator,
    required this.openRoom,
    required this.openRoute,
    required this.notify,
    Future<RoomPromptChoice> Function(BuildContext context, LiveRoom room)? prompt,
    this.release = releaseSharedFile,
  }) : prompt = prompt ?? ((context, room) => showRoomPrompt(context, room: room, shared: true));

  /// Playlist extensions (3.x `SharedMediaIntake.playlistExtensions`).
  static const Set<String> playlistExtensions = {'.m3u', '.m3u8', '.txt'};

  /// Guide extensions (3.x `SharedMediaIntake.epgExtensions`).
  static const Set<String> guideExtensions = {'.xml', '.gz', '.json'};

  /// The pages an outside intent may open: the launcher shortcuts' "搜索直播"
  /// and "录制中心" (U.14 c15; the recording notification opens the latter).
  /// The open intent is exported with the launcher activity, so another app
  /// could name any route; the rest are ignored.
  static const Set<String> openableRoutes = {RoutePath.kSearch, RoutePath.kRecordPage};

  /// Finds rooms in shared text.
  final LinkParser links;

  /// IPTV imports; null where IPTV is not set up.
  final IptvImporter? importer;

  /// The navigator's context once pages show (a share can start the app),
  /// or null when it does not come.
  final Future<BuildContext?> Function() navigator;

  /// Opens a room.
  final Future<void> Function(LiveRoom room) openRoom;

  /// Opens a page.
  final Future<void> Function(String route) openRoute;

  /// Shows a message.
  final void Function(String message) notify;

  /// Asks about a shared code's room.
  final Future<RoomPromptChoice> Function(BuildContext context, LiveRoom room) prompt;

  /// Deletes a shared file's copy.
  final Future<void> Function(String path) release;

  Future<void> _queue = Future.value();

  /// Handles [payload] after the ones before it.
  Future<ShareOutcome> ingest(SharedPayload payload) {
    final run = _queue.then((_) => _ingest(payload));
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<ShareOutcome> _ingest(SharedPayload payload) async {
    try {
      final route = payload.route;
      final shortcut = payload.room;
      if (route != null && !openableRoutes.contains(route)) {
        log('Ignored an outside request for $route', name: 'ShareIntake');
        return ShareOutcome.unsupported;
      }
      if (route != null || shortcut != null) {
        final context = await navigator();
        if (context == null) return ShareOutcome.notFound;
        if (route != null) {
          unawaited(openRoute(route).catchError((Object _) {}));
        } else {
          final room = _roomOf(shortcut!);
          if (room == null) return ShareOutcome.unsupported;
          unawaited(openRoom(room).catchError((Object _) {}));
        }
        return ShareOutcome.opened;
      }

      final text = payload.text?.trim() ?? '';
      final code = text.isEmpty ? null : decodeRoomShareCode(text);
      if (code != null) {
        final context = await navigator();
        if (context == null || !context.mounted) return ShareOutcome.notFound;
        if (await prompt(context, code) == RoomPromptChoice.enter) {
          unawaited(openRoom(code).catchError((Object _) {}));
        }
        return ShareOutcome.opened;
      }

      final files = [
        for (final path in payload.files)
          if (iptvExtension(path) != null) (location: path, local: true),
        if (iptvExtension(text) != null) (location: _isHttp(text) ? text : _localPath(text), local: !_isHttp(text)),
      ];
      if (files.isNotEmpty) return await _importAll(files);

      if (text.isNotEmpty && (SiteIds.isRetiredLink(text) || links.containsSupportedLink(text))) {
        return await _openLink(text);
      }
      notify(i18n(payload.files.isNotEmpty ? 'unsupported_file_format' : 'share_intake_no_room'));
      return ShareOutcome.unsupported;
    } on Object catch (error, stack) {
      log('Share intake failed', name: 'ShareIntake', error: error, stackTrace: stack);
      notify(i18n('share_intake_no_room'));
      return ShareOutcome.unsupported;
    } finally {
      for (final path in payload.files) {
        try {
          await release(path);
        } on Object catch (error) {
          log('Shared file not released: $error', name: 'ShareIntake');
        }
      }
    }
  }

  static LiveRoom? _roomOf(Map<String, String> fields) {
    final platform = fields['platform']?.trim() ?? '';
    final roomId = fields['roomId']?.trim() ?? '';
    if (platform.isEmpty || roomId.isEmpty) return null;
    return LiveRoom(platform: platform, roomId: roomId, title: fields['title'] ?? '', nick: fields['nick'] ?? '');
  }

  /// 3.x `SharedLiveLinkOpener.open`, with "正在打开分享的直播间…" first.
  Future<ShareOutcome> _openLink(String text) async {
    final context = await navigator();
    if (context == null) return ShareOutcome.notFound;
    notify(i18n('share_intake_opening'));
    RoomLink? found;
    try {
      found = await links.parse(text);
    } on Object catch (error) {
      log('Shared link not resolved: $error', name: 'ShareIntake');
    }
    if (found == null || found.roomId.trim().isEmpty || !SiteIds.isSupported(found.platform)) {
      notify(i18n(SiteIds.isRetiredLink(text) ? 'platform_retired' : 'toolbox_parse_failed'));
      return ShareOutcome.notFound;
    }
    // The room route ends when the room closes; the queue does not wait.
    unawaited(openRoom(LiveRoom(platform: found.platform, roomId: found.roomId)).catchError((Object _) {}));
    return ShareOutcome.opened;
  }

  Future<ShareOutcome> _importAll(List<({String location, bool local})> files) async {
    final importer = this.importer;
    if (importer == null) {
      notify(i18n('unsupported_file_format'));
      return ShareOutcome.unsupported;
    }
    final messages = <String>[];
    for (final file in files) {
      final guide = guideExtensions.contains(iptvExtension(file.location));
      final IptvImportResult result;
      if (!file.local) {
        result = guide
            ? await importer.importGuideFromUrl(file.location, confirmReplace: _confirmGuide)
            : await importer.importPlaylistFromUrl(file.location, confirmReplace: _confirmPlaylist);
      } else {
        final local = File(file.location);
        result = guide
            ? await importer.importGuideFile(local, confirmReplace: _confirmGuide)
            : await importer.importPlaylistFile(local, confirmReplace: _confirmPlaylist);
      }
      messages.add(await _message(importer, result, guide: guide));
    }
    // 3.x showed one message per file, each replacing the last.
    notify(messages.last);
    return ShareOutcome.imported;
  }

  Future<bool> _confirmPlaylist(String name) => _confirm(name, IptvImportKind.playlist);

  Future<bool> _confirmGuide(String name) => _confirm(name, IptvImportKind.guide);

  /// The IPTV page's replace question (3.x asked the same for shares).
  Future<bool> _confirm(String name, IptvImportKind kind) async {
    final context = await navigator();
    return context != null && context.mounted && await confirmReplace(context, name, kind);
  }

  /// The IPTV page's words for [result].
  static Future<String> _message(IptvImporter importer, IptvImportResult result, {required bool guide}) async {
    if (result.status == IptvImportStatus.cancelled) return i18n('iptv_replace_declined');
    if (!result.isImported) return failureText(result, guide: guide) ?? i18n('iptv_save_failed');
    var name = '';
    try {
      final library = importer.library;
      final id = result.id ?? '';
      name = guide ? guideName((await library.guideSource(id))!) : playlistName((await library.playlist(id))!);
    } on Object {
      // The name is only for the message.
    }
    if (guide) return i18n('iptv_guide_imported', args: {'name': name});
    return result.issues.isEmpty
        ? i18n('iptv_playlist_imported', args: {'name': name})
        : i18n('iptv_playlist_imported_skipped', args: {'name': name, 'count': '${result.issues.length}'});
  }

  /// [text] as a file path (a `file:` URI is converted).
  static String _localPath(String text) {
    final uri = Uri.tryParse(text);
    return uri != null && uri.scheme.toLowerCase() == 'file' ? uri.toFilePath() : text;
  }

  static bool _isHttp(String text) {
    final uri = Uri.tryParse(text);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  /// The playlist or guide extension of [location] (a path, `file:` URI or
  /// http(s) address without spaces), else null (3.x
  /// `SharedMediaIntake._supportedExtension`).
  static String? iptvExtension(String location) {
    final trimmed = location.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return null;
    final uri = Uri.tryParse(trimmed);
    final path = switch (uri?.scheme.toLowerCase()) {
      'file' => uri!.toFilePath(),
      'http' || 'https' => uri!.path,
      _ => trimmed,
    };
    final extension = p.extension(path).toLowerCase();
    return playlistExtensions.contains(extension) || guideExtensions.contains(extension) ? extension : null;
  }
}
