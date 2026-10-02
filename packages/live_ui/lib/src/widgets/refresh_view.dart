import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:live_ui/src/icons/app_icons.dart';
import 'package:live_ui/src/scope.dart';
import 'package:live_ui/src/theme/motion.dart';
import 'package:live_ui/src/theme/text_styles.dart';
import 'package:live_ui/src/widgets/status_view.dart';

// Pull to refresh with 3.x's feel (docs/T14/T14c/T14c.1/brief.md, research
// 2026-10-02 §2.2–2.3 option A): 3.x's lists sat in easy_refresh 3.5.1's
// `EasyRefresh` with its `ClassicHeader`, so they decelerated and bounced
// like iOS (`_ERScrollPhysics extends BouncingScrollPhysics`), drew no
// stretch, and showed the classic header. This is that behaviour, ported
// for the one header the app uses; easy_refresh is not a dependency.

/// A refresh that failed: [AppRefreshView.onRefresh] completes with one to
/// show "刷新失败", with [reason] under it (U.1c c19).
@immutable
final class AppRefreshFailure {
  /// Creates the failure.
  const new([this.reason]);

  /// One sentence on what went wrong; null shows the last refresh time.
  final String? reason;
}

/// Where the refresh header is (easy_refresh's `IndicatorMode`).
enum AppRefreshMode {
  /// Hidden.
  idle,

  /// Pulled, not far enough to refresh on release ("下拉刷新").
  drag,

  /// Pulled as far as the header is tall: releasing refreshes ("松开刷新").
  armed,

  /// Released past the header's height; settling at it, then the refresh
  /// starts.
  ready,

  /// The refresh runs; the header stays at the top ("正在刷新...").
  refreshing,

  /// The refresh ended; its result shows for [AppRefreshView.resultDuration]
  /// ("刷新成功" or "刷新失败").
  finished,

  /// Springing back after [finished].
  closing,
}

/// A list that refreshes when pulled down, with 3.x's touch feel (U.1c c19,
/// docs/T14/T14c/T14c.1/brief.md):
///
/// * both ends spring back when pulled past them (Bouncing), and a fling
///   decelerates like iOS: 3.x's main lists. There is no stretch or glow;
/// * a fling stops at the top instead of uncovering the header (3.x's
///   header did not "hit over"); with [stopAtEnd] a fling also stops at the
///   end, where the list shows its loading footer (3.x's footer);
/// * the classic header: an arrow and "下拉刷新", the arrow turns over and
///   "松开刷新" once pulled as far as the header is tall (the trigger), a
///   spinner in the loading style and "正在刷新..." while [onRefresh] runs
///   with the header held at the top, then "刷新成功" or "刷新失败" for a
///   second before it springs back; "上次刷新时间 H:mm" under the words.
///
/// The list must use the physics [builder] gets: physics of its own would
/// take over the edges.
class AppRefreshView extends StatefulWidget {
  /// Creates the view.
  const new({required this.onRefresh, required this.builder, this.stopAtEnd = false, super.key});

  /// How long the result shows before the header closes (3.x's
  /// `processedDuration`).
  static const Duration resultDuration = Duration(seconds: 1);

  /// The fewest logical pixels the header is tall (3.x's trigger offset);
  /// larger text makes it taller.
  static const double minTriggerOffset = 70;

  /// Refreshes; completes with an [AppRefreshFailure] (or throws) when the
  /// refresh failed.
  final Future<Object?> Function() onRefresh;

  /// Builds the list with the physics it must use.
  final Widget Function(BuildContext context, ScrollPhysics physics) builder;

  /// A fling stops at the end instead of bouncing: the list ends in a
  /// footer that loads more (3.x's loading footer).
  final bool stopAtEnd;

  @override
  State<AppRefreshView> createState() => AppRefreshViewState();
}

/// The state of an [AppRefreshView]; [show] refreshes as if pulled.
class AppRefreshViewState extends State<AppRefreshView> {
  late final _RefreshTracker _tracker = _RefreshTracker(onRefresh: () => widget.onRefresh())
    ..stopAtEnd = widget.stopAtEnd;
  late final ScrollPhysics _physics = _RefreshScrollPhysics(tracker: _tracker);
  _HeaderLayout? _layout;

