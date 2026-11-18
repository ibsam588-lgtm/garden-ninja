import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

typedef PlanterWarning = ({Offset foot, Offset flower, double? biteProgress});

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
