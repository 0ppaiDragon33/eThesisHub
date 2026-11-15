import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Two party poppers flanking [center] (usually a trophy). When shown, each
/// popper squashes, snaps, and fires three staggered confetti shots up and
/// inward over the whole screen, with a muzzle flash, sparkles, tumbling
/// confetti and ribbons, a light shower from the top, and balloons floating
/// up from the bottom.
///
/// Used by the student's "Congratulations!" dialog and the adviser's
/// archived-advisee dialog. The confetti is drawn on the root overlay, so it
/// is not clipped by the dialog and never blocks taps. With the platform's
/// reduce-motion setting on, the poppers stay still and nothing is drawn.
class PartyPopperHeader extends StatefulWidget {
  const PartyPopperHeader({
    super.key,
    required this.center,
    this.popperSize = 52,
  });

  final Widget center;
  final double popperSize;

  @override
  State<PartyPopperHeader> createState() => _PartyPopperHeaderState();
}

class _PartyPopperHeaderState extends State<PartyPopperHeader>
    with TickerProviderStateMixin {
  // Timeline, in ms on the pop controller:
  //   0 .. _lead                short beat while the dialog finishes rising in
  //   _lead .. _fireAt          squash (the anticipation)
  //   _fireAt                   RELEASE: first shot fires on this exact frame
  //   _fireAt .. _totalMs       snap + smooth settle (one pop, no second bounce)
  static const _lead = 160;
  static const _squashMs = 90;
  static const _settleMs = 430;
  static const _popMs = _squashMs + _settleMs;
  static const _totalMs = _lead + _popMs;
  static const _fireAt = _lead + _squashMs;

  static const _shots = <_Shot>[
    _Shot(
      _fireAt,
      70,
      spread: 0.5,
      sparkles: 12,
      flash: true,
      balloons: 12,
      haptic: true,
    ),
    _Shot(_fireAt + 160, 45, spread: 0.75, speed: 0.85),
    _Shot(_fireAt + 340, 40, spread: 0.9, speed: 1.1, shower: 80),
  ];

  static const _colors = <Color>[
    Color(0xFFE24B4A),
    Color(0xFFEF9F27),
    Color(0xFFFAC775),
    Color(0xFF1D9E75),
    Color(0xFF378ADD),
    Color(0xFF7F77DD),
    Color(0xFFD4537E),
  ];

  final _leftKey = GlobalKey();
  final _rightKey = GlobalKey();
  late final _ConfettiField _field = _ConfettiField(math.Random(), _colors);

  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
  )..addListener(_onPopTick);

  late final Ticker _ticker = createTicker(_onFrame);
  Duration _lastElapsed = Duration.zero;
  OverlayEntry? _entry;
  int _nextShot = 0;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    // Put the overlay layer in place now, so the first shot does not have to
    // pay for building it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareLayer());
    _pop.forward();
  }

  @override
  void dispose() {
    _popInterval.dispose();
    _pop.dispose();
    _ticker.dispose();
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    super.dispose();
  }

  void _onPopTick() {
    final ms = _pop.value * _totalMs;
    // `while`, not `if`: a hitched frame can cross more than one shot, and
    // every shot must still fire.
    while (_nextShot < _shots.length && ms >= _shots[_nextShot].at) {
      _fire(_shots[_nextShot]);
      _nextShot++;
    }
  }

  /// Makes sure the full-screen overlay layer is on screen and sized, and
  /// returns the overlay's box (null when there is no overlay to draw on).
  RenderBox? _prepareLayer() {
    if (!mounted) return null;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final overlayBox = overlay?.context.findRenderObject();
    if (overlay == null || overlayBox is! RenderBox) return null;

    _entry ??= OverlayEntry(
      builder: (_) => IgnorePointer(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_field),
        ),
      ),
    );
    if (!_entry!.mounted) overlay.insert(_entry!);
    _field.bounds = overlayBox.size;
    return overlayBox;
  }

  void _startTicker() {
    if (_ticker.isActive) return;
    _lastElapsed = Duration.zero;
    _ticker.start();
  }

  void _fire(_Shot shot) {
    if (shot.haptic) unawaited(HapticFeedback.mediumImpact());

    final overlayBox = _prepareLayer();
    if (overlayBox == null) return;

    if (shot.balloons > 0) _field.releaseBalloons(shot.balloons);
    if (shot.shower > 0) _field.startShower(shot.shower);

    // The mouth sits at (37, 27) in the popper's 64-unit drawing. These are
    // the popper's OWN coordinates: `localToGlobal` applies the mirror flip
    // itself, so the same point is right for both poppers.
    final s = widget.popperSize;
    final mouth = Offset(s * 37 / 64, s * 27 / 64);

    // Both poppers aim up and inward, so the two streams cross above the
    // trophy.
    final aims = <(GlobalKey, double)>[
      (_leftKey, -math.pi * 0.30),
      (_rightKey, -math.pi * 0.70),
    ];
    for (final (key, base) in aims) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final origin = overlayBox.globalToLocal(box.localToGlobal(mouth));
      _field.burst(origin, base, shot);
    }
    _startTicker();
  }

  void _onFrame(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 16667.0;
    _lastElapsed = elapsed;
    // Clamp so a stalled frame does not fling the confetti off screen.
    _field.step(math.min(dt, 3.0));
    if (_field.isEmpty) _ticker.stop();
  }

  // Maps the controller onto just the pop (after the lead-in beat).
  late final CurvedAnimation _popInterval = CurvedAnimation(
    parent: _pop,
    curve: const Interval(_lead / _totalMs, 1.0),
  );

  // One pop: squash, snap past full size, then ease down to 1.0. It never
  // drops below 1.0 again after the snap, so it reads as a single pop.
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.84,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 90,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.84,
        end: 1.22,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 110,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.22,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 320,
    ),
  ]).animate(_popInterval);

  // Degrees: tips back while squashing, kicks forward on release, settles.
  late final Animation<double> _turn = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: -7.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 90,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: -7.0,
        end: 9.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 110,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 9.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 320,
    ),
  ]).animate(_popInterval);

  // Recoil in logical px, along the popper's axis (away from the mouth).
  late final Animation<double> _kick = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 0.0,
        end: 2.0,
      ).chain(CurveTween(curve: Curves.easeIn)),
      weight: 90,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 2.0,
        end: 6.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 110,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 6.0,
        end: 0.0,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 320,
    ),
  ]).animate(_popInterval);

  Widget _popper(Key key, {required bool mirrored}) {
    final s = widget.popperSize;
    final popper = AnimatedBuilder(
      animation: _pop,
      builder: (context, child) => Transform.translate(
        offset: Offset(-_kick.value, _kick.value),
        child: Transform.rotate(
          angle: _turn.value * math.pi / 180,
          child: Transform.scale(scale: _scale.value, child: child),
        ),
      ),
      child: SizedBox(
        key: key,
        width: s,
        height: s,
        child: const CustomPaint(painter: _PopperPainter()),
      ),
    );
    return mirrored ? Transform.flip(flipX: true, child: popper) : popper;
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The drawing's mouth faces up-right, so the left popper is drawn
          // as-is and the right one is mirrored: both face the trophy.
          _popper(_leftKey, mirrored: false),
          const SizedBox(width: 10),
          widget.center,
          const SizedBox(width: 10),
          _popper(_rightKey, mirrored: true),
        ],
      ),
    );
  }
}