  /// Where the header is.
  AppRefreshMode get mode => _tracker.mode;

  /// Pulls the list down past the header and lets go, like 3.x's
  /// `callRefresh`: the header shows and [AppRefreshView.onRefresh] runs.
  /// Does nothing while a refresh runs.
  Future<void> show() => _tracker.show();

  @override
  void didUpdateWidget(AppRefreshView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tracker.stopAtEnd = widget.stopAtEnd;
  }

  @override
  void dispose() {
    _tracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final styles = AppTextStyles(theme);
    final words = LiveUiScope.of(context).strings;
    final titleStyle = styles.t15Medium.copyWith(color: theme.colorScheme.onSurface);
    final messageStyle = styles.t12.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
        final layout = _layout = _HeaderLayout.measure(
          context,
          previous: _layout,
          width: width,
          words: words,
          titleStyle: titleStyle,
          messageStyle: messageStyle,
        );
        _tracker.trigger = layout.height;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            ScrollConfiguration(
              // 3.x's `ERScrollBehavior`: the list springs back, so no stretch.
              behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
              child: widget.builder(context, _physics),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              // A finger on the header still drags the list under it.
              child: IgnorePointer(
                child: ListenableBuilder(
                  listenable: _tracker,
                  builder: (context, _) => _RefreshHeader(
                    tracker: _tracker,
                    layout: layout,
                    words: words,
                    titleStyle: titleStyle,
                    messageStyle: messageStyle,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The header's state at a ballistic start (easy_refresh's
/// `_BallisticSimulationCreationState`): a list resting past its edge gets a
/// new simulation only when this changed, so a header held at the top stays.
@immutable
final class _Snapshot {
  const new(this.mode, this.offset, this.trigger);

  final AppRefreshMode mode;
  final double offset;
  final double trigger;

  bool needsSimulation(_Snapshot next) =>
      mode != next.mode || offset != next.offset || (next.mode == AppRefreshMode.ready && next.offset >= trigger);
}

/// The header's state and the edge rules of [_RefreshScrollPhysics]
/// (easy_refresh's `HeaderNotifier` for a `ClassicHeader`: not clamping,
/// no secondary, no infinite scroll, no safe area).
class _RefreshTracker extends ChangeNotifier {
  new({required this._onRefresh});

  final Future<Object?> Function() _onRefresh;

  /// How far the header is pulled to refresh: its height.
  double trigger = AppRefreshView.minTriggerOffset;

  /// See [AppRefreshView.stopAtEnd].
  bool stopAtEnd = false;

  AppRefreshMode _mode = AppRefreshMode.idle;
  AppRefreshMode get mode => _mode;

  /// How far the list is pulled past its top.
  double _offset = 0;
  double get offset => _offset;

  /// The last refresh failed (with its reason).
  AppRefreshFailure? get failure => _failure;
  AppRefreshFailure? _failure;

  /// When the list was shown or last refreshed (3.x's `_updateTime`).
  DateTime get lastRefreshed => _lastRefreshed;
  DateTime _lastRefreshed = DateTime.now();

  ScrollMetrics? _position;
  double? _lastMaxScrollExtent;
  _Snapshot _lastSnapshot = const _Snapshot(AppRefreshMode.idle, 0, AppRefreshView.minTriggerOffset);
  double _releaseOffset = 0;
  bool _running = false;
  bool _disposed = false;
  bool _notifyScheduled = false;
  Timer? _resultTimer;

  /// A finger moves the list (easy_refresh's `userOffsetNotifier`).
  bool get dragging => _dragging;
  bool _dragging = false;
  set dragging(bool value) {
    if (value == _dragging) return;
    _dragging = value;
    if (!value) _releaseOffset = _offset;
  }

  bool get _locked => _mode == AppRefreshMode.refreshing || _mode == AppRefreshMode.finished;

  /// How far past its top the list rests: the header's height while it is
  /// held, else nothing.
  double get overExtent => _mode == AppRefreshMode.ready || _locked ? trigger : 0;

  @override
  void dispose() {
    _disposed = true;
    _resultTimer?.cancel();
    super.dispose();
  }

  /// Rebuilds the header; after the frame when asked during layout (a
  /// ballistic restart from `applyNewDimensions`).
  void _notify() {
    if (_disposed) return;
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    binding.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _setPosition(ScrollMetrics position) {
    _position = position;
    _lastMaxScrollExtent = position.maxScrollExtent;
  }

  /// easy_refresh's `_ERScrollPhysics.applyBoundaryConditions`, header part
  /// plus its loading footer's stop.
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final min = position.minScrollExtent;
    final max = position.maxScrollExtent;
    final pixels = position.pixels;
    // A fling (not a finger) stops at the top: 3.x's header does not "hit
    // over" (`hitOver: false`).
    if (!_locked && _mode != AppRefreshMode.ready && value < min && (min < pixels || (!_dragging && min == pixels))) {
      _updateOffset(position, min);
      return value - min;
    }
    // While a refresh runs, a fling stops at the held header.
    if (_locked && value + trigger < min && (min < pixels + trigger || (!_dragging && min == pixels + trigger))) {
      _updateOffset(position, min - trigger);
      return value + trigger - min;
    }
    // The loading footer: a fling stops at the end.
    if (stopAtEnd &&
        _mode != AppRefreshMode.refreshing &&
        max > min &&
        (pixels < max || (!_dragging && pixels == max)) &&
        max < value) {
      _updateOffset(position, max);
      return value - max;
    }
    _updateOffset(position, value);
    return 0;
  }

  /// easy_refresh's `_ERScrollPhysics.createBallisticSimulation`.
  Simulation? createBallisticSimulation(_RefreshScrollPhysics physics, ScrollMetrics position, double velocity) {
    final tolerance = physics.toleranceFor(position);
    final wasDragging = _dragging;
    dragging = false;
    final oldMaxScrollExtent = _lastMaxScrollExtent ?? position.maxScrollExtent;
    _updateOffset(position, position.pixels);
    final snapshot = _Snapshot(_mode, _offset, trigger);
    Simulation? simulation;
    if (velocity.abs() >= tolerance.velocity ||
        (_mode != AppRefreshMode.idle &&
            oldMaxScrollExtent != position.maxScrollExtent &&
            position.maxScrollExtent != 0) ||
        (position.outOfRange && (wasDragging || _lastSnapshot.needsSimulation(snapshot)))) {
      simulation = BouncingScrollSimulation(
        spring: physics.spring,
        position: position.pixels,
        velocity: velocity,
        leadingExtent: position.minScrollExtent - overExtent,
        trailingExtent: position.maxScrollExtent,
        tolerance: tolerance,
      );
    }
    _lastSnapshot = snapshot;
    return simulation;
  }

  /// Follows the list to [value] (easy_refresh's `_updateOffset`).
  void _updateOffset(ScrollMetrics position, double value) {
    _setPosition(position);
    final oldOffset = _offset;
    final oldMode = _mode;
    _offset = math.max(position.minScrollExtent - value, 0);
    if ((_offset - trigger).abs() <= precisionErrorTolerance) _offset = trigger;
    if (oldOffset == 0 && _offset == 0) {
      if (_mode == AppRefreshMode.closing) {
        _updateMode();
        _notify();
      }
      return;
    }
    _updateMode();
    if (oldOffset == _offset && oldMode == _mode) return;
    _notify();
  }

  /// easy_refresh's `_updateMode` for the header.
  void _updateMode() {
    if (_locked) return;
    if (_mode == AppRefreshMode.closing && _offset > 0) return;
    final settling = _mode == AppRefreshMode.ready && !_dragging;
    if (_offset == 0) {
      // A settling header may overshoot to the top; it stays ready.
      if (!settling) {
        _mode = AppRefreshMode.idle;
        _releaseOffset = 0;
      }
    } else if (_offset < trigger) {
      if (!settling) _mode = AppRefreshMode.drag;
    } else if (_offset == trigger) {
      if (_dragging) {
        _mode = _releaseOffset > trigger ? AppRefreshMode.ready : AppRefreshMode.armed;
      } else {
        // Only a released pull refreshes: an offset restored at the
        // header's height (page storage) springs back instead.
        _mode = settling ? AppRefreshMode.refreshing : AppRefreshMode.drag;
      }
    } else if (_dragging) {
      _mode = AppRefreshMode.armed;
    } else {
      _mode = _releaseOffset > trigger ? AppRefreshMode.ready : AppRefreshMode.armed;
    }
    if (_mode == AppRefreshMode.refreshing) unawaited(_run());
  }

  Future<void> _run() async {
    if (_running) return;
    _running = true;
    _failure = null;
    Object? outcome;
    try {
      outcome = await _onRefresh();
    } on Object catch (error, stack) {
      outcome = const AppRefreshFailure();
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'live_ui',
          context: ErrorDescription('refreshing'),
        ),
      );
    }
    _running = false;
    if (_disposed) return;
    _failure = outcome is AppRefreshFailure ? outcome : null;
    _lastRefreshed = DateTime.now();
    _mode = AppRefreshMode.finished;
    _notify();
    _resultTimer = Timer(AppRefreshView.resultDuration, _close);
  }

  /// easy_refresh's `_completeProcessedMode`.
  void _close() {
    if (_disposed || _mode != AppRefreshMode.finished) return;
    _mode = AppRefreshMode.closing;
    if (_offset == 0) _mode = AppRefreshMode.idle;
    _notify();
    if (_dragging) return;
    // Springs back from where the list rests (the held header).
    final position = _position;
    if (position is ScrollPosition && position.hasPixels) {
      // The running activity's velocity carries over, as in easy_refresh's
      // `_resetBallistic`; `activity` is protected for this reason only.
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      final activity = position.activity;
      activity?.delegate.goBallistic(activity.velocity);
    }
  }

  /// 3.x's `callRefresh`: from the top, pull 20 past the header in 200 ms
  /// and let go.
  Future<void> show() async {
    final position = _position;
    if (position is! ScrollPosition || !position.hasPixels || _locked || _mode == AppRefreshMode.ready) return;
    final over = trigger + 20;
    position.jumpTo(position.minScrollExtent);
    dragging = true;
    await position.animateTo(
      position.minScrollExtent - over,
      duration: const Duration(milliseconds: 200),
      curve: Curves.linear,
    );
    // The animation's end let go already (createBallisticSimulation).
    dragging = false;
  }
}

/// [BouncingScrollPhysics] with the refresh header's edges and
/// [AppMotion.refreshSpring] (easy_refresh's `_ERScrollPhysics`): it settles
/// the header at its height, closes it after a refresh and returns a list
/// pulled past either end in about 0.35 s.
class _RefreshScrollPhysics extends BouncingScrollPhysics {
  const new({required this.tracker, super.parent = const AlwaysScrollableScrollPhysics()});

  final _RefreshTracker tracker;

  @override
  _RefreshScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _RefreshScrollPhysics(tracker: tracker, parent: buildParent(ancestor));

  @override
  SpringDescription get spring => AppMotion.refreshSpring;

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    tracker.dragging = true;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) =>
      tracker.applyBoundaryConditions(position, value);

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) =>
      tracker.createBallisticSimulation(this, position, velocity);
}

/// The header's size from its words (3.x `_refreshLayout`): tall enough for
/// a line of each and at least [AppRefreshView.minTriggerOffset]; the words
/// as wide as the widest, so the arrow does not move when they change.
@immutable
final class _HeaderLayout {
  const new _(this.key, this.height, this.textWidth);

  /// Measures the words of [words] in [context]'s text scale.
  factory measure(
    BuildContext context, {
    required _HeaderLayout? previous,
    required double width,
    required LiveUiStrings words,
    required TextStyle titleStyle,
    required TextStyle messageStyle,
  }) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final titles = [
      words.refreshPull,
      words.refreshRelease,
      words.refreshRefreshing,
      words.refreshSucceeded,
      words.refreshFailed,
    ];
    final message = words.refreshLastTime.replaceAll('{time}', '23:59');
    final key = Object.hash(width, scaler, direction, Object.hashAll(titles), message, titleStyle, messageStyle);
    if (previous != null && previous.key == key) return previous;

    Size size(String text, TextStyle style, double maxWidth) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: maxWidth);
      final result = painter.size;
      painter.dispose();
      return result;
    }

