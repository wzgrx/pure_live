import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Where the app keeps its data (database, secrets, logs, IPTV files,
/// recordings by default).
///
/// Windows (F-WIN-06): [portableDataDir] beside the exe, so a portable copy
/// carries its data; when that folder cannot be written (Program Files,
/// read-only media) the per-user application support folder. It never uses
/// 3.x's `<exe folder>\AppData`, which v4 only reads for the import
/// (store.md §1). Elsewhere: the application support folder.
Future<Directory> resolveDataRoot({String? executable}) async {
  if (Platform.isWindows) {
    final portable = Directory(portableDataDir(executable ?? Platform.resolvedExecutable));
    if (await isWritableDirectory(portable)) return portable;
  }
  return await getApplicationSupportDirectory();
}

/// The portable data folder of the exe at [executable]: `UserData` beside
/// it. Not `data`: that is Flutter's own folder (flutter_assets, app.so,
/// icudtl.dat), which an update or a new portable copy replaces whole.
String portableDataDir(String executable, {String separator = r'\'}) {
  final cut = executable.lastIndexOf(RegExp(r'[\\/]'));
  final folder = cut < 0 ? '.' : executable.substring(0, cut);
  return '$folder${separator}UserData';
}

/// Whether [directory] exists or can be made, and takes a file.
Future<bool> isWritableDirectory(Directory directory) async {
  try {
    await directory.create(recursive: true);
    final probe = File('${directory.path}${Platform.pathSeparator}.write-test');
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// The data root; main() overrides it with [resolveDataRoot]'s answer.
final dataRootProvider = Provider<Directory>((ref) => throw StateError('The data root is resolved in main()'));