/// One confetti shot, fired when the pop controller reaches [at] ms.
class _Shot {
  const _Shot(
    this.at,
    this.count, {
    this.spread = 0.55,
    this.speed = 1.0,
    this.sparkles = 0,
    this.flash = false,
    this.balloons = 0,
    this.shower = 0,
    this.haptic = false,
  });

  final int at, count, sparkles, balloons, shower;
  final double spread, speed;
  final bool flash, haptic;
}

enum _Kind { rect, round, ribbon, star }

class _Balloon {
  _Balloon({
    required this.x,
    required this.y,
    required this.vy,
    required this.radius,
    required this.sway,
    required this.swaySpeed,
    required this.phase,
    required this.delay,
    required this.color,
  });

  final double x, vy, radius, sway, swaySpeed, phase;
  double y, delay, life = 0;
  final Color color;

  double get cx => x + math.sin(phase + life * swaySpeed) * sway;

  /// Lean into the sway, like a balloon on a string.
  double get tilt => math.cos(phase + life * swaySpeed) * 0.12;
}

class _Particle {
  _Particle({
    required this.kind,
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.w,
    required this.h,
    required this.rot,
    required this.vr,
    required this.vf,
    required this.phase,
    required this.drag,
    required this.gravity,
    required this.max,
    required this.color,
  });

