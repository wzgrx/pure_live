// The "×N" of a gift combo jumping when its count goes up: the chat list's
// gift lines (A08.11 c4, the platforms' and the local ones, D08.4) and the
// local gift banner (D08.4 c2).
//
// The banner's jump follows flame_barrage's ComboAnimation
// (lib/src/animation/combo_animation.dart, commit 3eddae8: the count drawn at
// 1.8 times, shrinking back at 4 a second), redrawn as a Flutter
// ScaleTransition instead of a Flame component:
//
// MIT License
//
// Copyright (c) 2026 bobobo
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
import 'package:flutter/material.dart';

/// How the count jumps.
enum GiftCountJump {
  /// The chat line's (A08.11 c4): up to 1.2 times and back, 200 ms.
  line(1.2, Duration(milliseconds: 200)),

  /// The banner's (D08.4 c2, flame_barrage's ComboAnimation): at 1.8 times
  /// at once, back to its size in 200 ms.
  banner(1.8, Duration(milliseconds: 200));

  new(this.peak, this.duration);

  /// The largest scale.
  final double peak;

  /// How long one jump takes.
  final Duration duration;
}

/// [child] (a combo's "×N") jumping once each time [count] changes, and on
/// its first build when [jumpFirst] (D07.1's merged line is a new widget).
/// Nothing moves while the system asks for less motion, and until the first
/// jump [child] is built as it is.
class GiftCountPulse extends StatefulWidget {
  /// Creates the pulse of [child].
  const new({
    required this.count,
    required this.child,
    this.jump = GiftCountJump.line,
    this.jumpFirst = false,
    super.key,
  });

  /// The count shown; a new one jumps.
  final int count;

  /// The count's words.
  final Widget child;

  /// How it jumps.
  final GiftCountJump jump;

  /// Whether it jumps when first built.
  final bool jumpFirst;

  @override
  State<GiftCountPulse> createState() => _GiftCountPulseState();
}

class _GiftCountPulseState extends State<GiftCountPulse> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _scale;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.jumpFirst) _jump();
  }

  @override
  void didUpdateWidget(GiftCountPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) _jump();
  }

  void _jump() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final jump = widget.jump;
    final controller = _controller ??= AnimationController(vsync: this, duration: jump.duration);
    // Decelerating, no bounce (docs/specs/UI.md §8.6).
    _scale ??= switch (jump) {
      GiftCountJump.line => TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 1, end: jump.peak).chain(CurveTween(curve: Curves.easeOut)),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: jump.peak, end: 1).chain(CurveTween(curve: Curves.easeOut)),
          weight: 1,
        ),
      ]),
      GiftCountJump.banner => Tween<double>(begin: jump.peak, end: 1).chain(CurveTween(curve: Curves.easeOut)),
    }.animate(controller);
    controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    return scale == null ? widget.child : ScaleTransition(scale: scale, child: widget.child);
  }
}
