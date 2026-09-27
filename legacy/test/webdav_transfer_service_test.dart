import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/web_dav/webdav_service.dart';

void main() {
  late HttpServer server;
  late StreamSubscription<HttpRequest> subscription;
  late WebDAVService service;
  final stored = <String, List<int>>{};
  final requests = <String>[];
  var putStatus = HttpStatus.created;

  setUp(() async {
    stored.clear();
    requests.clear();
    putStatus = HttpStatus.created;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    subscription = server.listen((request) async {
      final path = Uri.decodeComponent(request.uri.path);
      requests.add('${request.method} $path');
      final body = await request.fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
      switch (request.method) {
        case 'OPTIONS':
          request.response.statusCode = HttpStatus.ok;
        case 'MKCOL':
          request.response.statusCode = HttpStatus.created;
        case 'PUT':
          request.response.statusCode = putStatus;
          if (putStatus == HttpStatus.created) stored[path] = body;
        case 'GET':
          final bytes = stored[path];
          request.response.statusCode = bytes == null ? HttpStatus.notFound : HttpStatus.ok;
          if (bytes != null) request.response.add(bytes);
        case 'DELETE':
          stored.remove(path);
          request.response.statusCode = HttpStatus.noContent;
        default:
          request.response.statusCode = HttpStatus.methodNotAllowed;
      }
      await request.response.close();
    });
    service = WebDAVService(url: 'http://127.0.0.1:${server.port}/dav/', username: '', password: '');
  });

  tearDown(() async {
    service.close();
    await subscription.cancel();
    await server.close(force: true);
  });

  for (final path in ['/backup.txt', '/备份 空间/backup.txt']) {
    test('real client writes, reads and removes a backup relative to the configured base: $path', () async {
      final bytes = Uint8List.fromList(utf8.encode('{"backupVersion":3,"note":"往返"}'));
      await service.writeFile(path, bytes);
      expect(stored['/dav$path'], bytes);
      expect(await service.readFile(path), bytes);
      await service.removeFile(path);
      expect(stored, isEmpty);
      expect(requests, containsAllInOrder(['PUT /dav$path', 'GET /dav$path', 'DELETE /dav$path']));
    });
  }

  test('a server rejecting root writes reports failure and preserves existing data', () async {
    stored['/dav/existing.txt'] = [1, 2, 3];
    putStatus = HttpStatus.forbidden;
    await expectLater(service.writeFile('/backup.txt', Uint8List.fromList([4, 5])), throwsA(isA<Exception>()));
    expect(stored, {
      '/dav/existing.txt': [1, 2, 3],
    });
    expect(requests, contains('PUT /dav/backup.txt'));
  });
}
