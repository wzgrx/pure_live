import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:pure_live/app/services.dart';
import 'package:pure_live/i18n/i18n.dart';
import 'package:pure_live/routes/app_navigator.dart';

/// The two things the toolbox does with a link.
enum ToolboxAction {
  /// Open the room.
  jump,

  /// Copy a stream address.
  directLink,
}

/// The link parser of the toolbox (tests replace it).
final Provider<LinkParser> toolboxLinksProvider = Provider<LinkParser>(
  (ref) => LinkParser(ref.watch(sitesProvider), ref.watch(appServicesProvider).http),
);

/// The platform adapter for a platform id, or null (tests replace it).
final Provider<LiveSite? Function(String platform)> toolboxSiteProvider = Provider<LiveSite? Function(String)>(
  (ref) => ref.watch(sitesProvider).maybeOf,
);

/// Asks the user to pick one of [items]; null when they cancel.
typedef ToolboxChooser<T> = Future<T?> Function(List<T> items);

/// The user left or cancelled: no message.
final class ToolboxCancelled implements Exception {
  /// Creates the signal.
  const new();
}

/// The toolbox's work on a link (3.x `ToolBoxController` and
/// `ToolBoxDirectLinkFlow`): one action at a time, every platform request
/// limited to [timeout], cancelled when the user cancels, edits the link or
/// leaves. Messages go to [notify] as text keys.
final class ToolboxController extends ChangeNotifier {
  /// Creates the controller.
  new({
    required this.links,
    required this.siteOf,
    this.openRoom = AppNavigator.toLiveRoomDetail,
    this.copy = _copy,
    this.notify = _toast,
    this.timeout = const Duration(seconds: 12),
  });

  /// Finds the room of a link.
  final LinkParser links;

  /// The adapter of a platform.
  final LiveSite? Function(String platform) siteOf;

  /// Opens the live room.
  final Future<void> Function({required LiveRoom liveRoom}) openRoom;

  /// Puts text on the clipboard.
  final Future<void> Function(String text) copy;

  /// Shows a message by text key.
  final void Function(String key) notify;

  /// The limit of each platform request (3.x: 12 seconds).
  final Duration timeout;

  ToolboxAction? _action;
  CancelToken? _cancel;
  bool _disposed = false;

  /// The running action, or null.
  ToolboxAction? get action => _action;

  /// Whether an action runs.
  bool get isBusy => _action != null;

  /// Stops the running action quietly.
  void cancel() => _cancel?.cancel();

  @override
  void dispose() {
    cancel();
    _disposed = true;
    super.dispose();
  }

  static Future<void> _copy(String text) => Clipboard.setData(ClipboardData(text: text));

  static void _toast(String key) => AppNavigator.toast(i18n(key));

  /// Opens the room of [text] (3.x `jumpToRoom`).
  Future<void> jump(String text) => _run(text, ToolboxAction.jump, (link, cancel) async {
    final room = await _resolve(link, cancel);
    if (room == null) return;
    // The live room opening is not timed: it ends when the user leaves it.
    await openRoom(liveRoom: room);
  });

  /// Copies a stream address of the room of [text]: pick a quality, then a
  /// line (3.x `getPlayUrl`).
  Future<void> directLink(
    String text, {
    required ToolboxChooser<LivePlayQuality> chooseQuality,
    required ToolboxChooser<String> chooseLine,
  }) => _run(text, ToolboxAction.directLink, (link, cancel) async {
    final room = await _resolve(link, cancel);
    if (room == null) return;
    final site = siteOf(room.platform);
    if (site == null) {
      notify('toolbox_parse_failed');
      return;
    }
    final detail = await _timed(cancel, () => site.getRoomDetail(roomId: room.roomId));
    if (detail.effectiveLiveStatus == LiveStatus.offline || detail.effectiveLiveStatus == LiveStatus.banned) {
      notify('toolbox_room_offline');
      return;
    }
    final qualities = await _timed(cancel, () => site.discoverPlayQualities(detail: detail, cancel: cancel));
    if (qualities.isEmpty) {
      notify('toolbox_quality_failed');
      return;
    }
    // The user's choices have no time limit.
    final quality = qualities.length == 1 ? qualities.single : await _untimed(cancel, () => chooseQuality(qualities));
    if (quality == null) return;
    final resolution = await _timed(cancel, () => site.resolvePlayUrls(detail: detail, quality: quality));
    // An owned source plays only inside the app (relay, session seat).
    if (resolution.inputRecipe != null) {
      notify('toolbox_session_source');
      return;
    }
    final urls = resolution.urls;
    if (urls.isEmpty) {
      notify('toolbox_get_url_failed');
      return;
    }
    final url = urls.length == 1 ? urls.single : await _untimed(cancel, () => chooseLine(urls));
    if (url == null) return;
    try {
      await copy(url);
    } on Object {
      notify('toolbox_copy_failed');
      return;
    }
    notify('toolbox_copy_success');
  });

  Future<void> _run(
    String text,
    ToolboxAction action,
    Future<void> Function(String link, CancelToken cancel) work,
  ) async {
    if (_disposed || isBusy) return;
    final link = text.trim();
    if (link.isEmpty) {
      notify('toolbox_empty_link');
      return;
    }
    final cancel = _cancel = CancelToken();
    _action = action;
    notifyListeners();
    try {
      await work(link, cancel);
    } on ToolboxCancelled {
      // Cancelling, editing and leaving are the user's choice.
    } on Object catch (error) {
      if (!cancel.isCancelled && !_disposed) {
        notify(switch ((action, error)) {
          (_, TimeoutException()) => 'toolbox_timeout',
          (ToolboxAction.jump, _) => 'toolbox_parse_failed',
          (ToolboxAction.directLink, _) => 'toolbox_get_url_failed',
        });
      }
    } finally {
      cancel.cancel();
      if (identical(_cancel, cancel)) {
        _cancel = null;
        _action = null;
        if (!_disposed) notifyListeners();
      }
    }
  }

  /// The room [link] points to, or null after telling the user why not.
  Future<LiveRoom?> _resolve(String link, CancelToken cancel) async {
    if (SiteIds.isRetiredLink(link)) {
      notify('platform_retired');
      return null;
    }
    final found = await links.parse(link, cancel: cancel, timeout: timeout);
    _check(cancel);
    if (found == null || !SiteIds.isSupported(found.platform) || found.roomId.trim().isEmpty) {
      notify('toolbox_parse_failed');
      return null;
    }
    return LiveRoom(platform: found.platform, roomId: found.roomId, watching: '');
  }

  Future<T> _timed<T>(CancelToken cancel, Future<T> Function() work) => _untimed(cancel, () => work().timeout(timeout));

  Future<T> _untimed<T>(CancelToken cancel, Future<T> Function() work) async {
    _check(cancel);
    final result = await Future.any<T>([work(), cancel.whenCancelled.then<T>((_) => throw const ToolboxCancelled())]);
    _check(cancel);
    return result;
  }

  void _check(CancelToken cancel) {
    if (cancel.isCancelled || _disposed) throw const ToolboxCancelled();
  }
}

/// Platforms whose links the toolbox reads, in display order.
List<LiveSite> linkPlatforms(SiteRegistry registry) => [
  for (final site in registry.sites)
    if (site is LiveSiteLinks && site.id != SiteIds.iptv) site,
];
