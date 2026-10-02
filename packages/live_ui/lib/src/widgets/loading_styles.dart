import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:loading_indicator/loading_indicator.dart';

typedef _Builder = Widget Function(Color color, double size, ColorScheme colors);

/// The 85 loading animations the user can pick (3.x `AppConsts.allStyles`
/// and `AppStatusView._buildLoadingWidget`).
abstract final class LoadingStyles {
  /// The built-in spinner, shown for [defaultKey] and any unknown key.
  static const String defaultKey = 'default';

  static final Map<String, _Builder> _spinKit = {
    'rotatingPlain': (c, s, _) => SpinKitRotatingPlain(color: c, size: s),
    'doubleBounce': (c, s, _) => SpinKitDoubleBounce(color: c, size: s),
    'wave': (c, s, _) => SpinKitWave(color: c, size: s),
    'wanderingCubes': (c, s, _) => SpinKitWanderingCubes(color: c, size: s),
    'fadingFour': (c, s, _) => SpinKitFadingFour(color: c, size: s),
    'fadingCube': (c, s, _) => SpinKitFadingCube(color: c, size: s),
    'pulse': (c, s, _) => SpinKitPulse(color: c, size: s),
    'chasingDots': (c, s, _) => SpinKitChasingDots(color: c, size: s),
    'threeBounce': (c, s, _) => SpinKitThreeBounce(color: c, size: s),
    'circle': (c, s, _) => SpinKitCircle(color: c, size: s),
    'cubeGrid': (c, s, _) => SpinKitCubeGrid(color: c, size: s),
    'fadingCircle': (c, s, _) => SpinKitFadingCircle(color: c, size: s),
    'rotatingCircle': (c, s, _) => SpinKitRotatingCircle(color: c, size: s),
    'foldingCube': (c, s, _) => SpinKitFoldingCube(color: c, size: s),
    'pumpingHeart': (c, s, _) => SpinKitPumpingHeart(color: c, size: s),
    'hourGlass': (c, s, _) => SpinKitHourGlass(color: c, size: s),
    'pouringHourGlass': (c, s, _) => SpinKitPouringHourGlass(color: c, size: s),
    'pouringHourGlassRefined': (c, s, _) => SpinKitPouringHourGlassRefined(color: c, size: s),
    'fadingGrid': (c, s, _) => SpinKitFadingGrid(color: c, size: s),
    'ring': (c, s, _) => SpinKitRing(color: c, size: s),
    'ripple': (c, s, _) => SpinKitRipple(color: c, size: s),
    'spinningCircle': (c, s, _) => SpinKitSpinningCircle(color: c, size: s),
    'spinningLines': (c, s, _) => SpinKitSpinningLines(color: c, size: s),
    'squareCircle': (c, s, _) => SpinKitSquareCircle(color: c, size: s),
    'dualRing': (c, s, _) => SpinKitDualRing(color: c, size: s),
    'pianoWave': (c, s, _) => SpinKitPianoWave(color: c, size: s),
    'dancingSquare': (c, s, _) => SpinKitDancingSquare(color: c, size: s),
    'threeInOut': (c, s, _) => SpinKitThreeInOut(color: c, size: s),
    'waveSpinner': (c, s, _) => SpinKitWaveSpinner(color: c, size: s),
    'pulsingGrid': (c, s, _) => SpinKitPulsingGrid(color: c, size: s),
  };

  static final Map<String, _Builder> _animations = {
    'waveDots': (c, s, _) => LoadingAnimationWidget.waveDots(color: c, size: s),
    'inkDrop': (c, s, _) => LoadingAnimationWidget.inkDrop(color: c, size: s),
    'twistingDots': (c, s, k) =>
        LoadingAnimationWidget.twistingDots(leftDotColor: c, rightDotColor: k.secondary, size: s),
    'threeRotatingDots': (c, s, _) => LoadingAnimationWidget.threeRotatingDots(color: c, size: s),
    'staggeredDotsWave': (c, s, _) => LoadingAnimationWidget.staggeredDotsWave(color: c, size: s),
    'fourRotatingDots': (c, s, _) => LoadingAnimationWidget.fourRotatingDots(color: c, size: s),
    'fallingDot': (c, s, _) => LoadingAnimationWidget.fallingDot(color: c, size: s),
    'progressiveDots': (c, s, _) => LoadingAnimationWidget.progressiveDots(color: c, size: s),
    'discreteCircular': (c, s, _) => LoadingAnimationWidget.discreteCircle(color: c, size: s),
    'threeArchedCircle': (c, s, _) => LoadingAnimationWidget.threeArchedCircle(color: c, size: s),
    'bouncingBall': (c, s, _) => LoadingAnimationWidget.bouncingBall(color: c, size: s),
    'flickr': (c, s, k) => LoadingAnimationWidget.flickr(leftDotColor: c, rightDotColor: k.secondary, size: s),
    'hexagonDots': (c, s, _) => LoadingAnimationWidget.hexagonDots(color: c, size: s),
    'beat': (c, s, _) => LoadingAnimationWidget.beat(color: c, size: s),
    'twoRotatingArc': (c, s, _) => LoadingAnimationWidget.twoRotatingArc(color: c, size: s),
    'horizontalRotatingDots': (c, s, _) => LoadingAnimationWidget.horizontalRotatingDots(color: c, size: s),
    'newtonCradle': (c, s, _) => LoadingAnimationWidget.newtonCradle(color: c, size: s),
    'stretchedDots': (c, s, _) => LoadingAnimationWidget.stretchedDots(color: c, size: s),
    'halfTriangleDot': (c, s, _) => LoadingAnimationWidget.halfTriangleDot(color: c, size: s),
    'dotsTriangle': (c, s, _) => LoadingAnimationWidget.dotsTriangle(color: c, size: s),
  };

