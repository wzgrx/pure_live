// XML samples are written as adjacent strings without spaces between tags.
// ignore_for_file: missing_whitespace_between_adjacent_strings

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live/features/web_dav/web_dav_auth.dart';
import 'package:pure_live/features/web_dav/web_dav_client.dart';

const String _user = 'user@example.com';
const String _password = 'secret';
const String _realm = 'dav@example.com';

/// A `WWW-Authenticate` line [_AuthDav] replaces with its current Digest
/// challenge.
const String _digestLine = 'Digest';

WebDavConfig _config({String password = _password, String address = 'https://dav.example.com/dav/'}) =>
    WebDavConfig(name: 'test', address: address, username: _user, password: password);

/// The parameters of an `Authorization: Digest ...` value.
Map<String, String> _digestParams(String authorization) => {
  for (final match in RegExp(r'(\w+)=(?:"((?:[^"\\]|\\.)*)"|([^,\s]+))').allMatches(authorization))
    match.group(1)!: match.group(2) ?? match.group(3)!,
};

/// Checks a Digest answer the way a server does (RFC 7616), with its own
/// formula; [md5Hex] is pinned by the RFC vectors below.
bool _digestValid(
  Map<String, String> p, {
  required String method,
  required String target,
  required String nonce,
  String? algorithm,
  bool qop = true,
}) {
  if (p['username'] != _user || p['realm'] != _realm || p['nonce'] != nonce || p['uri'] != target) return false;
  String h(String text) => md5Hex(utf8.encode(text));
  var ha1 = h('$_user:$_realm:$_password');
  if (algorithm == 'MD5-sess') ha1 = h('$ha1:$nonce:${p['cnonce']}');
  final ha2 = h('$method:$target');
  final expected = qop ? h('$ha1:$nonce:${p['nc']}:${p['cnonce']}:auth:$ha2') : h('$ha1:$nonce:$ha2');
  return p['response'] == expected && p['algorithm'] == algorithm && (!qop || p['qop'] == 'auth');
}

/// A WebDAV server in memory below `/dav/` that answers `401` with the
/// [challenges] lines and takes Basic and/or Digest for `user@example.com`.
final class _AuthDav implements LiveHttp {
  new(this.challenges, {this.basic = false, this.digest = false, this.algorithm, this.qop = true});

  /// The `WWW-Authenticate` lines of a `401`.
  final List<String> challenges;

  /// Whether Basic is accepted.
  final bool basic;

  /// Whether Digest is accepted.
  final bool digest;

  /// The Digest algorithm offered (null: not named, MD5).
  final String? algorithm;

  /// Whether Digest offers `qop=auth`.
  final bool qop;

  /// The current nonce.
  String nonce = 'nonce-1';

  /// Whether a right answer with an old nonce gets `stale=true`.
  bool markStale = true;

  /// The last `nc` seen with [nonce].
  int lastCount = 0;

  /// Requests and the status they got.
  final List<(LiveRequest, int)> log = [];

  /// Files by path below `/dav/`.
  final Map<String, List<int>> files = {};

  String _digestChallenge({bool stale = false}) =>
      'Digest realm="$_realm", nonce="$nonce", opaque="op/aque"'
      '${qop ? ', qop="auth,auth-int"' : ''}${algorithm == null ? '' : ', algorithm=$algorithm'}'
      '${stale ? ', stale=true' : ''}';

  /// Null when [request] is signed right, otherwise whether the answer is
  /// right but its nonce is old.
  bool? _reject(LiveRequest request) {
    final authorization = request.headers['authorization'];
    if (authorization == null) return false;
    if (authorization.startsWith('Basic ')) {
      return basic && authorization == 'Basic ${base64.encode(utf8.encode('$_user:$_password'))}' ? null : false;
    }
    if (!digest || !authorization.startsWith('Digest ')) return false;
    final params = _digestParams(authorization);
    final target = request.url.hasQuery ? '${request.url.path}?${request.url.query}' : request.url.path;
    bool valid(String nonce) =>
        params['opaque'] == 'op/aque' &&
        _digestValid(params, method: request.method, target: target, nonce: nonce, algorithm: algorithm, qop: qop);
    if (!valid(nonce)) return valid(params['nonce'] ?? '');
    if (qop) {
      final count = int.parse(params['nc']!, radix: 16);
      if (params['nc']!.length != 8 || count <= lastCount) return false;
      lastCount = count;
    }
    return null;
  }

