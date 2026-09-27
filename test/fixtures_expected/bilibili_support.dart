// Bilibili helpers for the recorded-sample tests (spec/sites/bilibili.md §11).
import 'dart:async';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/core/common/core_error.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/bilibili/bilibili_site.dart';
import 'package:pure_live/get/get.dart';
import 'package:pure_live/model/live_play_quality.dart';

import 'support.dart';

/// BiliBiliSite reads the stored cookie through SettingsService; an in-memory
/// settings box is a guest (empty cookie).
Future<void> setUpBilibiliSettings() async {
  if (!Hive.isBoxOpen('app_settings')) await Hive.openBox<dynamic>('app_settings', bytes: Uint8List(0));
  await HivePrefUtil.init();
  if (!Get.isRegistered<SettingsService>()) Get.put(SettingsService(), permanent: true);
}

FixtureSample bilibiliSample(String sample) => FixtureSample.load('bilibili', sample);

/// The guest session a legacy entry point may fetch before its own request:
/// finger/spi (buvid, S10), nav (WBI keys, S11) and the /lol page (w_webid,
/// S12). The legacy site caches them in static fields; none of them reaches
/// an expected room value, so test order does not matter.
const bilibiliSessionSamples = ['S10-guest', 'S11-guest', 'S12-guest'];

/// Replays [samples] together with the guest session samples.
FixtureAdapter replayBilibili(List<FixtureSample> samples) =>
    replay([...samples, for (final sample in bilibiliSessionSamples) bilibiliSample(sample)]);

/// Forgets the legacy static caches (buvid, WBI keys) so a test observes its
/// own session requests.
void resetBilibiliStatics() {
  BiliBiliSite.buvid3 = '';
  BiliBiliSite.buvid4 = '';
  BiliBiliSite.kImgKey = '';
  BiliBiliSite.kSubKey = '';
}

/// Requests per URL path, sorted, so concurrent session fetches compare stably.
Map<String, int> requestCounts(FixtureAdapter adapter) {
  final counts = <String, int>{};
  for (final request in adapter.requests) {
    counts.update(request.uri.path, (count) => count + 1, ifAbsent: () => 1);
  }
  return Map.fromEntries(counts.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
}

/// The value of [body], or what it threw: failure samples freeze the legacy
/// failure mode as well.
Future<Object?> settle(FutureOr<Object?> Function() body) async {
  try {
    return await body();
  } catch (error) {
    return {'throws': describeError(error)};
  }
}

/// A stable description of a legacy error (no stack).
Map<String, Object?> describeError(Object error) => switch (error) {
  HttpError() => {'type': 'HttpError', 'statusCode': error.statusCode, 'message': error.message},
  FormatException() => {'type': 'FormatException', 'message': error.message},
  StateError() => {'type': 'StateError', 'message': error.message},
  _ => {'type': error is Exception ? 'Exception' : error.runtimeType.toString(), 'message': error.toString()},
};

Map<String, Object?> qualityProjection(LivePlayQuality quality) => {
  'quality': quality.quality,
  'id': quality.id,
  'data': quality.data,
  'sort': quality.sort,
};

Map<String, Object?> resolutionProjection(LivePlayUrlResolution resolution) => {
  'urls': resolution.urls,
  'appliedQualityData': resolution.appliedQualityData,
  'qualityUnconfirmed': resolution.qualityUnconfirmed,
};
