// Douyin-specific helpers for recorded-sample expected values
// (spec/sites/douyin.md §11, docs/adr/0009-fixture-format.md).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/settings/cookie_settings_controller.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/common/core_error.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/player/core/live_stream_geometry_hint.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

/// Synthetic account cookie so the legacy sites never fetch an anonymous
/// cookie during replay (DouyinSite.getRequestHeaders, DouyinSearch._getCookie).
const douyinReplayCookie = 'ttwid=fixture';

/// Registers the minimal settings the legacy Douyin code reads.
void setUpDouyinSettings() {
  late Directory hiveDirectory;
  setUpAll(() async {
    hiveDirectory = await Directory.systemTemp.createTemp('pure-live-douyin-fixtures-');
    SharedPreferences.setMockInitialValues({});
    Hive.init(hiveDirectory.path);
    await HivePrefUtil.init();
    Get.testMode = true;
    final cookies = CookieSettingsController();
    cookies.douyinCookie.value = douyinReplayCookie;
    Get.put<SettingsService>(_DouyinFixtureSettings(cookies));
  });
  tearDownAll(() async {
    Get.reset();
    await Hive.close().timeout(const Duration(seconds: 10));
    await hiveDirectory.delete(recursive: true);
  });
}

class _DouyinFixtureSettings extends SettingsService {
  _DouyinFixtureSettings(this._cookies);

  final CookieSettingsController _cookies;

  @override
  CookieSettingsController get cookieManager => _cookies;

  @override
  // Only the cookie controller is needed; skip production registrations.
  // ignore: must_call_super
  void onInit() {}
}

/// Serves samples by host and path (Douyin reuses one path on several hosts),
/// plus synthetic redirects for hops that have no recorded sample.
class DouyinFixtureAdapter implements HttpClientAdapter {
  DouyinFixtureAdapter(this.samples, {this.redirects = const {}});

  final List<FixtureSample> samples;

  /// `https://host/path` -> Location.
  final Map<String, String> redirects;
  final List<RequestOptions> requests = [];

  /// Method, host and path of every request, in order (queries carry random
  /// msToken/a_bogus values and are left out).
  List<String> get requestLog => [
    for (final request in requests) '${request.method} ${request.uri.host}${request.uri.path}',
  ];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    requests.add(options);
    final uri = options.uri;
    final location = redirects['https://${uri.host}${uri.path}'];
    if (location != null) {
      return Future.value(
        ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': [location],
          },
        ),
      );
    }
    final sample = samples.where((sample) => sample.url.host == uri.host && sample.url.path == uri.path).firstOrNull;
    if (sample == null) throw StateError('No recorded sample for ${options.method} ${uri.host}${uri.path}');
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

/// Like [replay], but matching host and path.
DouyinFixtureAdapter replayDouyin(List<FixtureSample> samples) {
  final dio = HttpClient.instance.dio;
  final previous = dio.httpClientAdapter;
  final adapter = DouyinFixtureAdapter(samples);
  dio.httpClientAdapter = adapter;
  addTearDown(() => dio.httpClientAdapter = previous);
  return adapter;
}

final _processVisitorId = RegExp(r'^7[3-9]\d{17}$');

/// [roomProjection] with the danmaku arguments decoded. The legacy visitor ID
/// is random per process (DouyinSite.generateAnonymousUserUniqueId), so only
/// its shape is kept.
Map<String, dynamic> douyinRoomProjection(LiveRoom room) {
  final json = roomProjection(room);
  final danmaku = json['danmakuData'];
  if (danmaku is String) {
    final args = jsonDecode(danmaku) as Map<String, dynamic>;
    final userId = args['userId'];
    if (userId is String && _processVisitorId.hasMatch(userId)) {
      args['userId'] = '<process visitor id 7[3-9]+17 digits>';
    }
    json['danmakuData'] = args;
  }
  json['streamUrlKept'] = room.data is Map && (room.data as Map).isNotEmpty;
  return json;
}

/// Quality list as the player sees it: id, label, sort rank and line URLs.
List<Map<String, dynamic>> qualityProjection(List<LivePlayQuality> qualities) => [
  for (final quality in qualities)
    {'id': quality.id, 'quality': quality.quality, 'sort': quality.sort, 'urls': quality.data},
];

Map<String, dynamic>? geometryProjection(LiveStreamGeometryHint? hint) => hint == null
    ? null
    : {'width': hint.width, 'height': hint.height, 'confidence': hint.confidence, 'source': hint.source};

/// Geometry before a URL is chosen and for the first line of every quality.
Map<String, dynamic> geometryPerQuality(dynamic streamUrl, List<LivePlayQuality> qualities) => {
  'unselected': geometryProjection(LiveStreamGeometryHintResolver.resolveDouyin(streamUrl)),
  for (final quality in qualities)
    '${quality.id}': geometryProjection(
      LiveStreamGeometryHintResolver.resolveDouyin(streamUrl, selectedUrl: (quality.data as List).first.toString()),
    ),
};

/// Error type plus the message when it is a fixed legacy text.
Map<String, dynamic> errorProjection(Object error) => {
  'type': error.runtimeType.toString(),
  if (error is HttpError) 'message': error.message,
};
