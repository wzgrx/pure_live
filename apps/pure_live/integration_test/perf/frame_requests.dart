import 'dart:ui';

import 'package:flutter/scheduler.dart';

/// Notes which frames the app asked for (P05).
///
/// Once the engine drew a frame, a live test binding asks for the next one
/// itself, so frames come on every vsync even while nothing changes; the app
/// would draw none then. A frame counts as the app's when something asked
/// the scheduler for it (a setState, an animation, a scroll, a gesture of the
/// test); the binding's own requests go to the engine directly.
final class FrameRequests {
  /// Starts noting; made once in `main`, right after the binding, so the
  /// frame callbacks keep the zone they had.
  factory install() {
    final requests = FrameRequests._();
    // A forced frame makes the binding register its frame callbacks (they
    // hold the warm-up frame's guard, which a deferred first frame uses);
    // they are then wrapped, not replaced.
    final scheduler = SchedulerBinding.instance..scheduleForcedFrame();
    final dispatcher = PlatformDispatcher.instance;
    final begin = dispatcher.onBeginFrame ?? scheduler.handleBeginFrame;
    final draw = dispatcher.onDrawFrame ?? scheduler.handleDrawFrame;
    assert(dispatcher.onBeginFrame != null, 'the binding registers its frame callbacks');
    dispatcher
      ..onBeginFrame = (timeStamp) {
        // Read before the scheduler clears it for this frame.
        requests._asked = scheduler.hasScheduledFrame;
        begin(timeStamp);
      }
      ..onDrawFrame = () {
        // The engine numbers the frame right after it begins.
        if (requests._asked) requests.frames.add(dispatcher.frameData.frameNumber);
        requests._asked = false;
        draw();
      };
    return requests;
  }

  new _();

  /// The engine numbers of the frames the app asked for.
  final Set<int> frames = {};

  bool _asked = false;
}
