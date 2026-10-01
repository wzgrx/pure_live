import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:scroll_animator/scroll_animator.dart';

/// Short enough to feel immediate on high-refresh displays while leaving the
/// tab indicator and page transition enough frames to look linear.
const Duration pureLiveTabTransitionDuration = Duration(milliseconds: 220);

/// Content lists: the platform's own touch model (a spring on iOS and macOS,
/// a hard edge elsewhere) instead of forcing one everywhere.
class PureLiveScrollPhysics extends ScrollPhysics {
  /// Creates the physics.
  const new({super.parent});

  /// The platform's physics over [parent].
  ScrollPhysics get _platform => switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => BouncingScrollPhysics(parent: parent),
    _ => ClampingScrollPhysics(parent: parent),
  };

  @override
  ScrollPhysics applyTo(ScrollPhysics? ancestor) {
    final parent = buildParent(ancestor);
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => BouncingScrollPhysics(parent: parent),
      _ => ClampingScrollPhysics(parent: parent),
    };
  }

  // Used without [applyTo] (as another physics' parent, or the scroll
  // behaviour's physics) the instance itself must act like the platform's
  // physics; plain ScrollPhysics has no edges, so lists scrolled past their
  // content.

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      _platform.applyPhysicsToUserOffset(position, offset);

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) =>
      _platform.applyBoundaryConditions(position, value);

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) =>
      _platform.createBallisticSimulation(position, velocity);

  @override
  double get minFlingVelocity => _platform.minFlingVelocity;

  @override
  double get maxFlingVelocity => _platform.maxFlingVelocity;

  @override
  double carriedMomentum(double existingVelocity) => _platform.carriedMomentum(existingVelocity);

  @override
  double? get dragStartDistanceMotionThreshold => _platform.dragStartDistanceMotionThreshold;
}

/// Navigation strips, filters and paged views: never an offset before the
/// first or after the last item on any platform, even when the content
/// shrinks while the route stays mounted.
class PureLiveBoundedScrollPhysics extends ClampingScrollPhysics {
  /// Creates the physics.
  const new({super.parent});

  @override
  PureLiveBoundedScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      PureLiveBoundedScrollPhysics(parent: buildParent(ancestor));

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final adjusted = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
    return adjusted.clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent);
  }
}

/// A scroll controller that turns discrete mouse-wheel steps on Windows into
/// one continuous movement (Chromium's ease-in-out curve); a plain controller
/// elsewhere, so touch keeps Flutter's own scrolling.
ScrollController createPureLiveScrollController({double initialScrollOffset = 0}) {
  if (defaultTargetPlatform == TargetPlatform.windows) {
    return AnimatedScrollController(
      animationFactory: const ChromiumEaseInOut(),
      initialScrollOffset: initialScrollOffset,
    );
  }
  return ScrollController(initialScrollOffset: initialScrollOffset);
}

/// Gives one desktop route its own animated primary scroll controller, so
/// pages without a controller of their own scroll smoothly with the wheel on
/// Windows. Per route: a controller at the app root would attach to several
/// offstage routes and tab views.
class PureLiveRouteScrollScope extends StatelessWidget {
  /// Wraps a route's [child].
  const new({required this.child, super.key});

  /// The route's page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows) return child;
    return AnimatedPrimaryScrollController(
      automaticallyInheritForPlatforms: const {TargetPlatform.windows},
      child: child,
    );
  }
}

/// Keeps a tab's page alive when it scrolls out of a [PageView] or
/// `TabBarView` (3.x `KeepAliveWrapper`).
class KeepAliveWrapper extends StatefulWidget {
  /// Keeps [child] alive.
  const new({required this.child, super.key});

  /// The page.
  final Widget child;

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
