import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:live_record/live_record.dart';
import 'package:test/test.dart';

import '../support/fake_live.dart';
import '../support/ts_live.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

void main() {
  final ts = TsLive(durationMs: 2000);
  final tsBytes = ts.bytes(0, 40);

  group('sniffContent (§8.1)', () {
    test('FLV, MPEG-TS and HLS by their first bytes', () {
      expect(sniffContent(FlvTag.fileHeader()), StreamContent.flv);
      expect(sniffContent(tsBytes), StreamContent.ts);
      expect(sniffContent(_bytes([1, 2, 3, ...tsBytes])), StreamContent.ts, reason: 'junk before the packets');
      expect(sniffContent(_bytes(utf8.encode('#EXTM3U\n#EXT-X-VERSION:3\n'))), StreamContent.hls);
      expect(sniffContent(_bytes([0xEF, 0xBB, 0xBF, ...utf8.encode('\r\n  #EXTM3U\n')])), StreamContent.hls);
    });

    test('more bytes are read while they could still decide', () {
      expect(sniffContent(Uint8List(0)), isNull);
      expect(sniffContent(_bytes('FL'.codeUnits)), isNull);
      expect(sniffContent(_bytes('#EXT'.codeUnits)), isNull);
      expect(sniffContent(Uint8List.sublistView(tsBytes, 0, 188 * 4)), isNull, reason: 'four packets are not enough');
      expect(sniffContent(Uint8List.sublistView(tsBytes, 0, 188 * 4), ended: true), StreamContent.unknown);
    });

    test('anything else is not recorded', () {
      final page = utf8.encode('<!DOCTYPE html><html><body>403</body></html>');
      expect(sniffContent(_bytes(page)), isNull, reason: 'short: it could still turn out to be something');
      expect(sniffContent(_bytes(page), ended: true), StreamContent.unknown);
      expect(sniffContent(_bytes([for (var i = 0; i < 40; i++) ...page])), StreamContent.unknown);
      final mp4 = _bytes([0, 0, 0, 0x20, ...'ftypisom'.codeUnits, ...List.filled(1200, 0)]);
      expect(sniffContent(mp4), StreamContent.unknown);
      // 192-byte M2TS packets: the sync bytes are 192 apart.
      final m2ts = Uint8List(192 * 6);
      for (var i = 0; i < 6; i++) {
        m2ts[i * 192 + 4] = 0x47;
      }
      expect(sniffContent(m2ts), StreamContent.unknown);
      expect(sniffContent(Uint8List(sniffLimit)..fillRange(0, sniffLimit, 0x20)), StreamContent.unknown);
    });

    test('sniffStream reads small pieces until it knows; an empty stream is an error', () async {
      final pieces = [
        for (var at = 0; at < tsBytes.length; at += 100)
          Uint8List.sublistView(tsBytes, at, at + 100 < tsBytes.length ? at + 100 : tsBytes.length),
      ];
      final sniff = await sniffStream(ListByteSource(pieces));
      expect(sniff.content, StreamContent.ts);
      expect(sniff.head, tsBytes.sublist(0, sniff.head.length));
      expect(sniff.head.length, greaterThan(188 * 4), reason: 'five sync bytes');
      await expectLater(sniffStream(ListByteSource(const [])), throwsStateError);
      await expectLater(
        sniffStream(ListByteSource(const [], error: const SocketException('reset'))),
        throwsA(isA<SocketException>()),
      );
    });
  });

  test('FlvByteSource frames the sniffed head and the rest into FLV packets', () async {
    final flv = BytesBuilder()..add(FlvTag.fileHeader());
    const synthetic = SyntheticFlv();
    synthetic.connection(0, 400).skip(1).forEach(flv.add);
    final all = flv.takeBytes();
    final source = FlvByteSource(ListByteSource([Uint8List.sublistView(all, 20)]), Uint8List.sublistView(all, 0, 20));
    final packets = <Uint8List>[];
    for (var packet = await source.next(); packet != null; packet = await source.next()) {
      packets.add(packet);
    }
    expect(packets.length, synthetic.connection(0, 400).length);
    expect(packets.first, FlvTag.fileHeader());
    final broken = FlvByteSource(ListByteSource([_bytes(List.filled(64, 0x41))]), _bytes('FLV'.codeUnits));
    expect(await broken.next(), isNull, reason: 'bad framing ends the connection');
    expect(broken.endReason, isA<FormatException>());
  });

  group('openHttpStream (§8.1, §18)', () {
    late HttpServer server;
    final requests = <HttpRequest>[];
    Future<void> Function(HttpRequest request)? handler;

    setUp(() async {
      requests.clear();
      server = (await HttpServer.bind(InternetAddress.loopbackIPv4, 0))
        ..listen((request) async {
          requests.add(request);
          await handler!(request);
        });
    });

    tearDown(() => server.close(force: true));

    StreamLine line(String path) => StreamLine(
      url: Uri.parse('http://127.0.0.1:${server.port}$path'),
      format: StreamFormat.other,
      lineId: 'line1',
      requested: quality,
      headers: const {'user-agent': 'Entry/2.0'},
    );

    test('reads the body with the line headers until the server closes it', () async {
      handler = (request) async {
        request.response.headers.contentType = ContentType('video', 'mp2t');
        request.response.add(tsBytes);
        await request.response.close();
      };
      final source = await openHttpStream(line('/udp/239.1.1.1:5000'));
      final got = BytesBuilder();
      for (var bytes = await source.next(); bytes != null; bytes = await source.next()) {
        got.add(bytes);
      }
      expect(got.takeBytes(), tsBytes);
      expect(requests.single.headers.value('user-agent'), 'Entry/2.0');
      expect(requests.single.uri.path, '/udp/239.1.1.1:5000');
    });

    test('a status other than 200 throws UpstreamStatusException', () async {
      handler = (request) async {
        request.response.statusCode = 404;
        await request.response.close();
      };
      await expectLater(
        openHttpStream(line('/missing')),
        throwsA(isA<UpstreamStatusException>().having((e) => e.status, 'status', 404)),
      );
    });

    test('no data for the idle timeout ends reading with a TimeoutException', () async {
      final hold = Completer<void>();
      // dart:io's server holds small writes back: send enough to go out at once.
      final body = Uint8List(188 * 100);
      handler = (request) async {
        request.response.add(body);
        await request.response.flush();
        await hold.future;
      };
      final source = await openHttpStream(line('/slow'), idleTimeout: const Duration(milliseconds: 300));
      var read = 0;
      Object? error;
      try {
        while (read < body.length) {
          read += (await source.next())!.length;
        }
        await source.next();
      } on Object catch (caught) {
        error = caught;
      }
      expect(read, body.length);
      expect(error, isA<TimeoutException>());
      hold.complete();
      await source.cancel();
    });
  });
}
