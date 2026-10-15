import 'dart:developer';
import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

/// The current user's start-up programs (3.x `WindowsAutoStart`).
const String startupRunKey = r'Software\Microsoft\Windows\CurrentVersion\Run';

/// v4's own value name under [startupRunKey]. 3.x's entry (`PureLive`) and
/// its install are never read or changed, so both versions can sit side by
/// side until M15 decides how v4 replaces 3.x.
const String startupValueName = 'PureLiveV4';

/// The command of the entry: the running exe, quoted (3.x).
String startupCommand(String executable) => '"$executable"';

/// Whether [command] starts [executable] (3.x `commandTargetsExecutable`).
bool commandTargets(String? command, String executable) {
  final value = command?.trim() ?? '';
  if (value.isEmpty || executable.trim().isEmpty) return false;
  final String path;
  if (value.startsWith('"')) {
    final end = value.indexOf('"', 1);
    if (end <= 1) return false;
    path = value.substring(1, end);
  } else {
    final space = value.indexOf(RegExp(r'\s'));
    path = space < 0 ? value : value.substring(0, space);
  }
  String normal(String text) => text.trim().replaceAll('/', r'\').toLowerCase();
  return normal(path) == normal(executable);
}

/// The Linux start-up entry's file name under `~/.config/autostart/`
/// (XDG autostart).
const String linuxAutostartFile = 'purelive.desktop';

/// The XDG autostart entry that starts [executable].
String linuxAutostartEntry(String executable) =>
    '[Desktop Entry]\nType=Application\nName=PureLive\nExec="$executable"\nX-GNOME-Autostart-enabled=true\n';

/// The folder of the current user's XDG autostart entries.
Directory linuxAutostartDirectory({Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final config = env['XDG_CONFIG_HOME'];
  final base = config != null && config.isNotEmpty ? config : '${env['HOME'] ?? ''}/.config';
  return Directory('$base/autostart');
}

/// Adds or removes this exe's start-up entry (`HKCU\...\Run\PureLiveV4`
/// on Windows, `~/.config/autostart/purelive.desktop` on Linux); true when
/// the entry now matches [enabled]. Nothing elsewhere.
Future<bool> applyStartupEntry({required bool enabled, String? executable, Directory? autostartDirectory}) async {
  if (Platform.isLinux || autostartDirectory != null) {
    final file = File('${(autostartDirectory ?? linuxAutostartDirectory()).path}/$linuxAutostartFile');
    try {
      if (enabled) {
        await file.parent.create(recursive: true);
        await file.writeAsString(linuxAutostartEntry(executable ?? Platform.resolvedExecutable));
      } else if (file.existsSync()) {
        await file.delete();
      }
      return true;
    } on Object catch (error, stack) {
      log('Start-up entry failed', name: 'Desktop', error: error, stackTrace: stack);
      return false;
    }
  }
  if (!Platform.isWindows) return true;
  final exe = executable ?? Platform.resolvedExecutable;
  RegistryKey? key;
  try {
    key = CURRENT_USER.create(startupRunKey);
    final current = key.getString(startupValueName);
    if (enabled) {
      if (!commandTargets(current, exe)) key.setValue(startupValueName, RegistryValue.string(startupCommand(exe)));
    } else if (current != null) {
      key.removeValue(startupValueName);
    }
    return true;
  } on Object catch (error, stack) {
    log('Start-up entry failed', name: 'Desktop', error: error, stackTrace: stack);
    return false;
  } finally {
    key?.close();
  }
}
