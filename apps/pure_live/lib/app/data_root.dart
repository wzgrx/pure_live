import 'dart:io';

import 'package:live_store/live_store.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32_registry/win32_registry.dart';

/// Where the app keeps its data (database, IPTV files).
///
/// - Windows: `UserData` beside the exe, so a portable copy carries its
///   data; the per-user application support folder when that cannot be
///   written (Program Files, read-only media). Never 3.x's
///   `<exe folder>\AppData`, which is only read by the 3.x import.
/// - Android: the application support folder (`files`).
///
/// Every desktop window uses this folder: an extra window shares the main
/// window's data (docs/ui/compare/U.13 c14; 3.x gave it a copy under
/// `instances\<id>`, which was lost when it closed). Only its log goes to
/// [instanceFolder].
/// Design borrowed from the archived v4 (`apps/pure_live/lib/core/data_root.dart`).
Future<Directory> resolveDataRoot({String? executable}) async {
  if (Platform.isWindows) {
    final root = Directory(portableDataDir(executable ?? Platform.resolvedExecutable));
    if (await isWritableDirectory(root)) return root;
  }
  return await getApplicationSupportDirectory();
}

/// An extra window's own folder (its log) under [root]: `instances\<id>`,
/// as 3.x named it.
Directory instanceFolder(Directory root, String instanceId) => Directory(p.join(root.path, 'instances', instanceId));

/// `UserData` beside [executable].
String portableDataDir(String executable) => p.join(p.dirname(executable), 'UserData');

/// Whether [directory] exists or can be made, and takes a file.
Future<bool> isWritableDirectory(Directory directory) async {
  try {
    await directory.create(recursive: true);
    final probe = File(p.join(directory.path, '.write-test'));
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

/// 3.x's settings boxes on this device, main source first (M9
/// `LegacyLocations`); empty where 3.x never ran.
Future<List<String>> legacyHiveFiles() async {
  if (Platform.isAndroid) {
    final documents = await getApplicationDocumentsDirectory();
    return [
      for (final path in LegacyLocations.android(documentsDirectory: documents.path))
        if (File(path).existsSync()) path,
    ];
  }
  if (Platform.isWindows) {
    return await LegacyLocations.windows(
      executableDirectory: p.dirname(Platform.resolvedExecutable),
      supportDirectory: (await getApplicationSupportDirectory()).path,
      documentsDirectory: (await getApplicationDocumentsDirectory()).path,
      installDirectories: windowsInstallLocations(),
    );
  }
  return const [];
}

/// Install folders of Pure Live from the uninstall entries (current user and
/// machine, both registry views), so a 3.x installed elsewhere is found
/// (3.x `AppPathManager._readWindowsInstallLocations`).
List<String> windowsInstallLocations() {
  final locations = <String>{};
  const uninstallPaths = [
    r'Software\Microsoft\Windows\CurrentVersion\Uninstall',
    r'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
  ];
  final name = RegExp('纯粹直播|pure[ _-]?live', caseSensitive: false);
  final uninstaller = RegExp(r'^"?([^"]+\\)unins\d*\.exe', caseSensitive: false);
  for (final root in [CURRENT_USER, LOCAL_MACHINE]) {
    for (final path in uninstallPaths) {
      RegistryKey? uninstall;
      try {
        uninstall = root.open(path);
        for (final childName in uninstall.keys) {
          RegistryKey? child;
          try {
            child = uninstall.open(childName);
            if (!name.hasMatch(child.getString('DisplayName') ?? '')) continue;
            var location = (child.getString('InstallLocation') ?? '').trim();
            if (location.isEmpty) {
              location = uninstaller.firstMatch(child.getString('UninstallString') ?? '')?.group(1) ?? '';
            }
            if (location.isNotEmpty) locations.add(location.replaceAll(RegExp(r'[\\/]+$'), ''));
          } on Object {
            // A stale or access-restricted entry.
          } finally {
            child?.close();
          }
        }
      } on Object {
        // A registry view may not exist.
      } finally {
        uninstall?.close();
      }
    }
  }
  return locations.toList();
}
