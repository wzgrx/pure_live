import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/site/niconico/niconico_api.dart';
import 'package:pure_live/core/site/niconico/niconico_quality_catalog.dart';
import 'package:pure_live/core/site/niconico/niconico_session.dart';
import 'package:pure_live/core/site/niconico/niconico_watch.dart';
import 'package:pure_live/recorder/services/niconico_hls_input.dart';

import 'niconico_hls_input_test.dart' as fixture;

Matcher kind(NiconicoFailure value) => throwsA(isA<NiconicoException>().having((e) => e.kind, 'kind', value));
String page(Map<String, dynamic> data) =>
    '<script id="embedded-data" data-props="${const HtmlEscape().convert(jsonEncode(data))}"></script>';
Future<void> tick() => Future<void>.delayed(Duration.zero);

class Harness {
  int requests = 0;
  int seats = 0;
  int reads = 0;
  String status = 'live';
  int http = 200;
  final owners = <fixture.Seat>[];
  NiconicoSeatFactory? factory;
  NiconicoMasterReader? reader;
  late final api = NiconicoApi(
    request: (_, _) async {
      requests++;
      return (status: http, body: page(fixture.fixture(status)));
    },
  );
  NiconicoQualityCatalog catalog({Duration deadline = const Duration(seconds: 2)}) => NiconicoQualityCatalog(
    api: api,
    deadline: deadline,
    findProxy: (_) => 'PROXY fixture.invalid:1',
    openSeat: (watch, cancel, proxy) async {
      seats++;
      expect(proxy(Uri.parse('https://fixture')), 'PROXY fixture.invalid:1');
      if (factory != null) return factory!(watch, cancel, proxy);
      final owner = fixture.Seat();
      owners.add(owner);
      return owner;
    },
    readMaster: (source, cookies, cancel, proxy) async {
      reads++;
      expect(proxy(source), 'PROXY fixture.invalid:1');
      if (reader != null) return reader!(source, cookies, cancel, proxy);
      expect(cookies(source), isNotNull);
      return fixture.officialMaster;
    },
  );
}

