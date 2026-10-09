// A big local gift's vehicle (D08.5 c4): a rocket, a jet or a meteor crossing
// the gift layer behind the banner for 2.8 s, with its smoke, contrail or
// embers.
//
// The drawing follows flame_barrage's motion effects
// (lib/src/effect/motion/rocket_launch_effect.dart, airplane_effect.dart,
// meteor_streak_effect.dart and barrage_fx_particle.dart, commit 3eddae8):
// the shapes of the rocket (hull, red nose and fins, porthole, two-tone
// flame), the jet (swept wing, red tail, fuselage, windows, blinking beacon)
// and the meteor (radial glow, a tail along its path), and the particle
// model (a solid circle moving with gravity, growing or shrinking and fading
// over its life). Redrawn for Flutter without Flame and without its engine:
// the poses and the particles are closed forms of the time (no state carried
// from frame to frame, no particle objects made per frame), the bodies are
// recorded once into a Picture, and there is no blur (UI.md §9.3).
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
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:live_ui/live_ui.dart';

/// The vehicles a big gift may have.
enum LocalGiftVehicle {
  /// Lifts off from the bottom and leaves at the top, smoke and sparks
  /// under it.
  rocket,

  /// Crosses from the left, climbing, a contrail behind it.
  airplane,

  /// Streaks from the top right to the bottom left and bursts.
  meteor;

  /// How long a vehicle and its last particles take.
  static const Duration duration = Duration(milliseconds: 2800);

  /// The vehicle of the gift [id]: the rockets fly as rockets; the other
  /// big gifts each have their own, the same every time (named here, or by
  /// the letters of the id for a gift added later).
  static LocalGiftVehicle of(String id) =>
      _byGift[id] ?? values[id.codeUnits.fold<int>(0, (sum, unit) => sum + unit) % values.length];

  static const Map<String, LocalGiftVehicle> _byGift = {
    'douyu_super_rocket': rocket,
    'huya_one': rocket,
    'bili_voyage': airplane,
    'douyin_carnival': airplane,
    'twitch_hype_train': airplane,
    'castle': airplane,
    'ks_guard': meteor,
    'cc_guard': meteor,
    'soop_signature_balloon': meteor,
  };
}

/// A deterministic number in 0..1 from [seed] and [salt] (flame_barrage's
/// `fxRand01`): a particle's details differ between shows, never between
/// frames.
double _rand(double seed, double salt) {
  final value = math.sin(seed * 12.9898 + salt * 78.233) * 43758.5453;
  return value - value.floorToDouble();
}

double _clamp01(double t) => t < 0 ? 0 : (t > 1 ? 1 : t);

double _easeOutCubic(double t) {
  final p = 1 - _clamp01(t);
  return 1 - p * p * p;
}

/// [color] at 8 opacities, so a fading particle picks one instead of
/// making a colour each frame.
List<Color> _fades(Color color) => [for (var i = 0; i <= 7; i++) color.withValues(alpha: color.a * i / 7)];

/// One kind of particle: its colours and how it moves and changes.
final class _Kind {
  new(Color color, {required this.from, required this.to}) : fades = _fades(color);

  /// The radius at birth and at death, in units.
  final double from;
  final double to;

  final List<Color> fades;
}

/// Where a vehicle is at a time: its point (the rocket's nozzle, the jet's
/// and the meteor's centre), its turn and its size.
typedef _Pose = ({double x, double y, double angle, double scale});

/// One vehicle's drawing over a gift layer of a given size: the body
/// recorded once, the poses and particles worked out from the time.
///
/// [paint] draws the time `seconds` after the start and returns how many
/// particles it drew (the frame-cost test counts them); nothing after
/// [LocalGiftVehicle.duration]. [dispose] lets the recorded body go.
final class LocalGiftVehicleScene {
  /// Creates the scene of [vehicle]; [seed] (0..1) varies its details.
  new(this.vehicle, {this.seed = 0.5});

  /// The vehicle.
  final LocalGiftVehicle vehicle;

  /// Varies the start, the side and the particles.
  final double seed;

  /// The most particles alive at once (the rocket's smoke and sparks come
  /// near 30; a few dozen at most, D08.5's brief).
  static const int maxParticles = 64;