    // The icon, the gap and room on either side.
    final available = math.max(1, width - _iconSize - _gap - 24).toDouble();
    var textWidth = size(message, messageStyle, double.infinity).width;
    for (final title in titles) {
      textWidth = math.max(textWidth, size(title, titleStyle, double.infinity).width);
    }
    textWidth = (textWidth.ceilToDouble() + 8).clamp(1, available);
    var titleHeight = 0.0;
    for (final title in titles) {
      titleHeight = math.max(titleHeight, size(title, titleStyle, textWidth).height);
    }
    final height = (titleHeight + 4 + size(message, messageStyle, textWidth).height + 16).ceilToDouble();
    return _HeaderLayout._(key, math.max(height, AppRefreshView.minTriggerOffset), textWidth);
  }

  static const double _iconSize = 24;
  static const double _gap = 12;

  final int key;

  /// The trigger offset.
  final double height;

  /// The width of the words.
  final double textWidth;
}

/// 3.x's `ClassicHeader` in the U.1c look: in the gap the list leaves at
/// its top, centred in it.
class _RefreshHeader extends StatelessWidget {
  const new({
    required this.tracker,
    required this.layout,
    required this.words,
    required this.titleStyle,
    required this.messageStyle,
  });

  final _RefreshTracker tracker;
  final _HeaderLayout layout;
  final LiveUiStrings words;
  final TextStyle titleStyle;
  final TextStyle messageStyle;

