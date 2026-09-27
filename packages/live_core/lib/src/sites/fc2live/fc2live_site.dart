import 'dart:async';

import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/fc2live/fc2live_control.dart';
import 'package:live_core/src/sites/fc2live/fc2live_parse.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_core/src/text_socket.dart';
import 'package:live_net/live_net.dart';

const _site = 'fc2live';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// A control socket kept open for a channel while its lease is renewed.
final class _Held {
  new(this.control, this.expiry);

  final Fc2Control control;
  Timer expiry;
}

/// The FC2 Live adapter (spec/sites/fc2live.md): the live directory with
/// the site's category filters, channel details, and HLS authorised by a
/// held control socket.
///
/// **Control lease** (§6.3): `streams` opens the channel's control socket
/// (the media server only serves playlists whose socket is open when they
/// are first requested) and returns lines whose [Lease] asks for a refresh
/// after [renewEvery]. Each `streams` call for the same channel reuses the
/// open socket and extends it to [holdFor]; a socket whose lease is not
/// renewed in time is closed. The playback session's prefetch at
/// `refreshAt` is the keep-alive signal, as for niconico seats.
final class Fc2LiveSite implements LiveSite, CatalogSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter. The connect function opens control sockets (by
  /// default over `dart:io` on the platform's proxy route of an
  /// [IoLiveHttp]); [now] is injectable for tests.
  new(
    this.http, {
    this._connect,
    DateTime Function()? now,
    this.renewEvery = const Duration(seconds: 60),
    this.holdFor = const Duration(seconds: 150),
  }) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  /// Lease refresh interval of a line (§6.3).
  final Duration renewEvery;

  /// How long a control socket stays open after the last `streams` call (§6.3).
  final Duration holdFor;

  final DateTime Function() _now;
  final TextSocketConnect? _connect;
  final Map<String, _Held> _held = {};

  @override
  String get id => _site;

  @override
  String get name => 'FC2ライブ';

  TextSocketConnect get _socket {
    final connect = _connect;
    if (connect != null) return connect;
    final client = http;
    final route = client is IoLiveHttp
        ? client.proxy.routeFor(_site, Uri.parse('wss://live.fc2.com/'))
        : const DirectRoute();
    return ioTextSocketConnect(route, pingInterval: const Duration(seconds: 15));
  }

  static const Map<String, String> _headers = {
    'origin': 'https://live.fc2.com',
    'referer': 'https://live.fc2.com/',
    'x-requested-with': 'XMLHttpRequest',
    'accept': 'application/json, text/javascript, */*; q=0.01',
    'user-agent': _userAgent,
  };

  Future<String> _post(String path, Map<String, String> form) async {
    final url = Uri.https('live.fc2.com', path);
    final LiveResponse response;
    try {
      response = await http.send(LiveRequest.form(site: _site, url: url, fields: form, headers: _headers));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    final status = response.status;
    if (status == 401 || status == 403) throw RiskControl(_site, detail: 'HTTP $status $path');
    if (status == 429) throw RateLimited(_site, detail: 'HTTP 429 $path');
    if (status >= 500) throw NetworkFailure(_site, 'HTTP $status $path');
    if (status != 200) throw ApiChanged(_site, 'HTTP $status $path');
    return response.text;
  }

  Future<String> _directory() => _post('/contents/allchannellist.php', const {});

  @override
  Future<List<Category>> categories() async => const [Fc2LiveParse.category];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    if (!Fc2LiveParse.areas.any((a) => a.id == area.id)) throw NotFound(_site, 'no area ${area.id}');
    if (cursor != null) return const Page.empty();
    return Fc2LiveParse.page(await _directory(), area: area);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) async {
    if (cursor != null) return const Page.empty();
    return Fc2LiveParse.page(await _directory());
  }

  Future<Fc2Member> _member(String roomId) async {
    if (!Fc2LiveParse.channelId.hasMatch(roomId)) throw NotFound(_site, 'not an FC2 channel id: $roomId');
    return Fc2LiveParse.member(
      await _post('/api/memberApi.php', {'channel': '1', 'profile': '1', 'user': '1', 'streamid': roomId}),
      roomId: roomId,
    );
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _member(ref.roomId)).detail;

  /// §6.3 the open control socket of [channel], extended to [holdFor].
  Fc2Control? _reuse(String channel) {
    final held = _held[channel];
    if (held == null) return null;
    if (!held.control.isOpen) {
      held.expiry.cancel();
      _held.remove(channel);
      return null;
    }
    held.expiry.cancel();
    held.expiry = Timer(holdFor, () => unawaited(_release(channel)));
    return held.control;
  }

  Future<void> _release(String channel) async {
    final held = _held.remove(channel);
    held?.expiry.cancel();
    await held?.control.close();
  }

  /// §6.1 a fresh control grant for a live channel that needs no payment
  /// or login. The chat connector uses it too: it holds its own control
  /// socket for the comments.
  Future<Fc2Grant> controlGrant(String channel) async {
    final member = await _member(channel);
    if (member.detail.state != LiveState.live) throw const StreamUnavailable(_site, 'not on air');
    if (member.restricted) throw const NeedsLogin(_site, 'paid, ticket or login-only channel');
    return Fc2LiveParse.grant(
      await _post('/api/getControlServer.php', {
        'channel_id': channel,
        'mode': 'play',
        'orz': '',
        'channel_version': member.version,
        'client_version': '2.1.0\n [1]',
        'client_type': 'pc',
        'client_app': 'browser_hls',
        'ipv6': '',
      }),
      roomId: channel,
    );
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final channel = room.ref.roomId;
    var control = _reuse(channel);
    if (control == null) {
      final grant = await controlGrant(channel);
      control = _reuse(channel);
      if (control == null) {
        final opened = await Fc2Control.open(grant, connect: _socket);
        _held[channel] = _Held(opened, Timer(holdFor, () => unawaited(_release(channel))));
        unawaited(opened.done.then((_) => _held[channel]?.control == opened ? _release(channel) : null));
        control = opened;
      }
    }
    final now = _now();
    final lease = Lease(refreshAt: now.add(renewEvery), expiresAt: now.add(holdFor), cutsConnection: false);
    const headers = {'origin': 'https://live.fc2.com', 'referer': 'https://live.fc2.com/', 'user-agent': _userAgent};
    final offered = [
      for (final q in Fc2LiveParse.qualities)
        if (Fc2LiveParse.line(control.playlists, q, headers: headers) != null) q,
    ];
    if (offered.isEmpty) throw const StreamUnavailable(_site, 'no video playlist');
    final selected = offered.firstWhere((q) => q.id == quality?.id, orElse: () => offered.first);
    final line = Fc2LiveParse.line(control.playlists, selected, headers: headers, lease: lease)!;
    return StreamSet(qualities: offered, selected: selected, lines: [line]);
  }

  /// Closes every held control socket.
  Future<void> close() async {
    for (final channel in [..._held.keys]) {
      await _release(channel);
    }
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (Fc2LiveParse.channelId.hasMatch(text)) return RoomRef(_site, text);
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    final url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null || url.host.toLowerCase() != 'live.fc2.com') return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final id = switch (segments) {
      [final id] => id,
      [final locale, final id] when Fc2LiveParse.locales.contains(locale.toLowerCase()) => id,
      _ => null,
    };
    return id != null && Fc2LiveParse.channelId.hasMatch(id) ? RoomRef(_site, id) : null;
  }
}
