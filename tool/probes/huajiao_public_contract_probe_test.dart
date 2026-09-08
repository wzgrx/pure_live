// Opt-in anonymous H5 data probe. No cookies, media download or device actions.
import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/huajiao/huajiao_api.dart';

void main() {
  test(
    'production Huajiao API preserves pagination and current owner/media identity',
    () async {
      await io.HttpOverrides.runWithHttpOverrides(() async {
        final original = HttpClient.instance.dio;
        final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)))
          ..httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () => io.HttpClient()..findProxy = (_) => 'DIRECT',
          );
        HttpClient.instance.dio = dio;
        try {
          final api = HuajiaoApi();
          final first = await api.directory();
          final second = first.hasMore ? await api.directory(offset: first.nextOffset) : null;
          expect(
            first.feeds.length + (second?.feeds.length ?? 0),
            greaterThan(0),
            reason: 'Current directory yielded no public rows; do not count empty pages as directory coverage',
          );
          final uid = io.Platform.environment['PURELIVE_HUAJIAO_UID']!;
          final room = await api.room(uid);
          expect(
            room.owner.isLive,
            isTrue,
            reason: 'Explicit public sample no longer live; select a fresh public sample',
          );
          expect(room.broadcast!.feed.userId, uid);
          expect(room.broadcast!.feed.liveId, room.owner.liveId);
          expect(room.broadcast!.media, isNotEmpty);
          final refreshed = await api.room(uid);
          expect(refreshed.broadcast, isNotNull);
          expect(refreshed.broadcast!.feed.userId, uid);
          final result = {
            'utc': DateTime.now().toUtc().toIso8601String(),
            'firstPage': {'rows': first.feeds.length, 'nextOffset': first.nextOffset, 'hasMore': first.hasMore},
            'secondPage': second == null
                ? null
                : {'rows': second.feeds.length, 'nextOffset': second.nextOffset, 'hasMore': second.hasMore},
            'ownerMatchesBroadcast': true,
            'refreshedOwnerMatchesBroadcast': true,
            'broadcastChangedBetweenReads': room.owner.liveId != refreshed.owner.liveId,
            'mediaFormats': room.broadcast!.media.map((e) => e.format).toList(),
            'mediaHosts': room.broadcast!.media.map((e) => Uri.parse(e.url).host).toSet().toList(),
            'routing': 'anonymous direct Dio; application proxy not exercised',
            'applicationRegistered': false,
            'mediaDownloaded': false,
            'nativePlaybackOrRecording': false,
          };
          final output = io.Platform.environment['PURELIVE_HUAJIAO_OUTPUT'];
          if (output != null) {
            await io.File(output).writeAsString('${const JsonEncoder.withIndent('  ').convert(result)}\n');
          }
          // ignore: avoid_print
          print(jsonEncode(result));
        } finally {
          HttpClient.instance.dio = original;
          dio.close(force: true);
        }
      }, _RealNetwork());
    },
    skip: io.Platform.environment['PURELIVE_HUAJIAO_UID'] == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _RealNetwork extends io.HttpOverrides {}
