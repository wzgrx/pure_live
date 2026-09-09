// Opt-in current metadata only. It does not assert a playable live stream.
import 'dart:convert';
import 'dart:io' as io;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/zhanqi/zhanqi_api.dart';

void main() {
  test(
    'Zhanqi production directory and room identity metadata contract',
    () async {
      final report = <String, Object?>{
        'utc': DateTime.now().toUtc().toIso8601String(),
        'route': 'DIRECT',
        'contract': 'failed',
        'stage': 'directory',
        'mediaValidated': false,
        'http': <Map<String, Object?>>[],
      };
      await io.HttpOverrides.runWithHttpOverrides(() async {
        final previous = HttpClient.instance.dio;
        final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)))
          ..httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () => io.HttpClient()..findProxy = (_) => 'DIRECT',
          );
        dio.interceptors.add(
          InterceptorsWrapper(
            onResponse: (response, handler) {
              (report['http'] as List).add({
                'kind': response.requestOptions.uri.path.contains('/domain/') ? 'room' : 'directory',
                'status': response.statusCode,
                'redirectsDisabled': !response.requestOptions.followRedirects,
                'refererMatches': response.requestOptions.headers['Referer'] == '${ZhanqiApi.origin}/',
              });
              handler.next(response);
            },
          ),
        );
        HttpClient.instance.dio = dio;
        try {
          final api = ZhanqiApi();
          final first = await api.directory();
          expect(first.rooms, isNotEmpty);
          report.addAll({
            'directoryCards': first.rooms.length,
            'reportedTotal': first.reportedTotal,
            'hasMore': first.hasMore,
          });
          final second = await api.directory(page: 2);
          report.addAll({
            'secondPageCards': second.rooms.length,
            'secondPageReportedTotal': second.reportedTotal,
            'secondPageHasMore': second.hasMore,
          });
          final selected = first.rooms.first;
          report['stage'] = 'room';
          final room = await api.room(
            code: selected.code,
            expectedRoomId: selected.roomId,
            expectedOwnerId: selected.ownerId,
          );
          expect(room.code, selected.code);
          expect(room.roomId, selected.roomId);
          expect(room.ownerId, selected.ownerId);
          for (final row in report['http'] as List<Map<String, Object?>>) {
            expect(row['redirectsDisabled'], isTrue);
            expect(row['refererMatches'], isTrue);
          }
          report.addAll({
            'contract': 'passed',
            'stage': 'complete',
            'identitiesMatch': true,
            'reportedStatus': room.reportedStatus,
            'reportedLive': room.reportedLive,
            'hasDeclaredStream': room.declaredStream != null,
          });
        } on ZhanqiException catch (error) {
          report['failure'] = error.kind.name;
          rethrow;
        } finally {
          HttpClient.instance.dio = previous;
          dio.close(force: true);
          final output = io.Platform.environment['PURELIVE_ZHANQI_OUTPUT'];
          if (output != null) {
            await io.File(output).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
          }
          // ignore: avoid_print
          print(jsonEncode(report));
        }
      }, _RealNetwork());
    },
    skip: io.Platform.environment['PURELIVE_ZHANQI_METADATA_PROBE'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _RealNetwork extends io.HttpOverrides {}