  final _Kind kind;
  double x, y, vx, vy, rot, flip = 0, life = 0;
  final double w, h, vr, vf, phase, drag, gravity, max;
  final Color color;
}

/// The bright ring that flashes at a popper's mouth when it fires.
class _Flash {
  _Flash(this.origin);

  static const max = 16.0;
  final Offset origin;
  double life = 0;
}

/// Confetti physics, stepped in 60 fps frames: heavy drag so pieces slow
/// down and float, light gravity, sideways flutter, spin, a flip that makes
/// each piece tumble like paper, and a fade over the end of its life.
class _ConfettiField extends ChangeNotifier {
  _ConfettiField(this._rng, this._colors);

  final math.Random _rng;
  final List<Color> _colors;

  final List<_Particle> particles = [];
  final List<_Balloon> balloons = [];
  final List<_Flash> flashes = [];
  Size bounds = Size.zero;

  double _showerLeft = 0;
  double _showerCarry = 0;

  static const _sparkleColors = <Color>[
    Color(0xFFFFF3C4),
    Color(0xFFFFD27A),
    Color(0xFFFFFFFF),
  ];

  bool get isEmpty =>
      particles.isEmpty &&
      balloons.isEmpty &&
      flashes.isEmpty &&
      _showerLeft <= 0;

  /// Scales speeds with the screen so a phone and a desktop both feel full.
  double get _sizeScale =>
      math.max(0.8, math.min(1.4, bounds.shortestSide / 420));

  void releaseBalloons(int n) {
    if (bounds.isEmpty) return;
    for (var i = 0; i < n; i++) {
      final r = 18 + _rng.nextDouble() * 10;
      balloons.add(
        _Balloon(
          // Spread across the width, with a margin so none is cut off.
          x: bounds.width * (0.06 + 0.88 * (i + _rng.nextDouble()) / n),
          y: bounds.height + r * 3.5,
          vy: 2.0 + _rng.nextDouble() * 1.8,
          radius: r,
          sway: 6 + _rng.nextDouble() * 10,
          swaySpeed: 0.02 + _rng.nextDouble() * 0.03,
          phase: _rng.nextDouble() * math.pi * 2,
          delay: _rng.nextDouble() * 70,
          color: _colors[_rng.nextInt(_colors.length)],
        ),
      );
    }
    notifyListeners();
  }

  void burst(Offset origin, double base, _Shot shot) {
    final k = _sizeScale;
    for (var i = 0; i < shot.count; i++) {
      final a = base + (_rng.nextDouble() - 0.5) * math.pi * shot.spread;
      final v = (9 + _rng.nextDouble() * 13) * shot.speed * k;
      final r = _rng.nextDouble();
      final kind = r < 0.5
          ? _Kind.rect
          : (r < 0.72 ? _Kind.round : _Kind.ribbon);
      final ribbon = kind == _Kind.ribbon;
      particles.add(
        _Particle(
          kind: kind,
          x: origin.dx,
          y: origin.dy,
          vx: math.cos(a) * v,
          vy: math.sin(a) * v,
          w: ribbon ? 3.0 : 6 + _rng.nextDouble() * 5,
          h: ribbon ? 14 + _rng.nextDouble() * 8 : 4 + _rng.nextDouble() * 3,
          rot: _rng.nextDouble() * math.pi * 2,
          vr: (_rng.nextDouble() - 0.5) * 0.35,
          vf: 0.12 + _rng.nextDouble() * 0.25,
          phase: _rng.nextDouble() * math.pi * 2,
          drag: 0.955 + _rng.nextDouble() * 0.02,
          gravity: 0.2,
          max: 150 + _rng.nextDouble() * 70,
          color: _colors[_rng.nextInt(_colors.length)],
        ),
      );
    }
    for (var i = 0; i < shot.sparkles; i++) {
      final a = base + (_rng.nextDouble() - 0.5) * math.pi * 0.9;
      final v = (4 + _rng.nextDouble() * 9) * k;
      particles.add(
        _Particle(
          kind: _Kind.star,
          x: origin.dx,
          y: origin.dy,
          vx: math.cos(a) * v,
          vy: math.sin(a) * v,
          w: 7 + _rng.nextDouble() * 5,
          h: 0,
          rot: _rng.nextDouble() * math.pi,
          vr: (_rng.nextDouble() - 0.5) * 0.1,
          vf: 0,
          phase: _rng.nextDouble() * math.pi * 2,
          drag: 0.93,
          gravity: 0.03,
          max: 40 + _rng.nextDouble() * 25,
          color: _sparkleColors[_rng.nextInt(_sparkleColors.length)],
        ),
      );
    }
    if (shot.flash) flashes.add(_Flash(origin));
    notifyListeners();
  }

