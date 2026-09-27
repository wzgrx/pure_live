import 'dart:convert';

import 'package:live_record/src/chat.dart';
import 'package:live_record/src/files.dart';
import 'package:live_record/src/flv/flv_repair.dart';
import 'package:live_record/src/gaps.dart';
import 'package:live_record/src/naming.dart';
import 'package:path/path.dart' as p;

Future<String> _freeName(RecordFiles files, String path) async {
  final extension = p.extension(path);
  final stem = path.substring(0, path.length - extension.length);
  for (var n = 0; ; n++) {
    final candidate = n == 0 ? path : '$stem-$n$extension';
    if (!await files.exists(candidate)) return candidate;
  }
}

/// Finishes the files of a session the app did not close (spec §14.1): every
/// `<prefix>_NNN.flv.part` is cut after its last complete tag and renamed
/// (one without media is deleted), every chat `.xml.part` gets its closing
/// `</i>` and is renamed, an unfinished `.mp4.partial` is deleted, and
/// `gaps.json` gets a `crash` entry of unknown length. Returns the session's
/// FLV segments in order.
Future<List<String>> recoverSession(RecordFiles files, SessionLayout layout, {required String room}) async {
  final names = (await files.list(layout.directory)).where((name) => name.startsWith('${layout.prefix}_')).toList()
    ..sort();
  final segments = <String>[];
  var lastTimestamp = 0;
  for (final name in names) {
    final path = p.join(layout.directory, name);
    if (name.endsWith('.flv$partSuffix')) {
      final scan = await repairFlv(files, path);
      if (scan.mediaTags == 0) {
        await files.delete(path);
        continue;
      }
      final target = await _freeName(files, path.substring(0, path.length - partSuffix.length));
      await files.rename(path, target);
      segments.add(target);
      lastTimestamp = scan.lastTimestamp;
    } else if (name.endsWith('.flv')) {
      segments.add(path);
    } else if (name.endsWith('.xml$partSuffix')) {
      final text = utf8.decode(await files.read(path), allowMalformed: true);
      if (!text.trimRight().endsWith('</i>')) {
        await files.append(path, utf8.encode('${text.endsWith('\n') ? '' : '\n'}$chatXmlTail'));
      }
      await files.rename(path, await _freeName(files, path.substring(0, path.length - partSuffix.length)));
    } else if (name.endsWith(partialSuffix)) {
      await files.delete(path);
    }
  }
  segments.sort();
  final ledger = GapLedger(files: files, path: layout.gaps, room: room, session: layout.prefix);
  await ledger.load();
  await ledger.add(
    RecordGap(part: segments.isEmpty ? '' : p.basename(segments.last), atMs: lastTimestamp, reason: GapReason.crash),
  );
  return segments;
}
