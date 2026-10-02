// The host side of the frame benchmarks (P05): `flutter drive --profile`
// runs integration_test/perf_test.dart on the phone and hands what it
// reported to this, which writes it to build/perf/perf-<time>.json and prints
// one line per scenario. See docs/cloud/records/P05.md for the command.
import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 30),
  responseDataCallback: (data) async {
    if (data == null) {
      stdout.writeln('perf: the app reported nothing');
      return;
    }
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp('[^0-9T]'), '').substring(0, 15);
    final file = File('build/perf/perf-$stamp.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    stdout
      ..writeln('perf: device ${jsonEncode(data['device'])}')
      ..writeln('perf: wrote ${file.absolute.path}');
    final scenarios = data['scenarios'];
    if (scenarios is! Map<String, dynamic>) return;
    for (final MapEntry(:key, :value) in scenarios.entries) {
      if (value is! Map<String, dynamic>) continue;
      final build = value['buildMs'] as Map<String, dynamic>;
      final raster = value['rasterMs'] as Map<String, dynamic>;
      final jank = value['jank'] as Map<String, dynamic>;
      stdout.writeln(
        'perf: ${key.padRight(26)} ${value['frames'].toString().padLeft(5)} frames  '
        'build P90 ${build['p90']} P99 ${build['p99']}  raster P90 ${raster['p90']} P99 ${raster['p99']}  '
        'jank ${((jank['rate'] as num) * 100).toStringAsFixed(2)}% (run ${jank['longestRun']})  '
        '${value['passed'] == true ? 'PASS' : 'FAIL'}',
      );
    }
  },
);
