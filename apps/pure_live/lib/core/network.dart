import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The kind of network the device is on (live-room Q-2, F-NEW-10).
enum NetworkKind {
  /// Wi-Fi, Ethernet or anything else that is not metered cellular.
  unmetered,

  /// Mobile data only: the cellular quality preference applies.
  cellular,

  /// No network.
  offline,
}

/// Reads connectivity results as one [NetworkKind]: Wi-Fi or Ethernet wins
/// over mobile data (a phone on Wi-Fi also reports mobile on some ROMs); a
/// VPN over mobile data is still cellular; only `none` or nothing is offline.
NetworkKind networkKindOf(List<ConnectivityResult> results) {
  final links = results.where((result) => result != ConnectivityResult.none).toSet();
  if (links.isEmpty) return NetworkKind.offline;
  if (links.contains(ConnectivityResult.wifi) || links.contains(ConnectivityResult.ethernet)) {
    return NetworkKind.unmetered;
  }
  return links.contains(ConnectivityResult.mobile) ? NetworkKind.cellular : NetworkKind.unmetered;
}

/// The network the device is on; unmetered until the platform answers, so a
/// missing plugin never blocks playback.
final StreamProvider<NetworkKind> networkKindProvider = StreamProvider<NetworkKind>((ref) async* {
  final connectivity = Connectivity();
  final changes = StreamController<NetworkKind>();
  final subscription = connectivity.onConnectivityChanged.listen(
    (results) => changes.add(networkKindOf(results)),
    onError: (Object _) {},
  );
  ref.onDispose(() {
    unawaited(subscription.cancel());
    unawaited(changes.close());
  });
  try {
    yield networkKindOf(await connectivity.checkConnectivity());
  } on Object {
    // No plugin on this platform: take the network as unmetered.
    yield NetworkKind.unmetered;
  }
  yield* changes.stream;
});
