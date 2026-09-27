import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/web_dav/webdav_service.dart';

void main() {
  late HttpServer server;
  late WebDAVService service;
  late StreamSubscription<HttpRequest> subscription;
  var status = HttpStatus.multiStatus;
  var children = '';
  var malformed = false;
  var requireAuthentication = false;
  final methods = <String>[];
  final authHeaders = <String?>[];

  setUp(() async {
    status = HttpStatus.multiStatus;
    children = '';
    malformed = false;
    requireAuthentication = false;
    methods.clear();
    authHeaders.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    subscription = server.listen((request) async {
      methods.add(request.method);
      authHeaders.add(request.headers.value(HttpHeaders.authorizationHeader));
      await request.drain<void>();
      if (requireAuthentication && authHeaders.last == null) {
        request.response.statusCode = HttpStatus.unauthorized;
        request.response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="fixture"');
        await request.response.close();
        return;
      }
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType('application', 'xml');
      request.response.write(
        malformed
            ? '<d:multistatus'
            : '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/backup/</d:href>
    <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop>
      <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  $children
</d:multistatus>''',
      );
      await request.response.close();
    });
    service = WebDAVService(url: 'http://127.0.0.1:${server.port}', username: 'fixture', password: 'fixture');
  });

  tearDown(() async {
    service.client.c.close(force: true);
    await subscription.cancel();
    await server.close(force: true);
  });

  test('valid PROPFIND containing only the collection is an empty directory', () async {
    expect(await service.readDirectory('/backup/'), isEmpty);
    expect(methods, ['PROPFIND']);
  });

  test('nonempty directory retains its child metadata', () async {
    children = '''<d:response>
      <d:href>/backup/settings.txt</d:href>
      <d:propstat><d:prop><d:resourcetype/><d:getcontentlength>42</d:getcontentlength></d:prop>
        <d:status>HTTP/1.1 200 OK</d:status></d:propstat>
    </d:response>''';
    final files = await service.readDirectory('/backup/');
    expect(files, hasLength(1));
    expect(files.single.name, 'settings.txt');
    expect(files.single.path, '/backup/settings.txt');
    expect(files.single.size, 42);
  });

  test('HTTP errors are not converted into empty-directory success', () async {
    status = HttpStatus.forbidden;
    await expectLater(service.readDirectory('/backup/'), throwsA(isA<Exception>()));
  });

  test('routine WebDAV traffic does not enable credential-bearing debug output', () {
    expect(service.client.debug, isFalse);
    expect(service.client.c.debug, isFalse);
  });

  test('malformed XML remains a failure rather than an empty directory', () async {
    malformed = true;
    await expectLater(service.readDirectory('/backup/'), throwsA(isA<Exception>()));
  });

  test('HTTP authentication still works with protocol logging disabled', () async {
    requireAuthentication = true;
    expect(await service.readDirectory('/backup/'), isEmpty);
    expect(methods, ['PROPFIND', 'PROPFIND']);
    expect(authHeaders, [null, 'Basic ${base64Encode(utf8.encode('fixture:fixture'))}']);
    expect(service.client.c.debug, isFalse);
  });
}
