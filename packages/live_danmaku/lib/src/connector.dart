import 'dart:async';

import 'package:live_core/live_core.dart';
import 'package:live_danmaku/src/model.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// A chat connection to one room (spec/modules/danmaku.md §2).
///
/// [events] carries every decoded message unfiltered; the pipeline
/// (`DanmakuPipeline`) filters, samples and batches them. A connector is
/// single-use: after [close] it cannot connect again; after a terminal
/// failure ([DanmakuStatus.closed]) [connect] starts over.
abstract interface class DanmakuConnector {
  /// The room.
  RoomRef get room;

  /// Token stamped on every event (CONN-4).
  int get session;

  /// Decoded messages and status notices.
  Stream<DanmakuEvent> get events;

  /// Starts connecting; completes with true once joined, false when the
  /// start failed terminally. A second call while running returns the same
  /// result.
  Future<bool> connect();

  /// Stops reconnecting and closes the socket; completes within 5 s.
  Future<void> close();
}

/// What a decoder needs to stamp events.
@immutable
final class DecodeContext {
  /// Creates a context.
  const new({required this.room, required this.session, required this.receivedAt, required this.now});

  /// `platform:roomId`.
  final String room;

  /// Session token.
  final int session;

  /// Monotonic receive time, microseconds.
  final int receivedAt;

  /// Wall-clock receive time.
  final DateTime now;
}

/// What decoding one received frame produced.
@immutable
final class FrameResult {
  /// Creates a result.
  const new({this.events = const [], this.replies = const [], this.joined = false, this.rejected = false});

  /// Nothing to report.
  static const empty = FrameResult();

  /// Unified messages, in frame order.
  final List<DanmakuEvent> events;

  /// Frames to send back at once (acknowledgements).
  final List<List<int>> replies;

  /// The server accepted the join (Bilibili auth reply `code == 0`).
  final bool joined;

  /// The server refused the credentials; reconnect with new ones.
  final bool rejected;
}

/// Credentials that live with the platform adapters on the UI isolate: the
/// app implements this on top of its site instances (they own the cookie
/// vault, buvid and WBI sessions). Connectors call it before connecting and
/// after a rejection.
abstract interface class DanmakuCredentials {
  /// Bilibili's `getDanmuInfo` for [room] (`BilibiliSite.danmakuInfo`).
  Future<BilibiliDanmakuInfo> bilibili(RoomDetail room);

  /// The cookie for [platform]'s chat requests, or null: Douyin's session
  /// cookie (`DouyinSite.sessionCookie`), the user's Kuaishou cookie.
  Future<String?> cookie(String platform);
}

/// [DanmakuCredentials] from the v4 site adapters.
final class SiteDanmakuCredentials implements DanmakuCredentials {
  /// Creates the credentials; a missing adapter makes that platform's
  /// request fail, a missing [cookies] vault means no user cookies.
  new({this.bilibiliSite, this.douyinSite, this.cookies});

  /// Source of Bilibili tokens.
  final BilibiliSite? bilibiliSite;

  /// Source of the Douyin session cookie.
  final DouyinSite? douyinSite;

  /// The user's cookies for the other platforms.
  final CookieVault? cookies;

  @override
  Future<BilibiliDanmakuInfo> bilibili(RoomDetail room) {
    final site = bilibiliSite;
    if (site == null) throw StateError('No Bilibili adapter for danmaku credentials');
    return site.danmakuInfo(room);
  }

  @override
  Future<String?> cookie(String platform) async {
    if (platform == 'douyin') return await douyinSite?.sessionCookie();
    final cookie = cookies?.cookieFor(platform)?.trim();
    return cookie == null || cookie.isEmpty ? null : cookie;
  }
}

/// Raised inside connectors when a start cannot proceed; reported as a
/// [DanmakuStatus.closed] notice, never thrown to the caller.
final class DanmakuStartFailure implements Exception {
  /// Creates the failure; [reason] is a code (`credentials`, `rejected`).
  const new(this.reason, [this.detail]);

  /// Reason code.
  final String reason;

  /// Diagnostic detail without cookies or tokens.
  final String? detail;

  @override
  String toString() => 'DanmakuStartFailure($reason${detail == null ? '' : ': $detail'})';
}
