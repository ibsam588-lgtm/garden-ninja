import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:garden_ninja/src/slicer/slicer_plant_art.dart';

enum _Material { leaf, bark, dust, drop, ice }

typedef _Palette = ({Color low, Color mid, Color shine});
typedef _Ribbon = ({double angle, double bend, double length, double width});
typedef _Spatter = ({Offset position, double radius});
typedef _Pool = ({
  Offset position,
  double angle,
  _Palette palette,
  double strength,
  double start,
  List<_Spatter> spatter,
});
typedef _Splash = ({
  Offset position,
  double angle,
  _Palette palette,
  double strength,
  double start,
  List<_Ribbon> ribbons,
});
typedef _Glint = ({
  Offset position,
  double angle,
  Color color,
  bool strong,
  double start,
});
typedef _Particle = ({
  Offset position,
  Offset velocity,
  double angle,
  double radius,
  double start,
  double duration,
  _Material type,
  _Palette palette,
});

const _sap = (
  low: Color(0xFF4C671D),
  mid: Color(0xFFA4C846),
  shine: Color(0xFFF3FAB6),
);
const _purpleSap = (
  low: Color(0xFF6B3B76),
  mid: Color(0xFFAD6EB4),
  shine: Color(0xFFF6D9FA),
);
const _water = (
  low: Color(0xFF238F99),
  mid: Color(0xFF76DBE4),
  shine: Color(0xFFDDFFFF),
);
const _ice = (
  low: Color(0xFF46788E),
  mid: Color(0xFF8ED0F1),
  shine: Color(0xFFE7FBFF),
);

const _leafColors = <SlicerPlantKind, Color>{
  SlicerPlantKind.thorn: Color(0xFFA8BF62),
  SlicerPlantKind.gobbler: Color(0xFFAFBB52),
  SlicerPlantKind.seed: Color(0xFFD9BE75),
  SlicerPlantKind.leaf: Color(0xFFACC86D),
  SlicerPlantKind.spike: Color(0xFFB5C876),
  SlicerPlantKind.purple: Color(0xFFB98BBB),
};

