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

/// Adds or removes this exe's start-up entry (`HKCU\...\Run\PureLiveV4`);
/// true when the registry now matches [enabled]. Nothing off Windows.
Future<bool> applyStartupEntry({required bool enabled, String? executable}) async {
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
