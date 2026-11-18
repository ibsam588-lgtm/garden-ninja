import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'planter_chew.dart';

typedef PlanterWarning = ({Offset foot, Offset flower, double? biteProgress});

typedef PlanterFragment = ({
  ui.Image image,
  Rect flower,
  Offset mouth,
  double before,
  double after,
  double direction,
  double edgeDirection,
  double progress,
});

class PlanterWarningsPainter extends CustomPainter {
  const PlanterWarningsPainter(this.warnings, {required this.frozen});

  final List<PlanterWarning> warnings;
  final bool frozen;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final warning in warnings) {
      final flower = warning.flower;
      final bite = warning.biteProgress;
      final color = frozen
          ? const Color(0xFFB8F0FF)
          : bite != null && bite > .68
          ? const Color(0xFFFFAB7B)
          : const Color(0xFFF6CD80);
      final end = flower - const Offset(0, 29);
      if (warning.foot.dy < end.dy - 4) {
        final bend = Offset(
          warning.foot.dx * .38 + end.dx * .62,
          (warning.foot.dy + end.dy) / 2,
        );
        final route = Path()
          ..moveTo(warning.foot.dx, warning.foot.dy)
          ..quadraticBezierTo(bend.dx, bend.dy, end.dx, end.dy);
        stroke
          ..color = color.withValues(alpha: .67)
          ..strokeWidth = 1.6;
        for (final line in route.computeMetrics()) {
          for (double start = 0; start < line.length; start += 10) {
            canvas.drawPath(
              line.extractPath(start, min(start + 4, line.length)),
              stroke,
            );
          }
        }
        canvas.drawPath(
          Path()
            ..moveTo(end.dx - 4, end.dy - 5)
            ..lineTo(end.dx, end.dy)
            ..lineTo(end.dx + 4, end.dy - 5),
          stroke,
        );
      }
      if (bite == null) continue;
      stroke
        ..color = const Color(0x92222418)
        ..strokeWidth = 4;
      canvas.drawCircle(flower, 35, stroke);
      stroke.color = color;
      canvas.drawArc(
        Rect.fromCircle(center: flower, radius: 35),
        -pi / 2,
        (1 - bite) * pi * 2,
        false,
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PlanterWarningsPainter oldDelegate) =>
      oldDelegate.frozen != frozen ||
      !listEquals(oldDelegate.warnings, warnings);
}

Path _cropEdge(Rect flower, double damage, double direction) {
  final y = flower.top + damage * flower.height;
  final relief = min(.058, (1 - damage) * .24) * flower.height;
  double x(double ratio) => flower.left + flower.width * ratio;
  return Path()
    ..moveTo(x(-.02), y - relief * direction)
    ..quadraticBezierTo(x(.10), y + relief * .9, x(.23), y - relief * .18)
    ..quadraticBezierTo(x(.34), y + relief * 1.35, x(.45), y + relief * .38)
    ..quadraticBezierTo(x(.59), y + relief * 1.2, x(.70), y)
    ..quadraticBezierTo(
      x(.87),
      y + relief * .67,
      x(1.02),
      y + relief * direction,
    );
}

Path _remainingCrop(Rect flower, double damage, double direction) {
  if (damage >= 1) return Path();
  if (damage <= 0) return Path()..addRect(flower);
  final margin = flower.width * .02;
  return _cropEdge(flower, damage, direction)
    ..lineTo(flower.right + margin, flower.bottom)
    ..lineTo(flower.left - margin, flower.bottom)
    ..close();
}

void _drawCrop(Canvas canvas, ui.Image image, Rect flower, double opacity) {
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    flower,
    Paint()
      ..filterQuality = FilterQuality.low
      ..color = Colors.white.withValues(alpha: opacity),
  );
}

class PlanterCropPainter extends CustomPainter {
  const PlanterCropPainter({
    required this.image,
    required this.crop,
    required this.damage,
  });

  final ui.Image image;
  final PlanterCrop crop;
  final double damage;

