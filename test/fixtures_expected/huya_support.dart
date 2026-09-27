// Huya helpers for the recorded-sample tests (fixtures/huya, spec/sites/huya.md §11).
//
// Huya serves several samples from one path (cache.php for lists and room
// details, bussLive for every top-level category), so replay matches the
// recorded query as well as the path. Legacy list and detail requests read the
// account cookie from SettingsService; an empty cookie store is registered.
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings/cookie_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/huya/huya_site.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/model/live_play_quality.dart';

import 'support.dart';

/// Query parameters that do not identify a sample: `_` is the detail cache
/// buster (a timestamp) and the search `uid=0` constant is rewritten by the
/// huya scrub rules (tools/live_cli/lib/src/fixture/rules/huya.dart).
const _ignoredQuery = {'_', 'uid'};

/// Serves recorded samples by host, path and query; unmatched requests fail.
class HuyaFixtureAdapter implements HttpClientAdapter {
  HuyaFixtureAdapter(this.samples);

  final List<FixtureSample> samples;
  final List<RequestOptions> requests = [];

  static Map<String, String> _identity(Uri uri) =>
      Map.of(uri.queryParameters)..removeWhere((key, _) => _ignoredQuery.contains(key));

  static bool _matches(FixtureSample sample, Uri uri) {
    if (sample.url.host != uri.host || sample.url.path != uri.path) return false;
    final recorded = _identity(sample.url);
    final requested = _identity(uri);
    return recorded.length == requested.length &&
        recorded.entries.every((entry) => requested[entry.key] == entry.value);
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requests.add(options);
    final sample = samples.where((sample) => _matches(sample, options.uri)).firstOrNull;
    if (sample == null) throw StateError('No recorded sample for ${options.method} ${options.uri}');
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

  @override
  void close({bool force = false}) {}
}

/// Replays [samples] through HttpClient.instance.dio for the current test.
HuyaFixtureAdapter replayHuya(List<FixtureSample> samples) {
  final dio = HttpClient.instance.dio;
  final previous = dio.httpClientAdapter;
  final adapter = HuyaFixtureAdapter(samples);
  dio.httpClientAdapter = adapter;
  addTearDown(() => dio.httpClientAdapter = previous);
  return adapter;
}

FixtureSample huyaSample(String sample) => FixtureSample.load('huya', sample);

/// Registers the settings service with an empty, in-memory cookie store.
void setUpHuyaSettings() {
  setUpAll(() async {
    await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
    await HivePrefUtil.init();
  });
  tearDownAll(() async => Hive.close());
  setUp(() {
    Get.testMode = true;
    Get.reset();
    Get.put<SettingsService>(_CookieOnlySettings(CookieSettingsController()));
  });
  tearDown(Get.reset);
}

class _CookieOnlySettings extends SettingsService {
  _CookieOnlySettings(this._cookies);

  final CookieSettingsController _cookies;

  @override
  CookieSettingsController get cookieManager => _cookies;

  @override
  // Only the cookie store is needed; skip the production controller graph.
  // ignore: must_call_super
  void onInit() {}
}

/// Runs a legacy entry point and records either its projection or the error
/// it throws (type, plus the message for the legacy's own format/state errors).
Future<Object?> huyaOutcome<T>(Future<T> Function() run, Object? Function(T value) project) async {
  try {
    return {'value': project(await run())};
  } on Object catch (error) {
    return {
      'error': error.runtimeType.toString(),
      if (error is FormatException) 'message': error.message,
      if (error is StateError) 'message': error.message,
    };
  }
}

Map<String, Object?> huyaLineProjection(HuyaLineModel line) => {
  'cdnType': line.cdnType,
  'lineType': line.lineType.name,
  'line': line.line,
  'secureHuyaCdnBase': HuyaSite.secureHuyaCdnBase(line.line),
  'streamName': line.streamName,
  'presenterUid': line.presenterUid,
  'flvAntiCode': line.flvAntiCode,
  'hlsAntiCode': line.hlsAntiCode,
  'bitRate': line.bitRate,
};

Map<String, Object?> huyaBitRateProjection(HuyaBitRateModel rate) => {'name': rate.name, 'bitRate': rate.bitRate};

Map<String, Object?> huyaDataProjection(HuyaUrlDataModel data) => {
  'url': data.url,
  'uid': data.uid,
  'isXingxiu': data.isXingxiu,
  'bitRates': [for (final rate in data.bitRates) huyaBitRateProjection(rate)],
  'lines': [for (final line in data.lines) huyaLineProjection(line)],
};

Map<String, Object?> huyaQualityProjection(LivePlayQuality quality) {
  final data = quality.data;
  return {
    'quality': quality.quality,
    'id': quality.id,
    'sort': quality.sort,
    if (data is Map) 'bitRate': data['bitRate'],
    if (data is Map && data['urls'] is List) 'lineCount': (data['urls'] as List).length,
  };
}

/// Static status and audience helpers applied to a profileRoom payload.
Map<String, Object?> huyaPayloadHelpers(Object? payload) {
  final data = payload is Map ? payload['data'] : null;
  if (data is! Map) return {'data': data?.runtimeType.toString()};
  final liveData = data['liveData'] is Map ? Map<String, dynamic>.from(data['liveData'] as Map) : null;
  final audience = HuyaSite.parseRoomAudience(liveData);
  return {
    'isExplicitOfflineState': HuyaSite.isExplicitOfflineState(data['liveStatus']),
    'parseHuyaLiveStatus': HuyaSite.parseHuyaLiveStatus(data['liveStatus']).name,
    'parseRoomAudience': {'popularity': audience.popularity, 'onlineViewers': audience.onlineViewers},
  };
}