  final Paint _paint = Paint()..isAntiAlias = true;
  final Paint _flameOuter = Paint()..color = GiftEffectColors.flame;
  final Paint _flameInner = Paint()..color = GiftEffectColors.flameCore;
  final List<Color> _beacon = _fades(GiftEffectColors.beacon);
  late final _Kind _smoke = _Kind(GiftEffectColors.smoke, from: 4.5, to: 14);
  late final _Kind _spark = _Kind(GiftEffectColors.spark, from: 2.6, to: 0.4);
  late final _Kind _contrail = _Kind(GiftEffectColors.contrail, from: 2.4, to: 6.5);
  late final _Kind _ember = _Kind(GiftEffectColors.ember, from: 2.4, to: 0.4);

  Size? _size;
  double _unit = 1;
  ui.Picture? _body;
  late Path _outer;
  late Path _inner;
  bool _disposed = false;

  /// The time the vehicle moves; its particles live on up to
  /// [LocalGiftVehicle.duration].
  double get _motion => switch (vehicle) {
    LocalGiftVehicle.rocket => 2.0,
    LocalGiftVehicle.airplane => 2.2,
    LocalGiftVehicle.meteor => 1.7,
  };

  static double get _total => LocalGiftVehicle.duration.inMilliseconds / 1000;

  /// Draws the vehicle [seconds] after its start on a layer of [size];
  /// returns the particles drawn.
  int paint(Canvas canvas, Size size, double seconds) {
    if (_disposed || seconds < 0 || seconds >= _total || size.isEmpty) return 0;
    _prepare(size);
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    final drawn = switch (vehicle) {
      LocalGiftVehicle.rocket => _rocket(canvas, size, seconds),
      LocalGiftVehicle.airplane => _airplane(canvas, size, seconds),
      LocalGiftVehicle.meteor => _meteor(canvas, size, seconds),
    };
    canvas.restore();
    return drawn;
  }

  /// Lets the recorded body go.
  void dispose() {
    _disposed = true;
    _body?.dispose();
    _body = null;
  }

  // ---- geometry, once a size ----

  void _prepare(Size size) {
    if (_size == size && _body != null) return;
    _size = size;
    // 1 on a landscape phone's picture; smaller on the inline one.
    _unit = (math.min(size.width, size.height) / 180).clamp(0.55, 1.4);
    _body?.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    switch (vehicle) {
      case LocalGiftVehicle.rocket:
        _recordRocket(canvas);
      case LocalGiftVehicle.airplane:
        _recordAirplane(canvas);
      case LocalGiftVehicle.meteor:
        _recordMeteor(canvas, size);
    }
    _body = recorder.endRecording();
  }

  double get _bodyWidth => 22 * _unit;

  double get _bodyHeight => _bodyWidth * 2.7;

  double get _planeLength => 96 * _unit;

  double get _meteorSize => 16 * _unit;

