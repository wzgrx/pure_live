import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show awaitNotRequired;
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

// The springs and fling thresholds of every drag, paged view and panel
// (research 2026-10-02 §2.3, docs/T14/T14c/T14c.2/brief.md), named once here
// instead of written at each use. A settling time is how long a spring
// takes to come within 1 % of the distance from its target, how §2.3
// counts it; Flutter's own fling (`AnimationController.fling`) stops there
// too. Lengths are logical pixels, velocities logical pixels a second.

/// The app's springs and fling thresholds.
abstract final class AppMotion {
  /// Tab pages (`TabBarView`): mass 1, stiffness 600, damping ratio 1. It
  /// settles in about 0.27 s, in step with the 220 ms of a tapped tab;
  /// Flutter's default scroll spring (mass 0.5, stiffness 100, ratio 1.1),
  /// which the pages had before, takes about 0.51 s.
  static final SpringDescription pageSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 600);

  /// A page turns by itself only after a release at least this fast
  /// (Android ViewPager's `MIN_FLING_VELOCITY`)...
  static const double pageFlingVelocity = 400;

  /// ...that moved at least this far (ViewPager's
  /// `MIN_DISTANCE_FOR_FLING`); otherwise it turns only when dragged past
  /// half, so the slight sideways movement of an upward scroll does not
  /// turn it. Flutter's default turned it from 50 a second.
  static const double pageFlingDistance = 25;

  /// Panels (the room's side panel, three-stop panel and details): mass 1,
  /// stiffness 500, damping ratio 1, the spring of Flutter's bottom sheet
  /// fling. It settles in about 0.3 s.
  static final SpringDescription panelSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 500);

  /// The pull-to-refresh header settling at its height, closing and a
  /// refreshable list springing back from past its ends: [panelSpring]
  /// (P02). 3.x used Flutter's default scroll spring, about 0.65 s.
  static final SpringDescription refreshSpring = panelSpring;

  /// A drag of a panel ending at least this fast flings it open or shut:
  /// Flutter's bottom sheet and `Dismissible`. The panels 4.0 added used
  /// 600; the thresholds 3.x had are kept (below).
  static const double panelFlingVelocity = 700;

  /// The portrait panel pulled down into the portrait fullscreen: a fling
  /// this fast (3.x `resolvePortraitPanelDragEnd`)...
  static const double panelFullscreenFlingVelocity = 900;

  /// ...after at least this far.
  static const double panelFullscreenFlingDistance = 28;

  /// The portrait fullscreen swiped up back to the panel: a fling this fast
  /// (3.x `shouldRestorePortraitPanelFromSwipe`)...
  static const double panelRestoreFlingVelocity = 850;

  /// ...after at least this far.
  static const double panelRestoreFlingDistance = 24;

  /// Swiping between rooms in the portrait fullscreen: mass 1, stiffness
  /// 400, damping ratio 1 (about 0.33 s).
  static final SpringDescription roomSwipeSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 400);

  /// A swipe between rooms switches with a fling this fast (U.2b2)...
  static const double roomSwipeFlingVelocity = 800;

  /// ...after at least this far (or a third of the screen without one).
  static const double roomSwipeFlingDistance = 48;

  /// Something dragged past its edge springing back: critically damped,
  /// stiffness 250, a period of 0.4 s (HyperOS's rubber band).
  static final SpringDescription overscrollSpring = SpringDescription.withDampingRatio(mass: 1, stiffness: 250);

  /// Small controls (a switch's knob, a chip): Material 3's fast spatial
  /// spring, damping ratio 0.9, stiffness 1400.
  static final SpringDescription controlSpring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 1400,
    ratio: 0.9,
  );

  /// How far something dragged [overscroll] past its edge moves, in a space
  /// [extent] long (HyperOS's rubber band): R·(x − x² + x³/3) with
  /// x = overscroll ÷ R, heavier the further it goes and at most R/3.
  static double rubberBand(double overscroll, double extent) {
    if (extent <= 0 || overscroll == 0) return 0;
    final x = math.min<double>(overscroll.abs() / extent, 1);
    return overscroll.sign * extent * (x - x * x + x * x * x / 3);
  }

  /// When a drag's spring has stopped on a screen of [devicePixelRatio]:
  /// within a physical pixel and slower than 20 physical pixels a second
  /// (Flutter's scroll tolerance).
  static Tolerance tolerance(double devicePixelRatio) =>
      Tolerance(distance: 1 / devicePixelRatio, velocity: 1 / (0.050 * devicePixelRatio));
}

