import 'dart:async';
import 'dart:io';

import 'package:live_core/live_core.dart';
import 'package:live_media/live_media.dart';
import 'package:test/test.dart';

import 'support/synthetic_flv.dart';

const _quality = Quality(id: '0', label: '原画', rank: 10);

/// A real HTTP upstream that streams a synthetic live FLV in real time and
/// cuts every connection after [cut], like Douyu's `expire`.
final class _Upstream {
  new _(this.server, this.cut);

  static Future<_Upstream> start({required Duration cut}) async {
    final upstream = _Upstream._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), cut);
    upstream.server.listen(upstream._serve);
    return upstream;
  }

  final HttpServer server;
  final Duration cut;
  final epoch = DateTime.now();
  final requests = <HttpRequest>[];
  final headers = <String?>[];
  static const flv = SyntheticFlv();

  int get _now => 100000 + DateTime.now().difference(epoch).inMilliseconds;

  Future<void> _serve(HttpRequest request) async {
    requests.add(request);
    headers.add(request.headers.value('referer'));
    // Unbuffered, or dart:io holds the body until close despite flush().
    final response = request.response
      ..bufferOutput = false
      ..headers.contentType = ContentType('video', 'x-flv');
    final joined = _now;
    final lastKey = joined ~/ flv.gopMs * flv.gopMs;
    response
      ..add(FlvTag.fileHeader())
      ..add(SyntheticFlv.script(0))
      ..add(flv.videoConfig(lastKey))
      ..add(SyntheticFlv.audioConfig(lastKey));
    flv.tags(lastKey, joined).forEach(response.add);
    var sent = joined;
    final end = joined + cut.inMilliseconds;
    try {
      while (sent < end) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final now = _now < end ? _now : end;
        flv.tags(sent, now).forEach(response.add);
        sent = now;
        await response.flush();
      }
    } on Object {
      return;
    }
    await response.close();
  }

  StreamLine line(int serial) {
    final issued = DateTime.now();
    return StreamLine(
      url: Uri.parse('http://127.0.0.1:${server.port}/live/$serial.flv?expire=3'),
      format: StreamFormat.flv,
      lineId: 'hw',
      requested: _quality,
      headers: const {'referer': 'https://www.douyu.com/9999'},
      lease: Lease(
        refreshAt: issued.add(const Duration(milliseconds: 1200)),
        expiresAt: issued.add(cut),
        cutsConnection: true,
      ),
    );
  }
}

Future<({int status, OutputCheck output})> _read(Uri uri, Duration duration) async {
  final client = HttpClient();
  final output = OutputCheck();
  final framer = FlvFramer();
  try {
    final response = await (await client.getUrl(uri)).close();
    if (response.statusCode != 200) return (status: response.statusCode, output: output);
    final done = Completer<void>();
    final subscription = response.listen(
      (chunk) => framer.add(chunk).forEach(output.add),
      onDone: done.complete,
      onError: (Object _) => done.complete(),
    );
    await done.future.timeout(duration, onTimeout: () {});
    await subscription.cancel();
    return (status: 200, output: output);
  } finally {
    client.close(force: true);
  }
}

void main() {
  late _Upstream upstream;
  late LoopbackRelay relay;

  setUp(() async {
    upstream = await _Upstream.start(cut: const Duration(milliseconds: 2500));
    relay = await LoopbackRelay.start();
  });

  tearDown(() async {
    await relay.close();
    await upstream.server.close(force: true);
  });

  test('serves one continuous FLV across real connection cuts', () async {
    var serial = 0;
    final events = <SpliceEvent>[];
    final renewed = <StreamLine>[];
    final input = relay.openSplice(
      upstream.line(0),
      site: 'douyu',
      renew: (current) async => upstream.line(++serial),
      onEvent: events.add,
      onRenewed: renewed.add,
    );
    expect(input.uri.host, '127.0.0.1');
    final result = await _read(input.uri, const Duration(seconds: 6));
    await input.close();

    expect(result.status, 200);
    final switches = events.whereType<SpliceSwitched>().toList();
    expect(switches.length, greaterThanOrEqualTo(3), reason: '$events');
    expect(renewed.map((line) => line.url.path), [for (var i = 1; i <= renewed.length; i++) '/live/$i.flv']);
    expect(input.line.url, renewed.last.url);
    final out = result.output;
    expect(out.videoMonotonic, isTrue);
    expect(out.audioMonotonic, isTrue);
    expect(out.repeatedVideo, 0);
    expect(out.maxVideoGap, 40);
    expect(out.scripts, 1);
    expect(upstream.headers.toSet(), {'https://www.douyu.com/9999'}, reason: 'line headers go upstream');
  });

  test('gives every input its own unguessable path and forgets it on close', () async {
    final first = relay.openSplice(upstream.line(0), site: 'douyu', renew: (current) async => current);
    final second = relay.openSplice(upstream.line(1), site: 'douyu', renew: (current) async => current);
    expect(first.uri.path, isNot(second.uri.path));
    expect(first.uri.pathSegments.first.length, greaterThanOrEqualTo(24));
    final guessed = first.uri.replace(path: '/live.flv');
    expect((await _read(guessed, const Duration(seconds: 1))).status, 404);
    await first.close();
    expect((await _read(first.uri, const Duration(seconds: 1))).status, 404);
    expect((await _read(second.uri, const Duration(milliseconds: 300))).status, 200);
  });

  test('answers 502 when the first upstream connection fails', () async {
    final line = StreamLine(
      url: Uri.parse('http://127.0.0.1:${upstream.server.port}/missing.flv'),
      format: StreamFormat.flv,
      lineId: 'hw',
      requested: _quality,
    );
    await upstream.server.close(force: true);
    final events = <SpliceEvent>[];
    final input = relay.openSplice(line, site: 'douyu', renew: (current) async => current, onEvent: events.add);
    expect((await _read(input.uri, const Duration(seconds: 2))).status, 502);
    expect(events.single, isA<SpliceEnded>());
  });

  test('the pipeline splices only FLV lines whose lease cuts the connection', () async {
    final pipeline = SourcePipeline(relay: () async => relay);
    final spliced = await pipeline.open(upstream.line(0), site: 'douyu', renew: (current) async => current);
    expect(spliced.mode, PipelineMode.splice);
    expect(spliced.local, isTrue);
    expect(spliced.headers, isEmpty);
    expect(spliced.renewsLease, isTrue);

    final huya = StreamLine(
      url: Uri.parse('https://al.flv.huya.com/src/1.flv'),
      format: StreamFormat.flv,
      lineId: 'al',
      requested: _quality,
      headers: const {'user-agent': 'x'},
      lease: Lease(refreshAt: DateTime.now(), cutsConnection: false),
    );
    final direct = await pipeline.open(huya, site: 'huya', renew: (current) async => current);
    expect(direct.mode, PipelineMode.direct);
    expect(direct.uri, huya.url);
    expect(direct.headers, {'user-agent': 'x'});
    expect(direct.local, isFalse);

    final hls = StreamLine(
      url: Uri.parse('https://x.test/a.m3u8'),
      format: StreamFormat.hls,
      lineId: 'x',
      requested: _quality,
      lease: Lease(refreshAt: DateTime.now(), cutsConnection: true),
    );
    expect(PipelineMode.of(hls, canRenew: true), PipelineMode.direct);
    expect(PipelineMode.of(upstream.line(0), canRenew: false), PipelineMode.direct);
    await spliced.close();
    await pipeline.close();
    expect(relay.isClosed, isFalse, reason: 'a shared relay belongs to its owner');
  });
}
