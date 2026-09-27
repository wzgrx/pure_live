import 'dart:async';

import 'package:live_core/src/live_state.dart';
import 'package:live_core/src/page.dart';
import 'package:live_core/src/room.dart';
import 'package:live_core/src/room_ref.dart';
import 'package:live_core/src/site.dart';
import 'package:live_core/src/site_error.dart';
import 'package:live_core/src/sites/niconico/niconico_parse.dart';
import 'package:live_core/src/sites/niconico/niconico_seat.dart';
import 'package:live_core/src/stream.dart';
import 'package:live_net/live_net.dart';

const _site = 'niconico';

Map<Object?, Object?> _obj(Object? value) => value is Map ? value : const <Object?, Object?>{};
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

/// A seat kept open for a program while its lease is renewed.
final class _Held {
  new(this.seat, this.expiry);

  final NiconicoSeat seat;
  Timer expiry;
}

/// The niconico live adapter (spec/sites/niconico.md): recent programs by
/// tab, on-air search, watch pages, and the HLS grant of a watching seat.
///
/// **Seat lease** (§6.4): `streams` opens a seat (a WebSocket that must stay
/// open while the grant is played) and returns a line whose [Lease] asks
/// for a refresh after [renewEvery]. Each `streams` call for the same
/// program reuses the open seat and extends it to [holdFor]; a seat whose
/// lease is not renewed in time is closed. The playback session's prefetch
/// at `refreshAt` is therefore the keep-alive signal: while something plays
/// the line, the seat stays; when playback stops, the seat closes within
/// [holdFor].
final class NiconicoSite implements LiveSite, CatalogSource, SearchSource, RoomSource, StreamSource, LinkResolver {
  /// Creates the adapter. The connect function opens seat sockets (by default over
  /// `dart:io` on the platform's proxy route of an [IoLiveHttp]); [now] is
  /// injectable for tests.
  new(
    this.http, {
    this._connect,
    DateTime Function()? now,
    this.renewEvery = const Duration(seconds: 60),
    this.holdFor = const Duration(seconds: 150),
  }) : _now = now ?? DateTime.now;

  /// Transport.
  final LiveHttp http;

  /// Lease refresh interval of a line (§6.4).
  final Duration renewEvery;

  /// How long a seat stays open after the last `streams` call (§6.4).
  final Duration holdFor;

  final DateTime Function() _now;
  final NiconicoConnect? _connect;
  final Map<String, _Held> _held = {};
  final Map<String, String> _programOf = {};

  @override
  String get id => _site;

  @override
  String get name => 'niconico';

  NiconicoConnect get _socket {
    final connect = _connect;
    if (connect != null) return connect;
    final client = http;
    final route = client is IoLiveHttp
        ? client.proxy.routeFor(_site, Uri.parse('wss://a.live2.nicovideo.jp/'))
        : const DirectRoute();
    return ioNiconicoConnect(route);
  }

  static const Map<String, String> _headers = {
    'accept': 'application/json, text/html;q=0.9, */*;q=0.8',
    'accept-language': 'ja,en;q=0.8',
    'user-agent': _userAgent,
  };

  Future<LiveResponse> _get(Uri url) async {
    final LiveResponse response;
    try {
      response = await http.send(LiveRequest(site: _site, url: url, headers: _headers));
    } on TransportFailure catch (failure) {
      if (failure.reason == TransportReason.cancelled) rethrow;
      throw NetworkFailure(_site, failure.toString());
    }
    final status = response.status;
    if (status == 403) throw RiskControl(_site, detail: 'HTTP 403 ${url.path}');
    if (status == 429) throw RateLimited(_site, detail: 'HTTP 429 ${url.path}');
    if (status >= 500) throw NetworkFailure(_site, 'HTTP $status ${url.path}');
    return response;
  }

  @override
  Future<List<Category>> categories() async => const [
    Category(id: NiconicoParse.categoryId, name: 'カテゴリ', areas: NiconicoParse.areas),
  ];

