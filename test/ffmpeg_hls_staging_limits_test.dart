import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/services/settings/log_controller.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/recorder/services/ffmpeg_hls_input_relay.dart';

void main() {
  setUp(() => Get.put<LogController>(_QuietLog()));
  tearDown(() => Get.delete<LogController>(force: true));

  test('a 3 MiB response spills once, publishes exact bytes and cleans its owned file', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final response = await fixture.request(0);
    expect(response.statusCode, HttpStatus.ok);
    expect(response.contentLength, 3 * 1024 * 1024);
    expect(await _checkBody(response), response.contentLength);
    await _until(() => fixture.relay.stagingBodyCount == 0);
    expect(fixture.allocations, 1);
    expect(await fixture.root.list().map((f) => f.path).toList(), [fixture.keep.path]);
    expect(await fixture.keep.readAsString(), 'unrelated');
    expect(fixture.relay.inputTailDiscarded, false);
  });

  test('eight spilled responses bound admission; the ninth fails before publication and stop cleans all', () async {
    final fixture = await _Fixture.create(holdBody: true);
    addTearDown(fixture.close);
    final requests = List.generate(8, fixture.request);
    await _until(() => fixture.allocations == 8);
    expect(fixture.relay.stagingBodyCount, 8);
    expect(await fixture.root.list().where((f) => f is Directory).length, 8);
    final rejected = await fixture.request(8).timeout(const Duration(seconds: 3));
    expect(rejected.statusCode, HttpStatus.serviceUnavailable);
    expect(await rejected.fold<int>(0, (n, chunk) => n + chunk.length), 0);
    expect(fixture.allocations, 8);
    expect(fixture.relay.inputTailDiscarded, false);
    await fixture.relay.finish();
    for (final response in await Future.wait(requests).timeout(const Duration(seconds: 3))) {
      expect(response.statusCode, HttpStatus.gone);
      expect(await response.fold<int>(0, (n, chunk) => n + chunk.length), 0);
    }
    await _until(() => fixture.relay.stagingBodyCount == 0);
    expect(fixture.relay.inputTailDiscarded, true);
    expect(await fixture.root.list().map((f) => f.path).toList(), [fixture.keep.path]);
  });

  test('close waits for a delayed spill allocation and removes the late owned file', () async {
    final allocation = Completer<void>();
    final release = Completer<void>();
    final fixture = await _Fixture.create(holdBody: true);
    fixture.directoryFactory = () async {
      final directory = await fixture.allocate();
      allocation.complete();
      await release.future;
      return directory;
    };
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      await fixture.close();
    });
    final response = fixture.request(0).then<void>((r) => r.drain<void>(), onError: (Object _) {});
    await allocation.future.timeout(const Duration(seconds: 3));
    var closed = false;
    final closing = fixture.relay.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, false, reason: 'close must keep ownership of a pending disk allocation');
    release.complete();
    await closing.timeout(const Duration(seconds: 3));
    await response.timeout(const Duration(seconds: 3));
    expect(fixture.relay.stagingBodyCount, 0);
    expect(fixture.relay.resourceCount, 0);
    expect(fixture.relay.inputTailDiscarded, false);
    expect(await fixture.root.list().map((f) => f.path).toList(), [fixture.keep.path]);
  });

  test('storage allocation failure rejects the body and releases admission for the next response', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    fixture.directoryFactory = () async => throw const FileSystemException('fixture storage unavailable');
    final failed = await fixture.request(0);
    expect(failed.statusCode, HttpStatus.badGateway);
    expect(await failed.fold<int>(0, (n, chunk) => n + chunk.length), 0);
    await _until(() => fixture.relay.stagingBodyCount == 0);
    fixture.directoryFactory = fixture.allocate;
    final recovered = await fixture.request(1);
    expect(recovered.statusCode, HttpStatus.ok);
    expect(await _checkBody(recovered), 3 * 1024 * 1024);
    await _until(() => fixture.relay.stagingBodyCount == 0);
    expect(fixture.relay.inputTailDiscarded, false);
  });

  test('a resource larger than 128 MiB is rejected without publishing a successful prefix', () async {
    final fixture = await _Fixture.create(bodyLength: 128 * 1024 * 1024 + 1);
    addTearDown(fixture.close);
    final response = await fixture.request(0).timeout(const Duration(seconds: 20));
    expect(response.statusCode, HttpStatus.badGateway);
    expect(await response.fold<int>(0, (n, chunk) => n + chunk.length), 0);
    await _until(() => fixture.relay.stagingBodyCount == 0);
    expect(fixture.allocations, 1);
    expect(await fixture.root.list().map((f) => f.path).toList(), [fixture.keep.path]);
    expect(fixture.relay.inputTailDiscarded, false);
  });
}