/// What something dragged does after the finger lets go (research
/// 2026-10-02 S2): [SpringSimulation] from `start` to [end], leaving at the
/// finger's `velocity`, and never past [end]: it stops the moment it gets
/// there, so a fast release does not overshoot.
///
/// With [beyond] it aims that far past [end] and stops on reaching [end]
/// still moving, as `AnimationController.fling` does with 1 %: for
/// something leaving the screen, where the slow tail of a spring would only
/// make it linger.
///
/// Run it with [ReleaseAnimation.animateRelease] so the frame after the
/// finger lifts already moves on.
class ReleaseSpringSimulation extends Simulation {
  /// Creates the simulation.
  new({
    required SpringDescription spring,
    required double start,
    required this.end,
    required double velocity,
    this.beyond = 0,
    super.tolerance,
  }) : _sign = (end - start).sign,
       _spring = SpringSimulation(spring, start, end + (end - start).sign * beyond, velocity, tolerance: tolerance);

  /// Where it stops.
  final double end;

  /// How far past [end] it aims.
  final double beyond;

  final double _sign;
  final SpringSimulation _spring;

  bool _arrived(double time) => _sign != 0 && (_spring.x(time) - end) * _sign >= 0;

  @override
  double x(double time) => isDone(time) ? end : _spring.x(time);

  @override
  double dx(double time) => isDone(time) ? 0 : _spring.dx(time);

  @override
  bool isDone(double time) => _arrived(time) || _spring.isDone(time);
}

/// Animations that continue a drag.
extension ReleaseAnimation on AnimationController {
  /// Runs [simulation] for a drag the finger just let go of, timed from the
  /// frame on screen at that moment rather than the next one. A controller
  /// started from a pointer event shows its first frame at time 0, which
  /// repeats the last frame of the drag: the motion would pause for a frame
  /// as the finger lifts. It catches up by at most [refreshRate]'s one frame,
  /// so a finger that rested before lifting does not make it jump.
  @awaitNotRequired
  TickerFuture animateRelease(Simulation simulation, {double refreshRate = 60}) => animateWith(
    _FromLastFrame(
      simulation,
      drawn: SchedulerBinding.instance.currentSystemFrameTimeStamp,
      frame: refreshRate > 0 ? 1 / refreshRate : 1 / 60,
    ),
  );
}

/// [_simulation] shifted to start at the frame `_drawn` (a raw frame time
/// stamp), by at most [_frame] seconds.
class _FromLastFrame extends Simulation {
  new(this._simulation, {required this._drawn, required this._frame}) : super(tolerance: _simulation.tolerance);

  final Simulation _simulation;
  final Duration _drawn;
  final double _frame;
  double? _lead;

  double _shifted(double time) {
    var lead = _lead;
    if (lead == null) {
      final binding = SchedulerBinding.instance;
      // The controller reads the start at once, outside a frame; the lead
      // is fixed at the first tick.
      if (binding.schedulerPhase != SchedulerPhase.transientCallbacks) return time;
      final since = (binding.currentSystemFrameTimeStamp - _drawn).inMicroseconds / Duration.microsecondsPerSecond;
      lead = _lead = math.max<double>(0, math.min(since / timeDilation, _frame) - time);
    }
    return time + lead;
  }

  @override
  double x(double time) => _simulation.x(_shifted(time));

  @override
  double dx(double time) => _simulation.dx(_shifted(time));

  @override
  bool isDone(double time) => _simulation.isDone(_shifted(time));
}