  @override
  Future<Page<RoomCard>> areaRooms(Area area, {PageCursor? cursor}) async {
    if (!NiconicoParse.areas.any((a) => a.id == area.id)) throw NotFound(_site, 'no area ${area.id}');
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final url = Uri.https('live.nicovideo.jp', '/front/api/pages/recent/v1/programs', {
      'tab': area.id,
      'offset': '${page - 1}',
      'sortOrder': 'recentDesc',
    });
    final response = await _get(url);
    if (response.status != 200) throw ApiChanged(_site, 'recent HTTP ${response.status}');
    return NiconicoParse.recent(response.text, page: page);
  }

  @override
  Future<Page<RoomCard>> recommended({PageCursor? cursor}) => areaRooms(NiconicoParse.areas.first, cursor: cursor);

  @override
  Future<Page<RoomCard>> search(String keyword, {PageCursor? cursor}) async {
    final query = keyword.trim();
    if (query.isEmpty) return const Page.empty();
    final page = int.tryParse(cursor?.value ?? '') ?? 1;
    final url = Uri.https('live.nicovideo.jp', '/front/api/pages/search/v1/programs', {
      'keyword': query,
      'column': 'main',
      'status': 'onair',
      'page': '$page',
      'disableGrouping': 'true',
    });
    final response = await _get(url);
    if (response.status != 200) throw ApiChanged(_site, 'search HTTP ${response.status}');
    return NiconicoParse.search(response.text, page: page);
  }

  Future<NiconicoWatch> _watch(String roomId) async {
    if (!NiconicoParse.roomId.hasMatch(roomId)) throw NotFound(_site, 'not a room id: $roomId');
    final response = await _get(NiconicoParse.link(roomId));
    if (response.status == 404) throw NotFound(_site, 'watch page $roomId');
    if (response.status != 200) throw ApiChanged(_site, 'watch page HTTP ${response.status}');
    final watch = NiconicoParse.watch(response.text, roomId: roomId);
    _programOf[roomId] = watch.programId;
    return watch;
  }

  @override
  Future<RoomDetail> detail(RoomRef ref) async => (await _watch(ref.roomId)).detail;

  /// §6.2 the seat socket URL of [ref]'s program on air. The chat connector
  /// uses it to open a seat of its own (the comment server is announced on
  /// the seat, §7).
  Future<Uri> seatSocket(RoomRef ref) async {
    final watch = await _watch(ref.roomId);
    if (watch.detail.state != LiveState.live) throw const StreamUnavailable(_site, 'not on air');
    final denied = watch.denied;
    if (denied != null) throw denied;
    final socket = watch.webSocket;
    if (socket == null) throw const ApiChanged(_site, 'watch page: no webSocketUrl');
    return socket;
  }

  /// §6.4 the open seat for [program], extended to [holdFor].
  NiconicoSeat? _reuse(String? program) {
    if (program == null) return null;
    final held = _held[program];
    if (held == null) return null;
    if (!held.seat.isOpen) {
      held.expiry.cancel();
      _held.remove(program);
      return null;
    }
    held.expiry.cancel();
    held.expiry = Timer(holdFor, () => unawaited(_release(program)));
    return held.seat;
  }

  Future<void> _release(String program) async {
    final held = _held.remove(program);
    held?.expiry.cancel();
    await held?.seat.close();
  }