  @override
  Widget build(BuildContext context) {
    final offset = tracker.offset;
    if (offset <= 0) return const SizedBox.shrink();
    final mode = tracker.mode;
    final failure = mode == AppRefreshMode.idle || mode == AppRefreshMode.drag || mode == AppRefreshMode.armed
        ? null
        : tracker.failure;
    final title = switch (mode) {
      AppRefreshMode.idle || AppRefreshMode.drag => words.refreshPull,
      AppRefreshMode.armed => words.refreshRelease,
      AppRefreshMode.ready || AppRefreshMode.refreshing => words.refreshRefreshing,
      AppRefreshMode.finished ||
      AppRefreshMode.closing => failure == null ? words.refreshSucceeded : words.refreshFailed,
    };
    final time = tracker.lastRefreshed;
    final message =
        failure?.reason ??
        words.refreshLastTime.replaceAll('{time}', '${time.hour}:${time.minute.toString().padLeft(2, '0')}');
    final body = SizedBox(
      key: const ValueKey('refresh-header'),
      height: layout.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: _HeaderLayout._iconSize,
            child: Center(child: _icon(context, mode, failure)),
          ),
          const SizedBox(width: _HeaderLayout._gap),
          SizedBox(
            width: layout.textWidth,
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: titleStyle, textAlign: TextAlign.center),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      message,
                      style: messageStyle,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return SizedBox(
      height: offset,
      child: ClipRect(
        child: OverflowBox(minHeight: layout.height, maxHeight: layout.height, child: body),
      ),
    );
  }

  Widget _icon(BuildContext context, AppRefreshMode mode, AppRefreshFailure? failure) {
    final colors = Theme.of(context).colorScheme;
    final Widget icon;
    final Object kind;
    switch (mode) {
      case AppRefreshMode.ready || AppRefreshMode.refreshing:
        kind = AppRefreshMode.refreshing;
        icon = const AppStatusView(type: AppStatusType.loading, isMini: true);
      case AppRefreshMode.finished || AppRefreshMode.closing:
        kind = failure == null ? 'succeeded' : 'failed';
        icon = failure == null
            ? Icon(AppIcons.refreshSucceeded, size: 24, color: colors.onSurfaceVariant)
            : Icon(AppIcons.refreshFailed, size: 24, color: colors.error);
      case AppRefreshMode.idle || AppRefreshMode.drag || AppRefreshMode.armed:
        kind = AppRefreshMode.drag;
        icon = AnimatedRotation(
          turns: mode == AppRefreshMode.armed ? 0.5 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(AppIcons.refreshPull, size: 24, color: colors.onSurfaceVariant),
        );
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: KeyedSubtree(key: ValueKey(kind), child: icon),
    );
  }
}
