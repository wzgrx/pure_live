import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_store/live_store.dart';
import 'package:pure_live_app/core/store.dart';

/// Asks the window for its highest refresh rate or gives the choice back.
typedef HighRefreshRequest = Future<void> Function({required bool high});

const _channel = MethodChannel('purelive/display');

Future<void> _noRequest({required bool high}) async {}

Future<void> _androidRequest({required bool high}) async {
  try {
    await _channel.invokeMethod<void>('setHighRefreshRate', {'enabled': high});
  } on Object {
    // No channel: the system keeps deciding.
  }
}

/// The 刷新率 setting on Android (F-SET-08): 省电 leaves the rate to the
/// system; 均衡 asks for the highest rate while a finger is down and for
/// [settle] after, then gives it back (one change per gesture: switching
/// modes can drop a frame); 最高 keeps it while the app is in front.
final class RefreshRateController {
  new(this._request, {this.settle = const Duration(milliseconds: 1500)});

  final HighRefreshRequest _request;

  /// How long 均衡 keeps the high rate after the last finger lifts.
  final Duration settle;

  RefreshRateMode _mode = RefreshRateMode.powerSaving;
  bool _resumed = true;
  int _pointers = 0;
  bool? _high;
  Timer? _settle;

  /// Whether the high rate is requested now.
  bool get high => _high ?? false;

  /// The mode in force.
  RefreshRateMode get mode => _mode;

  /// Applies [mode].
  set mode(RefreshRateMode mode) {
    _mode = mode;
    _pointers = 0;
    _settle?.cancel();
    _set(high: _wantsIdleHigh);
  }

  bool get _wantsIdleHigh => _resumed && _mode == RefreshRateMode.performance;

  /// A finger went down.
  void pointerDown() {
    if (_mode != RefreshRateMode.balanced || !_resumed) return;
    _pointers++;
    _settle?.cancel();
    _set(high: true);
  }

  /// A finger lifted or the gesture was cancelled.
  void pointerUp() {
    if (_pointers > 0) _pointers--;
    if (_mode != RefreshRateMode.balanced || !_resumed || _pointers > 0) return;
    _settle?.cancel();
    _settle = Timer(settle, () => _set(high: false));
  }

  /// Whether the app is in the foreground.
  bool get resumed => _resumed;

  /// The app went to the background or came back.
  set resumed(bool resumed) {
    _resumed = resumed;
    _pointers = 0;
    _settle?.cancel();
    _set(high: _wantsIdleHigh);
  }

  void _set({required bool high}) {
    if (_high == high) return;
    _high = high;
    unawaited(_request(high: high));
  }

  void dispose() => _settle?.cancel();
}

/// The app's refresh-rate controller; Android only (elsewhere the requests
/// go nowhere).
final Provider<RefreshRateController> refreshRateProvider = Provider<RefreshRateController>((ref) {
  final controller = RefreshRateController(Platform.isAndroid ? _androidRequest : _noRequest);
  ref.onDispose(controller.dispose);
  controller.mode = ref.watch(storeProvider).settings.get(Settings.refreshRateMode);
  final subscription = ref
      .watch(storeProvider)
      .settings
      .watch(Settings.refreshRateMode)
      .listen((mode) => controller.mode = mode);
  ref.onDispose(subscription.cancel);
  try {
    final lifecycle = AppLifecycleListener(
      onResume: () => controller.resumed = true,
      onPause: () => controller.resumed = false,
    );
    ref.onDispose(lifecycle.dispose);
  } on Object {
    // No widgets binding (unit tests).
  }
  return controller;
});

/// Feeds the app's pointers to the controller: wrap the router's child.
class RefreshRateScope extends ConsumerWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(refreshRateProvider);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => controller.pointerDown(),
      onPointerUp: (_) => controller.pointerUp(),
      onPointerCancel: (_) => controller.pointerUp(),
      child: child,
    );
  }
}
