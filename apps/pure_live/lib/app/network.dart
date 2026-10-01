import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The kind of network the device is on (3.x read connectivity_plus).
enum NetworkKind {
  /// No connection.
  none,

  /// Mobile data only.
  mobile,

  /// Wi-Fi, Ethernet or anything else (also "unknown").
  other,
}

/// Reads the current [NetworkKind].
typedef NetworkProbe = Future<NetworkKind> Function();

/// The kind of the connectivity results: none when there is no transport,
/// mobile when mobile data is the only one (3.x showed the mobile-data
/// notice whenever mobile was among them; Wi-Fi next to it is what carries
/// the traffic, so it no longer counts as mobile data).
NetworkKind networkKindOf(List<ConnectivityResult> results) {
  final active = results.where((result) => result != ConnectivityResult.none).toSet();
  if (active.isEmpty) return NetworkKind.none;
  if (active.contains(ConnectivityResult.mobile) &&
      !active.contains(ConnectivityResult.wifi) &&
      !active.contains(ConnectivityResult.ethernet)) {
    return NetworkKind.mobile;
  }
  return NetworkKind.other;
}

/// The network now (connectivity_plus). Desktops answer [NetworkKind.other]
/// without asking, and a failing plugin does too (3.x: no preflight on
/// desktops, fail open).
Future<NetworkKind> readNetworkKind() async {
  if (!Platform.isAndroid && !Platform.isIOS) return NetworkKind.other;
  try {
    return networkKindOf(await Connectivity().checkConnectivity());
  } on Object {
    return NetworkKind.other;
  }
}

/// How pages read the network (tests replace it).
final Provider<NetworkProbe> networkProbeProvider = Provider<NetworkProbe>((ref) => readNetworkKind);

/// A request was not sent because the device is offline (3.x
/// `network_disconnected`).
final class Offline implements Exception {
  /// Creates the failure.
  const new();

  @override
  String toString() => 'Offline';
}

/// The mobile-data notice of the lists (3.x `showCellularBanner`): shown
/// after a load on mobile data until the user picks "never show" (for the
/// rest of the session, as in 3.x).
abstract final class MobileDataNotice {
  /// Whether the last load ran on mobile data.
  static final ValueNotifier<bool> onMobileData = ValueNotifier(false);

  /// Whether the user hid the notice for this session.
  static final ValueNotifier<bool> dismissed = ValueNotifier(false);

  /// Checks the network before a list load: throws [Offline] when there is
  /// none and records whether it is mobile data.
  static Future<void> precheck(NetworkProbe probe) async {
    final kind = await probe();
    if (kind == NetworkKind.none) throw const Offline();
    onMobileData.value = kind == NetworkKind.mobile;
  }
}
