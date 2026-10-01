import 'dart:async';
import 'dart:convert';

import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:test/test.dart';

/// Answers requests with [handler]; records them.
final class _FakeHttp implements LiveHttp {
  new(this.handler);

  final Future<LiveResponse> Function(LiveRequest request) handler;
  final List<LiveRequest> requests = [];

  @override
  Future<LiveResponse> send(LiveRequest request) {
    requests.add(request);
    return handler(request);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) async {
    final response = await send(request);
    return LiveStreamedResponse(
      status: response.status,
      body: Stream.value(response.bytes),
      url: response.url,
      headers: response.headers,
    );
  }

  @override
  void close() {}
}

LiveResponse _redirect(int status, String location, LiveRequest request) => LiveResponse(
  status: status,
  bytes: const [],
  url: request.url,
  headers: {
    'location': [location],
  },
);

/// Bilibili-like: `live.bilibili.com/<digits>`; b23.tv short links redirect.
final class _Bilibili extends LiveSite with LiveSiteLinks {
  @override
  String get id => 'bilibili';

  @override
  String get name => '哔哩哔哩';

  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.parse(url);
    return uri.host == 'live.bilibili.com' ? RoomPaths.firstSegment(uri, RegExp(r'^\d+$')) : null;
  }

  @override
  bool needsResolving(String url) => RoomPaths.hostIs(Uri.parse(url).host, 'b23.tv');

  @override
  Future<LinkResolution?> resolveUrl(String url, ShortLinkSession session) async {
    final uri = Uri.parse(url);
    final target = ShortLinkSession.redirectTarget(uri, await session.get(uri));
    return target == null ? null : LinkRedirect(target);
  }
}

/// Huya-like: `huya.com/<name>`.
final class _Huya extends LiveSite with LiveSiteLinks {
  @override
  String get id => 'huya';

  @override
  String get name => '虎牙';

  @override
  String? roomIdFromUrl(String url) {
    final uri = Uri.parse(url);
    return RoomPaths.hostIs(uri.host, 'huya.com') ? RoomPaths.firstSegment(uri, RegExp(r'^[a-zA-Z0-9_-]+$')) : null;
  }
}

/// Xiaohongshu-like: rooms in app deep links of share texts.
final class _Xiaohongshu extends LiveSite with LiveSiteLinks {
  @override
  String get id => 'xiaohongshu';

  @override
  String get name => '小红书';

  @override
  Iterable<String> roomIdsInShareText(String text) sync* {
    for (final match in RegExp(r'xhsdiscover://live_audience\?room_id=(\d+)').allMatches(text)) {
      yield match.group(1)!;
    }
  }
}

/// A site without link abilities.
final class _Plain extends LiveSite {
  @override
  String get id => 'cc';

  @override
  String get name => '网易CC';
}

SiteRegistry _registry() =>
    SiteRegistry({'bilibili': _Bilibili.new, 'huya': _Huya.new, 'xiaohongshu': _Xiaohongshu.new, 'cc': _Plain.new});

