// Douyu helpers for the recorded-sample tests (spec/sites/douyu.md §11).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/core_error.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/site/douyu/douyu_site.dart';
import 'package:pure_live/core/site/douyu/douyu_utils.dart';
import 'package:pure_live/model/live_play_quality.dart';

import 'support.dart';

/// The value of [body], or what it threw: failure samples freeze the legacy
/// failure mode as well.
Future<Object?> settle(FutureOr<Object?> Function() body) async {
  try {
    return await body();
  } catch (error) {
    return {'throws': describeError(error)};
  }
}

/// A stable description of a legacy error (no stack, no Dio prose).
Map<String, Object?> describeError(Object error) => switch (error) {
  HttpError() => {'type': 'HttpError', 'statusCode': error.statusCode, 'responseBody': error.responseBody},
  DouyuPlayApiException() => {
    'type': 'DouyuPlayApiException',
    'message': error.message,
    if (error.cause != null) 'cause': describeError(error.cause!),
  },
  FormatException() => {'type': 'FormatException', 'message': error.message},
  _ => {'type': error is Exception ? 'Exception' : error.runtimeType.toString(), 'message': error.toString()},
};

Map<String, Object?> qualityProjection(LivePlayQuality quality) {
  final data = quality.data;
  return {
    'quality': quality.quality,
    'id': quality.id,
    'sort': quality.sort,
    if (data is DouyuPlayData) 'rate': data.rate,
    if (data is DouyuPlayData) 'cdns': data.cdns,
  };
}

Map<String, Object?> resolutionProjection(LivePlayUrlResolution resolution) => {
  'urls': resolution.urls,
  'appliedQualityData': resolution.appliedQualityData,
  'qualityUnconfirmed': resolution.qualityUnconfirmed,
};

/// The form a recorded getH5PlayV1 sample was requested with (values scrubbed).
Map<String, String> recordedForm(FixtureSample sample) =>
    Uri.splitQueryString((sample.meta['request'] as Map<String, dynamic>)['body'] as String? ?? '');

/// Serves getH5PlayV1 samples by path + form `rate` + form `cdn`, and a
/// synthetic, unexpired getEncryption descriptor (the recorded S06 one expires
/// ten minutes after capture, so it cannot drive a replay).
class DouyuPlayAdapter implements HttpClientAdapter {
  DouyuPlayAdapter(this.samples);

  final List<FixtureSample> samples;
  final List<Map<String, String>> forms = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    final path = options.uri.path;
    if (path.endsWith('/getEncryption')) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final descriptor = {
        'error': 0,
        'data': {
          'key': 'fixture',
          'rand_str': 'fixture',
          'enc_data': 'fixture',
          'enc_time': 1,
          'is_special': 0,
          'expire_at': now + 3600,
        },
      };
      return Future.value(_json(utf8.encode(jsonEncode(descriptor)), 200, 'application/json'));
    }
    final form = Uri.splitQueryString(options.data as String);
    forms.add(form);
    final sample = samples.where((sample) {
      final recorded = recordedForm(sample);
      return sample.url.path == path && recorded['rate'] == form['rate'] && recorded['cdn'] == form['cdn'];
    }).firstOrNull;
    if (sample == null) {
      throw StateError('No recorded sample for POST $path rate=${form['rate']} cdn=${form['cdn']}');
    }
    return Future.value(_json(sample.bodyBytes, sample.status, sample.contentType));
  }

  static ResponseBody _json(List<int> bytes, int status, String contentType) => ResponseBody.fromBytes(
    bytes,
    status,
    headers: {
      Headers.contentTypeHeader: [contentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

/// Replays getH5PlayV1 [samples] through HttpClient.instance.dio for the
/// current test.
DouyuPlayAdapter replayPlay(List<FixtureSample> samples) {
  final dio = HttpClient.instance.dio;
  final previous = dio.httpClientAdapter;
  final adapter = DouyuPlayAdapter(samples);
  dio.httpClientAdapter = adapter;
  addTearDown(() => dio.httpClientAdapter = previous);
  return adapter;
}

LiveRoom douyuRoom(String roomId) => LiveRoom(roomId: roomId, platform: 'douyu');

/// Synthetic vectors (S07, S12): inputs live in the file, outputs are the
/// legacy results. PURELIVE_UPDATE_EXPECTED=1 rewrites the outputs.
void expectVectors(String path, String listKey, Map<String, Object?> Function(Map<String, dynamic> input) compute) {
  final file = File(path);
  final document = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final entries = (document[listKey] as List).cast<Map<String, dynamic>>();
  final update = Platform.environment['PURELIVE_UPDATE_EXPECTED'] == '1';
  for (final entry in entries) {
    final output = jsonDecode(jsonEncode(compute(entry['input'] as Map<String, dynamic>)));
    if (update) {
      entry['output'] = output;
    } else {
      expect(entry['output'], output, reason: '${entry['name']}');
    }
  }
  if (update) file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(document)}\n');
}

/// S07: one signing vector.
Map<String, Object?> signVector(Map<String, dynamic> input) {
  final key = Map<String, dynamic>.from(input['encryptionKey'] as Map);
  final tt = input['timestampSeconds'] as int;
  final usable = DouyuUtils.isEncryptionKeyUsable(key, nowSeconds: tt);
  try {
    final form = DouyuUtils.buildSignedData(
      encryptionKey: key,
      roomId: input['roomId'] as String,
      timestampSeconds: tt,
      rate: input['rate'] as int,
      cdn: input['cdn'] as String,
      deviceId: input['deviceId'] as String,
    );
    return {'isEncryptionKeyUsable': usable, 'form': form, 'fields': Uri.splitQueryString(form)};
  } catch (error) {
    return {'isEncryptionKeyUsable': usable, 'throws': describeError(error)};
  }
}

/// S12: one passport renewal case, following DouyuUtils.refreshSession (no
/// Set-Cookie means nothing is merged and the save time is not renewed).
Map<String, Object?> sessionCase(Map<String, dynamic> input) {
  DateTime? at(Object? seconds) =>
      seconds == null ? null : DateTime.fromMillisecondsSinceEpoch((seconds as int) * 1000, isUtc: true);
  String? iso(DateTime? time) => time?.toUtc().toIso8601String();
  final now = at(input['nowSeconds'])!;
  final savedAt = at(input['savedAtSeconds']);
  final stored = input['stored'] as String;
  final lines = (input['setCookie'] as List).cast<String>();
  Map<String, Object?> state(String cookie, DateTime? saved) => {
    'sessionExpiry': iso(DouyuUtils.sessionExpiry(cookie, now: now, savedAt: saved)),
    'sessionState': DouyuUtils.sessionState(cookie, now: now, savedAt: saved).name,
  };
  final merged = lines.isEmpty ? null : DouyuUtils.mergeSetCookieLines(stored, lines);
  return {
    'before': state(stored, savedAt),
    'merged': ?merged,
    if (merged != null) 'after': state(merged, now),
    'cookieHeader': DouyuUtils.cookieHeader(accountCookie: merged ?? stored),
  };
}