  /// The rocket around its nozzle (0, 0), pointing up.
  void _recordRocket(Canvas canvas) {
    final w = _bodyWidth;
    final h = _bodyHeight;
    final hull = Paint()..color = GiftEffectColors.hull;
    final livery = Paint()..color = GiftEffectColors.livery;
    for (final side in const [-1.0, 1.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(side * w * 0.5, -w * 0.9)
          ..lineTo(side * w * 1.05, 0)
          ..lineTo(side * w * 0.5, 0)
          ..close(),
        livery,
      );
    }
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-w / 2, -h, w, h), Radius.circular(w * 0.24)), hull)
      ..drawPath(
        Path()
          ..moveTo(-w / 2, -h + w * 0.12)
          ..lineTo(0, -h - w * 0.6)
          ..lineTo(w / 2, -h + w * 0.12)
          ..close(),
        livery,
      )
      ..drawCircle(Offset(0, -h + w * 0.9), w * 0.26, Paint()..color = GiftEffectColors.trim)
      ..drawCircle(Offset(0, -h + w * 0.9), w * 0.18, Paint()..color = GiftEffectColors.glass);
    // The flame, a unit long; scaled to its length each frame.
    _outer = Path()
      ..moveTo(-w * 0.30, 0)
      ..lineTo(0, 1)
      ..lineTo(w * 0.30, 0)
      ..close();
    _inner = Path()
      ..moveTo(-w * 0.15, 0)
      ..lineTo(0, 0.55)
      ..lineTo(w * 0.15, 0)
      ..close();
  }

  /// The jet around its centre (0, 0), nose to the right.
  void _recordAirplane(Canvas canvas) {
    final length = _planeLength;
    final height = length * 0.2;
    final hull = Paint()..color = GiftEffectColors.hull;
    final trim = Paint()..color = GiftEffectColors.trim;
    canvas
      ..drawPath(
        Path()
          ..moveTo(length * 0.12, height * 0.1)
          ..lineTo(-length * 0.10, height * 1.35)
          ..lineTo(length * 0.02, height * 1.35)
          ..lineTo(length * 0.24, height * 0.1)
          ..close(),
        trim,
      )
      ..drawPath(
        Path()
          ..moveTo(-length * 0.42, -height * 0.1)
          ..lineTo(-length * 0.52, -height * 1.25)
          ..lineTo(-length * 0.36, -height * 1.2)
          ..lineTo(-length * 0.26, -height * 0.1)
          ..close(),
        Paint()..color = GiftEffectColors.livery,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-length * 0.5, -height * 0.5, length * 0.88, height),
          Radius.circular(height * 0.5),
        ),
        hull,
      )
      ..drawOval(Rect.fromCenter(center: Offset(length * 0.38, 0), width: height * 1.2, height: height), hull)
      ..drawArc(
        Rect.fromCenter(center: Offset(length * 0.36, -height * 0.16), width: height * 0.6, height: height * 0.5),
        math.pi + 0.35,
        0.9,
        false,
        trim,
      );
    for (var i = 0; i < 6; i++) {
      canvas.drawCircle(Offset(-length * 0.28 + i * length * 0.105, -height * 0.08), height * 0.09, trim);
    }
  }

  /// The meteor's glow and its tail along the path of a layer of [size].
  void _recordMeteor(Canvas canvas, Size size) {
    final h = _meteorSize;
    final (start, end) = _meteorPath(size);
    final angle = math.atan2(start.dy - end.dy, start.dx - end.dx);
    final tail = h * 6;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final across = Offset(-direction.dy, direction.dx);
    canvas
      ..drawPath(
        Path()
          ..moveTo(across.dx * h * 0.55, across.dy * h * 0.55)
          ..lineTo(direction.dx * tail + across.dx * h * 0.9, direction.dy * tail + across.dy * h * 0.9)
          ..lineTo(direction.dx * tail - across.dx * h * 0.9, direction.dy * tail - across.dy * h * 0.9)
          ..lineTo(-across.dx * h * 0.55, -across.dy * h * 0.55)
          ..close(),
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, direction * tail, GiftEffectColors.meteorTail, const [
            0.0,
            0.55,
            1.0,
          ]),
      )
      ..drawCircle(
        Offset.zero,
        h * 1.35,
        Paint()
          ..shader = ui.Gradient.radial(Offset.zero, h * 1.35, GiftEffectColors.meteorGlow, const [0.0, 0.45, 1.0]),
      )
      ..drawCircle(Offset.zero, h * 0.42, Paint()..color = GiftEffectColors.hull);
  }

  /// From beyond the top right to where it bursts, low on the left.
  (Offset, Offset) _meteorPath(Size size) {
    final h = _meteorSize;
    return (
      Offset(size.width * (0.82 + seed * 0.1) + h * 2, -h * 3),
      Offset(size.width * (0.14 + seed * 0.1), size.height * 0.8),
    );
  }

  // ---- poses ----

  _Pose _rocketAt(Size size, double t) {
    final h = _bodyHeight;
    final left = seed < 0.5;
    final x = size.width * (left ? 0.12 + seed * 0.12 : 0.76 + (seed - 0.5) * 0.24);
    final from = size.height + h * 0.15;
    final to = -h * 0.4;
    final q = _clamp01(t / _motion);
    // A slow lift-off, then faster and faster (flame_barrage: speed gained
    // at a fixed rate).
    final y = from - (from - to) * (0.18 * q + 0.82 * q * q);
    final shake = (1 - q) * 1.6 * _unit;
    return (
      x: x + math.sin(t * 47 + seed * 9) * shake,
      y: y,
      angle: math.sin(t * 39 + seed * 5) * 0.02 * (1 - q),
      scale: 1.0,
    );
  }

  _Pose _airplaneAt(Size size, double t) {
    final length = _planeLength;
    final q = _clamp01(t / _motion);
    final span = size.width + length * 1.2;
    final x = -length * 0.6 + span * q;
    final base = size.height * (0.62 + seed * 0.1);
    final climb = size.height * 0.5;
    final y = base - climb * q * q + math.sin(t * 8) * 1.5 * _unit;
    // Nose along the path: dy/dx of the climb.
    final angle = math.atan2(-2 * climb * q, span);
    return (x: x, y: y, angle: angle, scale: 0.85 + 0.15 * _easeOutCubic(q / 0.3));
  }

  _Pose _meteorAt(Size size, double t) {
    final (start, end) = _meteorPath(size);
    final q = _clamp01(t / _motion);
    final point = Offset.lerp(start, end, q)!;
    final grow = 0.1 + 0.9 * _easeOutCubic(t / 0.18);
    final burn = q > 0.82 ? 1 - (q - 0.82) / 0.18 * 0.45 : 1.0;
    return (x: point.dx, y: point.dy, angle: 0, scale: grow * burn);
  }

  // ---- frames ----

  int _rocket(Canvas canvas, Size size, double t) {
    final u = _unit;
    final w = _bodyWidth;
    const count = 96;
    final spawnEnd = _motion;
    var drawn = 0;
    for (var i = 0; i < count; i++) {
      final born = spawnEnd * i / count;
      final age = t - born;
      if (age < 0) break;
      final r = _rand(seed, i.toDouble());
      final smoke = r < 0.7;
      final life = smoke ? 0.55 + r * 0.35 : 0.25 + (r - 0.7) * 0.6;
      if (age >= life) continue;
      final at = _rocketAt(size, born);
      final r2 = _rand(seed, i + 101.0);
      if (smoke) {
        drawn += _dot(
          canvas,
          _smoke,
          x: at.x + (r - 0.35) * 18 * u,
          y: at.y + 4 * u,
          vx: (r2 - 0.5) * 90 * u,
          vy: (70 + r2 * 60) * u,
          gravity: -70 * u,
          age: age,
          life: life,
        );
      } else {
        drawn += _dot(
          canvas,
          _spark,
          x: at.x,
          y: at.y,
          vx: (r2 - 0.5) * 200 * u,
          vy: (140 + r2 * 140) * u,
          gravity: 90 * u,
          age: age,
          life: life,
        );
      }
    }
    if (t < _motion) {
      final at = _rocketAt(size, t);
      final q = t / _motion;
      final flicker = 0.72 + math.sin(t * 26) * 0.28;
      canvas
        ..save()
        ..translate(at.x, at.y)
        ..rotate(at.angle)
        ..drawPicture(_body!)
        ..translate(0, w * 0.05)
        ..scale(1, _bodyHeight * (0.55 + 0.85 * _clamp01(q * 2.5)) * flicker)
        ..drawPath(_outer, _flameOuter)
        ..drawPath(_inner, _flameInner)
        ..restore();
    }
    return drawn;
  }

  int _airplane(Canvas canvas, Size size, double t) {
    final u = _unit;
    final length = _planeLength;
    const count = 72;
    var drawn = 0;
    for (var i = 0; i < count; i++) {
      final born = _motion * i / count;
      final age = t - born;
      if (age < 0) break;
      final r = _rand(seed, i.toDouble());
      final life = 0.4 + r * 0.2;
      if (age >= life) continue;
      final at = _airplaneAt(size, born);
      final back = -length * 0.48 * at.scale;
      drawn += _dot(
        canvas,
        _contrail,
        x: at.x + math.cos(at.angle) * back,
        y: at.y + math.sin(at.angle) * back + (r - 0.5) * 4 * u,
        vx: (-70 - r * 40) * u,
        vy: (8 + r * 10) * u,
        gravity: 0,
        age: age,
        life: life,
      );
    }
    if (t < _motion) {
      final at = _airplaneAt(size, t);
      final height = length * 0.2;
      final blink = (math.sin(t * 10) + 1) / 2;
      canvas
        ..save()
        ..translate(at.x, at.y)
        ..rotate(at.angle)
        ..scale(at.scale)
        ..drawPicture(_body!);
      _paint.color = _beacon[(2 + blink * 5).round()];
      canvas
        ..drawCircle(Offset(-length * 0.44, -height * 0.95), 2.2 * u, _paint)
        ..restore();
    }
    return drawn;
  }

  int _meteor(Canvas canvas, Size size, double t) {
    final u = _unit;
    final (start, end) = _meteorPath(size);
    final velocity = (end - start) / _motion;
    const count = 48;
    var drawn = 0;
    for (var i = 0; i < count; i++) {
      final born = 0.1 + (_motion - 0.1) * i / count;
      final age = t - born;
      if (age < 0) break;
      final r = _rand(seed, i.toDouble());
      final life = 0.35 + r * 0.25;
      if (age >= life) continue;
      final at = _meteorAt(size, born);
      final r2 = _rand(seed, i + 57.0);
      drawn += _dot(
        canvas,
        r > 0.5 ? _spark : _ember,
        x: at.x + (r - 0.5) * _meteorSize,
        y: at.y + (r2 - 0.5) * _meteorSize,
        vx: -velocity.dx * 0.12 + (r - 0.5) * 60 * u,
        vy: -velocity.dy * 0.12 + (r2 - 0.5) * 60 * u,
        gravity: 130 * u,
        age: age,
        life: life,
      );
    }
    // The burst where it burns out.
    final burst = t - _motion;
    if (burst >= 0) {
      for (var i = 0; i < 12; i++) {
        final r = _rand(seed, 500 + i * 23.0);
        final life = 0.4 + r * 0.35;
        if (burst >= life) continue;
        final angle = r * math.pi * 2;
        final speed = (80 + r * 240) * u;
        drawn += _dot(
          canvas,
          r > 0.4 ? _spark : _ember,
          x: end.dx,
          y: end.dy,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed + 40 * u,
          gravity: 150 * u,
          age: burst,
          life: life,
        );
      }
    } else {
      final at = _meteorAt(size, t);
      canvas
        ..save()
        ..translate(at.x, at.y)
        ..scale(at.scale)
        ..drawPicture(_body!)
        ..restore();
    }
    return drawn;
  }

  /// One particle born at (x, y) moving at (vx, vy) with [gravity] (units
  /// already applied), [age] into its [life]: 1 when drawn.
  int _dot(
    Canvas canvas,
    _Kind kind, {
    required double x,
    required double y,
    required double vx,
    required double vy,
    required double gravity,
    required double age,
    required double life,
  }) {
    final left = 1 - age / life;
    final radius = (kind.to + (kind.from - kind.to) * left) * _unit;
    if (radius <= 0.05) return 0;
    _paint.color = kind.fades[(left * 7).ceil().clamp(0, 7)];
    canvas.drawCircle(Offset(x + vx * age, y + vy * age + 0.5 * gravity * age * age), radius, _paint);
    return 1;
  }
}