void main() {
  group('SiteIds', () {
    test('35 supported platforms in 3.x order (Kick back after CHZZK), IPTV last; retired ones are separate', () {
      expect(SiteIds.supported, hasLength(35));
      expect(SiteIds.supported.take(5), ['bilibili', 'douyu', 'huya', 'douyin', 'kuaishou']);
      expect(SiteIds.supported.last, 'iptv');
      expect(SiteIds.supported.toSet(), hasLength(35));
      expect(SiteIds.supported.skipWhile((id) => id != 'chzzk').take(2), ['chzzk', 'kick']);
      expect(SiteIds.supported.toSet().intersection(SiteIds.retired), isEmpty);
      expect(SiteIds.isSupported(' Douyu '), isTrue);
      expect(SiteIds.isSupported('kick'), isTrue);
      expect(SiteIds.isSupported('huajiao'), isFalse);
      expect(SiteIds.isRetired('HUAJIAO'), isTrue);
      expect(SiteIds.isRetired('kick'), isFalse);
    });

    test('retired links are recognised by host and subdomain', () {
      expect(SiteIds.isRetiredLink('看这个 https://rumble.com/xqc 好看'), isTrue);
      expect(SiteIds.isRetiredLink('https://kick.com/xqc'), isFalse);
      expect(SiteIds.isRetiredLink('https://www.huajiao.com/l/1'), isTrue);
      expect(SiteIds.isRetiredLink('https://notrumble.com/x'), isFalse);
      expect(SiteIds.isRetiredLink('https://live.bilibili.com/1'), isFalse);
    });
  });

  group('SiteRegistry', () {
    test('one adapter per platform, created on first use and kept', () {
      var built = 0;
      final registry = SiteRegistry({
        'huya': () {
          built++;
          return _Huya();
        },
        'bilibili': _Bilibili.new,
      });
      expect(built, 0);
      final first = registry.of(' HUYA ');
      expect(identical(first, registry.of('huya')), isTrue);
      expect(built, 1);
      expect(registry.ids, ['bilibili', 'huya'], reason: 'display order, not map order');
      expect(registry.maybeOf('douyu'), isNull);
      expect(() => registry.of('douyu'), throwsArgumentError);
    });

    test('the saved platform list keeps its order without duplicates or unknown ids', () {
      expect(_registry().availableIds(['huya', ' Bilibili ', 'huya', 'huajiao', 'douyu', 'cc']), [
        'huya',
        'bilibili',
        'cc',
      ]);
    });
  });

  group('shared links', () {
    test('trailing punctuation is dropped; signed spelling is kept', () {
      expect(LinkParser.sharedHttpUrls('打开 https://live.bilibili.com/123。快来！').toList(), [
        'https://live.bilibili.com/123',
      ]);
      expect(LinkParser.sharedHttpUrls('www.huya.com/abc,').toList(), ['https://www.huya.com/abc']);
      expect(LinkParser.sharedHttpUrls('https://cdn.test/a?sig=a%2Fb').toList(), ['https://cdn.test/a?sig=a%2Fb']);
    });

    test('Xiaohongshu and Weibo shares lose the prose glued to the link', () {
      expect(LinkParser.sharedHttpUrls('https://xhslink.com/a/Ab1复制本条信息，打开小红书').toList(), [
        'https://xhslink.com/a/Ab1复制本条信息',
      ]);
      expect(LinkParser.sharedHttpUrls('https://weibo.com/l/wblive/p/show/1022:23，快看...').toList(), [
        'https://weibo.com/l/wblive/p/show/1022:23',
      ]);
      expect(LinkParser.sharedHttpUrls('https://xiaohongshu.com/a/..').toList(), ['https://xiaohongshu.com/a/..']);
    });

    group('Weibo and Xiaohongshu shares (3.x cases)', () {
      const watch = 'https://weibo.com/l/wblive/p/show/1022:2321325000000000000000';
      test('prose is separated without cutting the id colon; escaped spelling is kept', () {
        expect(LinkParser.sharedHttpUrls('直播：$watch。打开应用观看').single, watch);
        const escaped = '$watch?token=a%2Fb%3D%3d&next=%EF%BC%8C%3A#part';
        expect(LinkParser.sharedHttpUrls('分享 $escaped。打开应用观看').single, escaped);
        expect(LinkParser.sharedHttpUrls('https://xhslink.com/m/abc123?q=%EF%BC%8C，复制').toList(), [
          'https://xhslink.com/m/abc123?q=%EF%BC%8C',
        ]);
      });

      for (final suffix in ['/.', '/..']) {
        test('the structural suffix $suffix is kept', () {
          expect(LinkParser.sharedHttpUrls('直播 $watch$suffix').single, '$watch$suffix');
        });
      }

      for (final url in [
        watch,
        watch.replaceFirst('https://weibo.com', 'HTTPS://WWW.WEIBO.COM'),
        watch.replaceFirst('https://weibo.com', 'http://weibo.com:80'),
        'https://weibo.com/l/wblive/p/show/1042152:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ]) {
        test('trailing prose and punctuation leave the exact link: $url', () {
          for (final punctuation in ['。打开应用观看', '，复制本条信息', ')', '.']) {
            expect(LinkParser.sharedHttpUrls('分享 $url$punctuation').single, url, reason: punctuation);
          }
        });
      }
    });

    test('other schemes, user info and undecodable escapes are skipped', () {
      expect(
        LinkParser.sharedHttpUrls(
          'ftp://www.huya.com/1 https://u:p@live.bilibili.com/1 https://x.test/%FF mailto:a@b.c',
        ).toList(),
        isEmpty,
      );
    });
  });

  group('parse', () {
    late _FakeHttp http;
    late LinkParser parser;

    void serve(Future<LiveResponse> Function(LiveRequest request) handler) {
      http = _FakeHttp(handler);
      parser = LinkParser(_registry(), http);
    }

    setUp(() => serve((_) async => throw StateError('unexpected request')));

    for (final status in [301, 302, 303, 307, 308]) {
      test('a short link resolves HTTP $status without fetching the final room', () async {
        serve((request) async => _redirect(status, 'https://live.bilibili.com/123', request));
        expect(await parser.parse('https://b23.tv/fixture'), const RoomLink('bilibili', '123'));
        expect(http.requests, hasLength(1));
        expect(http.requests.single.followRedirects, isFalse);
      });
    }

    test('a relative Location resolves against the current short link', () async {
      serve(
        (request) async => request.url.path == '/first'
            ? _redirect(302, '/second', request)
            : _redirect(302, 'https://live.bilibili.com/123', request),
      );
      expect(await parser.parse('https://b23.tv/first'), const RoomLink('bilibili', '123'));
      expect(http.requests.map((request) => request.url.path), ['/first', '/second']);
    });

    test('a self redirect stops before fetching the same URL twice; fragments do not reset it', () async {
      serve((request) async => _redirect(302, request.url.toString(), request));
      expect(await parser.parse('https://b23.tv/loop'), isNull);
      expect(http.requests, hasLength(1));
      var index = 0;
      serve((request) async => _redirect(302, 'https://b23.tv/fixture#${++index}', request));
      expect(await parser.parse('https://b23.tv/fixture'), isNull);
      expect(http.requests, hasLength(1));
    });

    test('different redirect URLs share a finite request budget', () async {
      var index = 0;
      serve((request) async => _redirect(302, 'https://b23.tv/next${++index}', request));
      expect(await parser.parse('https://b23.tv/first'), isNull);
      expect(http.requests.length, lessThanOrEqualTo(ShortLinkSession.maxRequests));
    });

    test('a failed short link does not hide a later direct room', () async {
      serve((_) async => throw const TransportFailure('links', TransportReason.connect));
      expect(await parser.parse('https://b23.tv/fail https://www.huya.com/fixture'), const RoomLink('huya', 'fixture'));
      serve((request) async => LiveResponse(status: 503, bytes: const [], url: request.url));
      expect(await parser.parse('https://b23.tv/fail https://www.huya.com/fixture'), const RoomLink('huya', 'fixture'));
    });

    test('direct links and deep links make no requests', () async {
      expect(await parser.parse('https://live.bilibili.com/123'), const RoomLink('bilibili', '123'));
      expect(
        await parser.parse('xhsdiscover://live_audience?room_id=77 https://live.bilibili.com/1'),
        const RoomLink('xiaohongshu', '77'),
        reason: 'deep links come first',
      );
      expect(http.requests, isEmpty);
    });

    for (final location in [
      'ftp://www.huya.com/123',
      'https://user@live.bilibili.com/123',
      'https://example.org/123',
      'https://[broken',
      '',
    ]) {
      test('an invalid or unrelated Location leads nowhere: "$location"', () async {
        serve((request) async => _redirect(302, location, request));
        expect(await parser.parse('https://b23.tv/fixture'), isNull);
        expect(http.requests, hasLength(1));
      });
    }

    test('duplicate Location headers and non-redirect statuses are ignored', () async {
      serve(
        (request) async => LiveResponse(
          status: 302,
          bytes: const [],
          url: request.url,
          headers: const {
            'location': ['https://live.bilibili.com/123', 'https://live.bilibili.com/456'],
          },
        ),
      );
      expect(await parser.parse('https://b23.tv/fixture'), isNull);
      for (final status in [200, 204, 304]) {
        serve((request) async => _redirect(status, 'https://live.bilibili.com/123', request));
        expect(await parser.parse('https://b23.tv/fixture'), isNull, reason: '$status');
      }
    });

    test('a timed-out parse cancels its requests and starts no more', () async {
      final started = Completer<void>();
      serve((request) async {
        started.complete();
        await request.cancel!.whenCancelled;
        throw const TransportFailure('links', TransportReason.cancelled);
      });
      final result = parser.parse('https://b23.tv/slow', timeout: const Duration(milliseconds: 50));
      await started.future;
      expect(await result, isNull);
      expect(http.requests.single.cancel!.isCancelled, isTrue);
    });

    test('caller cancellation ends the parse; a cancelled caller makes no request', () async {
      final started = Completer<void>();
      serve((request) async {
        started.complete();
        await request.cancel!.whenCancelled;
        throw const TransportFailure('links', TransportReason.cancelled);
      });
      final cancel = CancelToken();
      final result = parser.parse('https://b23.tv/slow', cancel: cancel);
      await started.future;
      cancel.cancel();
      expect(await result, isNull);
      expect(http.requests.single.cancel!.isCancelled, isTrue);
      expect(await parser.parse('https://b23.tv/x', cancel: cancel), isNull);
      expect(http.requests, hasLength(1));
    });

    test('containsSupportedLink knows rooms and short links without requests', () {
      expect(parser.containsSupportedLink('看 https://live.bilibili.com/1'), isTrue);
      expect(parser.containsSupportedLink('https://b23.tv/x'), isTrue);
      expect(parser.containsSupportedLink('xhsdiscover://live_audience?room_id=1'), isTrue);
      expect(parser.containsSupportedLink('https://www.huya.com/search'), isFalse, reason: 'reserved page');
      expect(parser.containsSupportedLink('https://cc.163.com/1'), isFalse, reason: 'no link ability');
      expect(http.requests, isEmpty);
    });
  });

  test('a short-link session reads bodies only when asked and stops after close', () async {
    final http = _FakeHttp(
      (request) async => LiveResponse(status: 200, bytes: utf8.encode('{"a":1}'), url: request.url),
    );
    final session = ShortLinkSession(http, timeout: const Duration(seconds: 1));
    expect((await session.get(Uri.parse('https://x.test/a')))!.bytes, isEmpty);
    expect((await session.get(Uri.parse('https://x.test/b'), readBody: true))!.json, {'a': 1});
    session.close();
    expect(await session.get(Uri.parse('https://x.test/c')), isNull);
    expect(http.requests, hasLength(2));
  });

  test('a short-link session sends a signed POST under its own rules and budget', () async {
    final http = _FakeHttp((request) async {
      final status = request.url.path == '/gone' ? 404 : 200;
      return LiveResponse(status: status, bytes: utf8.encode('{"a":1}'), url: request.url);
    });
    final session = ShortLinkSession(http, timeout: const Duration(seconds: 3));
    final own = CancelToken();
    final post = LiveRequest.form(
      site: 'liveme',
      url: Uri.parse('https://x.test/api#frag'),
      fields: const {'videoid': '1'},
      headers: const {'lm-s-sign': 'abc'},
      cancel: own,
    );
    expect((await session.send(post))!.json, {'a': 1}, reason: 'the body is read');
    final sent = http.requests.single;
    expect((sent.method, sent.url.toString(), sent.site), ('POST', 'https://x.test/api', 'links'));
    expect((sent.followRedirects, sent.timeout), (false, const Duration(seconds: 3)));
    expect(sent.headers['lm-s-sign'], 'abc');
    expect(utf8.decode(sent.body!), 'videoid=1');
    expect(identical(sent.cancel, own), isFalse, reason: "the session's cancellation");
    expect(await session.send(post), isNull, reason: 'the same method and URL once');
    expect(await session.get(Uri.parse('https://x.test/api')), isNotNull, reason: 'a GET of it is another request');
    expect(await session.send(LiveRequest(site: 'x', url: Uri.parse('https://x.test/gone'), method: 'POST')), isNull);
    expect(session.requestCount, 3);
    session.close();
    expect(await session.send(LiveRequest(site: 'x', url: Uri.parse('https://x.test/other'), method: 'POST')), isNull);
    expect(http.requests, hasLength(3));
  });
}