  /// A light, floaty fall of confetti from the top edge for [frames] frames.
  void startShower(int frames) {
    _showerLeft = math.max(_showerLeft, frames.toDouble());
  }

  void _tickShower(double frames) {
    if (_showerLeft <= 0) return;
    if (bounds.isEmpty) {
      _showerLeft = 0;
      return;
    }
    final active = math.min(frames, _showerLeft);
    _showerLeft -= frames;
    _showerCarry += active * 0.7;
    final n = _showerCarry.floor();
    _showerCarry -= n;
    for (var i = 0; i < n; i++) {
      final r = _rng.nextDouble();
      final kind = r < 0.5
          ? _Kind.rect
          : (r < 0.75 ? _Kind.round : _Kind.ribbon);
      final ribbon = kind == _Kind.ribbon;
      particles.add(
        _Particle(
          kind: kind,
          x: _rng.nextDouble() * bounds.width,
          y: -10,
          vx: (_rng.nextDouble() - 0.5) * 1.4,
          vy: 0.8 + _rng.nextDouble() * 1.6,
          w: ribbon ? 3.0 : 6 + _rng.nextDouble() * 4,
          h: ribbon ? 14 + _rng.nextDouble() * 6 : 4 + _rng.nextDouble() * 3,
          rot: _rng.nextDouble() * math.pi * 2,
          vr: (_rng.nextDouble() - 0.5) * 0.25,
          vf: 0.1 + _rng.nextDouble() * 0.2,
          phase: _rng.nextDouble() * math.pi * 2,
          drag: 0.97,
          gravity: 0.09,
          max: 200 + _rng.nextDouble() * 80,
          color: _colors[_rng.nextInt(_colors.length)],
        ),
      );
    }
  }

  void step(double frames) {
    for (final p in particles) {
      final d = math.pow(p.drag, frames).toDouble();
      // Sideways flutter on top of drag, so pieces sway as they fall.
      p.vx = p.vx * d + math.sin(p.phase + p.life * 0.15) * 0.05 * frames;
      p.vy = p.vy * d + p.gravity * frames;
      p.x += p.vx * frames;
      p.y += p.vy * frames;
      p.rot += p.vr * frames;
      p.flip += p.vf * frames;
      p.life += frames;
    }
    particles.removeWhere(
      (p) => p.life >= p.max || (bounds.height > 0 && p.y > bounds.height + 20),
    );

    for (final f in flashes) {
      f.life += frames;
    }
    flashes.removeWhere((f) => f.life >= _Flash.max);

    _tickShower(frames);

    for (final b in balloons) {
      if (b.delay > 0) {
        b.delay -= frames;
        continue;
      }
      b.y -= b.vy * frames;
      b.life += frames;
    }
    // Gone once the balloon, with its string, is well above the top edge.
    balloons.removeWhere((b) => b.y < -b.radius * 4);
    notifyListeners();
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.field) : super(repaint: field);

  final _ConfettiField field;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (final b in field.balloons) {
      if (b.delay > 0) continue;
      _paintBalloon(canvas, b);
    }

    for (final p in field.particles) {
      final fadeLen = p.max < 80 ? p.max * 0.5 : 30.0;
      final fadeStart = p.max - fadeLen;
      final alpha = p.life > fadeStart ? (p.max - p.life) / fadeLen : 1.0;
      paint.color = p.color.withValues(alpha: alpha.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(p.x, p.y);
      canvas.rotate(p.rot);
      switch (p.kind) {
        case _Kind.round:
          canvas.drawCircle(Offset.zero, p.h / 1.4, paint);
        case _Kind.rect:
        case _Kind.ribbon:
          // Tumbling paper: the piece's thickness follows |cos(flip)|.
          final squash = math.max(0.2, math.cos(p.flip).abs());
          canvas.drawRect(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.w,
              height: p.h * squash,
            ),
            paint,
          );
        case _Kind.star:
          final twinkle = math.sin(p.life * 0.35).abs();
          _paintStar(canvas, p.w * 0.5 * (0.35 + 0.65 * twinkle), paint);
      }
      canvas.restore();
    }