  @override
  Future<LiveResponse> send(LiveRequest request) async {
    LiveResponse answer(int status, {String body = '', Map<String, List<String>> headers = const {}}) {
      log.add((request, status));
      return LiveResponse(status: status, bytes: utf8.encode(body), url: request.url, headers: headers);
    }

    final stale = _reject(request);
    if (stale != null) {
      return answer(
        401,
        headers: {
          'www-authenticate': [
            for (final line in challenges)
              if (line == _digestLine) _digestChallenge(stale: stale && markStale) else line,
          ],
        },
      );
    }
    final key = request.url.pathSegments.skip(1).where((part) => part.isNotEmpty).join('/');
    switch (request.method) {
      case 'PROPFIND':
        String child(String name, int size) =>
            '<d:response><d:href>/dav/${Uri.encodeComponent(name)}</d:href><d:propstat><d:prop><d:resourcetype/>'
            '<d:getcontentlength>$size</d:getcontentlength></d:prop></d:propstat></d:response>';
        final children = [for (final MapEntry(key: name, value: bytes) in files.entries) child(name, bytes.length)];
        return answer(
          207,
          body:
              '<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"><d:response><d:href>/dav/</d:href>'
              '<d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>'
              '</d:response>${request.headers['depth'] == '1' ? children.join() : ''}</d:multistatus>',
        );
      case 'PUT':
        files[key] = request.body ?? const [];
        return answer(201);
      case 'GET':
        final bytes = files[key];
        if (bytes == null) return answer(404);
        log.add((request, 200));
        return LiveResponse(status: 200, bytes: bytes, url: request.url);
    }
    return answer(405);
  }

  @override
  Future<LiveStreamedResponse> open(LiveRequest request) => throw UnimplementedError();

  @override
  void close() {}
}