  // loading_indicator: one colour, except the two coloured triangles.
  static const Map<String, Indicator> _indicators = {
    'ballPulse': Indicator.ballPulse,
    'ballGridPulse': Indicator.ballGridPulse,
    'ballClipRotate': Indicator.ballClipRotate,
    'ballClipRotatePulse': Indicator.ballClipRotatePulse,
    'squareSpin': Indicator.squareSpin,
    'ballClipRotateMultiple': Indicator.ballClipRotateMultiple,
    'ballPulseRise': Indicator.ballPulseRise,
    'ballRotate': Indicator.ballRotate,
    'cubeTransition': Indicator.cubeTransition,
    'ballZigZag': Indicator.ballZigZag,
    'ballZigZagDeflect': Indicator.ballZigZagDeflect,
    'ballTrianglePath': Indicator.ballTrianglePath,
    'ballTrianglePathColored': Indicator.ballTrianglePathColored,
    'ballTrianglePathColoredFilled': Indicator.ballTrianglePathColoredFilled,
    'ballScale': Indicator.ballScale,
    'lineScale': Indicator.lineScale,
    'lineScaleParty': Indicator.lineScaleParty,
    'ballScaleMultiple': Indicator.ballScaleMultiple,
    'ballPulseSync': Indicator.ballPulseSync,
    'ballBeat': Indicator.ballBeat,
    'lineScalePulseOut': Indicator.lineScalePulseOut,
    'lineScalePulseOutRapid': Indicator.lineScalePulseOutRapid,
    'ballScaleRipple': Indicator.ballScaleRipple,
    'ballScaleRippleMultiple': Indicator.ballScaleRippleMultiple,
    'ballSpinFadeLoader': Indicator.ballSpinFadeLoader,
    'lineSpinFadeLoader': Indicator.lineSpinFadeLoader,
    'triangleSkewSpin': Indicator.triangleSkewSpin,
    'pacman': Indicator.pacman,
    'ballGridBeat': Indicator.ballGridBeat,
    'semiCircleSpin': Indicator.semiCircleSpin,
    'ballRotateChase': Indicator.ballRotateChase,
    'orbit': Indicator.orbit,
    'audioEqualizer': Indicator.audioEqualizer,
    'circleStrokeSpin': Indicator.circleStrokeSpin,
  };

  static const Set<String> _multiColour = {'ballTrianglePathColored', 'ballTrianglePathColoredFilled'};

  /// Every key in 3.x's order: the default, the spin kit styles, the
  /// animation widget styles, then the indicator styles.
  static List<String> get keys => [defaultKey, ..._spinKit.keys, ..._animations.keys, ..._indicators.keys];

  /// [key] when it names a style, otherwise [defaultKey] (3.x
  /// `normalizeLoadingStyle`).
  static String normalize(String key) {
    final trimmed = key.trim();
    return keys.contains(trimmed) ? trimmed : defaultKey;
  }

  /// The animation of [key] in [color] at [size] logical pixels.
  static Widget build(String key, {required Color color, required double size, required ColorScheme colors}) {
    if (_spinKit[key] case final builder?) return builder(color, size, colors);
    if (_animations[key] case final builder?) return builder(color, size, colors);
    if (_indicators[key] case final indicator?) {
      return SizedBox(
        width: size,
        height: size,
        child: LoadingIndicator(
          indicatorType: indicator,
          colors: _multiColour.contains(key) ? [color, colors.secondary, colors.primary] : [color],
        ),
      );
    }
    return DefaultLoadingIndicator(color: color, size: size);
  }
}

/// The default spinner: a ring with a fading sweep, turning once a second.
///
/// The spinner owns its ticker, so swapping the style disposes the old
/// animation (3.x kept the controller on the status view, which left an
/// invisible animation running after a style change).
class DefaultLoadingIndicator extends StatefulWidget {
  /// Creates the spinner.
  const new({required this.color, required this.size, super.key});

  /// Ring colour.
  final Color color;

  /// Diameter.
  final double size;

  @override
  State<DefaultLoadingIndicator> createState() => _DefaultLoadingIndicatorState();
}

class _DefaultLoadingIndicatorState extends State<DefaultLoadingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(duration: const Duration(seconds: 1), vsync: this)
    ..repeat();

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A layer of its own: each turn repaints the ring alone, not the page
    // around it (P05).
    return RepaintBoundary(
      child: RotationTransition(
        turns: _rotation,
        child: CustomPaint(size: Size.square(widget.size), painter: _LoadingRing(widget.color)),
      ),
    );
  }
}

/// The default spinner's ring: 3.5 wide inside its box, its colour fading
/// from the colour to 10 % along a sweep (3.x). The gradient is the stroke's
/// shader, one draw; 3.x masked a white ring with a ShaderMask, which draws
/// it offscreen first on every frame of the turn (P05, research 2026-10-02
/// §4.2).
class _LoadingRing extends CustomPainter {
  const new(this.color);

  final Color color;

  static const double _width = 3.5;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _width
      ..shader = SweepGradient(
        colors: [color, color.withValues(alpha: 0.1)],
        stops: const [0.0, 0.85],
      ).createShader(box);
    canvas.drawCircle(box.center, (size.shortestSide - _width) / 2, paint);
  }

  @override
  bool shouldRepaint(_LoadingRing oldDelegate) => oldDelegate.color != color;
}
