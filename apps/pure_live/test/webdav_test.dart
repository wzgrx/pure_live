import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_core/live_core.dart';
import 'package:live_net/live_net.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/features/sync/webdav_client.dart';
import 'package:pure_live_app/features/sync/webdav_profiles.dart';

/// A small in-memory WebDAV server with Basic authentication, answering the
/// way Nextcloud and Apache do (`d:` prefixes, percent-encoded hrefs,
/// collections with a trailing slash).
final class FakeWebDav {
  new _(this._server, {required this.user, required this.password});

  static Future<FakeWebDav> start({String user = 'alice', String password = 's3cret'}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dav = FakeWebDav._(server, user: user, password: password);
    server.listen(dav._handle);
    return dav;
  }

  final HttpServer _server;
  final String user;
  final String password;

  /// Files by decoded path below `/dav/` (no leading slash).
  final files = <String, List<int>>{};

  /// Directories by decoded path (no trailing slash); the root is ''.
  final directories = <String>{''};

  /// Requests seen, as `METHOD /path`.
  final requests = <String>[];

  Uri get base => Uri.parse('http://127.0.0.1:${_server.port}/dav/');

  Future<void> close() => _server.close(force: true);

  static final String _modified = HttpDate.format(DateTime.utc(2026, 9, 27, 2));

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final body = await request.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    requests.add('${request.method} ${request.uri.path}');
    final expected = 'Basic ${base64Encode(utf8.encode('$user:$password'))}';
    if (request.headers.value('authorization') != expected) {
      response.statusCode = 401;
      response.headers.set('www-authenticate', 'Basic realm="dav"');
      return await response.close();
    }
    final segments = request.uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (segments.isEmpty || segments.first != 'dav') {
      response.statusCode = 404;
      return await response.close();
    }
    final path = segments.skip(1).join('/');
    switch (request.method) {
      case 'PROPFIND':
        final isDirectory = directories.contains(path);
        if (!isDirectory && !files.containsKey(path)) {
          response.statusCode = 404;
          return await response.close();
        }
        expect(utf8.decode(body), contains('propfind'));
        final depth = request.headers.value('depth');
        final entries = <String>[_entry(path, directory: isDirectory)];
        if (isDirectory && depth == '1') {
          final prefix = path.isEmpty ? '' : '$path/';
          for (final directory in directories) {
            if (directory.startsWith(prefix) &&
                directory != path &&
                !directory.substring(prefix.length).contains('/')) {
              entries.add(_entry(directory, directory: true));
            }
          }
          for (final file in files.keys) {
            if (file.startsWith(prefix) && !file.substring(prefix.length).contains('/')) entries.add(_entry(file));
          }
        }
        response
          ..statusCode = 207
          ..headers.contentType = ContentType('application', 'xml', charset: 'utf-8')
          ..write('<?xml version="1.0"?><d:multistatus xmlns:d="DAV:" xmlns:oc="http://owncloud.org/ns">')
          ..write(entries.join())
          ..write('</d:multistatus>');
      case 'MKCOL':
        final parent = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
        if (directories.contains(path)) {
          response.statusCode = 405;
        } else if (!directories.contains(parent)) {
          response.statusCode = 409;
        } else {
          directories.add(path);
          response.statusCode = 201;
        }
      case 'PUT':
        final parent = path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '';
        if (!directories.contains(parent)) {
          response.statusCode = 409;
        } else {
          response.statusCode = files.containsKey(path) ? 204 : 201;
          files[path] = body;
        }
      case 'GET':
        final data = files[path];
        if (data == null) {
          response.statusCode = 404;
        } else {
          response.add(data);
        }
      case 'DELETE':
        response.statusCode = files.remove(path) == null ? 404 : 204;
      default:
        response.statusCode = 405;
    }
    await response.close();
  }

  String _entry(String path, {bool directory = false}) {
    final href = Uri(pathSegments: ['dav', ...path.split('/').where((s) => s.isNotEmpty), if (directory) '']).path;
    final size = directory ? '' : '<d:getcontentlength>${files[path]!.length}</d:getcontentlength>';
    return '<d:response><d:href>/$href</d:href><d:propstat><d:prop>'
        '<d:resourcetype>${directory ? '<d:collection/>' : ''}</d:resourcetype>$size'
        '<d:getlastmodified>$_modified</d:getlastmodified></d:prop>'
        '<d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>';
  }
}

