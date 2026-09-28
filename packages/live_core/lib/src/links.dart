import 'dart:async';

import 'package:live_core/src/live_site.dart';
import 'package:live_core/src/sites.dart';
import 'package:live_net/live_net.dart';
import 'package:meta/meta.dart';

/// A room a link points to.
@immutable
final class RoomLink {
  /// Creates the link target.
  const new(this.platform, this.roomId);

  /// Platform id.
  final String platform;

  /// Room id within the platform.
  final String roomId;

  @override
  bool operator ==(Object other) => other is RoomLink && other.platform == platform && other.roomId == roomId;

  @override
  int get hashCode => Object.hash(platform, roomId);

  @override
  String toString() => 'RoomLink($platform, $roomId)';
}

/// What a platform made of a link that needs requests.
@immutable
sealed class LinkResolution {
  const new();
}

/// The link points to [roomId].
final class LinkRoom extends LinkResolution {
  /// Creates the result.
  const new(this.roomId);

  /// Room id within the platform.
  final String roomId;
}

/// The link redirects to [target], which is parsed again (by any platform).
final class LinkRedirect extends LinkResolution {
  /// Creates the result.
  const new(this.target);

  /// Where the short link leads.
  final Uri target;
}

/// A platform that understands links and share texts. Mixed into its
/// adapter; the defaults understand nothing.
mixin LiveSiteLinks on LiveSite {
  /// The room of a room URL, without any request, or null.
  String? roomIdFromUrl(String url) => null;

  /// Whether [url] is this platform's link that needs requests to resolve
  /// (a short link or a share code).
  bool needsResolving(String url) => false;

  /// Resolves a link for which [needsResolving] is true; null when it leads
  /// nowhere. Requests go through [session].
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async => null;

  /// Rooms in app deep links of a share text (`xhsdiscover://…`), checked
  /// before web links.
  Iterable<String> roomIdsInShareText(String text) => const [];
}

/// The requests one link parse may make: one budget of [maxRequests]
/// distinct URLs, no redirect following by the transport, bodies not
/// downloaded unless asked for ([get]'s `readBody`, or [send]), and one
/// cancellation for all of them.
final class ShortLinkSession {
  /// A session on [http] whose requests each take at most [timeout].
  new(this.http, {required this.timeout, this.site = 'links'});

  /// Longest distinct URLs one parse may request.
  static const int maxRequests = 8;

  /// Statuses whose `Location` is followed.
  static const Set<int> redirectStatuses = {301, 302, 303, 307, 308};

  /// Transport.
  final LiveHttp http;

  /// Limit per request.
  final Duration timeout;

  /// Site id used for proxy routing of the requests.
  final String site;

  final CancelToken _cancel = CancelToken();
  final Set<String> _visited = {};
  bool _closed = false;

  /// Whether [close] was called.
  bool get isClosed => _closed;

  /// Number of requests made.
  int get requestCount => _visited.length;