    for (final f in field.flashes) {
      final t = f.life / _Flash.max;
      final a = 1 - t;
      canvas.drawCircle(
        f.origin,
        6 + t * 16,
        Paint()..color = const Color(0xFFFFD27A).withValues(alpha: 0.45 * a),
      );
      canvas.drawCircle(
        f.origin,
        8 + t * 34,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 + 3 * a
          ..color = const Color(0xFFFFE9A8).withValues(alpha: a),
      );
    }
  }

  void _paintStar(Canvas canvas, double r, Paint paint) {
    final inner = r * 0.28;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final rad = i.isEven ? r : inner;
      final a = i * math.pi / 4 - math.pi / 2;
      final x = math.cos(a) * rad;
      final y = math.sin(a) * rad;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _paintBalloon(Canvas canvas, _Balloon b) {
    final r = b.radius;
    canvas.save();
    canvas.translate(b.cx, b.y);
    canvas.rotate(b.tilt);

    // String, hanging from the knot.
    final string = Path()
      ..moveTo(0, r * 1.2 + 4)
      ..quadraticBezierTo(r * 0.5, r * 1.9, 0, r * 2.5)
      ..quadraticBezierTo(-r * 0.5, r * 3.1, 0, r * 3.6);
    canvas.drawPath(
      string,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF8A8A8A),
    );

    // Knot.
    final knot = Path()
      ..moveTo(0, r * 1.2 - 1)
      ..lineTo(-4, r * 1.2 + 5)
      ..lineTo(4, r * 1.2 + 5)
      ..close();
    canvas.drawPath(knot, Paint()..color = b.color);

    // Body.
    final body = Rect.fromCenter(
      center: Offset.zero,
      width: r * 2,
      height: r * 2.4,
    );
    canvas.drawOval(body, Paint()..color = b.color);
    // Soft shine.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-r * 0.35, -r * 0.5),
        width: r * 0.5,
        height: r * 0.8,
      ),
      Paint()..color = const Color(0x59FFFFFF),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.field != field;
}

/// The party popper from the mockup, drawn in its 64-unit viewBox.
class _PopperPainter extends CustomPainter {
  const _PopperPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 64, size.height / 64);

    Paint stroke(Color c, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..color = c
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Paint fill(Color c) => Paint()..color = c;

    const outline = Color(0xFFBA7517);

    // Cone.
    final cone = Path()
      ..moveTo(6, 60)
      ..lineTo(20, 20)
      ..lineTo(44, 44)
      ..close();
    canvas.drawPath(cone, fill(const Color(0xFFFAC775)));
    canvas.drawPath(cone, stroke(outline, 2));

    // Stripes.
    final stripes = Path()
      ..moveTo(12, 44)
      ..lineTo(28, 52)
      ..moveTo(16, 34)
      ..lineTo(35, 46)
      ..moveTo(10, 54)
      ..lineTo(22, 58);
    canvas.drawPath(stripes, stroke(const Color(0xFFD85A30), 3));

    // Rim (an ellipse turned 45 degrees about the centre).
    canvas.save();
    canvas.translate(32, 32);
    canvas.rotate(math.pi / 4);
    final rim = Rect.fromCenter(center: Offset.zero, width: 34, height: 10);
    canvas.drawOval(rim, fill(const Color(0xFFEF9F27)));
    canvas.drawOval(rim, stroke(outline, 2));
    canvas.restore();

    // Streamers.
    final pink = Path()
      ..moveTo(36, 27)
      ..quadraticBezierTo(40, 18, 47, 21)
      ..quadraticBezierTo(54, 24, 56, 11);
    canvas.drawPath(pink, stroke(const Color(0xFFD4537E), 2.5));
    final blue = Path()
      ..moveTo(39, 31)
      ..quadraticBezierTo(48, 29, 50, 36)
      ..quadraticBezierTo(52, 43, 60, 34);
    canvas.drawPath(blue, stroke(const Color(0xFF378ADD), 2.5));

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PopperPainter old) => false;
}
