import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// What EDITH is doing right now. The hologram reacts to it.
enum HologramMood { idle, listening, thinking, speaking }

/// Holds the view angle and zoom. Touch gestures drive it today. Hand
/// tracking from the camera can drive the same three calls later:
/// [rotateBy], [zoomBy] and [reset].
class HologramController extends ChangeNotifier {
  double yaw = 0.0;
  double pitch = 0.0;
  double zoom = 1.0;

  void rotateBy(double dYaw, double dPitch) {
    yaw += dYaw;
    pitch = (pitch + dPitch).clamp(-1.3, 1.3).toDouble();
    notifyListeners();
  }

  void setZoom(double value) {
    zoom = value.clamp(0.5, 3.0).toDouble();
    notifyListeners();
  }

  void zoomBy(double factor) => setZoom(zoom * factor);

  void reset() {
    yaw = 0.0;
    pitch = 0.0;
    zoom = 1.0;
    notifyListeners();
  }
}

class _Frame {
  final double time;
  final double energy;
  final double amp;
  final double spin;
  final double yaw;
  final double pitch;
  final double zoom;
  final Color color;
  const _Frame({
    required this.time,
    required this.energy,
    required this.amp,
    required this.spin,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.color,
  });
}

/// A live, glowing 3D knot made of light strands with drifting smoke
/// particles. Drag to turn it, pinch to zoom, double-tap to reset.
class HologramView extends StatefulWidget {
  final HologramMood mood;
  final HologramController controller;
  final Color color;

  const HologramView({
    super.key,
    required this.mood,
    required this.controller,
    required this.color,
  });

  @override
  State<HologramView> createState() => _HologramViewState();
}

class _HologramViewState extends State<HologramView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final _HologramPainter _painter;
  final ValueNotifier<int> _frameTick = ValueNotifier<int>(0);

  Duration _last = Duration.zero;
  double _time = 0.0;
  double _energy = 0.25;
  double _spin = 0.0;
  double _baseZoom = 1.0;

  @override
  void initState() {
    super.initState();
    _painter = _HologramPainter(
      read: _read,
      repaint: Listenable.merge([_frameTick, widget.controller]),
    );
    _ticker = createTicker(_tick)..start();
  }

  double get _amp {
    switch (widget.mood) {
      case HologramMood.speaking:
        return _energy *
            (0.55 +
                0.45 *
                    math.sin(_time * 9.0).abs() *
                    math.cos(_time * 2.3).abs());
      case HologramMood.listening:
        return _energy * (0.75 + 0.25 * math.sin(_time * 4.0));
      case HologramMood.thinking:
        return _energy * (0.85 + 0.15 * math.sin(_time * 6.0));
      case HologramMood.idle:
        return _energy * (0.9 + 0.1 * math.sin(_time * 1.2));
    }
  }

  _Frame _read() => _Frame(
        time: _time,
        energy: _energy,
        amp: _amp,
        spin: _spin,
        yaw: widget.controller.yaw,
        pitch: widget.controller.pitch,
        zoom: widget.controller.zoom,
        color: widget.color,
      );

  void _tick(Duration elapsed) {
    final dt =
        ((elapsed - _last).inMicroseconds / 1000000.0).clamp(0.0, 0.1).toDouble();
    _last = elapsed;
    _time += dt;
    double target = 0.25;
    switch (widget.mood) {
      case HologramMood.speaking:
        target = 0.95;
        break;
      case HologramMood.listening:
        target = 0.6;
        break;
      case HologramMood.thinking:
        target = 0.5;
        break;
      case HologramMood.idle:
        target = 0.25;
        break;
    }
    _energy += (target - _energy) * math.min(1.0, dt * 3.0);
    final speed = widget.mood == HologramMood.thinking ? 0.9 : 0.28;
    _spin += dt * speed * (0.6 + _energy);
    _frameTick.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frameTick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (_) => _baseZoom = widget.controller.zoom,
      onScaleUpdate: (d) {
        widget.controller.rotateBy(
          d.focalPointDelta.dx * 0.01,
          -d.focalPointDelta.dy * 0.01,
        );
        if (d.pointerCount > 1) {
          widget.controller.setZoom(_baseZoom * d.scale);
        }
      },
      onDoubleTap: widget.controller.reset,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _painter,
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double radius;
  final double speed;
  final double size;
  final double phase;
  const _Particle(this.angle, this.radius, this.speed, this.size, this.phase);
}

class _HologramPainter extends CustomPainter {
  final _Frame Function() read;

  _HologramPainter({required this.read, required Listenable repaint})
      : super(repaint: repaint);

  static final List<_Particle> _particles = () {
    final rnd = math.Random(7);
    return List<_Particle>.generate(130, (i) {
      return _Particle(
        rnd.nextDouble() * math.pi * 2,
        0.7 + rnd.nextDouble() * 1.4,
        (rnd.nextDouble() - 0.5) * 0.5,
        0.6 + rnd.nextDouble() * 1.8,
        rnd.nextDouble() * math.pi * 2,
      );
    });
  }();