void main() {
  test('catalog discovers actual size/bitrate pairs and closes its seat before return', () async {
    final h = Harness();
    final result = await h.catalog().load('lv100');
    expect(result.map((e) => e.id), ['800x450@1080800', '512x288@412800', '512x288@201600']);
    expect(h.requests, 1);
    expect(h.seats, 1);
    expect(h.reads, 1);
    expect(h.owners.single.closes, 1);
    expect(h.owners.single.cleanupSucceeded, isTrue);
    expect(h.owners.single.grant.retainedCookieCount, 0);
    expect(jsonEncode(result), isNot(contains('https://')));
    expect(() => result.clear(), throwsUnsupportedError);
  });
  test('parallel discovery calls never share a seat or retained cookie jar', () async {
    final h = Harness();
    final catalog = h.catalog();
    await Future.wait([catalog.load('lv100'), catalog.load('lv100')]);
    expect(h.requests, 2);
    expect(h.owners, hasLength(2));
    for (final owner in h.owners) {
      expect(owner.closes, 1);
      expect(owner.grant.retainedCookieCount, 0);
    }
  });
  test('pre-cancel allocates no metadata or seat', () async {
    final h = Harness();
    final cancel = CancelToken()..cancel();
    await expectLater(h.catalog().load('lv100', cancel: cancel), kind(NiconicoFailure.cancelled));
    expect(h.requests, 0);
    expect(h.seats, 0);
  });
  for (final (status, failure) in [
    ('ended', NiconicoFailure.notLive),
    ('scheduled', NiconicoFailure.notLive),
    ('region', NiconicoFailure.access),
  ]) {
    test('$status is rejected before session creation', () async {
      final h = Harness()..status = status;
      await expectLater(h.catalog().load('lv100'), kind(failure));
      expect(h.seats, 0);
    });
  }
  test('metadata service failure is preserved and creates no seat', () async {
    final h = Harness()..http = 503;
    await expectLater(h.catalog().load('lv100'), kind(NiconicoFailure.service));
    expect(h.seats, 0);
  });
  test('cancel while factory is pending joins late session cleanup before returning', () async {
    final h = Harness();
    final cancel = CancelToken();
    final ready = Completer<void>();
    final factory = Completer<NiconicoSession>();
    final owner = fixture.Seat()..closeGate = Completer<void>();
    h.factory = (_, _, _) {
      ready.complete();
      return factory.future;
    };
    var finished = false;
    final observed = expectLater(
      h.catalog().load('lv100', cancel: cancel),
      kind(NiconicoFailure.cancelled),
    ).then((_) => finished = true);
    await ready.future;
    cancel.cancel();
    factory.complete(owner);
    try {
      await owner.closeStarted.future;
      expect(finished, isFalse);
      expect(h.reads, 0);
    } finally {
      owner.closeGate!.complete();
      await observed;
    }
    expect(owner.closes, 1);
    expect(owner.grant.retainedCookieCount, 0);
  });
  test('cancel during master read drops its late response and keeps caller cancellation local', () async {
    final h = Harness();
    final cancel = CancelToken();
    final ready = Completer<void>();
    final master = Completer<String>();
    CancelToken? inner;
    h.reader = (_, _, token, _) {
      inner = token;
      ready.complete();
      return master.future;
    };
    final observed = expectLater(h.catalog().load('lv100', cancel: cancel), kind(NiconicoFailure.cancelled));
    await ready.future;
    cancel.cancel();
    await tick();
    expect(inner!.isCancelled, isTrue);
    master.complete(fixture.officialMaster);
    await observed;
    expect(h.owners.single.closes, 1);
  });
  test('discovery deadline cancels body work and closes the seat', () async {
    final h = Harness();
    h.reader = (_, _, token, _) async {
      await token.whenCancel;
      throw token.cancelError!;
    };
    await expectLater(
      h.catalog(deadline: const Duration(milliseconds: 20)).load('lv100'),
      kind(NiconicoFailure.transport),
    );
    expect(h.owners.single.closes, 1);
  });
  test('same-root refresh uses the latest path cookies', () async {
    final h = Harness();
    h.reader = (source, cookies, _, _) async {
      final old = cookies(source);
      h.owners.single.refresh();
      await tick();
      expect(cookies(source), isNot(old));
      expect(cookies(source), contains('refreshed'));
      return fixture.officialMaster;
    };
    await h.catalog().load('lv100');
    expect(h.owners.single.closes, 1);
  });
  for (final changeRoot in [true, false]) {
    test('${changeRoot ? 'root change' : 'remote end'} invalidates the discovery response', () async {
      final h = Harness();
      h.reader = (_, _, token, _) async {
        if (changeRoot) {
          h.owners.single.refresh(newRoot: true);
        } else {
          h.owners.single.disconnect();
        }
        await tick();
        expect(token.isCancelled, isTrue);
        return fixture.officialMaster;
      };
      await expectLater(
        h.catalog().load('lv100'),
        kind(changeRoot ? NiconicoFailure.sessionClosed : NiconicoFailure.sessionError),
      );
      expect(h.owners.single.closes, 1);
    });
  }
  test('caller cancellation while closing suppresses an otherwise valid catalog', () async {
    final h = Harness();
    final cancel = CancelToken();
    final owner = fixture.Seat()..closeGate = Completer<void>();
    h.factory = (_, _, _) async => owner;
    final observed = expectLater(h.catalog().load('lv100', cancel: cancel), kind(NiconicoFailure.cancelled));
    await owner.closeStarted.future;
    cancel.cancel();
    await tick();
    owner.closeGate!.complete();
    await observed;
  });
  for (final throws in [false, true]) {
    test('cleanup ${throws ? 'exception' : 'failure flag'} prevents successful result', () async {
      final h = Harness();
      final owner = fixture.Seat()
        ..badCleanup = !throws
        ..throwCleanup = throws;
      h.factory = (_, _, _) async => owner;
      await expectLater(h.catalog().load('lv100'), kind(NiconicoFailure.cleanup));
      expect(owner.closes, 1);
    });
  }
  test('successful discovery does not cancel its caller token', () async {
    final h = Harness();
    final cancel = CancelToken();
    await h.catalog().load('lv100', cancel: cancel);
    expect(cancel.isCancelled, isFalse);
  });
  for (final (name, master) in [
    ('missing resolution', fixture.officialMaster.replaceFirst('RESOLUTION=800x450,', '')),
    ('duplicate selector', fixture.officialMaster.replaceFirst('BANDWIDTH=201600', 'BANDWIDTH=412800')),
    (
      'multiple audio choices',
      fixture.officialMaster.replaceFirst(
        '#EXT-X-STREAM-INF:',
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="trial-audio-192Kbps",NAME="Other",URI="other.m3u8"\n#EXT-X-STREAM-INF:',
      ),
    ),
    ('empty response', ''),
  ]) {
    test('$name produces schema failure with joined cleanup', () async {
      final h = Harness()..reader = (_, _, _, _) async => master;
      await expectLater(h.catalog().load('lv100'), kind(NiconicoFailure.schema));
      expect(h.owners.single.closes, 1);
    });
  }
}