Future<int> _checkBody(Stream<List<int>> stream) async {
  var length = 0;
  var exact = true;
  await for (final chunk in stream) {
    for (final byte in chunk) {
      if (byte != (length % 65536) % 251) exact = false;
      length++;
    }
  }
  expect(exact, true, reason: 'every published byte must match the unmodified fixture');
  return length;
}

Future<void> _until(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(predicate(), true, reason: 'staging did not reach the expected owned-resource boundary');
}

class _Fixture {
  _Fixture(this.bodyLength, this.holdBody);
  final int bodyLength;
  final bool holdBody;
  final release = Completer<void>();
  final client = HttpClient()..maxConnectionsPerHost = 16;
  final chunk = Uint8List.fromList(List.generate(65536, (i) => i % 251));
  late Directory root;
  late File keep;
  late HttpServer origin;
  late StreamSubscription<HttpRequest> subscription;
  late FFmpegHlsInputRelay relay;
  late List<Uri> media;
  late Future<Directory> Function() directoryFactory;
  var allocations = 0;

  static Future<_Fixture> create({int bodyLength = 3 * 1024 * 1024, bool holdBody = false}) async {
    final fixture = _Fixture(bodyLength, holdBody);
    fixture.root = await Directory.systemTemp.createTemp('purelive-staging-limit-test-');
    fixture.keep = await File('${fixture.root.path}${Platform.pathSeparator}keep.txt').writeAsString('unrelated');
    fixture.directoryFactory = fixture.allocate;
    fixture.origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    fixture.subscription = fixture.origin.listen(fixture.serve);
    fixture.relay = (await FFmpegHlsInputRelay.startForArguments(
      ['-i', 'http://127.0.0.1:${fixture.origin.port}/live.m3u8'],
      drainOnStop: true,
      createStagingDirectory: () => fixture.directoryFactory(),
    ))!;
    final response = await (await fixture.client.getUrl(fixture.relay.inputUri)).close();
    final manifest = await utf8.decoder.bind(response).join();
    fixture.media = const LineSplitter()
        .convert(manifest)
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .map(Uri.parse)
        .toList();
    return fixture;
  }

  Future<Directory> allocate() async {
    final directory = await root.createTemp('owned-');
    allocations++;
    return directory;
  }

  Future<HttpClientResponse> request(int index) async => (await client.getUrl(media[index])).close();

  Future<void> serve(HttpRequest request) async {
    try {
      if (request.uri.path == '/live.m3u8') {
        request.response.write('#EXTM3U\n#EXT-X-TARGETDURATION:1\n');
        for (var i = 0; i < 9; i++) {
          request.response.write('#EXTINF:1,\n$i.m4s\n');
        }
      } else {
        request.response.contentLength = bodyLength + (holdBody ? 1 : 0);
        request.response.bufferOutput = false;
        for (var offset = 0; offset < bodyLength; offset += chunk.length) {
          final remaining = bodyLength - offset;
          request.response.add(remaining >= chunk.length ? chunk : Uint8List.sublistView(chunk, 0, remaining));
          await request.response.flush();
        }
        if (holdBody) {
          await release.future;
          request.response.add([0]);
        }
      }
      await request.response.close();
    } on Object {
      // Admission/stop deliberately closes the fixture's upstream socket.
      try {
        await request.response.close();
      } on Object {
        /* Already closed. */
      }
    }
  }

  Future<void> close() async {
    if (!release.isCompleted) release.complete();
    client.close(force: true);
    await relay.close().timeout(const Duration(seconds: 3));
    await origin.close(force: true);
    await subscription.cancel();
    await keep.delete();
    // Non-recursive: leaked spool files fail cleanup instead of being hidden.
    await root.delete();
  }
}

class _QuietLog extends GetxController implements LogController {
  @override
  // ignore: must_call_super
  Future<void> onInit() async {}
  @override
  bool get enableLog => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