void main() {
  late FakeWebDav dav;
  late IoLiveHttp http;

  setUp(() async {
    dav = await FakeWebDav.start();
    http = IoLiveHttp();
  });

  tearDown(() async {
    http.close();
    await dav.close();
  });

  WebDavClient client({String password = 's3cret'}) =>
      WebDavClient(http, base: dav.base, username: 'alice', password: password);

  test('checks the connection and reports a missing directory', () async {
    expect(await client().check(const []), isTrue);
    expect(await client().check(const ['pure_live']), isFalse);
    await expectLater(
      client(password: 'wrong').check(const []),
      throwsA(isA<WebDavException>().having((e) => e.error, 'error', WebDavError.unauthorized)),
    );
  });

  test('creates directories, uploads, lists, downloads and deletes', () async {
    final webdav = client();
    await webdav.ensureDirectory(const ['pure_live', 'phone 1']);
    expect(dav.directories, containsAll(['pure_live', 'pure_live/phone 1']));
    // Already there: no second MKCOL.
    final before = dav.requests.where((request) => request.startsWith('MKCOL')).length;
    await webdav.ensureDirectory(const ['pure_live', 'phone 1']);
    expect(dav.requests.where((request) => request.startsWith('MKCOL')), hasLength(before));

    const name = 'purelive_v4_2026-09-27T10_00_00_备份 #1.json';
    await webdav.put(const ['pure_live', 'phone 1', name], utf8.encode('{"a":1}'));
    expect(dav.files['pure_live/phone 1/$name'], utf8.encode('{"a":1}'));
    expect(dav.requests.last, startsWith('PUT /dav/pure_live/phone%201/'));

    final root = await webdav.list(const ['pure_live']);
    expect(root.map((entry) => entry.name), ['phone 1']);
    expect(root.single.isDirectory, isTrue);

    final entries = await webdav.list(const ['pure_live', 'phone 1']);
    expect(entries, hasLength(1));
    final file = entries.single;
    expect(file.name, name);
    expect(file.path, ['pure_live', 'phone 1', name]);
    expect(file.isDirectory, isFalse);
    expect(file.size, 7);
    expect(file.modified, DateTime.utc(2026, 9, 27, 2));

    expect(utf8.decode(await webdav.get(file.path)), '{"a":1}');
    await webdav.delete(file.path);
    expect(dav.files, isEmpty);
    // Deleting again is not an error.
    await webdav.delete(file.path);
    await expectLater(
      webdav.get(file.path),
      throwsA(isA<WebDavException>().having((e) => e.error, 'error', WebDavError.notFound)),
    );
  });

  test('a password with non-ASCII characters is sent as UTF-8 Basic credentials', () async {
    await dav.close();
    dav = await FakeWebDav.start(user: 'bob', password: '密码 pass');
    final webdav = WebDavClient(http, base: dav.base, username: 'bob', password: '密码 pass');
    expect(await webdav.check(const []), isTrue);
  });

  test('an unreachable server is a network error', () async {
    final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = closed.port;
    await closed.close(force: true);
    final webdav = WebDavClient(http, base: Uri.parse('http://127.0.0.1:$port/dav/'));
    await expectLater(
      webdav.list(const []),
      throwsA(isA<WebDavException>().having((e) => e.error, 'error', WebDavError.network)),
    );
  });

  group('multistatus parsing', () {
    test('Apache style: D: prefix, lp1: properties, absolute URLs', () {
      const xml = '''
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:" xmlns:ns0="DAV:">
<D:response xmlns:lp1="DAV:" xmlns:lp2="http://apache.org/dav/props/">
<D:href>https://nas.example.com/dav/backups/</D:href>
<D:propstat><D:prop><lp1:resourcetype><D:collection/></lp1:resourcetype></D:prop>
<D:status>HTTP/1.1 200 OK</D:status></D:propstat>
</D:response>
<D:response>
<D:href>https://nas.example.com/dav/backups/purelive_2026-01-01T00_00_00_x.txt</D:href>
<D:propstat><D:prop><lp1:resourcetype/><lp1:getcontentlength>1234</lp1:getcontentlength>
<lp1:getlastmodified>Thu, 01 Jan 2026 00:00:00 GMT</lp1:getlastmodified></D:prop>
<D:status>HTTP/1.1 200 OK</D:status></D:propstat>
</D:response>
</D:multistatus>''';
      final resources = WebDavClient.parseMultistatus(xml);
      expect(resources, hasLength(2));
      expect(resources.first.isCollection, isTrue);
      expect(resources.last.isCollection, isFalse);
      expect(resources.last.size, 1234);
      expect(resources.last.modified, DateTime.utc(2026));
    });

    test('default namespace, entities and a 404 propstat', () {
      const xml = '''
<multistatus xmlns="DAV:"><response><href>/dav/a%20b&amp;c.json</href>
<propstat><prop><resourcetype></resourcetype><getlastmodified>Sat, 26 Sep 2026 10:00:00 GMT</getlastmodified></prop>
<status>HTTP/1.1 200 OK</status></propstat>
<propstat><prop><getcontentlength/></prop><status>HTTP/1.1 404 Not Found</status></propstat>
</response></multistatus>''';
      final resource = WebDavClient.parseMultistatus(xml).single;
      expect(resource.href, '/dav/a%20b&c.json');
      expect(resource.size, isNull);
      expect(resource.isCollection, isFalse);
    });

    test('hrefs rewritten by a proxy still list the children', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = 207
          ..write(
            '<d:multistatus xmlns:d="DAV:">\n'
            '<d:response><d:href>/internal/root/backups/</d:href><d:propstat><d:prop>\n'
            '<d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>\n'
            '<d:response><d:href>/internal/root/backups/a.json</d:href><d:propstat><d:prop>\n'
            '<d:resourcetype/></d:prop></d:propstat></d:response>\n'
            '</d:multistatus>',
          );
        await request.response.close();
      });
      final webdav = WebDavClient(http, base: Uri.parse('http://127.0.0.1:${server.port}/dav/'));
      final entries = await webdav.list(const ['backups']);
      expect(entries.single.path, ['backups', 'a.json']);
      expect(entries.single.isDirectory, isFalse);
    });

    test('an HTML page is not a listing', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = 207
          ..write('<html><body>login</body></html>');
        await request.response.close();
      });
      final webdav = WebDavClient(http, base: Uri.parse('http://127.0.0.1:${server.port}/'));
      await expectLater(
        webdav.list(const []),
        throwsA(isA<WebDavException>().having((e) => e.error, 'error', WebDavError.invalidResponse)),
      );
    });
  });

  group('profiles', () {
    test('URL rules follow 3.x', () {
      expect(WebDavProfile.isValidUrl('https://dav.jianguoyun.com/dav/'), isTrue);
      expect(WebDavProfile.isValidUrl('http://192.168.1.2:5005'), isTrue);
      expect(WebDavProfile.isValidUrl('ftp://example.com/'), isFalse);
      expect(WebDavProfile.isValidUrl('https://user:pw@example.com/'), isFalse);
      expect(WebDavProfile.isValidUrl('https://example.com/dav?x=1'), isFalse);
      expect(WebDavProfile.isValidUrl('https://example.com/dav#top'), isFalse);
      expect(WebDavProfile.isValidUrl('https://'), isFalse);
    });

    test('are stored in the meta table with the password in the secret store', () async {
      final store = await LiveStore.inMemory();
      addTearDown(store.close);
      final secrets = await SecretStore.memory();
      final profiles = WebDavProfileStore(store.meta, secrets);

      final saved = await profiles.save(
        const WebDavProfile(
          id: 'p1',
          name: ' 坚果云 ',
          baseUrl: 'https://dav.jianguoyun.com/dav/',
          remoteDir: '/pure_live//a/',
        ),
        password: 'app-password',
      );
      expect(saved.name, '坚果云');
      expect(saved.remoteDir, 'pure_live/a');
      expect(saved.directory, ['pure_live', 'a']);
      expect(secrets.read(SecretRefs.webdav('p1')), 'app-password');
      expect(await store.meta.get(WebDavProfileStore.profilesKey), isNot(contains('app-password')));

      await expectLater(
        profiles.save(const WebDavProfile(id: 'p2', name: '坚果云', baseUrl: 'https://example.com/')),
        throwsA(isA<WebDavProfileException>().having((e) => e.error, 'error', WebDavProfileError.duplicateName)),
      );
      await expectLater(
        profiles.save(const WebDavProfile(id: 'p2', name: 'NAS', baseUrl: 'example.com')),
        throwsA(isA<WebDavProfileException>().having((e) => e.error, 'error', WebDavProfileError.invalidUrl)),
      );

      // Editing without a new password keeps the stored one.
      await profiles.save(saved.copyWith(username: 'me@example.com'));
      expect(profiles.passwordOf(saved), 'app-password');
      await profiles.save(const WebDavProfile(id: 'p2', name: 'NAS', baseUrl: 'http://192.168.1.2:5005/'));
      await profiles.setCurrent('p1');
      expect((await profiles.load()).map((profile) => profile.name), ['坚果云', 'NAS']);

      await profiles.delete('p1');
      expect(secrets.read(SecretRefs.webdav('p1')), isNull);
      expect(await profiles.currentId(), 'p2');
      expect((await profiles.load()).single.id, 'p2');
    });

    test('a v4 backup travels through WebDAV and restores', () async {
      final source = await LiveStore.inMemory();
      final target = await LiveStore.inMemory();
      addTearDown(source.close);
      addTearDown(target.close);
      await source.follows.follow(RoomSnapshot(ref: RoomRef('douyu', '5526219'), anchorName: '主播'));
      final webdav = client();
      final now = DateTime(2026, 9, 27, 10);
      final name = BackupService.fileName(BackupScope.follows, now);
      await webdav.ensureDirectory(const ['pure_live']);
      await webdav.put([
        'pure_live',
        name,
      ], utf8.encode(jsonEncode(await BackupService(source).export(scope: BackupScope.follows, now: now))));
      final entry = (await webdav.list(const ['pure_live'])).single;
      final document = jsonDecode(utf8.decode(await webdav.get(entry.path)));
      final report = await BackupService(target).restore(document, mode: RestoreMode.follows);
      expect(report.counts['follows']!.written, 1);
      expect((await target.follows.all()).single.room.ref, RoomRef('douyu', '5526219'));
    });
  });
}