  /// Whether [uri] is an http(s) URL with a host and no user info.
  static bool isHttpUri(Uri uri) =>
      (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty && uri.userInfo.isEmpty;

  /// GETs [uri] without following redirects; the body is read only with
  /// [readBody]. Returns null when closed, not http(s), over budget, already
  /// visited (fragments ignored), failed, or not answered with 2xx or 3xx.
  Future<LiveResponse?> get(Uri uri, {bool readBody = false, Map<String, String> headers = const {}}) async {
    final target = uri.removeFragment();
    if (_closed || !isHttpUri(uri) || _visited.length >= maxRequests || !_visited.add(target.toString())) {
      return null;
    }
    try {
      final request = LiveRequest(
        site: site,
        url: target,
        headers: headers,
        followRedirects: false,
        timeout: timeout,
        cancel: _cancel,
      );
      final LiveResponse response;
      if (readBody) {
        response = await http.send(request);
      } else {
        // Resolving a redirect needs headers only; never download a landing page.
        final streamed = await http.open(request);
        await streamed.discard();
        response = LiveResponse(status: streamed.status, bytes: const [], url: streamed.url, headers: streamed.headers);
      }
      if (_closed || response.status < 200 || response.status >= 400) return null;
      return response;
    } on TransportFailure {
      return null;
    }
  }

  /// Sends [request] (a signed form POST, say) under the rules of [get] and
  /// reads the body: its method and URL count against the budget, redirects
  /// are not followed, and the session's site, timeout and cancellation
  /// replace the request's own. Returns null in the cases [get] does.
  Future<LiveResponse?> send(LiveRequest request) async {
    final target = request.url.removeFragment();
    final method = request.method.toUpperCase();
    final key = method == 'GET' ? '$target' : '$method $target';
    if (_closed || !isHttpUri(target) || _visited.length >= maxRequests || !_visited.add(key)) return null;
    try {
      final response = await http.send(
        LiveRequest(
          site: site,
          url: target,
          method: method,
          headers: request.headers,
          body: request.body,
          followRedirects: false,
          timeout: timeout,
          cancel: _cancel,
        ),
      );
      if (_closed || response.status < 200 || response.status >= 400) return null;
      return response;
    } on TransportFailure {
      return null;
    }
  }

  /// The redirect target of [response] to [current]: exactly one non-empty
  /// `Location` on a redirect status, resolved against [current], http(s)
  /// and without user info; otherwise null.
  static Uri? redirectTarget(Uri current, LiveResponse? response) {
    if (response == null || !redirectStatuses.contains(response.status)) return null;
    final values = response.headers['location'];
    if (values == null || values.length != 1 || values.single.trim().isEmpty) return null;
    try {
      final target = current.resolve(values.single.trim());
      return isHttpUri(target) ? target : null;
    } on FormatException {
      return null;
    }
  }

  /// Cancels every request of the session.
  void close() {
    if (_closed) return;
    _closed = true;
    _cancel.cancel();
  }
}

/// Finds the room in a pasted link or share text by asking the platforms in
/// display order (3.x's `LiveUrlTool.parseLiveUrl`).
final class LinkParser {
  /// A parser over [registry]'s platforms; short links are requested with
  /// [http].
  new(this.registry, this.http);

  /// Platforms.
  final SiteRegistry registry;

  /// Transport for short links.
  final LiveHttp http;

  static final RegExp _urls = RegExp(r'(?:[a-z][a-z0-9+.-]*://|www\.)[^\s<>]+', caseSensitive: false);
  static final RegExp _chineseProse = RegExp('[，。！？、；：）》」』”’]');
  static const Set<String> _proseHosts = {
    'xhslink.com',
    'www.xiaohongshu.com',
    'xiaohongshu.com',
    'weibo.com',
    'www.weibo.com',
  };

  /// The http(s) links in [text], spelled as written (signed URLs must not
  /// be re-encoded).
  ///
  /// Share texts glue prose to links: everything from the first Chinese
  /// punctuation mark is dropped (3.x did this for Xiaohongshu and Weibo
  /// only, so `…/123。快来` failed for other platforms), then trailing ASCII
  /// punctuation. Xiaohongshu and Weibo keep a trailing `/.` or `/..`, which
  /// is route structure there. A link with user info, another scheme, or
  /// undecodable percent escapes is skipped.
  static Iterable<String> sharedHttpUrls(String text) sync* {
    for (final match in _urls.allMatches(text)) {
      var candidate = match.group(0)!;
      if (candidate.toLowerCase().startsWith('www.')) candidate = 'https://$candidate';
      candidate = candidate.split(_chineseProse).first;
      if (_proseHosts.contains(Uri.tryParse(candidate)?.host)) {
        candidate = candidate.replaceFirst(RegExp(r'''[,!?;:)\]}"']+$'''), '');
        // A trailing dot segment is URL structure, not prose punctuation.
        if (!candidate.endsWith('/.') && !candidate.endsWith('/..')) {
          candidate = candidate.replaceFirst(RegExp(r'\.+$'), '');
        }
      } else {
        candidate = candidate.replaceFirst(RegExp(r'''[.,!?;:)\]}。！？、，；：）》」』”’"']+$'''), '');
      }
      final uri = Uri.tryParse(candidate);
      if (uri == null ||
          uri.userInfo.isNotEmpty ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        continue;
      }
      // Uri.tryParse accepts `/%FF`, but decoding it throws.
      try {
        uri
          ..pathSegments
          ..queryParametersAll;
      } on FormatException {
        continue;
      }
      yield candidate;
    }
  }