void main() {
  test('MD5 and the Digest answer match RFC 1321 and the MD5 example of RFC 7616', () {
    expect(md5Hex(const []), 'd41d8cd98f00b204e9800998ecf8427e');
    expect(md5Hex(utf8.encode('abc')), '900150983cd24fb0d6963f7d28e17f72');
    expect(
      md5Hex(utf8.encode('12345678901234567890123456789012345678901234567890123456789012345678901234567890')),
      '57edf4a22be3c955ac49da2e2107b67a',
    );

    // RFC 7616 3.9.1: two lines, SHA-256 first (not supported), then MD5;
    // the qop list holds a comma inside quotes.
    String line(String algorithm) =>
        'Digest realm="http-auth@example.org", qop="auth, auth-int", algorithm=$algorithm, '
        'nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v", '
        'opaque="FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS"';
    final challenges = parseAuthChallenges([line('SHA-256'), line('MD5')]);
    expect([for (final c in challenges) c.params['algorithm']], ['SHA-256', 'MD5']);
    expect(DigestChallenge.from(challenges.first), isNull);
    final authorization = digestAuthorization(
      challenge: DigestChallenge.from(challenges.last)!,
      username: 'Mufasa',
      password: 'Circle of Life',
      method: 'GET',
      uri: '/dir/index.html',
      nc: 1,
      cnonce: 'f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ',
    );
    expect(_digestParams(authorization), {
      'username': 'Mufasa',
      'realm': 'http-auth@example.org',
      'nonce': '7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v',
      'uri': '/dir/index.html',
      'algorithm': 'MD5',
      'response': '8ca523f5e9506fed4657c9700eebdbec',
      'qop': 'auth',
      'nc': '00000001',
      'cnonce': 'f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ',
      'opaque': 'FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS',
    });

    // Several challenges on one line, an escaped quote, schemes in any case.
    final mixed = parseAuthChallenges([r'Basic realm="a, \"b\"", DIGEST realm="r", nonce=n1, Bearer']);
    expect([for (final c in mixed) c.scheme], ['basic', 'digest', 'bearer']);
    expect(mixed.first.params['realm'], 'a, "b"');
    expect(mixed[1].params['nonce'], 'n1');
  });

  test('a server that only takes Digest: test, upload, list and download; one 401, then signed directly', () async {
    final dav = _AuthDav([_digestLine], digest: true);
    final client = WebDavClient(dav, _config());
    await client.check();
    await client.write(['backup 1.txt'], utf8.encode('data'));
    expect([for (final entry in await client.list(const [])) entry.name], ['backup 1.txt']);
    expect(utf8.decode(await client.read(['backup 1.txt'])), 'data');

    expect([for (final (_, status) in dav.log) status], [401, 207, 201, 207, 200]);
    expect(dav.log.first.$1.headers['authorization'], isNull);
    final signed = [for (final (request, _) in dav.log.skip(1)) _digestParams(request.headers['authorization']!)];
    expect([for (final p in signed) p['nc']], ['00000001', '00000002', '00000003', '00000004']);
    expect(signed[1]['uri'], '/dav/backup%201.txt');
  });

  test('an expired nonce is renewed, with or without stale=true; a wrong password fails after two requests', () async {
    final dav = _AuthDav([_digestLine], digest: true, algorithm: 'MD5-sess');
    final client = WebDavClient(dav, _config());
    await client.check();
    dav
      ..nonce = 'nonce-2'
      ..lastCount = 0;
    await client.check();
    dav
      ..nonce = 'nonce-3'
      ..lastCount = 0
      ..markStale = false;
    await client.check();
    expect([for (final (_, status) in dav.log) status], [401, 207, 401, 207, 401, 207]);
    expect(dav.log[4].$1.headers['authorization'], contains('nc=00000002'));

    final legacy = _AuthDav([_digestLine], digest: true, qop: false);
    await WebDavClient(legacy, _config()).check();
    expect(legacy.log.last.$1.headers['authorization'], isNot(contains('nc=')));

    final wrong = _AuthDav([_digestLine], digest: true);
    await expectLater(
      WebDavClient(wrong, _config(password: 'wrong')).check(),
      throwsA(isA<WebDavFailure>().having((f) => f.problem, 'problem', WebDavProblem.auth)),
    );
    expect(wrong.log, hasLength(2));
  });

  test('Basic servers keep working; Digest wins when both are offered; Bearer gets no password', () async {
    Future<List<String?>> sent(_AuthDav dav) async {
      await WebDavClient(dav, _config()).check();
      return [for (final (request, _) in dav.log) request.headers['authorization']?.split(' ').first];
    }

    // Jianguoyun, Nextcloud and Alist answer `Basic realm=...`.
    expect(await sent(_AuthDav(['Basic realm="dav"'], basic: true)), [null, 'Basic']);
    expect(await sent(_AuthDav(['Basic realm="dav"', _digestLine], basic: true, digest: true)), [null, 'Digest']);
    expect(await sent(_AuthDav(const [], basic: true)), [null, 'Basic']);

    final bearer = _AuthDav(['Bearer realm="dav"'], basic: true);
    await expectLater(WebDavClient(bearer, _config()).check(), throwsA(isA<WebDavFailure>()));
    expect([for (final (request, _) in bearer.log) request.headers['authorization']], [null]);

    final basicWrong = _AuthDav(['Basic realm="dav"'], basic: true);
    final client = WebDavClient(basicWrong, _config(password: 'wrong'));
    await expectLater(client.check(), throwsA(isA<WebDavFailure>()));
    await expectLater(client.check(), throwsA(isA<WebDavFailure>()));
    expect(basicWrong.log, hasLength(3));
  });

  test('over the real HTTP stack: two WWW-Authenticate lines reach the client and Digest is used', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final authorizations = <String?>[];
    server.listen((request) async {
      await request.drain<void>();
      final authorization = request.headers.value('authorization');
      authorizations.add(authorization);
      final response = request.response;
      final valid =
          authorization != null &&
          _digestValid(_digestParams(authorization), method: request.method, target: request.uri.path, nonce: 'n-io');
      if (valid) {
        response
          ..statusCode = 207
          ..write('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:"></d:multistatus>');
      } else {
        response
          ..statusCode = 401
          ..headers.add('www-authenticate', 'Basic realm="$_realm"')
          ..headers.add('www-authenticate', 'Digest realm="$_realm", nonce="n-io", qop="auth"');
      }
      await response.close();
    });
    final http = IoLiveHttp();
    addTearDown(() async {
      http.close();
      await server.close(force: true);
    });

    await WebDavClient(http, _config(address: 'http://127.0.0.1:${server.port}/dav/')).check();
    expect([for (final value in authorizations) value?.split(' ').first], [null, 'Digest']);
  });
}