/// A big gift's vehicle on the gift layer, once (D08.5 c4): it starts when
/// built and is gone after [LocalGiftVehicle.duration]. Keep it under the
/// banner's `ValueKey(serial)` so a combo's new count does not start it
/// again. Each frame repaints only its own layer: nothing is built.
class LocalGiftVehicleView extends StatefulWidget {
  /// Creates the vehicle [vehicle]; [seed] (0..1) varies its details.
  const new({required this.vehicle, this.seed = 0.5, super.key});

  /// The vehicle.
  final LocalGiftVehicle vehicle;

  /// Varies the start, the side and the particles.
  final double seed;

  @override
  State<LocalGiftVehicleView> createState() => _LocalGiftVehicleViewState();
}

class _LocalGiftVehicleViewState extends State<LocalGiftVehicleView> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: LocalGiftVehicle.duration)
    ..addStatusListener(_ended)
    ..forward();
  late final LocalGiftVehicleScene _scene = LocalGiftVehicleScene(widget.vehicle, seed: widget.seed);
  bool _done = false;

  void _ended(AnimationStatus status) {
    if (status.isCompleted && mounted) setState(() => _done = true);
  }

  @override
  void dispose() {
    _clock.dispose();
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        key: const ValueKey('local-gift-vehicle'),
        size: Size.infinite,
        painter: _VehiclePainter(_scene, _clock),
      ),
    );
  }
}

class _VehiclePainter extends CustomPainter {
  new(this.scene, this.clock) : super(repaint: clock);

  final LocalGiftVehicleScene scene;
  final Animation<double> clock;

  @override
  void paint(Canvas canvas, Size size) =>
      scene.paint(canvas, size, clock.value * LocalGiftVehicle.duration.inMilliseconds / 1000);

  @override
  bool shouldRepaint(_VehiclePainter oldDelegate) => oldDelegate.scene != scene || oldDelegate.clock != clock;
}