double _smooth(double progress) {
  final t = progress.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _ease(double progress) {
  final remaining = 1 - progress.clamp(0.0, 1.0);
  return 1 - remaining * remaining * remaining;
}

Offset _unit(double angle) => Offset(cos(angle), sin(angle));

Color _fade(Color color, double opacity) =>
    color.withValues(alpha: color.a * opacity.clamp(0.0, 1.0));

/// Transient visuals for a Slicer round. Scoring and targets live in the game.
class SlicerEffects {
  static const waveDuration = 1.10;
  static const _icePulseDuration = .79;

  final Random _random = Random();
  final List<_Particle> _particles = [];
  final List<_Pool> _pools = [];
  final List<_Splash> _splashes = [];
  final List<_Glint> _glints = [];
  double _time = 0;
  double? _waterStart;
  double _freezeStart = double.negativeInfinity;
  Offset _freezeOrigin = Offset.zero;

  bool get waterActive => _waterStart != null;
  double get waterRemaining =>
      waterActive ? waveDuration - (_time - _waterStart!) : 0;
  bool get hasGround => _pools.isNotEmpty;
  bool get hasAction =>
      waterActive ||
      _freezeAge < _icePulseDuration ||
      _particles.isNotEmpty ||
      _splashes.isNotEmpty ||
      _glints.isNotEmpty;
  double get _freezeAge => _time - _freezeStart;
  double get frost => _smooth(_freezeAge / .43);

  void clear() {
    _particles.clear();
    _pools.clear();
    _splashes.clear();
    _glints.clear();
    _time = 0;
    _waterStart = null;
    _freezeStart = double.negativeInfinity;
  }

  void tick(double dt) {
    _time += dt;
    final waterStart = _waterStart;
    if (waterStart != null && _time - waterStart >= waveDuration) {
      _waterStart = null;
    }
    _particles.removeWhere((p) => _time - p.start >= p.duration);
    _pools.removeWhere((p) => _time - p.start >= 2.25);
    _splashes.removeWhere((s) => _time - s.start >= .44);
    _glints.removeWhere((g) => _time - g.start >= .31);
  }

  void castWater() => _waterStart = _time;

  void castIce(Offset origin) {
    _freezeStart = _time;
    _freezeOrigin = origin;
  }

  double _waterFront(double height, double age) =>
      height + 54 - (height + 72) * (age / waveDuration).clamp(0.0, 1.0);

  double _waterCurve(double x, double width, double age) {
    final lateral = (x - width / 2) / (width / 2);
    return 19 * lateral * lateral + 5 * sin(x / 31 + age * 12);
  }

  double waterCrest(double x, Size arena) {
    final start = _waterStart;
    if (start == null) return double.negativeInfinity;
    final age = _time - start;
    return _waterFront(arena.height, age) + _waterCurve(x, arena.width, age);
  }

  void cut({
    required Offset position,
    required double ground,
    required double angle,
    required SlicerPlantKind? kind,
    required bool defeated,
    required bool frozen,
    required bool reducedMotion,
  }) {
    final armored = kind == SlicerPlantKind.bramble;
    _append(_glints, 24, (
      position: position,
      angle: angle,
      color: frozen
          ? _ice.shine
          : armored
          ? const Color(0xFFFFE5A5)
          : const Color(0xFFFFF5C3),
      strong: defeated || armored,
      start: _time,
    ));
    if (frozen) {
      _spray(
        position,
        _ice.mid,
        defeated ? 28 : 16,
        _Material.ice,
        reducedMotion,
      );
    } else if (armored) {
      _spray(
        position,
        const Color(0xFFCDA076),
        defeated ? 30 : 17,
        _Material.bark,
        reducedMotion,
      );
      _spray(
        Offset(position.dx, ground),
        const Color(0xFFA78A54),
        5,
        _Material.dust,
        reducedMotion,
      );
      if (defeated) {
        _splash(position, ground, angle, _sap, .54, true, reducedMotion);
      }
    } else {
      final palette = kind == SlicerPlantKind.purple ? _purpleSap : _sap;
      _splash(
        position,
        ground,
        angle,
        palette,
        defeated ? 1.11 : .72,
        defeated,
        reducedMotion,
      );
      _spray(
        position,
        _leafColors[kind] ?? _sap.mid,
        defeated ? 13 : 5,
        _Material.leaf,
        reducedMotion,
      );
    }
  }

  void flower(Offset position, bool reducedMotion) => _spray(
    position,
    const Color(0xFFF2D4B4),
    7,
    _Material.leaf,
    reducedMotion,
  );

  void splashWater(Offset position, double ground, bool reducedMotion) =>
      _splash(
        position + const Offset(0, 10),
        ground,
        -pi / 2,
        _water,
        .86,
        true,
        reducedMotion,
      );

  void _splash(
    Offset position,
    double ground,
    double angle,
    _Palette palette,
    double strength,
    bool stains,
    bool reducedMotion,
  ) {
    if (!reducedMotion) {
      _append(_splashes, 18, (
        position: position,
        angle: angle,
        palette: palette,
        strength: strength,
        start: _time,
        ribbons: List.generate(
          7,
          (index) => (
            angle: (index - 3) * .30 + _range(-.10, .10),
            bend: _range(-13, 13),
            length: _range(33, 89),
            width: _range(3, 12),
          ),
        ),
      ));
    }
    final count = reducedMotion ? 5 : (15 * strength).floor() + 7;
    for (var index = 0; index < count; index++) {
      final heading = angle + _range(-1.16, 1.08);
      final speed = _range(52, 226) * (.58 + strength * .42);
      _append(_particles, 384, (
        position: position,
        velocity: _unit(heading) * speed - const Offset(0, 44),
        angle: heading,
        radius: _range(1.2, 1.2 + 4.7 * strength),
        start: _time,
        duration: _range(.28, .73),
        type: _Material.drop,
        palette: palette,
      ));
    }
    if (stains) {
      _append(_pools, 24, (
        position: Offset(position.dx + cos(angle) * 27, ground + 7),
        angle: angle * .25,
        palette: palette,
        strength: strength,
        start: _time + .10,
        spatter: List.generate(
          reducedMotion ? 3 : 8,
          (index) => (
            position: Offset(
              cos(index * 2.399) * _range(12, 46),
              sin(index * 2.399) * _range(7, 22),
            ),
            radius: _range(1.5, 5.3),
          ),
        ),
      ));
    }
  }

  void _spray(
    Offset position,
    Color color,
    int count,
    _Material type,
    bool reducedMotion,
  ) {
    if (reducedMotion) count = min(count, type == _Material.ice ? 5 : 3);
    final ice = type == _Material.ice;
    final dust = type == _Material.dust;
    final palette = ice ? _ice : (low: color, mid: color, shine: color);
    for (var index = 0; index < count; index++) {
      final angle = index / count * pi * 2 + _range(0, ice ? .35 : .88);
      final speed = dust
          ? 12 + index * 3.0
          : ice
          ? _range(41, 176)
          : _range(24, 124);
      final radius = dust
          ? 4 + index * .85
          : ice
          ? _range(1.5, 8.9)
          : _range(1.8, 5.7);
      _append(_particles, 384, (
        position: position,
        velocity:
            _unit(angle) * speed -
            Offset(
              0,
              dust
                  ? 0
                  : ice
                  ? 34
                  : 18,
            ),
        angle: angle,
        radius: radius,
        start: _time,
        duration: dust ? .43 : _range(.44, ice ? .78 : .73),
        type: type,
        palette: palette,
      ));
    }
  }

  double _range(double from, double to) =>
      from + (to - from) * _random.nextDouble();

  void _append<T>(List<T> list, int capacity, T value) {
    if (list.length >= capacity) list.removeAt(0);
    list.add(value);
  }
}

class SlicerEffectsPainter extends CustomPainter {
  SlicerEffectsPainter(
    this.effects, {
    required this.ground,
    required this.reducedMotion,
  });

  final SlicerEffects effects;
  final bool ground;
  final bool reducedMotion;

  @override
  void paint(Canvas canvas, Size size) {
    if (ground) {
      _paintPools(canvas);
      return;
    }
    if (effects.waterActive) _paintWater(canvas, size);
    if (effects._freezeAge < SlicerEffects._icePulseDuration) {
      _paintFreeze(canvas, size);
    }
    _paintSplashes(canvas);
    _paintParticles(canvas);
    _paintGlints(canvas);
  }

  static final _poolShape = Path()
    ..moveTo(-32, -3)
    ..cubicTo(-32, -11, -13, -10, -10, -15)
    ..cubicTo(-5, -21, 4, -9, 12, -11)
    ..cubicTo(21, -11, 26, -3, 34, -1)
    ..cubicTo(45, 5, 25, 11, 17, 11)
    ..cubicTo(5, 16, -5, 13, -14, 15)
    ..cubicTo(-25, 15, -22, 5, -33, 5)
    ..cubicTo(-40, 6, -37, -1, -32, -3)
    ..close();

  static final _poolShine = Path()
    ..moveTo(-16, -9)
    ..quadraticBezierTo(-11, -7, -1, -9)
    ..moveTo(15, -6)
    ..lineTo(22, -4);

  void _paintPools(Canvas canvas) {
    for (final pool in effects._pools) {
      final age = effects._time - pool.start;
      if (age < 0) continue;
      final spread = .31 + .69 * _ease(age / .45);
      final opacity = .66 * (1 - _smooth(age - 1.25));
      canvas.save();
      canvas.translate(pool.position.dx, pool.position.dy);
      canvas.rotate(pool.angle);
      canvas.scale(spread * (pool.strength + .26), spread * .55);
      final liquid = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, -15),
          const Offset(0, 16),
          [
            pool.palette.mid,
            pool.palette.low,
            const Color(0xFF4D5024),
          ].map((color) => _fade(color, opacity)).toList(),
          const [0, .70, 1],
        );
      canvas.drawPath(_poolShape, liquid);
      for (final mark in pool.spatter) {
        canvas.drawOval(
          Rect.fromCenter(
            center: mark.position,
            width: mark.radius * 2.76,
            height: mark.radius * 1.44,
          ),
          liquid,
        );
      }
      canvas.drawPath(
        _poolShine,
        Paint()
          ..color = _fade(pool.palette.shine, opacity)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.65,
      );
      canvas.restore();
    }
  }

  void _paintSplashes(Canvas canvas) {
    for (final splash in effects._splashes) {
      final age = effects._time - splash.start;
      final bloom = _ease(age / .19);
      if (bloom <= 0) continue;
      final fade = 1 - _smooth((age - .12) / .32);
      canvas.save();
      canvas.translate(splash.position.dx, splash.position.dy + 17 * age * age);
      canvas.rotate(splash.angle);
      for (final ribbon in splash.ribbons) {
        final length = ribbon.length * bloom * splash.strength;
        final bend = ribbon.bend * bloom;
        final width =
            ribbon.width *
            min(1, bloom + .14) *
            splash.strength *
            (.65 + fade * .35);
        canvas.save();
        canvas.rotate(ribbon.angle);
        final shape = Path()
          ..moveTo(-9, 0)
          ..cubicTo(
            length * .12,
            -width,
            length * .64,
            bend - width,
            length,
            bend,
          )
          ..cubicTo(
            length * .56,
            bend + width * .76,
            length * .24,
            width,
            -9,
            0,
          )
          ..close();
        canvas.drawPath(
          shape,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(0, -width),
              Offset(length * .73, width),
              [
                splash.palette.low,
                splash.palette.mid,
                splash.palette.shine,
              ].map((color) => _fade(color, fade * .91)).toList(),
              const [0, .62, 1],
            ),
        );
        final shine = Path()
          ..moveTo(length * .40, bend * .35 - width * .34)
          ..quadraticBezierTo(
            length * .62,
            bend * .63 - width * .45,
            length * .79,
            bend * .78 - width * .21,
          );
        canvas.drawPath(
          shine,
          Paint()
            ..color = _fade(splash.palette.shine, fade * .91)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .85,
        );
        canvas.restore();
      }
      canvas.restore();
    }
  }

  void _paintParticles(Canvas canvas) {
    final paint = Paint();
    for (final particle in effects._particles) {
      final age = effects._time - particle.start;
      final p = age / particle.duration;
      final type = particle.type;
      final dust = type == _Material.dust;
      final position =
          particle.position +
          particle.velocity * age +
          Offset(0, dust ? 0 : 166 * age * age);
      final angle = type == _Material.drop
          ? atan2(particle.velocity.dy + 332 * age, particle.velocity.dx)
          : particle.angle + age * 6;
      final opacity = (1 - p) * (dust ? .22 : .91);
      final radius = particle.radius;
      final palette = particle.palette;
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(angle);
      paint
        ..shader = null
        ..style = PaintingStyle.fill
        ..color = _fade(palette.mid, opacity);
      switch (type) {
        case _Material.dust:
          final spread = radius * (1 + p);
          canvas.scale(1, .55);
          canvas.drawCircle(
            Offset.zero,
            spread,
            paint
              ..shader = ui.Gradient.radial(Offset.zero, spread, [
                _fade(palette.mid, opacity),
                _fade(palette.mid, 0),
              ]),
          );
        case _Material.drop:
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: radius * 3.04,
              height: radius * 1.52,
            ),
            paint..color = _fade(palette.low, opacity),
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(-.28 * radius, -.17 * radius),
              width: radius * 2.43,
              height: radius * 1.2,
            ),
            paint..color = _fade(palette.mid, opacity),
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(.35 * radius, -.30 * radius),
              width: radius * .91,
              height: radius * .42,
            ),
            paint..color = _fade(palette.shine, opacity),
          );
        case _Material.ice:
          final glass = Path()
            ..moveTo(-radius, radius * .45)
            ..lineTo(radius * 1.23, -.46 * radius)
            ..lineTo(radius * .30, radius * .81)
            ..close();
          canvas.drawPath(
            glass,
            paint
              ..shader = ui.Gradient.linear(
                Offset(-radius, 0),
                Offset(radius, 0),
                [
                  palette.low,
                  palette.mid,
                  palette.shine,
                ].map((color) => _fade(color, opacity)).toList(),
                const [0, .81, 1],
              ),
          );
          canvas.drawPath(
            glass,
            paint
              ..shader = null
              ..color = _fade(const Color(0xC9DFFCFF), opacity)
              ..style = PaintingStyle.stroke
              ..strokeWidth = .7,
          );
        case _Material.bark:
          final chip = Path()
            ..moveTo(-radius, -.42 * radius)
            ..lineTo(.95 * radius, -.30 * radius)
            ..lineTo(.34 * radius, .72 * radius)
            ..close();
          canvas.drawPath(chip, paint);
        case _Material.leaf:
          final leaf = Path()
            ..moveTo(-radius, 0)
            ..quadraticBezierTo(0, -radius, radius, 0)
            ..quadraticBezierTo(0, radius, -radius, 0);
          canvas.drawPath(leaf, paint);
      }
      canvas.restore();
    }
  }

  void _paintGlints(Canvas canvas) {
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final glint in effects._glints) {
      final p = (effects._time - glint.start) / .31;
      final reach = 9 + p * (glint.strong ? 48 : 29);
      final arms = glint.strong && !reducedMotion ? 5 : 3;
      paint
        ..color = _fade(glint.color, pow(1 - p, 1.5).toDouble())
        ..strokeWidth = glint.strong ? 2 : 1.45;
      for (var arm = 0; arm < arms; arm++) {
        final ray = _unit(arm * pi * 2 / arms + .28 + glint.angle) * reach;
        canvas.drawLine(
          glint.position + ray * .70,
          glint.position + ray,
          paint,
        );
      }
    }
  }

  void _paintWater(Canvas canvas, Size size) {
    final age = effects._time - effects._waterStart!;
    final front = effects._waterFront(size.height, age);
    final opacity = reducedMotion ? .61 : 1.0;
    double crestAt(double x) => front + effects._waterCurve(x, size.width, age);
    final crest = Path()..moveTo(0, crestAt(0));
    for (double x = 8; x < size.width; x += 8) {
      crest.lineTo(x, crestAt(x));
    }
    crest.lineTo(size.width, crestAt(size.width));
    final wash = Path.from(crest)
      ..lineTo(size.width, front + 112)
      ..lineTo(0, front + 112)
      ..close();
    canvas.drawPath(
      wash,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, front - 5),
          Offset(0, front + 103),
          const [
            Color(0xAAC2FAFF),
            Color(0xAD51C9D8),
            Color(0x69378EAC),
            Color(0x00378EAC),
          ].map((color) => _fade(color, opacity)).toList(),
          const [0, .16, .51, 1],
        ),
    );
    final paint = Paint()..style = PaintingStyle.stroke;
    const contours = [
      (5.0, 13.0, Color(0x8294EEF4)),
      (0.0, 3.4, Color(0xEEF3FFFF)),
      (19.0, 1.4, Color(0xB0C4FCFF)),
      (37.0, 1.1, Color(0x80B3EFF3)),
    ];
    for (final (dy, width, color) in contours) {
      canvas.drawPath(
        crest.shift(Offset(0, dy)),
        paint
          ..strokeWidth = width
          ..color = _fade(color, opacity),
      );
    }
    paint.style = PaintingStyle.fill;
    for (var index = 0; index < (reducedMotion ? 16 : 49); index++) {
      final x = (index * 47.11 + age * (index % 4 - 1.5) * 36) % size.width;
      final y = crestAt(x) - 11 + (index * 13.32 + age * 48) % 48;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: 3.4 + (index % 4) * 1.82,
          height: 1.5 + index % 3,
        ),
        paint
          ..color = _fade(
            index % 3 == 0 ? const Color(0xDEF7FFFF) : const Color(0xBDDBFFFF),
            opacity,
          ),
      );
    }
  }

  void _paintFreeze(Canvas canvas, Size size) {
    final p = effects._freezeAge / SlicerEffects._icePulseDuration;
    final radius = 48 + _ease(p) * max(size.width * .8, size.height * .52);
    final opacity = (1 - p) * (reducedMotion ? .55 : .95);
    canvas.save();
    canvas.translate(effects._freezeOrigin.dx, effects._freezeOrigin.dy);
    canvas.scale(1, .75);
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          radius,
          const [
            Color(0x00BAF1FF),
            Color(0x38A0D9EF),
            Color(0xB0E3F9FF),
            Color(0x00E3F9FF),
          ].map((color) => _fade(color, opacity)).toList(),
          const [.73, .85, .95, 1],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SlicerEffectsPainter oldDelegate) => true;
}