  @override
  void paint(Canvas canvas, Size size) {
    final flower = Offset.zero & size;
    if (damage <= 0) {
      _drawCrop(canvas, image, flower, 1);
      return;
    }

    canvas.saveLayer(flower, Paint());
    canvas.save();
    canvas.clipPath(_remainingCrop(flower, damage, crop.edgeDirection));
    _drawCrop(canvas, image, flower, 1);
    canvas.restore();
    canvas.drawPath(
      _cropEdge(flower, damage, crop.edgeDirection),
      Paint()
        ..blendMode = BlendMode.srcATop
        ..color = const Color(0xAAE9D99E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PlanterCropPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.crop != crop ||
      oldDelegate.damage != damage;
}

class PlanterFragmentsPainter extends CustomPainter {
  const PlanterFragmentsPainter(this.fragments);

  final List<PlanterFragment> fragments;

  @override
  void paint(Canvas canvas, Size size) {
    for (final fragment in fragments) {
      final progress = fragment.progress;
      final move = Curves.easeOutCubic.transform(progress);
      final height = fragment.flower.height;
      final width = fragment.flower.width;
      final center = ui.lerpDouble(fragment.before, fragment.after, .56)!;
      final from = Offset(
        fragment.flower.center.dx,
        fragment.flower.top + height * center,
      );
      final position = Offset.lerp(from, fragment.mouth, move)!;
      final scale = ui.lerpDouble(.97, .18, move)!;
      final opacity =
          1 -
          Curves.easeInOut.transform(((progress - .56) / .44).clamp(0.0, 1.0));
      final local = Rect.fromLTWH(-width / 2, -height * center, width, height);
      final piece = Path.combine(
        PathOperation.difference,
        _remainingCrop(local, fragment.before, fragment.edgeDirection),
        _remainingCrop(local, fragment.after, fragment.edgeDirection),
      );
      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(move * fragment.direction * .56);
      canvas.scale(scale);
      canvas.clipPath(piece);
      _drawCrop(canvas, fragment.image, local, opacity);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant PlanterFragmentsPainter oldDelegate) =>
      !listEquals(oldDelegate.fragments, fragments);
}

class PlanterStumpPainter extends CustomPainter {
  const PlanterStumpPainter(this.crop);

  final PlanterCrop crop;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(5, 3, size.width - 10, 13),
        const Radius.circular(5),
      ),
      Paint()..color = const Color(0xFF33281E),
    );
    canvas.save();
    canvas.translate(size.width / 2, 9);
    canvas.drawPath(
      Path()
        ..moveTo(-25, -1)
        ..lineTo(-15, 4)
        ..lineTo(-18, 10),
      Paint()
        ..color = const Color(0xFFBA9470)
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-5, 3)
        ..lineTo(-3, -6)
        ..lineTo(2, -8)
        ..lineTo(5, -5)
        ..lineTo(5, 3)
        ..close(),
      Paint()..color = crop.stemColor,
    );
    canvas.drawOval(
      const Rect.fromLTWH(-3, -8, 8, 3),
      Paint()..color = const Color(0xFFE4C68F),
    );
    canvas.translate(15, 0);
    canvas.rotate(.24);
    canvas.drawOval(
      const Rect.fromLTWH(-4, -1.5, 8, 3),
      Paint()..color = crop.petalColor,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PlanterStumpPainter oldDelegate) =>
      oldDelegate.crop != crop;
}

class RainBarrelPainter extends CustomPainter {
  const RainBarrelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 110, size.height / 110);
    final paint = Paint()..color = const Color(0x99101C14);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(55, 96), width: 84, height: 16),
      paint,
    );

    final hull = Path()
      ..moveTo(19, 23)
      ..cubicTo(10, 42, 11, 73, 23, 91)
      ..quadraticBezierTo(55, 103, 87, 91)
      ..cubicTo(98, 73, 99, 42, 91, 23)
      ..close();
    paint.color = Colors.white;
    paint.shader = const LinearGradient(
      colors: [
        Color(0xFF633D27),
        Color(0xFFC18046),
        Color(0xFFA15D35),
        Color(0xFF503623),
      ],
      stops: [0, .33, .64, 1],
    ).createShader(const Rect.fromLTRB(20, 20, 87, 91));
    canvas.drawPath(hull, paint);

    paint
      ..shader = null
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.clipPath(hull);
    paint
      ..color = const Color(0x884B2E1C)
      ..strokeWidth = 1.8;
    for (final x in [31.0, 43.0, 55.0, 67.0, 79.0]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, 26)
          ..quadraticBezierTo(x + (x - 55) * .28, 60, x, 97),
        paint,
      );
    }
    for (final y in [45.0, 77.0]) {
      paint
        ..color = const Color(0xFF263D39)
        ..strokeWidth = 8;
      canvas.drawPath(
        Path()
          ..moveTo(10, y - 2)
          ..quadraticBezierTo(55, y + 14, 100, y - 2),
        paint,
      );
      paint
        ..color = const Color(0xFF62796A)
        ..strokeWidth = 1.7;
      canvas.drawPath(
        Path()
          ..moveTo(10, y - 5)
          ..quadraticBezierTo(55, y + 11, 100, y - 5),
        paint,
      );
    }
    canvas.restore();

    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFCE995E);
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(55, 24), width: 76, height: 28),
      paint,
    );
    final water = Rect.fromCenter(
      center: const Offset(55, 25),
      width: 64,
      height: 20,
    );
    paint.shader = const LinearGradient(
      colors: [Color(0xFF203B39), Color(0xFF509C99), Color(0xFF39716E)],
    ).createShader(water);
    canvas.drawOval(water, paint);
    paint
      ..shader = null
      ..color = const Color(0xFFB1EACE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawArc(
      Rect.fromCenter(center: const Offset(52, 24), width: 36, height: 6.8),
      .10,
      2.75,
      false,
      paint,
    );
    paint
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFE4B656);
    canvas.drawRRect(
      RRect.fromLTRBR(51, 66, 71, 73, const Radius.circular(3)),
      paint,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(64, 69, 72, 79, const Radius.circular(3)),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RainBarrelPainter oldDelegate) => false;
}
