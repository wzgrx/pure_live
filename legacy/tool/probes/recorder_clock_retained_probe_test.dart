// Re-evaluate immutable framemd5 observations with exact rational clocks.
// This does not rerun the native recorder or rewrite its original verdict.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'frame_hash_timeline.dart';

void main() {
  for (final fixture in ['av_cfr', 'av_vfr', 'video_only', 'audio_only']) {
    test('exact rational verdict for retained $fixture native evidence', () async {
      final manifest =
          jsonDecode(await File(Platform.environment['PURELIVE_CLOCK_RETAINED_MANIFEST']!).readAsString()) as Map;
      final item = (manifest['fixtures'] as Map)[fixture] as Map;
      final directory = Directory(item['directory'] as String);
      final texts = <String, String>{};
      for (final entry in (item['files'] as Map).entries) {
        final name = entry.key as String;
        expect(
          name == 'summary.json' ||
              RegExp(r'^(source|single|legacy|candidate)-(video|audio)\.framemd5$').hasMatch(name),
          true,
        );
        final bytes = await File(p.join(directory.path, name)).readAsBytes();
        expect(bytes.length, lessThanOrEqualTo(4 * 1024 * 1024));
        expect(sha256.convert(bytes).toString(), entry.value, reason: name);
        texts[name] = utf8.decode(bytes);
      }
      final original = jsonDecode(texts['summary.json']!) as Map;
      expect(original['fixture'], fixture);
      expect(original['stage'], 'comparison-gates');
      final report = <String, Object?>{
        'fixture': fixture,
        'newNativeRun': false,
        'originalNativeContract': original['contract'],
        'sourceHashesVerified': true,
        'contract': 'failed',
      };
      final comparisons = <String, Map<String, Map<String, Object?>>>{};
      for (final media in ['video', 'audio']) {
        if (!texts.containsKey('source-$media.framemd5')) continue;
        final source = FrameHashTimeline.parse(texts['source-$media.framemd5']!);
        final single = FrameHashTimeline.parse(texts['single-$media.framemd5']!);
        final legacy = FrameHashTimeline.parse(texts['legacy-$media.framemd5']!);
        final candidate = FrameHashTimeline.parse(texts['candidate-$media.framemd5']!);
        comparisons[media] = {
          'sourceToSingle': source.compare(single),
          'sourceToCandidate': source.compare(candidate),
          'singleToLegacy': single.compare(legacy),
          'singleToCandidate': single.compare(candidate),
        };
      }
      report['comparisons'] = comparisons;
      try {
        for (final entry in comparisons.entries) {
          for (final comparison in entry.value.values) {
            expect(comparison['orderedContentEqual'], true);
          }
          final spread = entry.value['singleToCandidate']!['offsetSpreadSeconds'] as double;
          expect(spread, lessThanOrEqualTo(entry.key == 'video' ? 2 / 90000 : 2 / 44100));
        }
        if (fixture == 'av_cfr') {
          expect(comparisons['video']!['singleToLegacy']!['offsetSpreadSeconds'] as double, greaterThan(0.001));
        }
        report['contract'] = 'passed';
      } finally {
        await File(p.join(directory.path, 'exact-clock-verdict.json'))
            .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        // ignore: avoid_print
        print(jsonEncode(report));
      }
    }, skip: Platform.environment['PURELIVE_CLOCK_RETAINED_MANIFEST'] == null);
  }
}