  static const int _segments = 220;
  static const int _strands = 9;
  static const int _chunk = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final f = read();
    final center = Offset(size.width / 2, size.height / 2);
    final base = math.min(size.width, size.height);
    final unit = base / 8.0 * f.zoom * (1.0 + 0.07 * f.amp);

    final yaw = f.yaw + f.spin;
    final pitch = f.pitch + 0.35;
    final cy = math.cos(yaw), sy = math.sin(yaw);
    final cp = math.cos(pitch), sp = math.sin(pitch);

    final glowColor = f.color;
    final coreColor = Color.lerp(f.color, Colors.white, 0.65)!;

    // Soft glow behind everything.
    final haloRadius = unit * 5.0;
    final halo = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          glowColor.withValues(alpha: 0.10 + 0.22 * f.amp),
          glowColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: haloRadius));
    canvas.drawCircle(center, haloRadius, halo);

    // Smoke and sparks drifting around the knot.
    final smoke = Paint()..blendMode = BlendMode.plus;
    for (final p in _particles) {
      final a = p.angle + f.time * p.speed * (1.0 + f.amp * 1.5);
      final r = (p.radius +
              0.18 * math.sin(f.time * 0.6 + p.phase) +
              0.35 * f.amp) *
          unit *
          2.2;
      final pos = center + Offset(math.cos(a) * r, math.sin(a) * r * 0.72);
      smoke.color = glowColor.withValues(alpha: 0.035 + 0.03 * f.amp);
      canvas.drawCircle(pos, p.size * unit * 0.35, smoke);
      final twinkle = 0.5 + 0.5 * math.sin(f.time * 2.0 + p.phase * 3.0);
      smoke.color = coreColor.withValues(alpha: (0.15 + 0.5 * twinkle) * 0.9);
      canvas.drawCircle(pos, p.size * (0.7 + 0.5 * f.amp), smoke);
    }

    // The knot: several strands of light.
    final points = List<Offset>.filled(_segments + 1, Offset.zero);
    final depth = List<double>.filled(_segments + 1, 0.0);

    for (var k = 0; k < _strands; k++) {
      for (var i = 0; i <= _segments; i++) {
        final th = i / _segments * math.pi * 2.0;
        final ripple =
            0.08 * (0.6 + f.amp) * math.sin(5.0 * th + f.time * 2.0 + k * 1.3);
        // Four-lobed knot made of nine parallel strands: a thick ribbon of
        // light, like the picture.
        final phi = k * math.pi * 2.0 / _strands + 2.0 * th + f.time * 0.6;
        final rr = 2.0 + math.cos(3.0 * th) + 0.24 * math.cos(phi) + ripple;
        final x = rr * math.cos(4.0 * th);
        final y = rr * math.sin(4.0 * th);
        final z = -math.sin(3.0 * th) + 0.24 * math.sin(phi);

        final x1 = x * cy + z * sy;
        final z1 = -x * sy + z * cy;
        final y2 = y * cp - z1 * sp;
        final z2 = y * sp + z1 * cp;

        final persp = 7.0 / (7.0 - z2);
        points[i] = center + Offset(x1 * persp * unit, y2 * persp * unit);
        depth[i] = z2;
      }

      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (var i = 1; i <= _segments; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 5.0 + 3.0 * f.amp
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7)
        ..blendMode = BlendMode.plus
        ..color = glowColor.withValues(alpha: 0.18 + 0.22 * f.amp);
      if (k % 3 == 0) canvas.drawPath(path, glow);

      final core = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..blendMode = BlendMode.plus;
      for (var start = 0; start < _segments; start += _chunk) {
        final end = math.min(start + _chunk, _segments);
        var zSum = 0.0;
        final seg = Path()..moveTo(points[start].dx, points[start].dy);
        for (var i = start; i <= end; i++) {
          seg.lineTo(points[i].dx, points[i].dy);
          zSum += depth[i];
        }
        final avgZ = zSum / (end - start + 1);
        final near = ((avgZ + 3.3) / 6.6).clamp(0.0, 1.0).toDouble();
        core
          ..strokeWidth = 1.0 + 1.3 * near + 0.8 * f.amp
          ..color = Color.lerp(glowColor, coreColor, near)!
              .withValues(alpha: 0.30 + 0.60 * near);
        canvas.drawPath(seg, core);
      }
    }

    // Bright heart.
    final heart = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          coreColor.withValues(alpha: 0.55 + 0.3 * f.amp),
          glowColor.withValues(alpha: 0.0),
        ],
      ).createShader(
          Rect.fromCircle(center: center, radius: unit * (0.9 + 0.5 * f.amp)));
    canvas.drawCircle(center, unit * (0.9 + 0.5 * f.amp), heart);
  }

  @override
  bool shouldRepaint(covariant _HologramPainter oldDelegate) => false;
}