  @override
  Future<StreamSet> streams(RoomDetail room, {Quality? quality}) async {
    final roomId = room.ref.roomId;
    var seat = _reuse(_programOf[roomId] ?? (NiconicoParse.programId.hasMatch(roomId) ? roomId : null));
    if (seat == null) {
      final watch = await _watch(roomId);
      if (watch.detail.state != LiveState.live) throw const StreamUnavailable(_site, 'not on air');
      final denied = watch.denied;
      if (denied != null) throw denied;
      final socket = watch.webSocket;
      if (socket == null) throw const ApiChanged(_site, 'watch page: no webSocketUrl');
      seat = _reuse(watch.programId);
      if (seat == null) {
        final opened = await NiconicoSeat.open(socket, connect: _socket);
        final program = watch.programId;
        _held[program] = _Held(opened, Timer(holdFor, () => unawaited(_release(program))));
        unawaited(opened.done.then((_) => _held[program]?.seat == opened ? _release(program) : null));
        seat = opened;
      }
    }
    final grant = seat.grant;
    final now = _now();
    const auto = Quality(id: 'abr', label: '自动', rank: 1);
    final line = StreamLine(
      url: grant.master,
      format: StreamFormat.hls,
      lineId: 'dlive',
      requested: auto,
      headers: {
        // Only the playlists' cookies fit one header; segments and keys need
        // their own (§6.3, cookieFile).
        'cookie': grant.cookieHeader(grant.master),
        'origin': 'https://live.nicovideo.jp',
        'referer': 'https://live.nicovideo.jp/',
        'user-agent': _userAgent,
      },
      codec: 'avc',
      lease: Lease(refreshAt: now.add(renewEvery), expiresAt: now.add(holdFor), cutsConnection: false),
    );
    return StreamSet(qualities: const [auto], selected: auto, lines: [line]);
  }

  /// §6.3 the path-scoped cookies of the grant behind [line] as a Netscape
  /// cookie file, for a player or relay that sends per-path cookies (mpv
  /// `cookies-file`); null when no open seat issued [line].
  String? cookieFile(StreamLine line) {
    for (final held in _held.values) {
      if (held.seat.isOpen && held.seat.grant.master == line.url) return held.seat.grant.netscapeCookies();
    }
    return null;
  }

  /// The grant behind [line] while its seat is open (§6.3).
  NiconicoGrant? grantFor(StreamLine line) {
    for (final held in _held.values) {
      if (held.seat.isOpen && held.seat.grant.master == line.url) return held.seat.grant;
    }
    return null;
  }

  /// Closes every held seat.
  Future<void> close() async {
    for (final program in [..._held.keys]) {
      await _release(program);
    }
  }

  @override
  Future<RoomRef?> resolve(String input) async {
    final text = input.trim();
    if (NiconicoParse.roomId.hasMatch(text)) return await _canonical(text);
    final match = RegExp(r'https?://[^\s，。！？、“”"<>]+').firstMatch(text);
    final url = match == null ? null : Uri.tryParse(match.group(0)!);
    if (url == null) return null;
    final host = url.host.toLowerCase();
    if (host != 'live.nicovideo.jp' && host != 'sp.live.nicovideo.jp' && host != 'nico.ms') return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    final id = switch (segments) {
      ['watch', 'user', final user] => 'user/$user',
      ['watch', final id] => id,
      [final id] when host == 'nico.ms' => id,
      _ => null,
    };
    if (id == null || !NiconicoParse.roomId.hasMatch(id)) return null;
    return await _canonical(id);
  }

  /// §1 a program id becomes its user's or channel's room when the watch page
  /// names one.
  Future<RoomRef> _canonical(String id) async {
    if (!NiconicoParse.programId.hasMatch(id)) return RoomRef(_site, id);
    final response = await _get(NiconicoParse.link(id));
    if (response.status == 404) throw NotFound(_site, 'watch page $id');
    if (response.status != 200) throw ApiChanged(_site, 'watch page HTTP ${response.status}');
    final props = NiconicoParse.props(response.text);
    final program = _obj(props['program']);
    final supplier = _obj(program['supplier']);
    final social = _obj(props['socialGroup']);
    final room = NiconicoParse.roomOf(
      program: id,
      provider: switch (supplier['supplierType']) {
        'user' => 'user',
        'channel' => 'channel',
        _ => '${program['providerType']}',
      },
      userId: '${supplier['programProviderId'] ?? ''}',
      channelId: '${social['id'] ?? ''}',
    );
    return RoomRef(_site, room);
  }
}
