import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The battery level the fullscreen bars show beside the clock (3.x
/// `BatteryInfo` via battery_plus; docs/A-界面设计/A07-直播间界面/A07.4-横屏全屏 change 4): Android
/// from the activity (`pure_live/device_controls`), Windows from
/// `GetSystemPowerStatus`, Linux from `/sys/class/power_supply`. Null where
/// the device has no battery (most desktops) or it cannot be read: the bars
/// then show only the time.
abstract final class DeviceBattery {
  static const MethodChannel _channel = MethodChannel('pure_live/device_controls');

  /// The charge in percent, or null.
  static Future<int?> level() async {
    if (kIsWeb) return null;
    try {
      if (Platform.isAndroid) return _valid(await _channel.invokeMethod<int>('getBattery'));
      if (Platform.isWindows) return _windows();
      if (Platform.isLinux) return await _linux();
    } on Object {
      return null;
    }
    return null;
  }

  static int? _valid(int? value) => value == null || value < 0 || value > 100 ? null : value;

  static int? _windows() {
    // SYSTEM_POWER_STATUS: ACLineStatus, BatteryFlag, BatteryLifePercent,
    // SystemStatusFlag (one byte each), then two DWORDs.
    final status = calloc<Uint8>(12);
    try {
      final kernel = DynamicLibrary.open('kernel32.dll');
      final get = kernel.lookupFunction<Int32 Function(Pointer<Uint8>), int Function(Pointer<Uint8>)>(
        'GetSystemPowerStatus',
      );
      if (get(status) == 0) return null;
      // 128: no system battery; 255: unknown.
      if (status[1] == 128 || status[1] == 255) return null;
      return _valid(status[2]);
    } finally {
      calloc.free(status);
    }
  }

  static Future<int?> _linux() async {
    final supplies = Directory('/sys/class/power_supply');
    if (!supplies.existsSync()) return null;
    await for (final entry in supplies.list()) {
      final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (!name.startsWith('BAT')) continue;
      final capacity = File('${entry.path}/capacity');
      if (!capacity.existsSync()) continue;
      return _valid(int.tryParse((await capacity.readAsString()).trim()));
    }
    return null;
  }
}
