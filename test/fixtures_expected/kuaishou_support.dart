// Kuaishou-specific helpers for the recorded samples (spec/sites/kuaishou.md §11).
//
// The list, category and search endpoints reuse one path with different
// queries, so replay here matches path + query exactly; that also proves the
// legacy code still builds the recorded request.
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/danmaku/kuaishou_danmaku.dart';
import 'package:pure_live/core/site/kuaishou/kuaishou_site.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/model/live_play_quality.dart';

import 'support.dart';

/// Registers the settings the legacy site reads (cookie, proxy) on an
/// in-memory Hive box, and makes any request outside the replayed Dio fail
/// (the legacy session bootstrap uses its own Dio, site:370-374).
Future<void> setUpKuaishouLegacy() async {
  io.HttpOverrides.global = _NoNetwork();
  await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
  await HivePrefUtil.init();
  Get.put(SettingsService(), permanent: true);
}

/// A configured user cookie makes the legacy `_ensureSession` return at once
/// (site:506), so retry paths replay the sample instead of bootstrapping a
/// session over the network. The value is synthetic.
const fixtureUserCookie = 'fixture_cookie=1';

/// Sets the legacy "user cookie" setting for the current test.
void useKuaishouCookie(String value) {
  final setting = SettingsService.to.cookieManager.kuaishouCookie;
  final previous = setting.value;
  setting.value = value;
  addTearDown(() => setting.value = previous);
}

class _NoNetwork extends io.HttpOverrides {
  @override
  io.HttpClient createHttpClient(io.SecurityContext? context) =>
      throw StateError('Kuaishou fixture tests must not reach the network');
}

/// Serves samples whose recorded URL has the same path and query.
class ExactFixtureAdapter implements HttpClientAdapter {
  ExactFixtureAdapter(this.samples);

  final List<FixtureSample> samples;
  final List<Uri> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    final uri = options.uri;
    requests.add(uri);
    final sample = samples
        .where((sample) => sample.url.path == uri.path && _query(sample.url) == _query(uri))
        .firstOrNull;
    if (sample == null) throw StateError('No recorded sample for ${options.method} $uri');
    return Future.value(
      ResponseBody.fromBytes(
        sample.bodyBytes,
        sample.status,
        headers: {
          Headers.contentTypeHeader: [sample.contentType],
        },
      ),
    );
  }

  static String _query(Uri uri) {
    final pairs = [
      for (final entry in uri.queryParametersAll.entries)
        for (final value in entry.value) '${entry.key}=$value',
    ]..sort();
    return pairs.join('&');
  }

  @override
  void close({bool force = false}) {}
}

/// Replays [samples] through HttpClient.instance.dio, matching path + query.
ExactFixtureAdapter replayExact(List<FixtureSample> samples) {
  final dio = HttpClient.instance.dio;
  final previous = dio.httpClientAdapter;
  final adapter = ExactFixtureAdapter(samples);
  dio.httpClientAdapter = adapter;
  addTearDown(() => dio.httpClientAdapter = previous);
  return adapter;
}

/// [roomProjection] plus the Kuaishou danmaku arguments (the class has no
/// toString) and, when present, the legacy quality list of the attached
/// `playUrls` (site:186).
Map<String, dynamic> kuaishouRoomProjection(LiveRoom room, {bool withQualities = false}) {
  final json = roomProjection(room);
  final args = room.danmakuData;
  if (args is KuaishouDanmakuArgs) {
    json['danmakuData'] = {'liveStreamId': args.liveStreamId, 'cookie': args.cookie};
  }
  if (withQualities) json['qualities'] = qualityProjection(KuaishowSite.parsePlayQualities(room.data));
  return json;
}

/// Quality name, legacy id, sort key and line URLs in order.
List<Map<String, dynamic>> qualityProjection(List<LivePlayQuality> qualities) => [
  for (final quality in qualities)
    {'quality': quality.quality, 'id': quality.id?.toString(), 'sort': quality.sort, 'lines': quality.data},
];

/// The thrown value, kept as the expected result where the legacy code fails.
Map<String, dynamic> errorProjection(Object error) => {
  'throws': switch (error) {
    TypeError() => 'TypeError',
    FormatException() => 'FormatException',
    StateError() => 'StateError',
    NoSuchMethodError() => 'NoSuchMethodError',
    _ => error.runtimeType.toString(),
  },
  'message': error.toString(),
};

/// Runs [body] and returns its projected value, or the projected error.
Future<Object?> outcome<T>(Future<T> Function() body, Object? Function(T value) project) async {
  try {
    return project(await body());
  } on Object catch (error) {
    return errorProjection(error);
  }
}

/// The room page state the way the legacy parser cuts it (site:448-450).
Map<String, dynamic> legacyInitialState(String html) {
  final text = RegExp(r'window\.__INITIAL_STATE__=(.*?);').firstMatch(html)?.group(1);
  if (text == null) throw const FormatException('Kuaishou initial state is missing');
  return jsonDecode(text.replaceAll('undefined', 'null')) as Map<String, dynamic>;
}