  Iterable<LiveSiteLinks> get _linkSites => registry.sites.whereType<LiveSiteLinks>();

  /// Whether [text] holds a link some platform recognises, without requests
  /// (a short link counts when its platform would resolve it).
  bool containsSupportedLink(String text) {
    final sites = _linkSites.toList();
    if (sites.any((site) => site.roomIdsInShareText(text).isNotEmpty)) return true;
    return sharedHttpUrls(text)
        .any((url) => sites.any((site) => site.roomIdFromUrl(url) != null || site.needsResolving(url)));
  }

  /// The room [text] points to, or null. Gives up after [timeout] or on
  /// [cancel]; all its requests are cancelled when it returns.
  Future<RoomLink?> parse(String text, {CancelToken? cancel, Duration timeout = const Duration(seconds: 12)}) async {
    if (cancel?.isCancelled ?? false) return null;
    final session = ShortLinkSession(http, timeout: timeout);
    try {
      final parsing = _parse(text, session);
      final cancelled = cancel?.whenCancelled.then<RoomLink?>((_) => null);
      return await Future.any<RoomLink?>([parsing, ?cancelled]).timeout(timeout, onTimeout: () => null);
    } finally {
      session.close();
    }
  }

  Future<RoomLink?> _parse(String text, ShortLinkSession session) async {
    final sites = _linkSites.toList();
    for (final site in sites) {
      final roomId = site.roomIdsInShareText(text).firstOrNull;
      if (roomId != null) return RoomLink(site.id, roomId);
    }
    for (final url in sharedHttpUrls(text)) {
      if (session.isClosed) return null;
      for (final site in sites) {
        final roomId = site.roomIdFromUrl(url);
        if (roomId != null) return RoomLink(site.id, roomId);
      }
      for (final site in sites) {
        if (!site.needsResolving(url)) continue;
        final resolution = await site.resolveUrl(url, session);
        if (session.isClosed) return null;
        switch (resolution) {
          case LinkRoom(:final roomId):
            return RoomLink(site.id, roomId);
          case LinkRedirect(:final target):
            final found = await _parse(target.toString(), session);
            if (found != null) return found;
          case null:
            break;
        }
      }
    }
    return null;
  }
}

/// Room-path rules shared by several platforms' links (3.x's
/// `WebSearchRoomParser`).
abstract final class RoomPaths {
  /// Path segments that name pages, not rooms.
  static const Set<String> reservedSegments = {
    'search',
    'category',
    'categories',
    'directory',
    'directories',
    'game',
    'games',
    'video',
    'videos',
    'user',
    'users',
    'index',
    'topic',
    'topics',
    'downloads',
    'settings',
    'login',
    'signup',
  };

  /// Whether [roomId] matches [pattern] and is not a reserved page name.
  static bool isRoomIdentifier(String roomId, RegExp pattern) =>
      roomId.isNotEmpty && !reservedSegments.contains(roomId.toLowerCase()) && pattern.hasMatch(roomId);

  /// Whether [host] is [root] or one of its subdomains.
  static bool hostIs(String host, String root) => host == root || host.endsWith('.$root');

  /// The non-empty path segments of [uri].
  static List<String> segments(Uri uri) =>
      uri.pathSegments.where((segment) => segment.trim().isNotEmpty).toList(growable: false);

  /// The first path segment of [uri] as a room id matching [pattern], or null.
  static String? firstSegment(Uri uri, RegExp pattern) {
    final parts = segments(uri);
    if (parts.isEmpty) return null;
    final roomId = parts.first.trim();
    return isRoomIdentifier(roomId, pattern) ? roomId : null;
  }
}
