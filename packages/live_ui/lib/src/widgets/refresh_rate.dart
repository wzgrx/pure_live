import 'dart:async';

import 'package:flutter/widgets.dart';

/// The display refresh policy of the Android settings (3.x
/// `AppRefreshRateMode`).
enum RefreshRateMode {
  /// Leave the rate to the system.
  powerSaving,

  /// The high rate while touching or scrolling, released 1.5 s after.
  balanced,

  /// The high rate whenever the app is in front.
  performance,
}

/// Decides when the window asks for the display's high refresh rate (3.x
/// `AdaptiveRefreshRateController`).
///
/// Pinning 120/144 Hz for the whole process doubles the frame pressure of
/// every animation and image update, so in [RefreshRateMode.balanced] the high
/// rate covers touches, scrolls and their animations and is released after
/// [settleDelay]. Requests go to `apply` one at a time, coalesced to the latest
/// (Android advises against changing the hint several times a second).
///
/// 3.x kept this state in statics; here it is an object the app owns, so two
/// windows or tests do not share it.
final class AdaptiveRefreshRateController {
  /// Creates the controller; `apply` asks the platform for the high rate
  /// (true) or the system's choice (false).
  new(this._apply);

  /// How long the high rate outlives the last interaction.
  static const Duration settleDelay = Duration(milliseconds: 1500);

  final Future<void> Function({required bool high}) _apply;
  Timer? _settleTimer;
  RefreshRateMode _mode = RefreshRateMode.powerSaving;
  bool _resumed = true;
  bool? _requestedHigh;
  int _activePointers = 0;
  Future<void> _queue = Future<void>.value();
  bool? _pending;

  /// The last state requested.
  bool get requestedHigh => _requestedHigh ?? false;

  /// The policy.
  RefreshRateMode get mode => _mode;

  /// Switches the policy.
  void setMode(RefreshRateMode mode) {
    _mode = mode;
    _activePointers = 0;
    _settleTimer?.cancel();
    _request(high: false);
  }

  /// A pointer went down.
  void beginPointer() {
    if (_mode != RefreshRateMode.balanced || !_resumed) return;
    _activePointers++;
    _settleTimer?.cancel();
    _request(high: true);
  }

  /// A pointer moved or a scroll is running.
  void keepInteractive() {
    if (_mode != RefreshRateMode.balanced || !_resumed) return;
    _request(high: true);
    if (_activePointers == 0) _scheduleSettle();
  }

  /// A pointer went up or was cancelled.
  void endPointer() {
    if (_activePointers > 0) _activePointers--;
    _settleIfIdle();
  }

  /// A scroll ended. 3.x counted this as a pointer going up, so a fling that
  /// ended (or a nested list's scroll end) under a finger still down started
  /// the release timer early.
  void endScroll() => _settleIfIdle();

  /// The app went to the background: release the high rate.
  void pause() {
    _resumed = false;
    _activePointers = 0;
    _settleTimer?.cancel();
    _request(high: false);
  }

  /// The app came back.
  void resume() {
    _resumed = true;
    _activePointers = 0;
    _settleTimer?.cancel();
    _request(high: false);
  }

  /// Stops the release timer.
  void dispose() => _settleTimer?.cancel();

  void _settleIfIdle() {
    if (_mode == RefreshRateMode.balanced && _resumed && _activePointers == 0) _scheduleSettle();
  }

  void _scheduleSettle() {
    _settleTimer?.cancel();
    _settleTimer = Timer(settleDelay, () => _request(high: false));
  }

  void _request({required bool high}) {
    final target = _resumed && (_mode == RefreshRateMode.performance || (_mode == RefreshRateMode.balanced && high));
    if (_requestedHigh == target) return;
    _requestedHigh = target;
    final idle = _pending == null;
    _pending = target;
    if (idle) _queue = _queue.then((_) => _drain());
  }

  Future<void> _drain() async {
    for (var value = _pending; value != null; value = _pending) {
      try {
        await _apply(high: value);
      } on Object catch (error, stack) {
        FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'live_ui'));
      }
      if (_pending == value) _pending = null;
    }
  }
}

/// Feeds pointer, scroll and lifecycle events of [child] to a
/// [AdaptiveRefreshRateController] (3.x `AdaptiveRefreshRateScope`; Android).
class AdaptiveRefreshRateScope extends StatefulWidget {
  /// Watches [child] for [controller] under [mode].
  const new({required this.controller, required this.mode, required this.child, super.key});

  /// The controller.
  final AdaptiveRefreshRateController controller;

  /// The policy.
  final RefreshRateMode mode;

  /// The app.
  final Widget child;

  @override
  State<AdaptiveRefreshRateScope> createState() => _AdaptiveRefreshRateScopeState();
}

class _AdaptiveRefreshRateScopeState extends State<AdaptiveRefreshRateScope> with WidgetsBindingObserver {
  AdaptiveRefreshRateController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller
      ..setMode(widget.mode)
      ..resume();
  }

  @override
  void didUpdateWidget(AdaptiveRefreshRateScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.pause();
      _controller
        ..setMode(widget.mode)
        ..resume();
    } else if (oldWidget.mode != widget.mode) {
      _controller.setMode(widget.mode);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android picture-in-picture is visible while Flutter reports inactive:
    // keep the policy there so the PiP danmaku and the native surface agree.
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.inactive) {
      _controller.resume();
    } else {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.pause();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _controller.keepInteractive();
    } else if (notification is ScrollEndNotification) {
      _controller.endScroll();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _controller.beginPointer(),
      onPointerMove: (_) => _controller.keepInteractive(),
      onPointerUp: (_) => _controller.endPointer(),
      onPointerCancel: (_) => _controller.endPointer(),
      child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
    );
  }
}
